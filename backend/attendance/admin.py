from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, StudentProfile, Class, Enrollment

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
    search_fields = ('student_name__username', 'roll_no', 'student_name__email')  # Fixed: was 'user__'
    
    def get_username(self, obj):
        return obj.student_name.username  # Fixed: was obj.user.username
    get_username.short_description = 'Username'
    
    def get_email(self, obj):
        return obj.student_name.email  # Fixed: was obj.user.email
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
