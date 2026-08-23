import json
import uuid
import re
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.decorators import api_view, permission_classes
from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone
from datetime import timedelta


from .serializers import (
    RegistrationSerializer, 
    UserSerializer, 
    LoginSerializer,
    ClassSerializer,
    ClassListSerializer,
    CreateClassSerializer,
    StudentDetailSerializer,
    CreateSessionSerializer,  
    SessionSerializer,
    AttendanceRecordSerializer,
    TeacherAttendanceHistorySerializer,
    UpdateAttendanceStatusSerializer,
    AnnouncementSerializer,
)
from .models import Class, Enrollment, StudentProfile, AttendanceSession, AttendanceRecord, Announcement
from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

User = get_user_model()

class RegisterView(generics.CreateAPIView):
    """Public endpoint for new user registration"""
    permission_classes = (permissions.AllowAny,)
    serializer_class = RegistrationSerializer


class MeView(generics.RetrieveAPIView):
    """Returns details about currently authenticated user"""
    permission_classes = (permissions.IsAuthenticated,)
    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user


class MyTokenObtainPairSerializer(TokenObtainPairSerializer):
    @classmethod
    def get_token(cls, user):
        """Generate JWT token with custom claims"""
        token = super().get_token(user)
        # Add custom claims
        token['role'] = user.role
        token['username'] = user.username
        return token

    def validate(self, attrs):
        """Authenticate user and return tokens + user data"""
        #Step 1: Validate credentials
        data = super().validate(attrs)
        # Add user data to response
        data['user'] = UserSerializer(self.user).data
        return data


class MyTokenObtainPairView(TokenObtainPairView):
    """Custom token view using our serializer"""
    serializer_class = MyTokenObtainPairSerializer


@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def ping(request):
    return Response({"status": "ok", "message": "Server is running!"})


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
        }, status=status.HTTP_200_OK)


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def get_class_students(request, class_id):
    """Get all students enrolled in a class"""
    user = request.user
    
    try:
        class_obj = Class.objects.get(id=class_id, teacher=user)
    except Class.DoesNotExist:
        return Response(
            {'error': 'Class not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    # Get all enrollments with student profiles
    enrollments = Enrollment.objects.filter(
        class_obj=class_obj
    ).select_related('student__student_profile')
    
    students_data = []
    for enrollment in enrollments:
        student = enrollment.student
        try:
            profile = student.student_profile
            students_data.append({
                'id': student.id,
                'username': student.username,
                'email': student.email,
                'roll_no': profile.roll_no,
                'enrolled_at': enrollment.enrolled_at,
                'status': enrollment.status
            })
        except StudentProfile.DoesNotExist:
            students_data.append({
                'id': student.id,
                'username': student.username,
                'email': student.email,
                'roll_no': 'N/A',
                'enrolled_at': enrollment.enrolled_at,
                'status': enrollment.status
            })
    
    return Response({
        'class_code': class_obj.class_code,
        'class_name': class_obj.class_name,
        'semester': class_obj.semester,
        'students': students_data,
        'total': len(students_data)
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
                
                # Enroll existing student directly
                Enrollment.objects.create(
                    class_obj=class_obj,
                    student=existing_user,
                    status='enrolled'
                )
                
                try:
                    roll_no = existing_user.student_profile.roll_no
                except:
                    roll_no = 'N/A'
                
                return Response({
                    'message': f"Student {existing_user.username} enrolled successfully",
                    'student': {
                        'id': existing_user.id,
                        'username': existing_user.username,
                        'email': existing_user.email,
                        'roll_no': roll_no,
                        'status': 'existing'
                    }
                }, status=status.HTTP_201_CREATED)
            
            else:
                # New student - create user and profile
                required_for_new = ['name', 'password', 'rollNo']
                for field in required_for_new:
                    if field not in student_data:
                        return Response(
                            {'error': f'Missing required field for new student: {field}'},
                            status=status.HTTP_400_BAD_REQUEST
                        )
                
                # Check if roll number exists
                if StudentProfile.objects.filter(roll_no=student_data['rollNo']).exists():
                    return Response(
                        {'error': f"Roll number {student_data['rollNo']} already exists"},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                
                # Generate unique username from email
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
                
                # Create student profile (FIXED)
                StudentProfile.objects.create(
                    student=student,  # ✅ Correct field name
                    roll_no=student_data['rollNo']
                )
                
                # Enroll in class directly
                Enrollment.objects.create(
                    class_obj=class_obj,
                    student=student,
                    status='enrolled'
                )
                
                return Response({
                    'message': f"New student {student_data['name']} created and enrolled",
                    'student': {
                        'id': student.id,
                        'username': student.username,
                        'email': student.email,
                        'roll_no': student_data['rollNo'],
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


# ============================================
#  SESSION MANAGEMENT VIEWS
# ============================================

@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def create_session(request):
    """Create a new attendance session with QR code"""
    user = request.user
    
    if user.role != 'teacher':
        return Response(
            {'error': 'Only teachers can create sessions'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    serializer = CreateSessionSerializer(data=request.data, context={'request': request})
    
    if not serializer.is_valid():
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
    
    class_id = serializer.validated_data['class_id']
    duration_minutes = serializer.validated_data['duration_minutes']
    reference_image = request.FILES.get('reference_image')

    class_type = serializer.validated_data.get('class_type', 'online')
    board_type = serializer.validated_data.get('board_type', 'whiteboard')
    
    # Reference image is uploaded later for offline sessions via a separate endpoint.
    # Online sessions don't require it at all.
    
    try:
        class_obj = Class.objects.get(id=class_id, teacher=user)
    except Class.DoesNotExist:
        return Response(
            {'error': 'Class not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    # Calculate end time
    start_time = timezone.now()
    end_time = start_time + timedelta(minutes=duration_minutes)
    
    # Generate session UUID
    session_uuid = uuid.uuid4()
    
    import random
    import string
    
    instruction_card = None
    shape_combo = None
    if class_type == 'offline':
        from attendance.verification import generate_shape_combo
        shape_combo, instruction_card, pattern_code = generate_shape_combo()
    else:
        pattern_code = None
    
    # Create QR code data (JSON string)
    qr_data = {
        'session_id': str(session_uuid),
        'class_id': class_obj.id,
        'class_code': class_obj.class_code,
        'class_name': class_obj.class_name,
        'semester': class_obj.semester,
        'teacher': user.username,
        'start_time': start_time.isoformat(),
        'end_time': end_time.isoformat(),
        'duration': duration_minutes,
        'class_type': class_type,
        'board_type': board_type,
        'pattern_code': pattern_code
    }
    
    # Create session
    session = AttendanceSession.objects.create(
        session_id=session_uuid,
        class_obj=class_obj,
        teacher=user,
        duration_minutes=duration_minutes,
        end_time=end_time,
        qr_code_data=json.dumps(qr_data),
        reference_image=reference_image,
        class_type=class_type,
        board_type=board_type,
        pattern_code=pattern_code,
        instruction_card=instruction_card,
        shape_data=shape_combo,
        status='active'
    )
    
    response_serializer = SessionSerializer(session)
    return Response({
        'message': 'Session created successfully',
        'session': response_serializer.data
    }, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def get_active_sessions(request):
    """Get all active sessions for logged-in teacher"""
    user = request.user
    
    if user.role != 'teacher':
        return Response(
            {'error': 'Only teachers can view sessions'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    # Get active sessions
    sessions = AttendanceSession.objects.filter(
        teacher=user,
        status='active',
        end_time__gt=timezone.now()
    ).select_related('class_obj')
    
    serializer = SessionSerializer(sessions, many=True)
    return Response({
        'sessions': serializer.data,
        'total': sessions.count()
    })

@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def get_student_active_sessions(request):
    """Get all active sessions for classes the student is enrolled in"""
    user = request.user
    
    if user.role != 'student':
        return Response(
            {'error': 'Only students can view these sessions'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    # Get enrolled classes
    enrolled_classes = Enrollment.objects.filter(student=user, status='enrolled').values_list('class_obj_id', flat=True)
    
    # Get active sessions for those classes
    sessions = AttendanceSession.objects.filter(
        class_obj_id__in=enrolled_classes,
        status='active',
        end_time__gt=timezone.now()
    ).select_related('class_obj', 'teacher')
    
    sessions_data = []
    for session in sessions:
        data = {
            'session_id': str(session.session_id),
            'class_code': session.class_obj.class_code,
            'class_name': session.class_obj.class_name,
            'class_type': session.class_type,
            'pattern_code': session.pattern_code,
            'has_reference_image': bool(session.reference_image),
            'end_time': session.end_time,
            'status': session.status,
        }
        sessions_data.append(data)

    return Response({
        'sessions': sessions_data,
        'total': len(sessions_data)
    })

@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def get_session_details(request, session_id):
    """Get session details with attendance records"""
    user = request.user
    
    try:
        session = AttendanceSession.objects.get(
            session_id=session_id,
            teacher=user
        )
    except AttendanceSession.DoesNotExist:
        return Response(
            {'error': 'Session not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    # Get attendance records
    records = AttendanceRecord.objects.filter(session=session).select_related('student')
    
    session_data = SessionSerializer(session).data
    records_data = AttendanceRecordSerializer(records, many=True).data
    
    return Response({
        'session': session_data,
        'attendance': records_data,
        'total_present': records.filter(status='present').count(),
        'total_students': session.class_obj.student_count
    })


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def mark_attendance(request, session_id):
    """Student marks attendance by scanning QR code"""
    user = request.user
    
    if user.role != 'student':
        return Response(
            {'error': 'Only students can mark attendance'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    try:
        session = AttendanceSession.objects.get(session_id=session_id)
    except AttendanceSession.DoesNotExist:
        return Response(
            {'error': 'Invalid QR code - Session not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    # Check if session is active
    if session.status != 'active':
        return Response(
            {'error': 'This session has ended'},
            status=status.HTTP_400_BAD_REQUEST
        )
    
    # Check if session has expired
    if not session.is_active:
        return Response(
            {'error': f'Session expired at {session.end_time.strftime("%I:%M %p")}'},
            status=status.HTTP_400_BAD_REQUEST
        )
    
    # Check if student is enrolled in the class
    if not Enrollment.objects.filter(class_obj=session.class_obj, student=user).exists():
        return Response(
            {'error': f'You are not enrolled in {session.class_obj.class_code}'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    # Check if already marked
    existing_record = AttendanceRecord.objects.filter(session=session, student=user).first()
    if existing_record:
        return Response({
            'error': 'Attendance already marked',
            'marked_at': existing_record.marked_at,
            'status': existing_record.status
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Mark attendance
    record = AttendanceRecord.objects.create(
        session=session,
        student=user,
        status='present'
    )
    
    return Response({
        'message': f'Attendance marked for {session.class_obj.class_code}',
        'class': session.class_obj.class_name,
        'marked_at': record.marked_at,
        'status': 'present'
    }, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def upload_reference_image(request, session_id):
    """Teacher uploads the reference pattern image for offline session"""
    user = request.user
    
    if user.role != 'teacher':
        return Response(
            {'error': 'Only teachers can upload reference images'},
            status=status.HTTP_403_FORBIDDEN
        )
        
    try:
        session = AttendanceSession.objects.get(
            session_id=session_id,
            teacher=user
        )
    except AttendanceSession.DoesNotExist:
        return Response(
            {'error': 'Session not found'},
            status=status.HTTP_404_NOT_FOUND
        )
        
    if 'reference_image' not in request.FILES:
        return Response(
            {'error': 'No image provided'},
            status=status.HTTP_400_BAD_REQUEST
        )
        
    ref_file = request.FILES['reference_image']
    
    from attendance.verification import verify_teacher_reference
    
    try:
        ref_bytes = ref_file.read()
        ref_file.seek(0) # Reset pointer so Django can save it
        
        success, message = verify_teacher_reference(ref_bytes, session.pattern_code, session.shape_data)
        if not success:
            return Response(
                {'error': message},
                status=status.HTTP_400_BAD_REQUEST
            )
            
    except Exception as e:
        return Response(
            {'error': f'Failed to process image: {str(e)}'},
            status=status.HTTP_400_BAD_REQUEST
        )
        
    session.reference_image = ref_file
    session.save()
    
    return Response({
        'message': 'Reference image verified and uploaded successfully'
    })

@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def verify_image(request):
    """Student verifies attendance with a live photo and focal distance."""
    user = request.user

    if user.role != 'student':
        return Response(
            {'error': 'Only students can verify attendance'},
            status=status.HTTP_403_FORBIDDEN
        )

    session_id = request.data.get('session_id')
    focal_distance = request.data.get('focal_distance')
    student_image = request.FILES.get('student_image')
    
    flash_fired_str = request.data.get('flash_fired', 'false').lower()
    flash_fired = flash_fired_str in ['true', '1', 'yes']

    if not session_id:
        return Response({'error': 'session_id is required'}, status=status.HTTP_400_BAD_REQUEST)
    if student_image is None:
        return Response({'error': 'student_image is required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        session = AttendanceSession.objects.get(session_id=session_id)
    except AttendanceSession.DoesNotExist:
        return Response(
            {'error': 'Session not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    if session.status != 'active':
        return Response({'error': 'This session has ended'}, status=status.HTTP_400_BAD_REQUEST)

    if not session.is_active:
        return Response(
            {'error': f'Session expired at {session.end_time.strftime("%I:%M %p")}'},
            status=status.HTTP_400_BAD_REQUEST
        )

    if not Enrollment.objects.filter(class_obj=session.class_obj, student=user).exists():
        return Response(
            {'error': f'You are not enrolled in {session.class_obj.class_code}'},
            status=status.HTTP_403_FORBIDDEN
        )

    try:
        if session.class_type == 'offline':
            if not session.pattern_code:
                return Response(
                    {'error': 'Session has no pattern code for verification'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            if not session.reference_image:
                return Response(
                    {'error': 'Teacher has not uploaded the reference image yet'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        existing_record = AttendanceRecord.objects.filter(session=session, student=user).first()
        if existing_record:
            if existing_record.status == 'pending_review':
                # Allow the student to retry scanning if their previous attempt failed verification
                existing_record.delete()
            else:
                return Response({
                    'error': 'Attendance already marked',
                    'marked_at': existing_record.marked_at,
                    'status': existing_record.status
                }, status=status.HTTP_400_BAD_REQUEST)

        from attendance.verification import verify_offline_code, validate_focal_distance
        
        is_valid_distance, distance_result = validate_focal_distance(focal_distance)
        if not is_valid_distance:
            return Response({'error': distance_result}, status=status.HTTP_400_BAD_REQUEST)

        matched, final_score, reasons = verify_offline_code(
            session.pattern_code, session.reference_image, student_image, session.board_type, flash_fired
        )
        
        status_val = 'present' if matched else 'pending_review'

        record = AttendanceRecord.objects.create(
            session=session,
            student=user,
            status=status_val,
            verification_score=final_score,
            verification_reasons=json.dumps(reasons)
        )

        if not matched:
            return Response({
                'status': 'fail',
                'score': final_score,
                'reasons': reasons,
                'error': f'Verification failed. Reasons: {", ".join(reasons)}'
            }, status=status.HTTP_400_BAD_REQUEST)

        return Response({
            'status': 'pass',
            'score': final_score,
            'message': f'Attendance verified for {session.class_obj.class_code}',
            'focal_distance': distance_result,
            'marked_at': record.marked_at,
        }, status=status.HTTP_201_CREATED)
    except Exception as e:
        import traceback
        return Response({'error': f"Backend Error: {str(e)}", 'trace': traceback.format_exc()}, status=status.HTTP_400_BAD_REQUEST)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def end_session(request, session_id):
    """Teacher ends an active session and marks absent students"""
    user = request.user
    
    try:
        session = AttendanceSession.objects.get(
            session_id=session_id,
            teacher=user
        )
    except AttendanceSession.DoesNotExist:
        return Response(
            {'error': 'Session not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    if session.status != 'active':
        return Response(
            {'error': 'Session is not active'},
            status=status.HTTP_400_BAD_REQUEST
        )
    
    # Mark all absent students before ending session
    with transaction.atomic():
        # Get all enrolled students in this class
        enrolled_students = Enrollment.objects.filter(
            class_obj=session.class_obj
        ).select_related('student')
        
        # Get students who already marked attendance
        already_marked = AttendanceRecord.objects.filter(
            session=session
        ).values_list('student_id', flat=True)
        
        # Find students who haven't marked attendance
        absent_students = enrolled_students.exclude(
            student_id__in=already_marked
        )
        
        # Create attendance records for absent students
        absent_records = []
        for enrollment in absent_students:
            absent_records.append(
                AttendanceRecord(
                    session=session,
                    student=enrollment.student,
                    status='absent'
                )
            )
        
        # Bulk create all absent records
        auto_marked_count = 0
        if absent_records:
            AttendanceRecord.objects.bulk_create(absent_records)
            auto_marked_count = len(absent_records)
        
        # Update session status
        session.status = 'completed'
        session.end_time = timezone.now()
        session.save()
    
    # Get final statistics
    total_students = enrolled_students.count()
    present_count = AttendanceRecord.objects.filter(
        session=session,
        status='present'
    ).count()
    absent_count = total_students - present_count
    attendance_rate = round((present_count / total_students * 100), 2) if total_students > 0 else 0
    
    return Response({
        'success': True,
        'message': 'Session ended successfully',
        'session': SessionSerializer(session).data,
        'statistics': {
            'total_students': total_students,
            'present': present_count,
            'absent': absent_count,
            'attendance_rate': attendance_rate,
            'auto_marked_absent': auto_marked_count
        }
    }, status=status.HTTP_200_OK)


# ============================================
#  STUDENT ENROLLED CLASSES VIEW
# ============================================

@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def get_student_enrolled_classes(request):
    """Get all classes the logged-in student is enrolled in"""
    user = request.user
    
    if user.role != 'student':
        return Response(
            {'error': 'Only students can view enrolled classes'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    # Get all enrollments for this student
    enrollments = Enrollment.objects.filter(
        student=user
    ).select_related('class_obj__teacher')
    
    classes_data = []
    for enrollment in enrollments:
        class_obj = enrollment.class_obj
        classes_data.append({
            'id': class_obj.id,
            'class_code': class_obj.class_code,
            'class_name': class_obj.class_name,
            'semester': class_obj.semester,
            'teacher_name': class_obj.teacher.username,
            'teacher_email': class_obj.teacher.email,
            'student_count': class_obj.student_count,
            'enrolled_at': enrollment.enrolled_at,
            'created_at': class_obj.created_at,
        })
    
    return Response({
        'classes': classes_data,
        'total': len(classes_data)
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def get_student_attendance_history(request):
    """Get attendance history for logged-in student"""
    user = request.user
    
    if user.role != 'student':
        return Response(
            {'error': 'Only students can view attendance history'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    # Get all attendance records for this student
    records = AttendanceRecord.objects.filter(
        student=user
    ).select_related('session__class_obj').order_by('-marked_at')
    
    attendance_data = []
    for record in records:
        session = record.session
        attendance_data.append({
            'id': record.id,
            'class_code': session.class_obj.class_code,
            'class_name': session.class_obj.class_name,
            'semester': session.class_obj.semester,
            'date': session.start_time.date(),
            'time': session.start_time.time(),
            'status': record.status,
            'marked_at': record.marked_at,
        })
    
    return Response({
        'attendance': attendance_data,
        'total': len(attendance_data)
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def check_student_by_email(request):
    """
    Check if a student exists by email and return their details
    GET /api/v1/auth/check-student/?email=student@example.com
    """
    email = request.query_params.get('email')
    
    if not email:
        return Response(
            {'error': 'Email parameter is required'},
            status=status.HTTP_400_BAD_REQUEST
        )
    
    # Validate email format
    import re
    email_pattern = r'^[\w\.-]+@[\w\.-]+\.\w+$'
    if not re.match(email_pattern, email):
        return Response(
            {'error': 'Invalid email format'},
            status=status.HTTP_400_BAD_REQUEST
        )
    
    try:
        user = User.objects.get(email=email, role='student')
        
        # Try to get student profile
        try:
            profile = user.student_profile
            roll_no = profile.roll_no
        except StudentProfile.DoesNotExist:
            roll_no = None
        
        return Response({
            'exists': True,
            'student': {
                'id': user.id,
                'username': user.username,
                'email': user.email,
                'roll_no': roll_no,
            }
        }, status=status.HTTP_200_OK)
        
    except User.DoesNotExist:
        return Response({
            'exists': False,
            'message': 'Student not found with this email'
        }, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({
            'error': f'Error checking student: {str(e)}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['PUT'])
@permission_classes([permissions.IsAuthenticated])
def update_student_in_class(request, class_id, student_id):
    """Update student details in a class"""
    user = request.user
    
    try:
        class_obj = Class.objects.get(id=class_id, teacher=user)
        enrollment = Enrollment.objects.get(class_obj=class_obj, student_id=student_id)
        
        # Update student profile
        profile = enrollment.student.student_profile
        roll_no = request.data.get('roll_no')
        
        if roll_no:
            # Check if roll number already exists
            if StudentProfile.objects.filter(roll_no=roll_no).exclude(student=enrollment.student).exists():
                return Response(
                    {'error': 'Roll number already exists'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            profile.roll_no = roll_no
            profile.save()
        
        return Response({'message': 'Student updated successfully'})
    
    except Class.DoesNotExist:
        return Response({'error': 'Class not found'}, status=status.HTTP_404_NOT_FOUND)
    except Enrollment.DoesNotExist:
        return Response({'error': 'Student not enrolled'}, status=status.HTTP_404_NOT_FOUND)



@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def get_teacher_attendance_history(request):
    """
    Get attendance history for teacher's classes
    Query params:
    - class_id: Filter by specific class (optional)
    - session_id: Filter by specific session (optional)
    - date_from: Filter from date (YYYY-MM-DD) (optional)
    - date_to: Filter to date (YYYY-MM-DD) (optional)
    """
    user = request.user
    
    if user.role != 'teacher':
        return Response(
            {'error': 'Only teachers can view attendance history'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    # Base query: all attendance records for teacher's classes
    records = AttendanceRecord.objects.filter(
        session__teacher=user
    ).select_related(
        'student__student_profile',
        'session__class_obj'
    ).order_by('-marked_at')
    
    # Apply filters
    class_id = request.query_params.get('class_id')
    if class_id:
        records = records.filter(session__class_obj_id=class_id)
    
    session_id = request.query_params.get('session_id')
    if session_id:
        records = records.filter(session__session_id=session_id)
    
    date_from = request.query_params.get('date_from')
    if date_from:
        try:
            from_date = timezone.datetime.strptime(date_from, '%Y-%m-%d').date()
            records = records.filter(session__start_time__date__gte=from_date)
        except ValueError:
            pass
    
    date_to = request.query_params.get('date_to')
    if date_to:
        try:
            to_date = timezone.datetime.strptime(date_to, '%Y-%m-%d').date()
            records = records.filter(session__start_time__date__lte=to_date)
        except ValueError:
            pass
    
    serializer = TeacherAttendanceHistorySerializer(records, many=True)
    
    # Calculate statistics
    total_records = records.count()
    present_count = records.filter(status='present').count()
    absent_count = records.filter(status='absent').count()
    
    return Response({
        'attendance': serializer.data,
        'statistics': {
            'total': total_records,
            'present': present_count,
            'absent': absent_count,
            'attendance_rate': round((present_count / total_records * 100), 2) if total_records > 0 else 0
        }
    })


@api_view(['PUT'])
@permission_classes([permissions.IsAuthenticated])
def update_attendance_status(request, record_id):
    """Update attendance status (teacher only)"""
    user = request.user
    
    if user.role != 'teacher':
        return Response(
            {'error': 'Only teachers can update attendance'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    try:
        # Verify record belongs to teacher's class
        record = AttendanceRecord.objects.select_related('session').get(
            id=record_id,
            session__teacher=user
        )
    except AttendanceRecord.DoesNotExist:
        return Response(
            {'error': 'Attendance record not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    serializer = UpdateAttendanceStatusSerializer(data=request.data)
    
    if not serializer.is_valid():
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
    
    new_status = serializer.validated_data['status']
    old_status = record.status
    
    record.status = new_status
    record.save()
    
    return Response({
        'message': f'Attendance updated from {old_status} to {new_status}',
        'record': TeacherAttendanceHistorySerializer(record).data
    })


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def manual_mark_attendance(request, session_id):
    """
    Teacher manually marks attendance for a student
    POST /api/v1/sessions/{session_id}/mark-student/
    Body: {
        "student_id": 1,
        "status": "present" or "absent"
    }
    """
    user = request.user
    
    if user.role != 'teacher':
        return Response(
            {'error': 'Only teachers can manually mark attendance'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    try:
        session = AttendanceSession.objects.get(
            session_id=session_id,
            teacher=user
        )
    except AttendanceSession.DoesNotExist:
        return Response(
            {'error': 'Session not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    student_id = request.data.get('student_id')
    new_status = request.data.get('status')
    
    if not student_id or not new_status:
        return Response(
            {'error': 'student_id and status are required'},
            status=status.HTTP_400_BAD_REQUEST
        )
    
    if new_status not in ['present', 'absent']:
        return Response(
            {'error': 'status must be "present" or "absent"'},
            status=status.HTTP_400_BAD_REQUEST
        )
    
    try:
        student = User.objects.get(id=student_id, role='student')
    except User.DoesNotExist:
        return Response(
            {'error': 'Student not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    # Check if student is enrolled
    if not Enrollment.objects.filter(class_obj=session.class_obj, student=student).exists():
        return Response(
            {'error': 'Student not enrolled in this class'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    # Create or update attendance record
    record, created = AttendanceRecord.objects.update_or_create(
        session=session,
        student=student,
        defaults={'status': new_status}
    )
    
    action = 'marked' if created else 'updated'
    
    return Response({
        'success': True,
        'message': f'Attendance {action} as {new_status}',
        'record': {
            'id': record.id,
            'student_id': student.id,
            'student_name': student.username,
            'status': record.status,
            'marked_at': record.marked_at,
        }
    }, status=status.HTTP_200_OK)


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def get_session_attendance_details(request, session_id):
    """
    Get detailed attendance information for a specific session
    Returns session info + list of all enrolled students with their attendance status
    """
    user = request.user
    
    if user.role != 'teacher':
        return Response(
            {'error': 'Only teachers can view session attendance details'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    try:
        session = AttendanceSession.objects.select_related('class_obj').get(
            session_id=session_id,
            teacher=user
        )
    except AttendanceSession.DoesNotExist:
        return Response(
            {'error': 'Session not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    # Get all enrolled students
    enrollments = Enrollment.objects.filter(
        class_obj=session.class_obj
    ).select_related('student__student_profile')
    
    # Get attendance records for this session
    attendance_records = AttendanceRecord.objects.filter(
        session=session
    ).select_related('student')
    
    # Create a map of student_id -> attendance record
    attendance_map = {record.student_id: record for record in attendance_records}
    
    # Build student list with attendance status
    students_data = []
    for enrollment in enrollments:
        student = enrollment.student
        record = attendance_map.get(student.id)
        
        try:
            roll_no = student.student_profile.roll_no
        except StudentProfile.DoesNotExist:
            roll_no = 'N/A'
        
        students_data.append({
            'id': student.id,
            'username': student.username,
            'email': student.email,
            'roll_no': roll_no,
            'status': record.status if record else 'absent',
            'marked_at': record.marked_at.isoformat() if record and record.marked_at else None,
            'record_id': record.id if record else None,
            'has_record': record is not None
        })
    
    # Calculate statistics
    total_students = len(students_data)
    present_count = sum(1 for s in students_data if s['status'] == 'present')
    absent_count = total_students - present_count
    attendance_rate = round((present_count / total_students * 100), 2) if total_students > 0 else 0
    
    return Response({
        'session': SessionSerializer(session).data,
        'students': students_data,
        'statistics': {
            'total': total_students,
            'present': present_count,
            'absent': absent_count,
            'attendance_rate': attendance_rate
        }
    })

@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def get_pending_classes(request):
    user = request.user
    if user.role != 'student':
        return Response({'error': 'Only students can view pending classes'}, status=status.HTTP_403_FORBIDDEN)
    
    yesterday = timezone.now() - timedelta(days=1)
    
    # Delete expired pending invitations
    Enrollment.objects.filter(student=user, status='pending', enrolled_at__lt=yesterday).delete()
    
    pending_enrollments = Enrollment.objects.filter(
        student=user,
        status='pending'
    ).select_related('class_obj', 'class_obj__teacher')
    
    classes_data = []
    for enrollment in pending_enrollments:
        cls = enrollment.class_obj
        classes_data.append({
            'id': cls.id,
            'class_code': cls.class_code,
            'class_name': cls.class_name,
            'semester': cls.semester,
            'teacher_name': cls.teacher_name,
            'pending_since': enrollment.enrolled_at
        })
        
    return Response({'pending_classes': classes_data})

@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def join_class(request):
    user = request.user
    if user.role != 'student':
        return Response({'error': 'Only students can join classes'}, status=status.HTTP_403_FORBIDDEN)
        
    class_code = request.data.get('class_code')
    if not class_code:
        return Response({'error': 'Class code is required'}, status=status.HTTP_400_BAD_REQUEST)
        
    try:
        class_obj = Class.objects.get(class_code=class_code)
    except Class.DoesNotExist:
        return Response({'error': 'Invalid class code'}, status=status.HTTP_404_NOT_FOUND)
        
    enrollment, created = Enrollment.objects.get_or_create(
        class_obj=class_obj,
        student=user,
        defaults={'status': 'enrolled'}
    )
    
    if not created:
        if enrollment.status == 'enrolled':
            return Response({'error': 'Already enrolled in this class'}, status=status.HTTP_400_BAD_REQUEST)
        else:
            enrollment.status = 'enrolled'
            enrollment.save()
            return Response({'message': f'Successfully joined {class_obj.class_name}'}, status=status.HTTP_200_OK)
            
    return Response({'message': f'Successfully joined {class_obj.class_name}'}, status=status.HTTP_201_CREATED)

from django.http import HttpResponse

def join_fallback(request, code):
    html = f"""<!DOCTYPE html>
<html>
<head>
<title>Join Class</title>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<script>
  window.location.href = 'attendapp://join/{code}';
</script>
<style>
  body {{ font-family: sans-serif; text-align: center; padding: 50px; background: #E0F7FA; }}
  .btn {{ display: inline-block; padding: 14px 28px; background: #007C91; color: white; text-decoration: none; border-radius: 12px; font-weight: bold; margin-top: 30px; font-size: 18px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }}
</style>
</head>
<body>
  <h2>Opening Attendance App...</h2>
  <p>If the app didn't open automatically, please tap the button below.</p>
  <a href='attendapp://join/{code}' class='btn'>Open in App</a>
</body>
</html>"""
    return HttpResponse(html)

from django.http import JsonResponse

def assetlinks_view(request):
    return JsonResponse([{
        "relation": ["delegate_permission/common.handle_all_urls"],
        "target": {
            "namespace": "android_app",
            "package_name": "com.example.attendance_app",
            "sha256_cert_fingerprints": [
                "87:17:E3:5D:41:92:69:09:62:28:72:43:E3:68:77:C8:BF:2C:F4:BA:97:47:37:DE:B4:52:D2:4D:6B:94:83:C9"
            ]
        }
    }], safe=False)

# ============================================================
# ANNOUNCEMENTS
# ============================================================

from rest_framework.permissions import IsAuthenticated

@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def announcement_list_create(request):
    """GET: list teacher's announcements. POST: create a new announcement."""
    if request.user.role != 'teacher':
        return Response({'error': 'Only teachers can manage announcements'}, status=403)

    if request.method == 'GET':
        announcements = Announcement.objects.filter(teacher=request.user)
        serializer = AnnouncementSerializer(announcements, many=True)
        return Response({'announcements': serializer.data})

    # POST
    target_type = request.data.get('target_type')
    target_class_id = request.data.get('target_class_id')
    target_student_id = request.data.get('target_student_id')
    message = request.data.get('message', '').strip()
    is_urgent = request.data.get('is_urgent', False)
    attendance_threshold = request.data.get('attendance_threshold', 75.0)

    if not message:
        return Response({'error': 'Message is required'}, status=400)
    if not target_type:
        return Response({'error': 'Target type is required'}, status=400)
    if target_type not in ['class', 'individual', 'low_attendance']:
        return Response({'error': 'Invalid target type'}, status=400)

    target_class = None
    target_student = None

    if target_type in ['class', 'low_attendance']:
        if not target_class_id:
            return Response({'error': 'Class is required for this target type'}, status=400)
        try:
            target_class = Class.objects.get(id=target_class_id, teacher=request.user)
        except Class.DoesNotExist:
            return Response({'error': 'Class not found'}, status=404)

    if target_type == 'individual':
        if not target_class_id:
            return Response({'error': 'Class is required'}, status=400)
        if not target_student_id:
            return Response({'error': 'Student is required for individual announcements'}, status=400)
        try:
            target_class = Class.objects.get(id=target_class_id, teacher=request.user)
        except Class.DoesNotExist:
            return Response({'error': 'Class not found'}, status=404)
        try:
            target_student = User.objects.get(id=target_student_id, role='student')
            # Verify student is enrolled in the class
            if not Enrollment.objects.filter(class_obj=target_class, student=target_student, status='enrolled').exists():
                return Response({'error': 'Student is not enrolled in this class'}, status=400)
        except User.DoesNotExist:
            return Response({'error': 'Student not found'}, status=404)

    announcement = Announcement.objects.create(
        teacher=request.user,
        target_type=target_type,
        target_class=target_class,
        target_student=target_student,
        message=message,
        is_urgent=is_urgent,
        attendance_threshold=float(attendance_threshold),
    )

    serializer = AnnouncementSerializer(announcement)
    return Response({'message': 'Announcement sent successfully', 'announcement': serializer.data}, status=201)


@api_view(['GET', 'PUT', 'DELETE'])
@permission_classes([IsAuthenticated])
def announcement_detail(request, announcement_id):
    """GET/PUT/DELETE a specific announcement (teacher only, own announcements)."""
    if request.user.role != 'teacher':
        return Response({'error': 'Only teachers can manage announcements'}, status=403)

    try:
        announcement = Announcement.objects.get(id=announcement_id, teacher=request.user)
    except Announcement.DoesNotExist:
        return Response({'error': 'Announcement not found'}, status=404)

    if request.method == 'GET':
        serializer = AnnouncementSerializer(announcement)
        return Response(serializer.data)

    if request.method == 'PUT':
        message = request.data.get('message', announcement.message).strip()
        is_urgent = request.data.get('is_urgent', announcement.is_urgent)
        if not message:
            return Response({'error': 'Message cannot be empty'}, status=400)
        announcement.message = message
        announcement.is_urgent = is_urgent
        announcement.save()
        serializer = AnnouncementSerializer(announcement)
        return Response({'message': 'Announcement updated', 'announcement': serializer.data})

    if request.method == 'DELETE':
        announcement.delete()
        return Response({'message': 'Announcement deleted'}, status=200)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def student_announcements(request):
    """GET: list announcements visible to the authenticated student."""
    if request.user.role != 'student':
        return Response({'error': 'Only students can view student announcements'}, status=403)

    # Get all classes the student is enrolled in
    enrolled_class_ids = Enrollment.objects.filter(
        student=request.user, status='enrolled'
    ).values_list('class_obj_id', flat=True)

    from django.db.models import Q

    # Class-wide announcements for enrolled classes
    class_q = Q(target_type='class', target_class_id__in=enrolled_class_ids)

    # Individual announcements addressed to this student
    individual_q = Q(target_type='individual', target_student=request.user)

    # Low-attendance announcements: need to check attendance per class
    low_att_announcements_ids = []
    low_att_announcements = Announcement.objects.filter(
        target_type='low_attendance', target_class_id__in=enrolled_class_ids
    )
    for ann in low_att_announcements:
        # Calculate student's attendance percentage in this class
        total_sessions = AttendanceSession.objects.filter(class_obj=ann.target_class).exclude(status='active').count()
        if total_sessions == 0:
            continue
        attended = AttendanceRecord.objects.filter(
            session__class_obj=ann.target_class,
            student=request.user,
            status='present'
        ).exclude(session__status='active').count()
        percentage = (attended / total_sessions) * 100
        if percentage < ann.attendance_threshold:
            low_att_announcements_ids.append(ann.id)

    low_att_q = Q(id__in=low_att_announcements_ids)

    announcements = Announcement.objects.filter(
        class_q | individual_q | low_att_q
    ).distinct().order_by('-created_at')

    serializer = AnnouncementSerializer(announcements, many=True)
    return Response({'announcements': serializer.data})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def low_attendance_students(request, class_id):
    """GET: list students in a class whose attendance is below a threshold."""
    if request.user.role != 'teacher':
        return Response({'error': 'Only teachers can view this'}, status=403)

    try:
        class_obj = Class.objects.get(id=class_id, teacher=request.user)
    except Class.DoesNotExist:
        return Response({'error': 'Class not found'}, status=404)

    threshold = float(request.query_params.get('threshold', 75.0))
    total_sessions = AttendanceSession.objects.filter(class_obj=class_obj).exclude(status='active').count()

    students_below = []
    enrollments = Enrollment.objects.filter(class_obj=class_obj, status='enrolled').select_related('student')

    for enrollment in enrollments:
        if total_sessions == 0:
            percentage = 100.0
        else:
            attended = AttendanceRecord.objects.filter(
                session__class_obj=class_obj,
                student=enrollment.student,
                status='present'
            ).exclude(session__status='active').count()
            percentage = (attended / total_sessions) * 100

        if percentage < threshold:
            students_below.append({
                'id': enrollment.student.id,
                'username': enrollment.student.username,
                'first_name': enrollment.student.first_name,
                'last_name': enrollment.student.last_name,
                'email': enrollment.student.email,
                'attendance_percentage': round(percentage, 1),
            })

    return Response({
        'class_name': class_obj.class_name,
        'class_code': class_obj.class_code,
        'threshold': threshold,
        'total_sessions': total_sessions,
        'students': students_below,
        'total': len(students_below),
        'count': len(students_below),
    })
