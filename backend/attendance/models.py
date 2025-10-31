from django.db import models
from django.contrib.auth.models import AbstractUser
import uuid

# Create your models here.

class User(AbstractUser):
    ROLE_CHOICES = (
        ('student', 'Student'),
        ('teacher', 'Teacher'),
        ('admin', 'Admin')
   )
    email = models.EmailField(unique=True, blank=False)  # Add blank=False explicitly
    role = models.CharField(max_length=10, choices=ROLE_CHOICES, default='student')

    def __str__(self):
        return f"{self.username} ({self.role})"
    
    class Meta:
        db_table = 'users' #Table name in PostgreSQL


class StudentProfile(models.Model):
    """Table for student roll numbers and student specific data"""
    student = models.OneToOneField(
        User, 
        on_delete=models.CASCADE,
        primary_key=True,  # Keep this as the only primary key
        related_name='student_profile',
        limit_choices_to={'role': 'student'}
    )
    roll_no = models.CharField(max_length=20, unique=True)

    class Meta:
        db_table = 'student_profiles'  # Table name in PostgreSQL

    def __str__(self):
        return f"{self.student.username} - {self.roll_no}"
    
class Class(models.Model):
    """Table for class/course information"""
    class_code = models.CharField(max_length=20, unique=True)
    class_name = models.CharField(max_length=200)
    semester = models.CharField(max_length=50)
    teacher = models.ForeignKey(User, on_delete=models.CASCADE, related_name='classes_taught', limit_choices_to={'role': 'teacher'})
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'classes'  # Table name in PostgreSQL
        verbose_name_plural = 'Classes'
        ordering = ['class_code']

    def __str__(self):
        return f"{self.class_code} - {self.class_name}"
    
    @property
    def teacher_name(self):
        return self.teacher.username or self.teacher.get_full_name()
    
    @property
    def student_count(self):
        return self.enrollments.count()
    
class Enrollment(models.Model):
    """Table for student enrollments in classes"""
    class_obj = models.ForeignKey(Class, on_delete=models.CASCADE, related_name='enrollments')
    student = models.ForeignKey(User, on_delete=models.CASCADE, related_name='enrolled_classes', limit_choices_to={'role': 'student'})
    enrolled_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'enrollments'  # Table name in PostgreSQL
        unique_together = ('class_obj', 'student')
        ordering = ['class_obj', 'student']

    def __str__(self):
        return f"{self.student.username} enrolled in {self.class_obj.class_code}"


# AttendanceSession
class AttendanceSession(models.Model):
    """Table for attendance sessions with QR codes"""
    STATUS_CHOICES = (
        ('active', 'Active'),
        ('expired', 'Expired'),
        ('completed', 'Completed'),
    )
    
    session_id = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    class_obj = models.ForeignKey(Class, on_delete=models.CASCADE, related_name='sessions')
    teacher = models.ForeignKey(User, on_delete=models.CASCADE, related_name='created_sessions')
    
    start_time = models.DateTimeField(auto_now_add=True)
    duration_minutes = models.IntegerField()  # Duration in minutes
    end_time = models.DateTimeField()  # Calculated: start_time + duration
    
    qr_code_data = models.TextField()  # JSON string with session info
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='active')
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'attendance_sessions'
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.class_obj.class_code} - {self.start_time.strftime('%Y-%m-%d %H:%M')}"
    
    @property
    def is_active(self):
        """Check if session is still active"""
        from django.utils import timezone
        return self.status == 'active' and timezone.now() < self.end_time


# Attendance Record
class AttendanceRecord(models.Model):
    """Table for individual attendance records"""
    session = models.ForeignKey(AttendanceSession, on_delete=models.CASCADE, related_name='records')
    student = models.ForeignKey(User, on_delete=models.CASCADE, related_name='attendance_records')
    
    marked_at = models.DateTimeField(auto_now_add=True)
    status = models.CharField(
        max_length=10,
        choices=(('present', 'Present'), ('absent', 'Absent')),
        default='present'
    )
    
    class Meta:
        db_table = 'attendance_records'
        unique_together = ('session', 'student')
        ordering = ['marked_at']

    def __str__(self):
        return f"{self.student.username} - {self.session.class_obj.class_code} - {self.status}"