from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, StudentProfile, Class, Enrollment, AttendanceSession, AttendanceRecord

@admin.register(User)
class UserAdmin(BaseUserAdmin):
    list_display = ('username', 'email', 'role', 'is_active', 'is_staff')
    list_filter = ('role', 'is_active', 'is_staff')
    search_fields = ('username', 'email')
    
    fieldsets = BaseUserAdmin.fieldsets + (
        ('Role', {'fields': ('role',)}),
    )
    add_fieldsets = BaseUserAdmin.add_fieldsets + (
        ('Role', {'fields': ('role',)}),
    )


@admin.register(StudentProfile)
class StudentProfileAdmin(admin.ModelAdmin):
    list_display = ('get_username', 'roll_no', 'get_email')
    search_fields = ('student__username', 'roll_no', 'student__email')  # Fixed: was 'user__'
    
    def get_username(self, obj):
        return obj.student.username  # Fixed: was obj.user.username
    get_username.short_description = 'Username'
    
    def get_email(self, obj):
        return obj.student.email  # Fixed: was obj.user.email
    get_email.short_description = 'Email'


class EnrollmentInline(admin.TabularInline):  # Fixed: was ClassEnrollmentInline
    model = Enrollment
    extra = 1
    raw_id_fields = ('student',)


@admin.register(Class)
class ClassAdmin(admin.ModelAdmin):
    list_display = ('class_code', 'class_name', 'semester', 'teacher', 'get_student_count', 'created_at')
    list_filter = ('semester', 'created_at')
    search_fields = ('class_code', 'class_name', 'teacher__username')
    inlines = [EnrollmentInline]
    
    def get_student_count(self, obj):
        return obj.student_count
    get_student_count.short_description = 'Students'


@admin.register(Enrollment)  # Fixed: was ClassEnrollment
class EnrollmentAdmin(admin.ModelAdmin):
    list_display = ('class_obj', 'student', 'enrolled_at')
    list_filter = ('enrolled_at', 'class_obj')
    search_fields = ('class_obj__class_code', 'student__username')
    raw_id_fields = ('class_obj', 'student')


# @admin.register(AttendanceSession)
# class AttendanceSessionAdmin(admin.ModelAdmin):
#     list_display = ('class_obj', 'date', 'start_time', 'end_time', 'qr_code_generated', 'created_at')
#     list_filter = ('date', 'qr_code_generated', 'created_at')
#     search_fields = ('class_obj__class_code', 'class_obj__class_name')
#     readonly_fields = ('qr_code', 'created_at')
#     ordering = ['-date', '-start_time']
    
#     def get_queryset(self, request):
#         qs = super().get_queryset(request)
#         return qs.select_related('class_obj', 'class_obj__teacher')


@admin.register(AttendanceSession)
class AttendanceSessionAdmin(admin.ModelAdmin):
    list_display = ('session_id', 'class_obj', 'teacher', 'start_time', 'end_time', 'status', 'is_active')
    list_filter = ('status', 'start_time', 'class_obj')
    search_fields = ('class_obj__class_code', 'class_obj__class_name', 'teacher__username')
    readonly_fields = ('session_id', 'created_at', 'updated_at', 'qr_code_data')
    ordering = ['-start_time']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        return qs.select_related('class_obj', 'teacher')


@admin.register(AttendanceRecord)
class AttendanceRecordAdmin(admin.ModelAdmin):
    list_display = ('get_student_name', 'get_class_code', 'get_session_date', 'status', 'marked_at')
    list_filter = ('status', 'marked_at', 'session__start_time')
    search_fields = ('student__username', 'student__email', 'session__class_obj__class_code')
    readonly_fields = ('marked_at',)
    ordering = ['-marked_at']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        return qs.select_related('student', 'session', 'session__class_obj')
    
    def get_student_name(self, obj):
        return obj.student.username
    get_student_name.short_description = 'Student'
    
    def get_class_code(self, obj):
        return obj.session.class_obj.class_code
    get_class_code.short_description = 'Class'
    
    def get_session_date(self, obj):
        return obj.session.start_time.strftime('%Y-%m-%d %H:%M')
    get_session_date.short_description = 'Session Date/Time'
