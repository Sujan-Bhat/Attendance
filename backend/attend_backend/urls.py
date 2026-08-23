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
    get_pending_classes,
    join_class,
    join_fallback,
    assetlinks_view,
    announcement_list_create,
    announcement_detail,
    student_announcements,
    low_attendance_students,
)
from rest_framework_simplejwt.views import TokenRefreshView
from django.views.static import serve as static_serve
from django.urls import re_path

FLUTTER_WEB_DIR = os.path.join(settings.BASE_DIR, 'flutter_web')

def serve_flutter(request, path=''):
    file_path = os.path.join(FLUTTER_WEB_DIR, path)
    if path and os.path.exists(file_path) and os.path.isfile(file_path):
        return static_serve(request, path, document_root=FLUTTER_WEB_DIR)
    return static_serve(request, 'index.html', document_root=FLUTTER_WEB_DIR)

urlpatterns = [
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

    # Student enrolled classes
    path('api/v1/students/my-classes/', get_student_enrolled_classes, name='student_enrolled_classes'),
    path('api/v1/students/pending-classes/', get_pending_classes, name='student_pending_classes'),
    path('api/v1/students/join-class/', join_class, name='join_class'),
    path('api/v1/students/my-attendance/', get_student_attendance_history, name='student_attendance_history'),

    # Session management
    path('api/v1/sessions/create/', create_session, name='create_session'),
    path('api/v1/sessions/verify-image/', verify_image, name='verify_image'),
    path('api/v1/sessions/<uuid:session_id>/upload-reference/', upload_reference_image, name='upload_reference_image'),
    path('api/v1/sessions/active/', get_active_sessions, name='active_sessions'),
    path('api/v1/sessions/student-active/', get_student_active_sessions, name='student_active_sessions'),
    path('api/v1/sessions/<uuid:session_id>/', get_session_details, name='session_details'),
    path('api/v1/sessions/<uuid:session_id>/mark/', mark_attendance, name='mark_attendance'),
    path('api/v1/sessions/<uuid:session_id>/end/', end_session, name='end_session'),

    # Manual mark attendance
    path('api/v1/sessions/<uuid:session_id>/mark-student/', manual_mark_attendance, name='manual_mark_attendance'),

    # Teacher attendance history
    path('api/v1/teachers/attendance-history/', get_teacher_attendance_history, name='teacher_attendance_history'),
    path('api/v1/attendance/<int:record_id>/update/', update_attendance_status, name='update_attendance'),
    path('api/v1/sessions/<uuid:session_id>/attendance/', get_session_attendance_details, name='session_attendance_details'),

    # Announcements
    path('api/v1/announcements/', announcement_list_create, name='announcement_list_create'),
    path('api/v1/announcements/<int:announcement_id>/', announcement_detail, name='announcement_detail'),
    path('api/v1/students/announcements/', student_announcements, name='student_announcements'),
    path('api/v1/classes/<int:class_id>/low-attendance/', low_attendance_students, name='low_attendance_students'),

    # Utility
    path('api/v1/ping/', ping, name='ping'),

    # Deep Link Fallback (handles with or without trailing slash)
    re_path(r'^join/(?P<code>[^/]+)/?$', join_fallback, name='join_fallback'),

    # Android App Links (assetlinks.json)
    path('.well-known/assetlinks.json', assetlinks_view, name='assetlinks'),

    # Flutter Web — must be last
    re_path(r'^(?P<path>.*)$', serve_flutter, name='flutter_web'),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
