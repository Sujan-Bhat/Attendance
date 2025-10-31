"""
URL configuration for attend_backend project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path, include
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
    # Session views
    create_session,
    get_active_sessions,
    get_session_details,
    mark_attendance,
    end_session,
)
from rest_framework_simplejwt.views import TokenRefreshView

urlpatterns = [
    path('admin/', admin.site.urls),
    
    # JWT Authentication
    path('api/v1/auth/token/', MyTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/v1/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    
    # User management
    path('api/v1/auth/register/', RegisterView.as_view(), name='register'),
    path('api/v1/auth/me/', MeView.as_view(), name='me'),
    
    # Class management
    path('api/v1/classes/', class_list_create, name='class_list_create'),
    path('api/v1/classes/<int:class_id>/', class_detail, name='class_detail'),
    path('api/v1/classes/<int:class_id>/students/', get_class_students, name='class_students'),
    path('api/v1/classes/<int:class_id>/add-student/', add_student_to_class, name='add_student'),
    path('api/v1/classes/<int:class_id>/remove-student/<int:student_id>/', remove_student_from_class, name='remove_student'),
    
    # Session management
    path('api/v1/sessions/create/', create_session, name='create_session'),
    path('api/v1/sessions/active/', get_active_sessions, name='active_sessions'),
    path('api/v1/sessions/<uuid:session_id>/', get_session_details, name='session_details'),
    path('api/v1/sessions/<uuid:session_id>/mark/', mark_attendance, name='mark_attendance'),
    path('api/v1/sessions/<uuid:session_id>/end/', end_session, name='end_session'),
    
    # Utility
    path('api/v1/ping/', ping, name='ping'),
]
