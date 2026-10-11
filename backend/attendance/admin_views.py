import json
import uuid
import re
from collections import OrderedDict
from io import BytesIO
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
)
from .models import Class, Enrollment, StudentProfile, AttendanceSession, AttendanceRecord
from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

User = get_user_model()



@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_classes_summary(request):
    """
    Admin: Get all classes grouped by semester with student counts.
    Returns a summary per semester: semester label + class count + enrolled
    student count + total students (includes newly added, not-yet-enrolled
    students of that semester). Semesters that only have newly added students
    (no classes yet) are still included so those students remain reachable.
    """
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can access this endpoint'},
            status=status.HTTP_403_FORBIDDEN
        )

    from django.db.models import Count

    class_counts = dict(
        Class.objects
        .values_list('semester')
        .annotate(classes_count=Count('id'))
    )

    row_counts = dict(
        Enrollment.objects
        .filter(class_obj__semester__isnull=False)
        .values_list('class_obj__semester')
        .annotate(student_count=Count('id'))
    )

    enrolled_map = {}
    for enrollment in Enrollment.objects.values('class_obj__semester', 'student_id'):
        if enrollment['class_obj__semester']:
            enrolled_map.setdefault(
                enrollment['class_obj__semester'], set()
            ).add(enrollment['student_id'])

    unassigned_map = {}
    for profile in (
        StudentProfile.objects
        .filter(semester__isnull=False)
        .exclude(semester='')
        .exclude(student__enrolled_classes__isnull=False)
        .values('semester', 'student_id')
    ):
        unassigned_map.setdefault(profile['semester'], set()).add(
            profile['student_id']
        )

    semester_names = set(class_counts) | set(enrolled_map) | set(unassigned_map)

    semesters = []
    for semester in sorted(semester_names):
        enrolled = enrolled_map.get(semester, set())
        unassigned = unassigned_map.get(semester, set())
        semesters.append({
            'semester': semester,
            'class_count': class_counts.get(semester, 0),
            'student_count': row_counts.get(semester, 0),
            'total_students': len(enrolled | unassigned),
        })

    return Response({
        'semesters': semesters,
        'total_semesters': len(semesters),
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_semester_classes(request, semester):
    """
    Admin: Get all classes in a given semester with their enrolled students.
    """
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can access this endpoint'},
            status=status.HTTP_403_FORBIDDEN
        )

    classes = Class.objects.filter(semester=semester)

    result = []
    for cls in classes:
        student_list = []
        for enrollment in cls.enrollments.all():
            student = enrollment.student
            student_list.append({
                'id': student.id,
                'username': student.username,
                'email': student.email,
            })

        result.append({
            'id': cls.id,
            'class_code': cls.class_code,
            'class_name': cls.class_name,
            'teacher_name': cls.teacher_name,
            'semester': cls.semester,
            'student_count': len(student_list),
            'students': student_list,
        })

    return Response({
        'semester': semester,
        'classes': result,
        'total_classes': len(result),
        'total_students': sum(c['student_count'] for c in result),
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_semester_students(request, semester):
    """
    Admin: Get all unique students in a given semester with their enrolled class codes.
    Deduplicates students who are enrolled in multiple classes.
    """
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can access this endpoint'},
            status=status.HTTP_403_FORBIDDEN
        )

    classes = Class.objects.filter(semester=semester)

    students_map = {}
    for cls in classes:
        for enrollment in cls.enrollments.all():
            student = enrollment.student
            if student.id not in students_map:
                students_map[student.id] = {
                    'id': student.id,
                    'username': student.username,
                    'email': student.email,
                    'is_active': student.is_active,
                    'classes': [],
                }
            students_map[student.id]['classes'].append({
                'id': cls.id,
                'class_code': cls.class_code,
            })

    students_list = list(students_map.values())

    return Response({
        'semester': semester,
        'total_students': len(students_list),
        'students': students_list,
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_unassigned_students(request):
    """
    Admin: Get students pre-registered by an admin (assigned a semester but
    not yet enrolled in any class). These are surfaced in the Manage Students
    page's 'Newly Added' section.
    """
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can access this endpoint'},
            status=status.HTTP_403_FORBIDDEN
        )

    students = StudentProfile.objects.filter(
        semester__isnull=False,
    ).exclude(semester='').exclude(
        student__enrolled_classes__isnull=False
    ).select_related('student').distinct()

    result = []
    for profile in students.order_by('semester', 'student__username'):
        result.append({
            'id': profile.student.id,
            'username': profile.student.username,
            'email': profile.student.email,
            'is_active': profile.student.is_active,
            'semester': profile.semester,
        })

    # Also surface students that no other admin flow can reach: those with a
    # blank/missing profile semester, or no StudentProfile row at all. Without
    # this they are invisible in the Manage Students flow.
    reachable_ids = {s['id'] for s in result}
    unreachable = []
    enrolled_ids = set(
        Enrollment.objects.values_list('student_id', flat=True).distinct()
    )
    for u in User.objects.filter(role='student').order_by('username'):
        if u.id in enrolled_ids or u.id in reachable_ids:
            continue
        unreachable.append({
            'id': u.id,
            'username': u.username,
            'email': u.email,
            'is_active': u.is_active,
            'semester': '',
        })

    return Response({
        'students': result,
        'unreachable': unreachable,
        'total': len(result),
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_teachers_list(request):
    """
    Admin: Get all teachers with their class details.
    Returns each teacher's info + list of classes they teach.
    """
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can access this endpoint'},
            status=status.HTTP_403_FORBIDDEN
        )

    from django.db.models import Count

    teachers = User.objects.filter(role='teacher').annotate(
        class_count=Count('classes_taught')
    ).prefetch_related('classes_taught').order_by('username')

    result = []
    for teacher in teachers:
        classes_list = []
        for cls in teacher.classes_taught.all():
            classes_list.append({
                'id': cls.id,
                'class_code': cls.class_code,
                'class_name': cls.class_name,
                'semester': cls.semester,
                'student_count': cls.student_count,
            })

        result.append({
            'id': teacher.id,
            'username': teacher.username,
            'email': teacher.email,
            'is_active': teacher.is_active,
            'date_joined': teacher.date_joined,
            'class_count': teacher.class_count,
            'classes': classes_list,
        })

    return Response({
        'teachers': result,
        'total_teachers': len(result),
    })


@api_view(['PATCH'])
@permission_classes([permissions.IsAuthenticated])
def admin_update_teacher(request, teacher_id):
    """Admin: Update teacher's name and email"""
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can update teachers'},
            status=status.HTTP_403_FORBIDDEN
        )

    try:
        teacher = User.objects.get(id=teacher_id, role='teacher')
    except User.DoesNotExist:
        return Response(
            {'error': 'Teacher not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    username = request.data.get('username')
    email = request.data.get('email')

    if username is not None:
        username = username.strip()
        if not username:
            return Response(
                {'error': 'Name cannot be empty'},
                status=status.HTTP_400_BAD_REQUEST
            )
        teacher.username = username

    if email is not None:
        email = email.strip().lower()
        if not email:
            return Response(
                {'error': 'Email cannot be empty'},
                status=status.HTTP_400_BAD_REQUEST
            )
        if User.objects.filter(email=email).exclude(id=teacher_id).exists():
            return Response(
                {'error': 'Email already in use by another user'},
                status=status.HTTP_400_BAD_REQUEST
            )
        teacher.email = email

    teacher.save()

    return Response({
        'message': 'Teacher updated successfully',
        'teacher': {
            'id': teacher.id,
            'username': teacher.username,
            'email': teacher.email,
        }
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_stats(request):
    """Admin: Get aggregate counts for dashboard."""
    user = request.user

    if user.role != 'admin':
        return Response({'error': 'Forbidden'}, status=status.HTTP_403_FORBIDDEN)

    return Response({
        'teachers_count': User.objects.filter(role='teacher').count(),
        'students_count': User.objects.filter(role='student').count(),
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_users_list(request, role):
    """
    Admin: Get users by role for login-reset management.
    GET /api/v1/admin/users/teachers/ or /api/v1/admin/users/students/
    """
    user = request.user

    if user.role != 'admin':
        return Response({'error': 'Forbidden'}, status=status.HTTP_403_FORBIDDEN)

    if role not in ('teachers', 'students'):
        return Response({'error': 'Invalid role'}, status=status.HTTP_400_BAD_REQUEST)

    users = User.objects.filter(role=role[:-1]).order_by('username')

    if role == 'teachers':
        data = [{
            'id': u.id,
            'username': u.username,
            'full_name': u.get_full_name() or u.username,
            'email': u.email,
            'is_active': u.is_active,
        } for u in users]
    else:
        data = []
        for u in users:
            data.append({
                'id': u.id,
                'username': u.username,
                'full_name': u.get_full_name() or u.username,
                'email': u.email,
                'is_active': u.is_active,
            })

    return Response({
        role: data,
        'total': len(data),
    })


@api_view(['PATCH'])
@permission_classes([permissions.IsAuthenticated])
def admin_toggle_user_access(request, user_id):
    """Admin: Toggle is_active for a user."""
    user = request.user

    if user.role != 'admin':
        return Response({'error': 'Forbidden'}, status=status.HTTP_403_FORBIDDEN)

    try:
        target = User.objects.get(id=user_id)
    except User.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    # Guards: an admin must not be able to lock themselves out, and
    # superuser accounts are protected from casual blocking.
    if target.id == user.id:
        return Response(
            {'error': 'You cannot block or unblock your own account'},
            status=status.HTTP_400_BAD_REQUEST
        )
    if target.is_superuser:
        return Response(
            {'error': 'Superuser accounts cannot be blocked here'},
            status=status.HTTP_403_FORBIDDEN
        )

    target.is_active = not target.is_active
    target.save(update_fields=['is_active'])

    return Response({
        'id': target.id,
        'username': target.username,
        'email': target.email,
        'role': target.role,
        'is_active': target.is_active,
    })


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def admin_create_user(request):
    """Admin: Create a new user (student or teacher)"""
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can create users'},
            status=status.HTTP_403_FORBIDDEN
        )

    username = request.data.get('username', '').strip()
    email = request.data.get('email', '').strip().lower()
    password = request.data.get('password', '')
    role = request.data.get('role', '')
    semester = request.data.get('semester', '').strip()

    if not username:
        return Response({'error': 'Name is required'}, status=status.HTTP_400_BAD_REQUEST)
    if not email:
        return Response({'error': 'Email is required'}, status=status.HTTP_400_BAD_REQUEST)
    if not password or len(password) < 6:
        return Response({'error': 'Password must be at least 6 characters'}, status=status.HTTP_400_BAD_REQUEST)
    if role not in ('student', 'teacher'):
        return Response({'error': 'Role must be student or teacher'}, status=status.HTTP_400_BAD_REQUEST)

    if User.objects.filter(email=email).exists():
        return Response({'error': 'Email already in use'}, status=status.HTTP_400_BAD_REQUEST)
    if User.objects.filter(username=username).exists():
        return Response({'error': 'Username already taken'}, status=status.HTTP_400_BAD_REQUEST)

    new_user = User(
        username=username,
        email=email,
        role=role,
    )
    new_user.set_password(password)
    new_user.save()

    if role == 'student':
        student_profile = StudentProfile.objects.create(student=new_user)
        if semester:
            student_profile.semester = semester
            student_profile.save(update_fields=['semester'])

    return Response({
        'message': f'{role.capitalize()} created successfully',
        'user': {
            'id': new_user.id,
            'username': new_user.username,
            'email': new_user.email,
            'role': new_user.role,
            'semester': semester if role == 'student' else None,
        }
    }, status=status.HTTP_201_CREATED)


@api_view(['DELETE'])
@permission_classes([permissions.IsAuthenticated])
def admin_delete_user(request, user_id):
    """Admin: Permanently delete a user"""
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can delete users'},
            status=status.HTTP_403_FORBIDDEN
        )

    try:
        target = User.objects.get(id=user_id)
    except User.DoesNotExist:
        return Response(
            {'error': 'User not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    if target == user:
        return Response(
            {'error': 'You cannot delete yourself'},
            status=status.HTTP_400_BAD_REQUEST
        )

    if target.role == 'teacher':
        from django.db.models import Count
        class_count = target.classes_taught.count()
        if class_count > 0:
            return Response(
                {'error': f'Teacher still has {class_count} class(es) assigned. Reassign or delete classes first.'},
                status=status.HTTP_400_BAD_REQUEST
            )

    username = target.username
    role = target.role
    target.delete()

    return Response({
        'message': f'{role.capitalize()} "{username}" deleted permanently',
    })


@api_view(['DELETE'])
@permission_classes([permissions.IsAuthenticated])
def admin_delete_student(request, student_id):
    """Admin: Permanently delete a student and all of their data"""
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can delete students'},
            status=status.HTTP_403_FORBIDDEN
        )

    try:
        student = User.objects.get(id=student_id, role='student')
    except User.DoesNotExist:
        return Response(
            {'error': 'Student not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    username = student.username
    student.delete()

    return Response({
        'message': f'Student "{username}" deleted permanently',
    })


@api_view(['PUT'])
@permission_classes([permissions.IsAuthenticated])
def admin_update_class(request, class_id):
    """Admin: Update class details (code, name, semester)"""
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can update classes'},
            status=status.HTTP_403_FORBIDDEN
        )

    try:
        class_obj = Class.objects.get(id=class_id)
    except Class.DoesNotExist:
        return Response(
            {'error': 'Class not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    class_code = request.data.get('class_code')
    class_name = request.data.get('class_name')
    semester = request.data.get('semester')
    teacher_id = request.data.get('teacher_id')

    if class_code is not None:
        class_code = class_code.strip()
        if not class_code:
            return Response(
                {'error': 'Class code cannot be empty'},
                status=status.HTTP_400_BAD_REQUEST
            )
        if Class.objects.filter(class_code=class_code).exclude(id=class_id).exists():
            return Response(
                {'error': 'Class code already exists'},
                status=status.HTTP_400_BAD_REQUEST
            )
        class_obj.class_code = class_code

    if class_name is not None:
        class_name = class_name.strip()
        if not class_name:
            return Response(
                {'error': 'Class name cannot be empty'},
                status=status.HTTP_400_BAD_REQUEST
            )
        class_obj.class_name = class_name

    if semester is not None:
        semester = semester.strip()
        if not semester:
            return Response(
                {'error': 'Semester cannot be empty'},
                status=status.HTTP_400_BAD_REQUEST
            )
        class_obj.semester = semester

    if teacher_id is not None:
        try:
            teacher_id = int(teacher_id)
        except (TypeError, ValueError):
            return Response(
                {'error': 'Invalid teacher id'},
                status=status.HTTP_400_BAD_REQUEST
            )
        try:
            teacher = User.objects.get(id=teacher_id, role='teacher')
        except User.DoesNotExist:
            return Response(
                {'error': 'Teacher not found'},
                status=status.HTTP_404_NOT_FOUND
            )
        class_obj.teacher = teacher

    class_obj.save()

    return Response({
        'message': 'Class updated successfully',
        'class': {
            'id': class_obj.id,
            'class_code': class_obj.class_code,
            'class_name': class_obj.class_name,
            'semester': class_obj.semester,
            'teacher_name': class_obj.teacher_name,
            'student_count': class_obj.student_count,
        }
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_class_detail(request, class_id):
    """Admin: Get class details with enrolled students"""
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can access this endpoint'},
            status=status.HTTP_403_FORBIDDEN
        )

    try:
        class_obj = Class.objects.get(id=class_id)
    except Class.DoesNotExist:
        return Response(
            {'error': 'Class not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    enrollments = class_obj.enrollments.select_related('student')
    students_list = []
    for enrollment in enrollments:
        student = enrollment.student
        students_list.append({
            'id': student.id,
            'username': student.username,
            'email': student.email,
        })

    return Response({
        'id': class_obj.id,
        'class_code': class_obj.class_code,
        'class_name': class_obj.class_name,
        'semester': class_obj.semester,
        'teacher_name': class_obj.teacher_name,
        'student_count': len(students_list),
        'students': students_list,
    })


@api_view(['DELETE'])
@permission_classes([permissions.IsAuthenticated])
def admin_remove_student_from_class(request, class_id, student_id):
    """Admin: Remove a student from a class"""
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can perform this action'},
            status=status.HTTP_403_FORBIDDEN
        )

    try:
        class_obj = Class.objects.get(id=class_id)
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


@api_view(['PATCH'])
@permission_classes([permissions.IsAuthenticated])
def admin_update_student(request, student_id):
    """Admin: Update student's name, email, and roll number"""
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can update students'},
            status=status.HTTP_403_FORBIDDEN
        )

    try:
        student = User.objects.get(id=student_id, role='student')
    except User.DoesNotExist:
        return Response(
            {'error': 'Student not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    username = request.data.get('username')
    email = request.data.get('email')

    if username is not None:
        username = username.strip()
        if not username:
            return Response(
                {'error': 'Name cannot be empty'},
                status=status.HTTP_400_BAD_REQUEST
            )
        student.username = username

    if email is not None:
        email = email.strip().lower()
        if not email:
            return Response(
                {'error': 'Email cannot be empty'},
                status=status.HTTP_400_BAD_REQUEST
            )
        if User.objects.filter(email=email).exclude(id=student_id).exists():
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


@api_view(['DELETE'])
@permission_classes([permissions.IsAuthenticated])
def admin_delete_all_students(request, semester):
    """Admin: Permanently delete every student of a given semester.

    Targets the union of students enrolled in any class of the semester and
    students whose profile semester matches (i.e. the semester page contents).
    Because a student can only belong to one semester, this is safe.
    """
    user = request.user

    if user.role != 'admin':
        return Response(
            {'error': 'Only admins can delete students'},
            status=status.HTTP_403_FORBIDDEN
        )

    semester = (semester or '').strip()
    if not semester:
        return Response(
            {'error': 'Semester is required'},
            status=status.HTTP_400_BAD_REQUEST
        )

    if not request.data.get('confirm'):
        return Response(
            {'error': 'Confirmation required'},
            status=status.HTTP_400_BAD_REQUEST
        )

    enrolled_ids = set(
        Enrollment.objects
        .filter(class_obj__semester=semester)
        .values_list('student_id', flat=True)
    )
    profile_ids = set(
        StudentProfile.objects
        .filter(semester=semester)
        .values_list('student_id', flat=True)
    )
    student_ids = enrolled_ids | profile_ids

    if not student_ids:
        return Response(
            {'error': 'No students in this semester'},
            status=status.HTTP_400_BAD_REQUEST
        )

    deleted, _ = (
        User.objects
        .filter(id__in=student_ids, role='student')
        .delete()
    )

    return Response({
        'message': f'Deleted {deleted} students from {semester}',
    })

@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_attendance_semesters(request):
    """
    Admin: Attendance Management - list every semester that has attendance
    sessions, with aggregate session/record stats per semester.
    """
    if request.user.role != 'admin':
        return Response(
            {'error': 'Only admins can access this endpoint'},
            status=status.HTTP_403_FORBIDDEN
        )

    from django.db.models import Count, Q

    # One aggregated row per semester (not per class).
    rows = (
        AttendanceSession.objects
        .values('class_obj__semester')
        .annotate(
            session_count=Count('id', distinct=True),
            record_count=Count('records', distinct=True),
            present_count=Count(
                'records',
                filter=Q(records__status='present'),
                distinct=True,
            ),
            class_count=Count('class_obj__id', distinct=True),
        )
        .order_by('class_obj__semester')
    )

    semesters = [
        {
            'semester': row['class_obj__semester'],
            'class_count': row['class_count'],
            'session_count': row['session_count'],
            'record_count': row['record_count'],
            'present_count': row['present_count'],
        }
        for row in rows
    ]

    return Response({
        'semesters': semesters,
        'total_semesters': len(semesters),
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_attendance_by_semester(request, semester):
    """
    Admin: Attendance Management - every attendance session of a semester,
    grouped by class (each class carries its sessions and their records).
    """
    if request.user.role != 'admin':
        return Response(
            {'error': 'Only admins can access this endpoint'},
            status=status.HTTP_403_FORBIDDEN
        )

    sessions = (
        AttendanceSession.objects
        .filter(class_obj__semester=semester)
        .select_related('class_obj', 'teacher')
        .prefetch_related('records__student')
        .order_by('-start_time')
    )

    classes = OrderedDict()
    for session in sessions:
        records = []
        for record in session.records.all():
            student = record.student
            records.append({
                'id': record.id,
                'student_id': student.id,
                'username': student.username,
                'email': student.email,
                'status': record.status,
                'marked_at': record.marked_at,
                'verification_score': record.verification_score,
            })

        class_obj = session.class_obj
        session_data = {
            'session_uuid': str(session.session_id),
            'status': session.status,
            'class_type': session.class_type,
            'teacher': session.teacher.username,
            'start_time': session.start_time,
            'end_time': session.end_time,
            'duration_minutes': session.duration_minutes,
            'record_count': len(records),
            'present_count': sum(1 for r in records if r['status'] == 'present'),
            'records': records,
        }

        cls = classes.setdefault(class_obj.id, {
            'class_id': class_obj.id,
            'class_code': class_obj.class_code,
            'class_name': class_obj.class_name,
            'teacher': class_obj.teacher.username,
            'sessions': [],
        })
        cls['sessions'].append(session_data)

    by_class = []
    for cls in classes.values():
        cls['session_count'] = len(cls['sessions'])
        cls['record_count'] = sum(s['record_count'] for s in cls['sessions'])
        cls['present_count'] = sum(s['present_count'] for s in cls['sessions'])
        by_class.append(cls)

    by_class.sort(key=lambda c: c['class_code'])

    return Response({
        'semester': semester,
        'total_sessions': sessions.count(),
        'total_records': sum(c['record_count'] for c in by_class),
        'classes': by_class,
    })


# ---------------------------------------------------------------------------
# Admin exports (PDF / Excel)
# ---------------------------------------------------------------------------

def _build_workbook(title, headers, rows):
    """Build an in-memory xlsx with a styled header row; returns bytes."""
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment
    from openpyxl.utils import get_column_letter

    wb = Workbook()
    ws = wb.active
    ws.title = title[:31] or 'Sheet1'

    ws.append([title])
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=max(len(headers), 1))
    title_cell = ws.cell(row=1, column=1)
    title_cell.font = Font(bold=True, size=13)
    ws.append([])

    header_fill = PatternFill('solid', fgColor='007C91')
    for col, header in enumerate(headers, start=1):
        cell = ws.cell(row=3, column=col, value=header)
        cell.font = Font(bold=True, color='FFFFFF')
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal='center')

    for row in rows:
        ws.append(list(row))

    for col, header in enumerate(headers, start=1):
        max_len = len(str(header))
        for row_idx in range(4, ws.max_row + 1):
            value = ws.cell(row=row_idx, column=col).value
            if value is not None:
                max_len = max(max_len, min(len(str(value)), 60))
        ws.column_dimensions[get_column_letter(col)].width = min(max_len + 4, 62)

    ws.freeze_panes = 'A4'

    buffer = BytesIO()
    wb.save(buffer)
    return buffer.getvalue()


def _build_pdf(title, headers, rows):
    """Build an in-memory A4 PDF table (landscape when wide); returns bytes."""
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
    from reportlab.lib.units import mm
    from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    style = getSampleStyleSheet()
    heading = style['Heading2']
    heading.alignment = 1

    # Separate style objects: sharing style['BodyText'] between body and
    # header made the white header textColor apply to body cells too.
    cell_style = ParagraphStyle(
        'ExportCell',
        parent=style['BodyText'],
        fontSize=8,
        leading=10,
        spaceAfter=0,
        textColor=colors.black,
    )

    header_style = ParagraphStyle(
        'ExportHeader',
        parent=style['BodyText'],
        fontSize=8,
        leading=10,
        spaceAfter=0,
        fontName='Helvetica-Bold',
        textColor=colors.white,
    )

    page_size = landscape(A4) if len(headers) > 5 else A4
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=page_size,
        leftMargin=12 * mm,
        rightMargin=12 * mm,
        topMargin=14 * mm,
        bottomMargin=14 * mm,
        title=title,
    )

    usable = doc.width
    col_widths = []
    for idx in range(len(headers)):
        sample_max = max([len(str(headers[idx]))] + [len(str(r[idx])) for r in rows[:50]] or [1])
        col_widths.append(max(sample_max, 8))
    total = sum(col_widths)
    col_widths = [usable * w / total for w in col_widths]

    table_rows = [[Paragraph(str(h), header_style) for h in headers]]
    for row in rows:
        table_rows.append([Paragraph('' if v is None else str(v), cell_style) for v in row])

    table = Table(table_rows, colWidths=col_widths, repeatRows=1)
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#007C91')),
        ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#B8C4CC')),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F2F7F9')]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
        ('LEFTPADDING', (0, 0), (-1, -1), 4),
        ('RIGHTPADDING', (0, 0), (-1, -1), 4),
    ]))

    doc.build([Paragraph(title, heading), Spacer(1, 6), table])
    return buffer.getvalue()


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_export(request, dataset, file_format):
    """
    Admin: export details as PDF or Excel.

    GET /api/v1/admin/export/<dataset>/<format>/
      dataset: students | teachers | classes | attendance
      format:  pdf | xlsx
    Optional query param for attendance: ?semester=<label>
    """
    if request.user.role != 'admin':
        return Response({'error': 'Forbidden'}, status=status.HTTP_403_FORBIDDEN)

    if file_format not in ('pdf', 'xlsx'):
        return Response({'error': 'Invalid format'}, status=status.HTTP_400_BAD_REQUEST)

    if dataset == 'students':
        title = 'Student Details'
        headers = ['ID', 'Username', 'Full Name', 'Email', 'Semester', 'Classes', 'Status']
        rows = []
        for u in User.objects.filter(role='student').order_by('username'):
            profile = getattr(u, 'student_profile', None)
            semester = (profile.semester if profile else '') or '—'
            codes = ', '.join(
                e.class_obj.class_code for e in u.enrolled_classes.select_related('class_obj')
            ) or '—'
            rows.append([
                u.id, u.username, u.get_full_name() or u.username, u.email,
                semester, codes, 'Active' if u.is_active else 'Blocked',
            ])
    elif dataset == 'teachers':
        title = 'Teacher Details'
        headers = ['ID', 'Username', 'Full Name', 'Email', 'Classes Taught', 'Status']
        rows = []
        for u in User.objects.filter(role='teacher').order_by('username'):
            codes = ', '.join(c.class_code for c in u.classes_taught.all()) or '—'
            rows.append([
                u.id, u.username, u.get_full_name() or u.username, u.email,
                codes, 'Active' if u.is_active else 'Blocked',
            ])
    elif dataset == 'classes':
        title = 'Class Details'
        headers = ['Code', 'Name', 'Semester', 'Teacher', 'Students', 'Sessions']
        rows = []
        for c in Class.objects.select_related('teacher').all().order_by('class_code'):
            rows.append([
                c.class_code, c.class_name, c.semester,
                c.teacher.get_full_name() or c.teacher.username,
                c.student_count, c.sessions.count(),
            ])
    elif dataset == 'attendance':
        semester = (request.query_params.get('semester') or '').strip()
        title = 'Attendance Details' + (f' - Semester {semester}' if semester else '')
        headers = ['Semester', 'Class', 'Date', 'Time', 'Teacher', 'Student', 'Email', 'Status']
        records = (
            AttendanceRecord.objects
            .select_related('session__class_obj', 'session__teacher', 'student')
            .order_by('session__start_time', 'marked_at')
        )
        if semester:
            records = records.filter(session__class_obj__semester=semester)
        rows = []
        for r in records:
            session = r.session
            rows.append([
                session.class_obj.semester,
                session.class_obj.class_code,
                timezone.localtime(session.start_time).strftime('%d %b %Y'),
                timezone.localtime(r.marked_at).strftime('%H:%M'),
                session.teacher.username,
                r.student.username,
                r.student.email,
                (r.status or '').replace('_', ' ').title() or '—',
            ])
    else:
        return Response({'error': 'Invalid dataset'}, status=status.HTTP_400_BAD_REQUEST)

    stamp = timezone.localtime().strftime('%Y%m%d_%H%M')
    filename = f'{dataset}_details_{stamp}.{file_format}'

    if file_format == 'xlsx':
        content = _build_workbook(title, headers, rows)
        content_type = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    else:
        content = _build_pdf(title, headers, rows)
        content_type = 'application/pdf'

    from django.http import HttpResponse
    response = HttpResponse(content, content_type=content_type)
    response['Content-Disposition'] = f'attachment; filename="{filename}"'
    return response
