from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.decorators import api_view, permission_classes
from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone
from datetime import timedelta
import json
import uuid

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
)
from .models import Class, Enrollment, StudentProfile, AttendanceSession, AttendanceRecord
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
        }, status=status.HTTP_204_NO_CONTENT)


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
                'enrolled_at': enrollment.enrolled_at
            })
        except StudentProfile.DoesNotExist:
            students_data.append({
                'id': student.id,
                'username': student.username,
                'email': student.email,
                'roll_no': 'N/A',
                'enrolled_at': enrollment.enrolled_at
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
    Add a single student to an existing class
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
    required_fields = ['name', 'email', 'password', 'rollNo']
    for field in required_fields:
        if field not in student_data:
            return Response(
                {'error': f'Missing required field: {field}'},
                status=status.HTTP_400_BAD_REQUEST
            )
    
    # Check if email exists
    if User.objects.filter(email=student_data['email']).exists():
        return Response(
            {'error': f"Email {student_data['email']} already exists"},
            status=status.HTTP_400_BAD_REQUEST
        )
    
    # Check if roll number exists
    if StudentProfile.objects.filter(roll_no=student_data['rollNo']).exists():
        return Response(
            {'error': f"Roll number {student_data['rollNo']} already exists"},
            status=status.HTTP_400_BAD_REQUEST
        )
    
    try:
        with transaction.atomic():
            # Generate unique username from email
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
            
            # Create student profile
            StudentProfile.objects.create(
                student_name=student,
                roll_no=student_data['rollNo']
            )
            
            # Enroll in class
            Enrollment.objects.create(
                class_obj=class_obj,
                student=student
            )
            
            return Response({
                'message': f"Student {student_data['name']} added successfully",
                'student': {
                    'id': student.id,
                    'username': student.username,
                    'email': student.email,
                    'roll_no': student_data['rollNo']
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
    }
    
    # Create session
    session = AttendanceSession.objects.create(
        session_id=session_uuid,
        class_obj=class_obj,
        teacher=user,
        duration_minutes=duration_minutes,
        end_time=end_time,
        qr_code_data=json.dumps(qr_data),
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
            {'error': 'Invalid session'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    # Check if session is active
    if not session.is_active:
        return Response(
            {'error': 'Session has expired or ended'},
            status=status.HTTP_400_BAD_REQUEST
        )
    
    # Check if student is enrolled in the class
    if not Enrollment.objects.filter(class_obj=session.class_obj, student=user).exists():
        return Response(
            {'error': 'You are not enrolled in this class'},
            status=status.HTTP_403_FORBIDDEN
        )
    
    # Check if already marked
    existing_record = AttendanceRecord.objects.filter(session=session, student=user).first()
    if existing_record:
        return Response({
            'message': 'Attendance already marked',
            'marked_at': existing_record.marked_at,
            'status': existing_record.status
        })
    
    # Mark attendance
    record = AttendanceRecord.objects.create(
        session=session,
        student=user,
        status='present'
    )
    
    return Response({
        'message': 'Attendance marked successfully',
        'session': session.class_obj.class_code,
        'marked_at': record.marked_at
    }, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def end_session(request, session_id):
    """Teacher ends an active session"""
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
    
    session.status = 'completed'
    session.end_time = timezone.now()
    session.save()
    
    return Response({
        'message': 'Session ended successfully',
        'session': SessionSerializer(session).data
    })

