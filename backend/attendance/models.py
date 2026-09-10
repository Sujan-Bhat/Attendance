from django.db import models
from django.contrib.auth.models import AbstractUser
import uuid

class User(AbstractUser):
    ROLE_CHOICES = (
        ('student', 'Student'),
        ('teacher', 'Teacher'),
        ('admin', 'Admin')
    )
    email = models.EmailField(unique=True, blank=False)
    role = models.CharField(max_length=10, choices=ROLE_CHOICES, default='student')

    USERNAME_FIELD = 'email'  # Use email for authentication instead of username
    REQUIRED_FIELDS = ['username']  # Username becomes optional field

    def __str__(self):
        return f"{self.username} ({self.role})"
    
    class Meta:
        db_table = 'users'


class StudentProfile(models.Model):
    """Table for student roll numbers and student specific data"""
    student = models.OneToOneField(
        User, 
        on_delete=models.CASCADE,
        primary_key=True,  # Keep this as the only primary key
        related_name='student_profile',
        limit_choices_to={'role': 'student'}
    )
    semester = models.CharField(max_length=50, blank=True, null=True)

    class Meta:
        db_table = 'student_profiles'  # Table name in PostgreSQL

    def __str__(self):
        return f"{self.student.username}"

    
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
    
    CLASS_TYPE_CHOICES = (
        ('qr', 'QR'),
        ('pattern', 'Pattern'),
    )
    

    session_id = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    class_obj = models.ForeignKey(Class, on_delete=models.CASCADE, related_name='sessions')
    teacher = models.ForeignKey(User, on_delete=models.CASCADE, related_name='created_sessions')
    
    class_type = models.CharField(max_length=10, choices=CLASS_TYPE_CHOICES, default='qr')
    totp_secret = models.CharField(max_length=64, blank=True, null=True)
    rotation_interval = models.IntegerField(default=10)

    pattern_code = models.CharField(max_length=50, blank=True, null=True)
    instruction_card = models.TextField(blank=True, null=True)
    shape_data = models.JSONField(blank=True, null=True)
    
    from django.utils import timezone
    start_time = models.DateTimeField(default=timezone.now)
    duration_minutes = models.IntegerField()  # Duration in minutes
    end_time = models.DateTimeField()  # Calculated: start_time + duration
    
    qr_code_data = models.TextField()  # JSON string with session info
    reference_image = models.ImageField(
        upload_to='session_references/%Y/%m/%d/',
        blank=True,
        null=True,
    )
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
        max_length=20,
        choices=(('present', 'Present'), ('absent', 'Absent'), ('pending_review', 'Pending Review')),
        default='present'
    )
    
    verification_score = models.FloatField(null=True, blank=True)
    verification_reasons = models.TextField(null=True, blank=True)  # Store JSON string of reasons
    
    class Meta:
        db_table = 'attendance_records'
        unique_together = ('session', 'student')
        ordering = ['marked_at']

    def __str__(self):
        return f"{self.student.username} - {self.session.class_obj.class_code} - {self.status}"


class Announcement(models.Model):
    TARGET_TYPE_CHOICES = (
        ('class', 'Class'),
        ('individual', 'Individual'),
        ('low_attendance', 'Low Attendance'),
    )

    sender = models.ForeignKey(User, on_delete=models.CASCADE, related_name='sent_announcements', limit_choices_to={'role': 'teacher'})
    title = models.CharField(max_length=200)
    content = models.TextField()
    
    target_type = models.CharField(max_length=20, choices=TARGET_TYPE_CHOICES, default='class')
    target_class = models.ForeignKey(Class, on_delete=models.CASCADE, related_name='announcements', null=True, blank=True)
    min_attendance_threshold = models.IntegerField(null=True, blank=True)
    
    is_urgent = models.BooleanField(default=False)
    recipients = models.ManyToManyField(User, related_name='announcements_received')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'announcements'
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.title} by {self.sender.username}"