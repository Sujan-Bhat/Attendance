from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.decorators import api_view, permission_classes
from django.db import transaction
from django.contrib.auth import get_user_model

from ..models import Class, Enrollment, StudentProfile
from ..semester_rules import enforce_single_semester, set_student_semester, student_current_semester
from ..serializers import ClassSerializer, ClassListSerializer, CreateClassSerializer

User = get_user_model()




# ============================================
# CLASS MANAGEMENT VIEWS
# ============================================

@api_view(['GET', 'POST'])
@permission_classes([permissions.IsAuthenticated])
def class_list_create(request):
    """
    GET: List all classes for the logged-in teacher
    POST: Create a new class with students
    """
    user = request.user
    
    # Verify user is a teacher
    if user.role != 'teacher':
        return Response(
            {'error': 'Only teachers can manage classes'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    if request.method == 'GET':
        # Get all classes taught by this teacher
        classes = Class.objects.filter(teacher=user).prefetch_related('enrollments')
        serializer = ClassListSerializer(classes, many=True)
        return Response({'classes': serializer.data})
    
    elif request.method == 'POST':
        # Create new class with students
        serializer = CreateClassSerializer(
            data=request.data,
            context={'request': request}
        )
        
        if serializer.is_valid():
            try:
                result = serializer.save()
                class_obj = result['class']
                
                # Return created class details
                class_serializer = ClassSerializer(class_obj)
                return Response({
                    'message': 'Class created successfully',
                    'class': class_serializer.data
                }, status=status.HTTP_201_CREATED)
            
            except Exception as e:
                return Response({
                    'error': f'Failed to create class: {str(e)}'
                }, status=status.HTTP_400_BAD_REQUEST)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['GET', 'PUT', 'DELETE'])
@permission_classes([permissions.IsAuthenticated])
def class_detail(request, class_id):
    """
    GET: Get class details with enrolled students
    PUT: Update class details
    DELETE: Delete class
    """
    user = request.user
    
    try:
        class_obj = Class.objects.get(id=class_id, teacher=user)
    except Class.DoesNotExist:
        return Response(
            {'error': 'Class not found or you do not have permission'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    if request.method == 'GET':
        serializer = ClassSerializer(class_obj)
        return Response(serializer.data)
    
    elif request.method == 'PUT':
        # Update class details
        class_code = request.data.get('code')
        class_name = request.data.get('name')
        semester = request.data.get('semester')
        
        if class_code:
            # Check if code is already taken by another class
            if Class.objects.filter(class_code=class_code).exclude(id=class_id).exists():
                return Response(
                    {'error': 'Class code already exists'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            class_obj.class_code = class_code
        
        if class_name:
            class_obj.class_name = class_name
        if semester:
            class_obj.semester = semester
        
        class_obj.save()
        serializer = ClassSerializer(class_obj)
        return Response({
            'message': 'Class updated successfully',
            'class': serializer.data
        })
    
    elif request.method == 'DELETE':
        class_name = class_obj.class_name
        class_obj.delete()
        return Response({
            'message': f'Class "{class_name}" deleted successfully'
        }, status=status.HTTP_204_NO_CONTENT)


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def get_class_students(request, class_id):
    """Get all students enrolled in a class"""
    user = request.user
    
    try:
        class_obj = Class.objects.get(id=class_id, teacher=user)
        # test query to see if student_profile is missing
        list(StudentProfile.objects.all()[:1])
    except Class.DoesNotExist:
        return Response(
            {'error': 'Class not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    except Exception as e:
        # If SQLite says no such column, force a migration!
        from django.core.management import call_command
        try:
            call_command('migrate', interactive=False)
        except Exception as migrate_e:
            print("Migrate failed:", migrate_e)
    
    # Get all enrollments with student profiles
    enrollments = Enrollment.objects.filter(
        class_obj=class_obj
    ).select_related('student__student_profile')
    
    students_data = []
    for enrollment in enrollments:
        student = enrollment.student
        students_data.append({
            'id': student.id,
            'username': student.username,
            'email': student.email,
            'enrolled_at': enrollment.enrolled_at
        })
    
    # Students registered for this class's semester who are not yet enrolled
    # in this class (candidates the teacher can add).
    enrolled_ids = [enrollment.student_id for enrollment in enrollments]
    available_profiles = StudentProfile.objects.filter(
        semester=class_obj.semester
    ).exclude(
        semester=''
    ).exclude(
        student_id__in=enrolled_ids
    ).select_related('student').order_by('student__username')
    
    available_students = [{
        'id': profile.student.id,
        'username': profile.student.username,
        'email': profile.student.email,
    } for profile in available_profiles]
    
    return Response({
        'class_code': class_obj.class_code,
        'class_name': class_obj.class_name,
        'semester': class_obj.semester,
        'students': students_data,
        'total': len(students_data),
        'available_students': available_students,
        'total_available': len(available_students)
    })


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def add_student_to_class(request, class_id):
    """
    Add a student to an existing class
    - If student exists: just enroll them
    - If student is new: create user, profile, and enroll
    """
    user = request.user
    
    try:
        class_obj = Class.objects.get(id=class_id, teacher=user)
    except Class.DoesNotExist:
        return Response(
            {'error': 'Class not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    student_data = request.data
    
    # Validate required fields
    required_fields = ['email']
    for field in required_fields:
        if field not in student_data:
            return Response(
                {'error': f'Missing required field: {field}'},
                status=status.HTTP_400_BAD_REQUEST
            )
    
    email = student_data['email']
    
    try:
        with transaction.atomic():
            # Check if user already exists
            existing_user = User.objects.filter(email=email).first()
            
            if existing_user:
                # User exists - just enroll them in this class
                if existing_user.role != 'student':
                    return Response(
                        {'error': f'{email} is not a student account'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                
                # Check if already enrolled
                if Enrollment.objects.filter(class_obj=class_obj, student=existing_user).exists():
                    return Response(
                        {'error': f'Student already enrolled in this class'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                
                # Enforce single semester per student
                semester_error = enforce_single_semester(existing_user, class_obj)
                if semester_error:
                    return Response(
                        {'error': semester_error},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                
                # Enroll existing student
                Enrollment.objects.create(
                    class_obj=class_obj,
                    student=existing_user
                )
                
                if student_current_semester(existing_user) is None:
                    set_student_semester(existing_user, class_obj.semester)
                
                return Response({
                    'message': f'Student {existing_user.username} successfully added to class',
                    'student': {
                        'id': existing_user.id,
                        'username': existing_user.username,
                        'email': existing_user.email,
                        'status': 'existing'
                    }
                }, status=status.HTTP_201_CREATED)
                
            else:
                # New student - create user and profile
                required_for_new = ['name', 'password']
                for field in required_for_new:
                    if field not in student_data:
                        return Response(
                            {'error': f"Missing required field: {field} for new student"},
                            status=status.HTTP_400_BAD_REQUEST
                        )
                
                # Generate unique username
                email = student_data['email']
                username = email.split('@')[0]
                base_username = username
                counter = 1
                
                while User.objects.filter(username=username).exists():
                    username = f"{base_username}{counter}"
                    counter += 1
                
                # Create user
                student = User.objects.create_user(
                    username=username,
                    email=email,
                    password=student_data['password'],
                    role='student'
                )
                
                # Create profile
                StudentProfile.objects.create(
                    student=student,
                    semester=class_obj.semester
                )
                
                # Create enrollment
                Enrollment.objects.create(
                    class_obj=class_obj,
                    student=student
                )
                
                return Response({
                    'message': f'New student {username} created and added to class',
                    'student': {
                        'id': student.id,
                        'username': student.username,
                        'email': student.email,
                        'status': 'new'
                    }
                }, status=status.HTTP_201_CREATED)
    
    except Exception as e:
        return Response({
            'error': f'Failed to add student: {str(e)}'
        }, status=status.HTTP_400_BAD_REQUEST)


@api_view(['DELETE'])
@permission_classes([permissions.IsAuthenticated])
def remove_student_from_class(request, class_id, student_id):
    """Remove a student from a class (unenroll)"""
    user = request.user
    
    try:
        class_obj = Class.objects.get(id=class_id, teacher=user)
    except Class.DoesNotExist:
        return Response(
            {'error': 'Class not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    try:
        enrollment = Enrollment.objects.get(
            class_obj=class_obj,
            student_id=student_id
        )
        student_username = enrollment.student.username
        enrollment.delete()
        
        return Response({
            'message': f'Student {student_username} removed from class'
        }, status=status.HTTP_200_OK)
    
    except Enrollment.DoesNotExist:
        return Response(
            {'error': 'Student not found in this class'},
            status=status.HTTP_404_NOT_FOUND
        )


@api_view(['PUT'])
@permission_classes([permissions.IsAuthenticated])
def update_student_in_class(request, class_id, student_id):
    """Update a student's email within a class the teacher owns."""
    user = request.user

    if user.role != 'teacher':
        return Response(
            {'error': 'Only teachers can update students'},
            status=status.HTTP_403_FORBIDDEN
        )

    try:
        class_obj = Class.objects.get(id=class_id, teacher=user)
        enrollment = Enrollment.objects.get(class_obj=class_obj, student_id=student_id)
    except Class.DoesNotExist:
        return Response({'error': 'Class not found'}, status=status.HTTP_404_NOT_FOUND)
    except Enrollment.DoesNotExist:
        return Response({'error': 'Student not enrolled in this class'}, status=status.HTTP_404_NOT_FOUND)

    student = enrollment.student

    email = request.data.get('email')
    if email is not None:
        email = email.strip().lower()
        if not email:
            return Response({'error': 'Email cannot be empty'}, status=status.HTTP_400_BAD_REQUEST)
        if User.objects.filter(email=email).exclude(id=student.id).exists():
            return Response(
                {'error': 'Email already in use by another user'},
                status=status.HTTP_400_BAD_REQUEST
            )
        student.email = email

    student.save()
    return Response({
        'message': 'Student updated successfully',
        'student': {
            'id': student.id,
            'username': student.username,
            'email': student.email,
        }
    })

@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def join_class_by_code(request):
    """
    Allow a student to join a class by providing its class_code
    """
    user = request.user
    if user.role != 'student':
        return Response({'error': 'Only students can join classes directly'}, status=status.HTTP_403_FORBIDDEN)
        
    class_code = request.data.get('class_code')
    if not class_code:
        return Response({'error': 'class_code is required'}, status=status.HTTP_400_BAD_REQUEST)
        
    try:
        class_obj = Class.objects.get(class_code=class_code)
    except Class.DoesNotExist:
        return Response({'error': 'Class not found'}, status=status.HTTP_404_NOT_FOUND)
        
    # Check if already enrolled
    if Enrollment.objects.filter(class_obj=class_obj, student=user).exists():
        return Response({'message': 'Already enrolled'}, status=status.HTTP_200_OK)
    
    # Enforce single semester per student
    semester_error = enforce_single_semester(user, class_obj)
    if semester_error:
        return Response({'error': semester_error}, status=status.HTTP_400_BAD_REQUEST)
    
    Enrollment.objects.create(class_obj=class_obj, student=user)
    
    if student_current_semester(user) is None:
        set_student_semester(user, class_obj.semester)
    
    return Response({
        'message': f"Successfully joined {class_obj.class_name}",
        'class': {
            'id': class_obj.id,
            'name': class_obj.class_name,
            'code': class_obj.class_code
        }
    }, status=status.HTTP_200_OK)
