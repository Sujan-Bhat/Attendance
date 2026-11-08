import math
from datetime import timedelta
from rest_framework import permissions, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from django.utils import timezone
from django.db.models import Count, Q

from ..models import Class, Enrollment, AttendanceSession, AttendanceRecord, User


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def teacher_analytics(request):
    """
    Returns comprehensive analytics for the logged-in teacher:
    - Overall attendance statistics
    - Class-by-class comparison
    - At-risk students (< 75% attendance)
    - Weekly attendance trend
    """
    user = request.user
    if user.role != 'teacher':
        return Response(
            {'error': 'Only teachers can access teacher analytics'},
            status=status.HTTP_403_FORBIDDEN
        )

    teacher_classes = Class.objects.filter(teacher=user)
    total_classes = teacher_classes.count()

    teacher_sessions = AttendanceSession.objects.filter(teacher=user)
    total_sessions = teacher_sessions.count()

    records = AttendanceRecord.objects.filter(session__teacher=user)
    total_records = records.count()
    present_count = records.filter(status='present').count()
    absent_count = records.filter(status='absent').count()
    pending_count = records.filter(status='pending_review').count()

    overall_rate = (
        round((present_count / total_records * 100), 1)
        if total_records > 0 else 0.0
    )

    total_unique_students = (
        Enrollment.objects.filter(class_obj__teacher=user)
        .values('student')
        .distinct()
        .count()
    )

    # Class-by-class breakdown
    classes_analytics = []
    for cls in teacher_classes:
        cls_sessions = AttendanceSession.objects.filter(class_obj=cls)
        cls_sessions_count = cls_sessions.count()
        cls_records = AttendanceRecord.objects.filter(session__class_obj=cls)
        cls_total = cls_records.count()
        cls_present = cls_records.filter(status='present').count()
        cls_absent = cls_records.filter(status='absent').count()
        cls_rate = (
            round((cls_present / cls_total * 100), 1)
            if cls_total > 0 else 0.0
        )
        classes_analytics.append({
            'class_id': cls.id,
            'class_code': cls.class_code,
            'class_name': cls.class_name,
            'semester': cls.semester,
            'enrolled_students': cls.enrollments.count(),
            'total_sessions': cls_sessions_count,
            'total_records': cls_total,
            'present_count': cls_present,
            'absent_count': cls_absent,
            'attendance_rate': cls_rate,
        })

    # At-risk students (< 75% in any enrolled class under this teacher)
    at_risk_students = []
    enrollments = (
        Enrollment.objects.filter(class_obj__teacher=user)
        .select_related('student', 'class_obj')
    )

    for enr in enrollments:
        cls_sessions_count = AttendanceSession.objects.filter(class_obj=enr.class_obj).count()
        if cls_sessions_count > 0:
            student_records = AttendanceRecord.objects.filter(
                session__class_obj=enr.class_obj,
                student=enr.student
            )
            student_present = student_records.filter(status='present').count()
            student_rate = round((student_present / cls_sessions_count * 100), 1)

            if student_rate < 75.0:
                at_risk_students.append({
                    'student_id': enr.student.id,
                    'name': enr.student.username,
                    'email': enr.student.email,
                    'class_code': enr.class_obj.class_code,
                    'class_name': enr.class_obj.class_name,
                    'total_sessions': cls_sessions_count,
                    'attended': student_present,
                    'attendance_rate': student_rate,
                })

    at_risk_students.sort(key=lambda s: s['attendance_rate'])

    # Weekly trend (last 7 days)
    weekly_trend = []
    now = timezone.now()
    for days_ago in range(6, -1, -1):
        target_date = (now - timedelta(days=days_ago)).date()
        day_records = records.filter(marked_at__date=target_date)
        day_total = day_records.count()
        day_present = day_records.filter(status='present').count()
        day_rate = round((day_present / day_total * 100), 1) if day_total > 0 else 0.0
        weekly_trend.append({
            'date': target_date.strftime('%Y-%m-%d'),
            'day': target_date.strftime('%a'),
            'total': day_total,
            'present': day_present,
            'rate': day_rate,
        })

    return Response({
        'overview': {
            'total_classes': total_classes,
            'total_sessions': total_sessions,
            'total_records': total_records,
            'present_count': present_count,
            'absent_count': absent_count,
            'pending_count': pending_count,
            'overall_rate': overall_rate,
            'total_students': total_unique_students,
            'at_risk_count': len(at_risk_students),
        },
        'classes_analytics': classes_analytics,
        'at_risk_students': at_risk_students[:15],  # top 15 most at-risk
        'weekly_trend': weekly_trend,
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def student_analytics(request):
    """
    Returns personalized attendance analytics for the logged-in student:
    - Overall attendance gauge and status (Safe, Warning, Critical)
    - Subject-wise breakdown with safe skips / classes needed
    - Attendance streak
    - Recent attendance logs
    """
    user = request.user
    if user.role != 'student':
        return Response(
            {'error': 'Only students can access student analytics'},
            status=status.HTTP_403_FORBIDDEN
        )

    enrollments = (
        Enrollment.objects.filter(student=user)
        .select_related('class_obj__teacher')
    )

    classes_analytics = []
    total_conducted_sessions = 0
    total_attended_sessions = 0

    for enr in enrollments:
        cls = enr.class_obj
        cls_sessions_count = AttendanceSession.objects.filter(class_obj=cls).count()
        student_records = AttendanceRecord.objects.filter(session__class_obj=cls, student=user)
        attended_count = student_records.filter(status='present').count()
        missed_count = max(0, cls_sessions_count - attended_count)

        total_conducted_sessions += cls_sessions_count
        total_attended_sessions += attended_count

        if cls_sessions_count > 0:
            rate = round((attended_count / cls_sessions_count * 100), 1)
            if rate >= 75.0:
                status_label = 'Safe'
                safe_skips = max(0, math.floor((attended_count - 0.75 * cls_sessions_count) / 0.75))
                classes_needed = 0
            else:
                status_label = 'Warning' if rate >= 65.0 else 'Critical'
                safe_skips = 0
                needed = math.ceil((0.75 * cls_sessions_count - attended_count) / 0.25)
                classes_needed = max(0, int(needed))
        else:
            rate = 100.0
            status_label = 'No Sessions'
            safe_skips = 0
            classes_needed = 0

        classes_analytics.append({
            'class_id': cls.id,
            'class_code': cls.class_code,
            'class_name': cls.class_name,
            'semester': cls.semester,
            'teacher_name': cls.teacher_name,
            'total_sessions': cls_sessions_count,
            'attended': attended_count,
            'missed': missed_count,
            'attendance_rate': rate,
            'status': status_label,
            'safe_skips': safe_skips,
            'classes_needed': classes_needed,
        })

    overall_rate = (
        round((total_attended_sessions / total_conducted_sessions * 100), 1)
        if total_conducted_sessions > 0 else 0.0
    )

    if overall_rate >= 75.0:
        overall_status = 'Safe'
    elif overall_rate >= 65.0:
        overall_status = 'Warning'
    else:
        overall_status = 'Critical'

    # Safe skips overall
    if overall_rate >= 75.0 and total_conducted_sessions > 0:
        overall_safe_skips = max(0, math.floor((total_attended_sessions - 0.75 * total_conducted_sessions) / 0.75))
        overall_needed = 0
    elif total_conducted_sessions > 0:
        overall_safe_skips = 0
        overall_needed = max(0, int(math.ceil((0.75 * total_conducted_sessions - total_attended_sessions) / 0.25)))
    else:
        overall_safe_skips = 0
        overall_needed = 0

    # Calculate present streak
    all_student_records = (
        AttendanceRecord.objects.filter(student=user)
        .order_by('-marked_at')
    )
    streak = 0
    for rec in all_student_records:
        if rec.status == 'present':
            streak += 1
        else:
            break

    # Recent activity
    recent_activity = []
    for rec in all_student_records[:8]:
        recent_activity.append({
            'id': rec.id,
            'class_code': rec.session.class_obj.class_code,
            'class_name': rec.session.class_obj.class_name,
            'status': rec.status,
            'marked_at': rec.marked_at.strftime('%Y-%m-%d %H:%M'),
        })

    return Response({
        'overview': {
            'total_classes': len(classes_analytics),
            'total_conducted_sessions': total_conducted_sessions,
            'attended_sessions': total_attended_sessions,
            'missed_sessions': max(0, total_conducted_sessions - total_attended_sessions),
            'overall_rate': overall_rate,
            'status': overall_status,
            'safe_skips': overall_safe_skips,
            'classes_needed': overall_needed,
            'streak': streak,
        },
        'classes_analytics': classes_analytics,
        'recent_activity': recent_activity,
    })
