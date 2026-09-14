import json
import uuid
import hashlib
from datetime import timedelta

from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.decorators import api_view, permission_classes
from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from ..models import Class, Enrollment, AttendanceSession, AttendanceRecord
from ..serializers import (
    CreateSessionSerializer,
    SessionSerializer,
    AttendanceRecordSerializer,
)

User = get_user_model()




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
    rotation_interval = serializer.validated_data.get('rotation_interval', 10)
    
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
    import secrets
    
    instruction_card = None
    if class_type == 'pattern':
        from attendance.verification import generate_shape_combo
        shape_combo, instruction_card, pattern_code = generate_shape_combo()
    else:
        pattern_code = None
        shape_combo = None
    
    totp_secret = secrets.token_hex(16)

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
        totp_secret=totp_secret,
        rotation_interval=rotation_interval,

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



def calculate_totp_and_captcha(session_id, totp_secret, rotation_interval, timestamp, start_timestamp=0):
    window = int((timestamp - start_timestamp) / rotation_interval)
    
    # Token
    token_input = f"{session_id}-{totp_secret}-{window}"
    token = hashlib.sha256(token_input.encode('utf-8')).hexdigest()[:16]
    
    # Captcha
    captcha_input = f"{session_id}-{totp_secret}-{window}-captcha"
    captcha_hash = hashlib.sha256(captcha_input.encode('utf-8')).hexdigest()
    
    chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    num = int(captcha_hash[:8], 16)
    captcha = ""
    for i in range(4):
        captcha += chars[num % len(chars)]
        num = num // len(chars)
        
    return token, captcha


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
    
    # Validate rotating QR and captcha if it's a QR session
    if session.class_type == 'qr':
        token = request.data.get('token')
        captcha = request.data.get('captcha')
        
        if not token or not captcha:
            return Response(
                {'error': 'QR code token and captcha are required'},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        target_time = scan_time or timezone.now()
        target_timestamp = target_time.timestamp()
        start_timestamp = session.start_time.timestamp()
        
        valid = False
        # Allow current, previous, and next windows (total 3 windows to be highly tolerant of drift)
        for offset in [0, -1, 1]:
            test_timestamp = target_timestamp + (offset * (session.rotation_interval or 10))
            expected_token, expected_captcha = calculate_totp_and_captcha(
                str(session.session_id),
                session.totp_secret or '',
                session.rotation_interval or 10,
                test_timestamp,
                start_timestamp
            )
            if token == expected_token and captcha.upper() == expected_captcha.upper():
                valid = True
                break
                
        if not valid:
            return Response(
                {'error': 'Invalid or expired QR code or captcha'},
                status=status.HTTP_400_BAD_REQUEST
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
