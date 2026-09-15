from django.contrib import admin
from django.urls import path
from django.conf import settings
from django.conf.urls.static import static
from django.views.generic import TemplateView
from django.contrib.staticfiles.views import serve
import os
from attendance.views import (
    RegisterView,
    MeView,
    MyTokenObtainPairView,
    ping,
    class_list_create,
    class_detail,
    get_class_students,
    add_student_to_class,
    remove_student_from_class,
    create_session,
    get_active_sessions,
    get_session_details,
    mark_attendance,
    end_session,
    get_student_enrolled_classes,
    get_student_attendance_history,
    check_student_by_email,
    update_student_in_class,
    get_teacher_attendance_history,
    get_session_attendance_details,
    update_attendance_status,
    manual_mark_attendance,
    verify_image,
    upload_reference_image,
    get_student_active_sessions,
    join_class_by_code,
    assetlinks_json,
    sync_offline_pattern,
    sync_offline_session,
    cancel_session,
    mark_all_present_session,
    edit_session,
    update_session_attendance,
    announcements_list_create,
    announcement_detail,
    register_face,
    verify_face_auth,
)
from rest_framework_simplejwt.views import TokenRefreshView
from django.views.static import serve as static_serve
from django.urls import re_path

from attendance.admin_bulk_views import (
    admin_bulk_validate_students,
    admin_bulk_validate_rows,
    admin_bulk_create_students,
)
from attendance.admin_views import (
    admin_classes_summary,
    admin_semester_classes,
    admin_semester_students,
    admin_unassigned_students,
    admin_teachers_list,
    admin_update_teacher,
    admin_stats,
    admin_users_list,
    admin_toggle_user_access,
    admin_create_user,
    admin_delete_user,
    admin_update_class,
    admin_class_detail,
    admin_remove_student_from_class,
    admin_update_student,
    admin_delete_student,
    admin_delete_all_students,
    admin_attendance_semesters,
    admin_attendance_by_semester,
)

FLUTTER_WEB_DIR = os.path.join(settings.BASE_DIR, 'flutter_web')

def serve_flutter(request, path=''):
    file_path = os.path.join(FLUTTER_WEB_DIR, path)
    if path and os.path.exists(file_path) and os.path.isfile(file_path):
        response = static_serve(request, path, document_root=FLUTTER_WEB_DIR)
    else:
        path = 'index.html'
        response = static_serve(request, path, document_root=FLUTTER_WEB_DIR)
    # Flutter's web assets (main.dart.js, flutter_bootstrap.js, index.html, and
    # the files under /assets/ and /canvaskit/) are requested at stable URLs
    # that do NOT change between builds. Force the browser to always revalidate
    # against the server so every build is picked up immediately without manual
    # cache clearing (an earlier stale-cache bug kept showing an old build).
    response['Cache-Control'] = 'no-cache'
    return response

urlpatterns = [
    path('.well-known/assetlinks.json', assetlinks_json, name='assetlinks'),
    path('admin/', admin.site.urls),

    # JWT Authentication
    path('api/v1/auth/token/', MyTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/v1/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),

    # User management
    path('api/v1/auth/register/', RegisterView.as_view(), name='register'),
    path('api/v1/auth/me/', MeView.as_view(), name='me'),
    path('api/v1/auth/check-student/', check_student_by_email, name='check-student'),

    # Class management (Teacher)
    path('api/v1/classes/', class_list_create, name='class_list_create'),
    path('api/v1/classes/<int:class_id>/', class_detail, name='class_detail'),
    path('api/v1/classes/<int:class_id>/students/', get_class_students, name='class_students'),
    path('api/v1/classes/<int:class_id>/add-student/', add_student_to_class, name='add_student'),
    path('api/v1/classes/<int:class_id>/remove-student/<int:student_id>/', remove_student_from_class, name='remove_student'),
    path('api/v1/classes/<int:class_id>/update-student/<int:student_id>/', update_student_in_class, name='update_student'),
    path('api/v1/classes/join/', join_class_by_code, name='join_class_by_code'),

    # Student enrolled classes
    path('api/v1/students/my-classes/', get_student_enrolled_classes, name='student_enrolled_classes'),
    path('api/v1/students/my-attendance/', get_student_attendance_history, name='student_attendance_history'),

    # Session management
    path('api/v1/sessions/create/', create_session, name='create_session'),
    path('api/v1/sessions/verify-image/', verify_image, name='verify_image'),
    path('api/v1/sessions/sync-offline-pattern/', sync_offline_pattern, name='sync_offline_pattern'),
    path('api/v1/sessions/sync-offline-session/', sync_offline_session, name='sync_offline_session'),
    path('api/v1/sessions/<uuid:session_id>/upload-reference/', upload_reference_image, name='upload_reference_image'),
    path('api/v1/sessions/active/', get_active_sessions, name='active_sessions'),
    path('api/v1/sessions/student-active/', get_student_active_sessions, name='student_active_sessions'),
    path('api/v1/sessions/<uuid:session_id>/', get_session_details, name='session_details'),
    path('api/v1/sessions/<uuid:session_id>/mark/', mark_attendance, name='mark_attendance'),
    path('api/v1/sessions/<uuid:session_id>/end/', end_session, name='end_session'),
    path('api/v1/sessions/<uuid:session_id>/delete/', cancel_session, name='cancel_session'),
    path('api/v1/sessions/<uuid:session_id>/mark-all-present/', mark_all_present_session, name='mark_all_present_session'),
    path('api/v1/sessions/<uuid:session_id>/edit/', edit_session, name='edit_session'),
    path('api/v1/sessions/<uuid:session_id>/attendance/update-bulk/', update_session_attendance, name='update_session_attendance'),

    # Manual mark attendance
    path('api/v1/sessions/<uuid:session_id>/mark-student/', manual_mark_attendance, name='manual_mark_attendance'),

    # Teacher attendance history
    path('api/v1/teachers/attendance-history/', get_teacher_attendance_history, name='teacher_attendance_history'),
    path('api/v1/attendance/<int:record_id>/update/', update_attendance_status, name='update_attendance'),
    path('api/v1/sessions/<uuid:session_id>/attendance/', get_session_attendance_details, name='session_attendance_details'),

    # Announcements
    path('api/v1/announcements/', announcements_list_create, name='announcements'),
    path('api/v1/announcements/<int:pk>/', announcement_detail, name='announcement_detail'),

    # Utility
    path('api/v1/ping/', ping, name='ping'),

    # Face Auth
    path('api/v1/faces/register/', register_face, name='register_face'),
    path('api/v1/faces/verify/', verify_face_auth, name='verify_face_auth'),

    # Admin API (from teacher branch, adapted — no roll_no)
    path('api/v1/admin/classes/summary/', admin_classes_summary, name='admin_classes_summary'),
    path('api/v1/admin/classes/by-semester/<str:semester>/', admin_semester_classes, name='admin_semester_classes'),
    path('api/v1/admin/students/by-semester/<str:semester>/', admin_semester_students, name='admin_semester_students'),
    path('api/v1/admin/students/unassigned/', admin_unassigned_students, name='admin_unassigned_students'),
    path('api/v1/admin/students/bulk/validate/', admin_bulk_validate_students, name='admin_bulk_validate_students'),
    path('api/v1/admin/students/bulk/validate-rows/', admin_bulk_validate_rows, name='admin_bulk_validate_rows'),
    path('api/v1/admin/students/bulk/create/', admin_bulk_create_students, name='admin_bulk_create_students'),
    path('api/v1/admin/teachers/', admin_teachers_list, name='admin_teachers_list'),
    path('api/v1/admin/stats/', admin_stats, name='admin_stats'),
    path('api/v1/admin/users/create/', admin_create_user, name='admin_create_user'),
    path('api/v1/admin/users/<str:role>/', admin_users_list, name='admin_users_list'),
    path('api/v1/admin/users/<int:user_id>/toggle-access/', admin_toggle_user_access, name='admin_toggle_user_access'),
    path('api/v1/admin/users/<int:user_id>/delete/', admin_delete_user, name='admin_delete_user'),
    path('api/v1/admin/students/<int:student_id>/update/', admin_update_student, name='admin_update_student'),
    path('api/v1/admin/students/<int:student_id>/delete/', admin_delete_student, name='admin_delete_student'),
    path('api/v1/admin/students/delete-all/<str:semester>/', admin_delete_all_students, name='admin_delete_all_students'),
    path('api/v1/admin/teachers/<int:teacher_id>/update/', admin_update_teacher, name='admin_update_teacher'),
    path('api/v1/admin/classes/<int:class_id>/update/', admin_update_class, name='admin_update_class'),
    path('api/v1/admin/classes/<int:class_id>/detail/', admin_class_detail, name='admin_class_detail'),
    path('api/v1/admin/classes/<int:class_id>/remove-student/<int:student_id>/', admin_remove_student_from_class, name='admin_remove_student'),

    # Admin attendance management
    path('api/v1/admin/attendance/semesters/', admin_attendance_semesters, name='admin_attendance_semesters'),
    path('api/v1/admin/attendance/by-semester/<str:semester>/', admin_attendance_by_semester, name='admin_attendance_by_semester'),

    # Flutter Web — must be last
    re_path(r'^(?P<path>.*)$', serve_flutter, name='flutter_web'),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
