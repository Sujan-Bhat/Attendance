from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.decorators import api_view, permission_classes
from django.contrib.auth import get_user_model
from django.utils import timezone

from ..models import Class, Enrollment, AttendanceSession, AttendanceRecord
from ..serializers import TeacherAttendanceHistorySerializer, UpdateAttendanceStatusSerializer

User = get_user_model()




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
