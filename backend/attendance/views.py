import json
import uuid
import re
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.decorators import api_view, permission_classes
from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime
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
from .semester_rules import (
    enforce_single_semester,
    set_student_semester,
    student_current_semester,
)
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
    class_type = serializer.validated_data.get('class_type', 'qr')
    start_time = serializer.validated_data.get('start_time') or timezone.now()
    
    try:
        class_obj = Class.objects.get(id=class_id, teacher=user)
    except Class.DoesNotExist:
        return Response(
            {'error': 'Class not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    
    # Calculate end time
    end_time = start_time + timedelta(minutes=duration_minutes)
    
    # If the session end time is already in the past, mark it as completed
    session_status = 'active'
    if end_time < timezone.now():
        session_status = 'completed'

    
    # Generate session UUID
    session_uuid = uuid.uuid4()
    
    import random
    import string
    
    instruction_card = None
    if class_type == 'pattern':
        from attendance.verification import generate_shape_combo
        shape_combo, instruction_card, pattern_code = generate_shape_combo()
    else:
        pattern_code = None
        shape_combo = None
    
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

        'pattern_code': pattern_code
    }
    
    # Create session
    session = AttendanceSession.objects.create(
        session_id=session_uuid,
        class_obj=class_obj,
        teacher=user,
        start_time=start_time,
        duration_minutes=duration_minutes,
        end_time=end_time,
        qr_code_data=json.dumps(qr_data),
        class_type=class_type,

        pattern_code=pattern_code,
        instruction_card=instruction_card,
        shape_data=shape_combo,
        status=session_status
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
    enrolled_classes = Enrollment.objects.filter(student=user).values_list('class_obj_id', flat=True)
    
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
    
    is_offline_sync = request.data.get('is_offline_sync', False)
    timestamp_str = request.data.get('timestamp')
    scan_time = None
    if is_offline_sync and timestamp_str:
        from django.utils.dateparse import parse_datetime
        scan_time = parse_datetime(timestamp_str)
    
    # Check if session is active (unless offline sync)
    if not is_offline_sync:
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
    
    # Check 24-hour expiration for offline syncs
    if is_offline_sync:
        time_diff = timezone.now() - session.start_time
        if time_diff.total_seconds() > (24 * 3600):
            return Response(
                {'error': 'Sync window expired. Attendance must be synced within 24 hours.'},
                status=status.HTTP_400_BAD_REQUEST
            )
    
    # Check if already marked
    existing_record = AttendanceRecord.objects.filter(session=session, student=user).first()
    if existing_record:
        if is_offline_sync and existing_record.status == 'absent':
            # Allow offline sync to overwrite 'absent' with 'present'
            existing_record.status = 'present'
            existing_record.save()
            if scan_time:
                AttendanceRecord.objects.filter(id=existing_record.id).update(marked_at=scan_time)
                existing_record.refresh_from_db()
            return Response({
                'message': f'Attendance marked for {session.class_obj.class_code}',
                'class': session.class_obj.class_name,
                'marked_at': existing_record.marked_at,
                'status': 'present'
            }, status=status.HTTP_200_OK)

        return Response({
            'error': 'Attendance already marked',
            'marked_at': existing_record.marked_at,
            'status': existing_record.status
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Extract BLE Mesh Proofs
    ble_hop_count = request.data.get('ble_hop_count')
    ble_rssi = request.data.get('ble_rssi')
    
    verification_reasons_dict = {}
    verification_score = 1.0 # Default score
    
    if session.class_type == 'qr':
        if ble_hop_count is not None and ble_rssi is not None:
            verification_reasons_dict['ble_verified'] = True
            try:
                verification_reasons_dict['ble_hop_count'] = int(ble_hop_count)
                verification_reasons_dict['ble_rssi'] = int(float(ble_rssi))
                
                # Penalize score slightly for higher hop counts (further from teacher)
                score_penalty = verification_reasons_dict['ble_hop_count'] * 0.05
                verification_score = max(0.0, 1.0 - score_penalty)
            except (ValueError, TypeError):
                pass
        else:
            return Response({
                'error': 'Proxy attendance detected: BLE verification missing. Ensure Bluetooth is on and you are near the teacher.',
                'status': 'proxy_detected'
            }, status=status.HTTP_400_BAD_REQUEST)
    else:
        # Pattern mode or other modes might not require BLE strictly yet
        pass

    # Mark attendance
    record = AttendanceRecord.objects.create(
        session=session,
        student=user,
        status='present',
        verification_score=verification_score,
        verification_reasons=json.dumps(verification_reasons_dict)
    )
    if scan_time:
        AttendanceRecord.objects.filter(id=record.id).update(marked_at=scan_time)
        record.refresh_from_db()
    
    return Response({
        'message': f'Attendance marked for {session.class_obj.class_code}',
        'class': session.class_obj.class_name,
        'marked_at': record.marked_at,
        'status': 'present'
    }, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def upload_reference_image(request, session_id):
    """Teacher uploads the reference pattern image for pattern session"""
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
        if session.class_type == 'pattern':
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

        # Extract BLE Mesh Proofs
        ble_hop_count = request.data.get('ble_hop_count')
        ble_rssi = request.data.get('ble_rssi')
        
        verification_reasons_dict = {}
        if ble_hop_count is not None and ble_rssi is not None:
            verification_reasons_dict['ble_verified'] = True
            try:
                verification_reasons_dict['ble_hop_count'] = int(ble_hop_count)
                verification_reasons_dict['ble_rssi'] = int(float(ble_rssi))
            except (ValueError, TypeError):
                pass
        else:
            return Response({
                'error': 'Proxy attendance detected: BLE verification missing. Ensure Bluetooth is on and you are near the teacher.',
                'status': 'proxy_detected'
            }, status=status.HTTP_400_BAD_REQUEST)

        matched, final_score, reasons = verify_offline_code(
            session.pattern_code, session.reference_image, student_image, flash_fired
        )
        
        if matched:
            verification_reasons_dict['ai_verified'] = True
            verification_reasons_dict['ai_score'] = final_score
        
        verification_reasons_dict['reasons'] = reasons

        # Penalize score slightly for higher hop counts (further from teacher)
        if 'ble_hop_count' in verification_reasons_dict:
            score_penalty = verification_reasons_dict['ble_hop_count'] * 0.05
            final_score = max(0.0, final_score - score_penalty)

        status_val = 'present' if matched else 'pending_review'

        record = AttendanceRecord.objects.create(
            session=session,
            student=user,
            status=status_val,
            verification_score=final_score,
            verification_reasons=json.dumps(verification_reasons_dict)
        )

        if not matched:
            return Response({
                'status': 'pending_review',
                'score': final_score,
                'reasons': reasons,
                'message': f'Verification failed. Marked for manual review. Reasons: {", ".join(reasons)}'
            }, status=status.HTTP_200_OK)

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
def sync_offline_session(request):
    """Teacher syncs an offline session creation and upload reference."""
    user = request.user
    if user.role != 'teacher':
        return Response({'error': 'Only teachers can sync offline sessions'}, status=status.HTTP_403_FORBIDDEN)

    try:
        class_id = request.data.get('class_id')
        class_type = request.data.get('class_type', 'qr')
        duration_minutes = request.data.get('duration_minutes')
        start_time_str = request.data.get('start_time')
        end_time_str = request.data.get('end_time')
        shape_data_str = request.data.get('shape_data')
        reference_image = request.FILES.get('reference_image')

        if not all([class_id, start_time_str, end_time_str, duration_minutes]):
            return Response({'error': 'Missing required fields'}, status=status.HTTP_400_BAD_REQUEST)

        from django.utils.dateparse import parse_datetime
        start_time = parse_datetime(start_time_str)
        end_time = parse_datetime(end_time_str)
        
        class_obj = Class.objects.get(id=class_id)
        
        session_uuid_str = request.data.get('session_id')
        if not session_uuid_str:
            return Response({'error': 'Missing session_id'}, status=status.HTTP_400_BAD_REQUEST)
        
        session_uuid = uuid.UUID(session_uuid_str)
        
        existing_session = AttendanceSession.objects.filter(session_id=session_uuid).first()

        if existing_session:
            # Maybe update reference image if missing
            if reference_image and not existing_session.reference_image:
                existing_session.reference_image = reference_image
                existing_session.save()
            return Response({'message': 'Session already synced'}, status=status.HTTP_201_CREATED)

        shape_data = None
        pattern_code = None
        instruction_card = None

        if shape_data_str:
            try:
                shape_data = json.loads(shape_data_str)
                pattern_code = shape_data.get('number')
                outer = shape_data.get('outer')
                inner = shape_data.get('inner', 'none')
                if inner != 'none':
                    instruction_card = f"Draw a large {outer}. Inside it, draw a smaller {inner}. Finally, write the number '{pattern_code}' inside the {inner}."
                else:
                    instruction_card = f"Draw a large {outer}. Finally, write the number '{pattern_code}' inside the {outer}."
            except Exception:
                pass

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
            'pattern_code': pattern_code
        }

        session = AttendanceSession(
            session_id=session_uuid,
            class_obj=class_obj,
            teacher=user,
            duration_minutes=duration_minutes,
            class_type=class_type,
            pattern_code=pattern_code,
            instruction_card=instruction_card,
            shape_data=shape_data,
            qr_code_data=json.dumps(qr_data),
            status='completed' # Offline sessions are synced after they finish usually
        )
        # Override start_time and end_time, which might be auto_now_add
        session.start_time = start_time
        session.end_time = end_time
        
        if reference_image:
            session.reference_image = reference_image
            
        session.save()

        # Update start_time because auto_now_add overrides it on save
        AttendanceSession.objects.filter(session_id=session_uuid).update(
            start_time=start_time,
            end_time=end_time
        )
        
        # Reload session to have correct times
        session = AttendanceSession.objects.get(session_id=session_uuid)

        # Bulk mark absent students (or present if > 24 hours)
        enrolled_students = Enrollment.objects.filter(
            class_obj=class_obj
        ).select_related('student')
        
        already_marked = AttendanceRecord.objects.filter(
            session=session
        ).values_list('student_id', flat=True)
        
        absent_students = enrolled_students.exclude(
            student_id__in=already_marked
        )
        
        # 24-hour rule check
        time_diff = timezone.now() - session.start_time
        is_expired = time_diff.total_seconds() > (24 * 3600)
        default_status = 'present' if is_expired else 'absent'
        
        absent_records = []
        for enrollment in absent_students:
            absent_records.append(
                AttendanceRecord(
                    session=session,
                    student=enrollment.student,
                    status=default_status
                )
            )
        
        if absent_records:
            AttendanceRecord.objects.bulk_create(absent_records)

        return Response({'message': 'Offline session synced successfully'}, status=status.HTTP_201_CREATED)
    except Class.DoesNotExist:
        return Response({'error': 'Class not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        import traceback
        return Response({'error': str(e), 'trace': traceback.format_exc()}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def sync_offline_pattern(request):
    """Student syncs an offline pattern scan."""
    user = request.user
    if user.role != 'student':
        return Response({'error': 'Only students can sync attendance'}, status=status.HTTP_403_FORBIDDEN)

    timestamp_str = request.data.get('timestamp')
    student_image = request.FILES.get('student_image')

    if not timestamp_str or not student_image:
        return Response({'error': 'timestamp and student_image are required'}, status=status.HTTP_400_BAD_REQUEST)

    scan_time = parse_datetime(timestamp_str)
    if not scan_time:
        return Response({'error': 'Invalid timestamp format'}, status=status.HTTP_400_BAD_REQUEST)

    # Find the session active at that time for this student
    enrolled_class_ids = Enrollment.objects.filter(student=user).values_list('class_obj_id', flat=True)
    
    session = AttendanceSession.objects.filter(
        class_obj_id__in=enrolled_class_ids,
        class_type='pattern',
        start_time__lte=scan_time,
        end_time__gte=scan_time
    ).order_by('-start_time').first()

    if not session:
        return Response({'error': f'No active pattern session found for you at {scan_time.strftime("%I:%M %p")}'}, status=status.HTTP_404_NOT_FOUND)

    # Check 24-hour expiration for offline pattern syncs
    time_diff = timezone.now() - session.start_time
    if time_diff.total_seconds() > (24 * 3600):
        return Response(
            {'error': 'Sync window expired. Attendance must be synced within 24 hours.'},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        if not session.reference_image:
            return Response({'error': 'Teacher has not uploaded the reference image yet'}, status=status.HTTP_400_BAD_REQUEST)

        existing_record = AttendanceRecord.objects.filter(session=session, student=user).first()
        if existing_record:
            if existing_record.status not in ['absent', 'pending_review']:
                return Response({'error': 'Attendance already marked', 'marked_at': existing_record.marked_at, 'status': existing_record.status}, status=status.HTTP_400_BAD_REQUEST)

        # Extract BLE Mesh Proofs
        ble_hop_count = request.data.get('ble_hop_count')
        ble_rssi = request.data.get('ble_rssi')
        
        verification_reasons_dict = {}
        if ble_hop_count is not None and ble_rssi is not None:
            verification_reasons_dict['ble_verified'] = True
            try:
                verification_reasons_dict['ble_hop_count'] = int(ble_hop_count)
                verification_reasons_dict['ble_rssi'] = int(float(ble_rssi))
            except (ValueError, TypeError):
                pass
        else:
            return Response({
                'error': 'Proxy attendance detected: BLE verification missing. Ensure Bluetooth is on and you are near the teacher.',
                'status': 'proxy_detected'
            }, status=status.HTTP_400_BAD_REQUEST)

        from attendance.verification import verify_offline_code
        
        # Focal distance not recorded offline, pass default or assume None
        matched, final_score, reasons = verify_offline_code(
            session.pattern_code, session.reference_image, student_image, False
        )
        
        if matched:
            verification_reasons_dict['ai_verified'] = True
            verification_reasons_dict['ai_score'] = final_score
        
        verification_reasons_dict['reasons'] = reasons

        # Penalize score slightly for higher hop counts (further from teacher)
        if 'ble_hop_count' in verification_reasons_dict:
            score_penalty = verification_reasons_dict['ble_hop_count'] * 0.05
            final_score = max(0.0, final_score - score_penalty)

        status_val = 'present' if matched else 'pending_review'

        if existing_record:
            existing_record.status = status_val
            existing_record.verification_score = final_score
            existing_record.verification_reasons = json.dumps(verification_reasons_dict)
            existing_record.save()
            record = existing_record
        else:
            record = AttendanceRecord.objects.create(
                session=session,
                student=user,
                status=status_val,
                verification_score=final_score,
                verification_reasons=json.dumps(verification_reasons_dict)
            )

        if scan_time:
            AttendanceRecord.objects.filter(id=record.id).update(marked_at=scan_time)
            record.refresh_from_db()

        if not matched:
            return Response({'status': 'pending_review', 'message': f'Verification failed. Marked for manual review. Reasons: {", ".join(reasons)}'}, status=status.HTTP_200_OK)

        return Response({'status': 'pass', 'message': f'Offline attendance synced for {session.class_obj.class_code}'}, status=status.HTTP_201_CREATED)
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
        if session.status == 'completed':
            # This happens if the session was created offline and synced in the background
            enrolled_students = Enrollment.objects.filter(
                class_obj=session.class_obj
            ).select_related('student')
            total_students = enrolled_students.count()
            present_count = AttendanceRecord.objects.filter(session=session, status='present').count()
            absent_count = total_students - present_count
            attendance_rate = round((present_count / total_students * 100), 2) if total_students > 0 else 0
            
            return Response({
                'success': True,
                'message': 'Session already synced and ended',
                'session': SessionSerializer(session).data,
                'statistics': {
                    'total_students': total_students,
                    'present': present_count,
                    'absent': absent_count,
                    'attendance_rate': attendance_rate,
                    'auto_marked_absent': 0
                }
            }, status=status.HTTP_200_OK)

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


@api_view(['DELETE'])
@permission_classes([permissions.IsAuthenticated])
def cancel_session(request, session_id):
    """Teacher cancels/aborts a session and deletes all associated records"""
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
    
    # Delete the session (cascade will delete attendance records automatically)
    session.delete()
    
    return Response({
        'success': True,
        'message': 'Session successfully cancelled and deleted.'
    }, status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def mark_all_present_session(request, session_id):
    """Teacher marks all enrolled students as present in an active or past session"""
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

    enrolled_students = Enrollment.objects.filter(
        class_obj=session.class_obj
    ).select_related('student')
    
    # Update existing attendance records
    existing_records = AttendanceRecord.objects.filter(session=session)
    existing_student_ids = list(existing_records.values_list('student_id', flat=True))
    
    # Update all existing to present
    existing_records.update(status='present')
    
    # Create records for students who haven't been marked yet
    new_records = []
    for enrollment in enrolled_students:
        if enrollment.student.id not in existing_student_ids:
            new_records.append(
                AttendanceRecord(
                    session=session,
                    student=enrollment.student,
                    status='present',
                    marked_at=timezone.now()
                )
            )
            
    if new_records:
        AttendanceRecord.objects.bulk_create(new_records)
        
    return Response({
        'success': True,
        'message': 'All students marked as present.'
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
            'teacher_name': session.class_obj.teacher_name if session.class_obj else 'Unknown Teacher',
            'semester': session.class_obj.semester,
            'date': session.start_time.date(),
            'time': session.start_time.time(),
            'session_date': session.start_time,
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
        except Exception:
            profile = None
        
        return Response({
            'exists': True,
            'student': {
                'id': user.id,
                'username': user.username,
                'email': user.email,
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
        
        students_data.append({
            'id': student.id,
            'username': student.username,
            'email': student.email,
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

@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def assetlinks_json(request):
    """
    Serve the assetlinks.json file required for Android App Links (Deep Linking).
    """
    from django.http import JsonResponse
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
@api_view(['PATCH'])
@permission_classes([permissions.IsAuthenticated])
def edit_session(request, session_id):
    """Edit session start time, duration, and status"""
    try:
        session = AttendanceSession.objects.get(session_id=session_id, teacher=request.user)
    except AttendanceSession.DoesNotExist:
        return Response({'error': 'Session not found or unauthorized'}, status=status.HTTP_404_NOT_FOUND)
    
    start_time = request.data.get('start_time')
    duration_minutes = request.data.get('duration_minutes')
    new_status = request.data.get('status')
    
    if start_time:
        from dateutil.parser import parse
        try:
            session.start_time = parse(start_time)
        except ValueError:
            return Response({'error': 'Invalid start_time format'}, status=status.HTTP_400_BAD_REQUEST)
            
    if duration_minutes:
        try:
            session.duration_minutes = int(duration_minutes)
        except ValueError:
            return Response({'error': 'Invalid duration format'}, status=status.HTTP_400_BAD_REQUEST)
            
    # Recalculate end_time
    session.end_time = session.start_time + timedelta(minutes=session.duration_minutes)
    
    if new_status and new_status in dict(AttendanceSession.STATUS_CHOICES).keys():
        session.status = new_status
        
    session.save()
    serializer = SessionSerializer(session)
    return Response({'message': 'Session updated successfully', 'session': serializer.data})

@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def update_session_attendance(request, session_id):
    """Bulk update attendance records for a session"""
    try:
        session = AttendanceSession.objects.get(session_id=session_id, teacher=request.user)
    except AttendanceSession.DoesNotExist:
        return Response({'error': 'Session not found or unauthorized'}, status=status.HTTP_404_NOT_FOUND)
        
    attendance_data = request.data.get('attendance', []) # Expected list of dicts: [{'student_id': 1, 'status': 'present'}, ...]
    if not isinstance(attendance_data, list):
        return Response({'error': 'attendance must be a list of updates'}, status=status.HTTP_400_BAD_REQUEST)
        
    # Get all enrollments for this class to ensure students are actually enrolled
    enrolled_student_ids = list(Enrollment.objects.filter(class_obj=session.class_obj).values_list('student_id', flat=True))
    
    updated_records = 0
    for record_data in attendance_data:
        student_id = record_data.get('student_id')
        new_status = record_data.get('status')
        if student_id not in enrolled_student_ids or new_status not in ['present', 'absent']:
            continue
            
        record, created = AttendanceRecord.objects.update_or_create(
            session=session,
            student_id=student_id,
            defaults={'status': new_status, 'marked_at': timezone.now()}
        )
        updated_records += 1
        
    return Response({'message': f'Successfully updated {updated_records} records'})


@api_view(['GET', 'POST'])
@permission_classes([permissions.IsAuthenticated])
def announcements_list_create(request):
    """Get or Create announcements"""
    user = request.user
    
    if request.method == 'POST':
        if user.role != 'teacher':
            return Response({'error': 'Only teachers can create announcements'}, status=status.HTTP_403_FORBIDDEN)
        
        serializer = AnnouncementSerializer(data=request.data)
        if serializer.is_valid():
            announcement = serializer.save(sender=user)
            
            # Resolve target recipients
            target_type = announcement.target_type
            
            if target_type == 'class':
                target_class = announcement.target_class
                if not target_class:
                    announcement.delete()
                    return Response({'error': 'Target class is required for class announcements'}, status=status.HTTP_400_BAD_REQUEST)
                enrolled_students = User.objects.filter(enrolled_classes__class_obj=target_class)
                announcement.recipients.set(enrolled_students)
                
            elif target_type == 'individual':
                student_id = request.data.get('target_student_id')
                if not student_id:
                    announcement.delete()
                    return Response({'error': 'Target student is required for individual announcements'}, status=status.HTTP_400_BAD_REQUEST)
                try:
                    student = User.objects.get(id=student_id, role='student')
                except User.DoesNotExist:
                    announcement.delete()
                    return Response({'error': 'Student not found'}, status=status.HTTP_404_NOT_FOUND)
                announcement.recipients.add(student)
                
            elif target_type == 'low_attendance':
                target_class = announcement.target_class
                threshold = announcement.min_attendance_threshold
                if not target_class or threshold is None:
                    announcement.delete()
                    return Response({'error': 'Target class and min attendance threshold are required'}, status=status.HTTP_400_BAD_REQUEST)
                
                enrolled_users = User.objects.filter(enrolled_classes__class_obj=target_class)
                total_sessions = AttendanceSession.objects.filter(class_obj=target_class).count()
                
                recipients_list = []
                for student in enrolled_users:
                    if total_sessions > 0:
                        present_count = AttendanceRecord.objects.filter(
                            session__class_obj=target_class,
                            student=student,
                            status='present'
                        ).count()
                        rate = (present_count / total_sessions) * 100
                    else:
                        rate = 100.0
                        
                    if rate < threshold:
                        recipients_list.append(student)
                
                announcement.recipients.set(recipients_list)
                
            return Response(AnnouncementSerializer(announcement).data, status=status.HTTP_201_CREATED)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    else:
        if user.role == 'teacher':
            announcements = Announcement.objects.filter(sender=user)
        else:
            announcements = Announcement.objects.filter(recipients=user)
            
        serializer = AnnouncementSerializer(announcements, many=True)
        return Response(serializer.data)
