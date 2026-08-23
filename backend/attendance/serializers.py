from rest_framework import serializers
from django.contrib.auth import get_user_model, authenticate
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from .models import StudentProfile, Class, Enrollment, AttendanceSession, AttendanceRecord, Announcement
import json
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

User = get_user_model()

class UserSerializer(serializers.ModelSerializer):
    """ Read only serializer for User model """
    class Meta:
        model = User
        fields = ('id', 'username', 'email', 'role', 'is_staff','is_active')
        read_only_fields = ('id', 'is_staff','is_active')

class RegistrationSerializer(serializers.ModelSerializer):
    """Serializer for user registration - username only system."""
    password = serializers.CharField(
        write_only=True, 
        required=True, 
        min_length=6,
        style={'input_type': 'password'},
        error_messages={'min_length': 'Password must be at least 6 characters long.'}
    )
    password2 = serializers.CharField(
        write_only=True, 
        required=True, 
        label='Confirm password',
        style={'input_type': 'password'}
    )

    class Meta:
        model = User
        fields = ('username', 'email', 'role', 'password', 'password2')
        extra_kwargs = {'email': {'required': True}}
    
    def validate_email(self, value):
        """Step 1 : Check if email already exists"""
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("A user with this email already exists.")
        return value
    
    def validate(self, data):
        """ Step 2 : Check if passwords match and validate password """
        if data['password'] != data['password2']:
            raise serializers.ValidationError({"password2": "Password fields didn't match."})
        try:
            validate_password(data['password'])
        except DjangoValidationError as e:
            raise serializers.ValidationError({"password": list(e.messages)})
        return data
    
    def create(self, validated_data):
        """Step 4: Create the user"""
        validated_data.pop('password2', None)   #Remove password2 as it not required in database
        password = validated_data.pop('password')

        #Create user instance
        user = User(**validated_data)

        #Hash the password
        user.set_password(password)
        
        if user.role == 'admin':
            user.is_staff = True
            user.is_superuser = False
        
        user.save()
        return user


class LoginSerializer(serializers.Serializer):
    """ Serializer for user login """
    email = serializers.EmailField(required=True)  
    password = serializers.CharField(required=True, write_only=True)

    def validate(self, data):
        email = data.get('email')  
        password = data.get('password')

        if email and password:
            
            user = authenticate(username=email, password=password)  # Django uses 'username' param even for email
            if user:
                if user.is_active:
                    data['user'] = user
                else:
                    raise serializers.ValidationError("User account is disabled.")
            else:
                raise serializers.ValidationError("Invalid email or password.")  # ✅ CHANGED message
        else:
            raise serializers.ValidationError("Email and password are required.")  # ✅ CHANGED message

        return data

# Serializer for Class Management

class StudentProfileSerializer(serializers.ModelSerializer):
    """Serializers for StudentProfile model"""
    username = serializers.CharField(source='student.username', read_only=True)
    email = serializers.EmailField(source='student.email', read_only=True)

    class Meta:
        model = StudentProfile
        fields = ('student', 'username', 'email', 'roll_no')
        read_only_fields = ('student',)


class StudentCreateSerializer(serializers.Serializer):  # Changed from ModelSerializer
    """Serializer for creating Student during class creation"""
    name = serializers.CharField(max_length=150)
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, min_length=6, style={'input_type': 'password'})
    rollNo = serializers.CharField(max_length=20)

    def validate_email(self, value):
        """Check if email already exists"""
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError(f"Email {value} already exists.")
        return value
    
    def validate_rollNo(self, value):
        """Check if roll number already exists"""
        if StudentProfile.objects.filter(roll_no=value).exists():
            raise serializers.ValidationError(f"Roll number {value} already exists.")
        return value


class StudentDetailSerializer(serializers.ModelSerializer):
    """Serializer for student details in class"""
    username = serializers.CharField(source='student.username', read_only=True)  # Fixed: was 'student.username'
    email = serializers.EmailField(source='student.email', read_only=True)  # Fixed: was 'student.email'
    roll_no = serializers.CharField(read_only=True)
    user_id = serializers.IntegerField(source='student.id', read_only=True)  # Fixed: was 'student.id'

    class Meta:
        model = StudentProfile
        fields = ('user_id', 'username', 'email', 'roll_no')


class ClassSerializer(serializers.ModelSerializer):
    """Serializer for Class model"""
    teacher_name = serializers.ReadOnlyField()
    student_count = serializers.ReadOnlyField()
    students = serializers.SerializerMethodField()

    class Meta:
        model = Class
        fields = ['id', 'class_code', 'class_name', 'semester', 'teacher', 'teacher_name', 'student_count', 'students', 'created_at', 'updated_at']
        read_only_fields = ('id', 'teacher', 'created_at', 'updated_at')

    def get_students(self, obj):
        """Get enrolled students with their details"""
        enrollments = obj.enrollments.select_related('student__student_profile')
        students = []
        for enrollment in enrollments:
            student = enrollment.student
            try:
                profile = student.student_profile
                students.append({
                    'user_id': student.id,
                    'username': student.username,
                    'email': student.email,
                    'roll_no': profile.roll_no
                })
            except StudentProfile.DoesNotExist:
                students.append({
                    'user_id': student.id,
                    'username': student.username,
                    'email': student.email,
                    'roll_no': 'N/A'
                })
        return students


class ClassListSerializer(serializers.ModelSerializer):
    """Serializer for listing classes with minimal details"""
    teacher_name = serializers.ReadOnlyField()
    student_count = serializers.ReadOnlyField()

    class Meta:
        model = Class
        fields = ['id', 'class_code', 'class_name', 'semester', 'teacher_name', 'student_count', 'created_at']


class CreateClassSerializer(serializers.Serializer):  # Changed from ModelSerializer
    """Serializer for creating a class"""
    name = serializers.CharField(max_length=200)
    semester = serializers.CharField(max_length=50)
    students = StudentCreateSerializer(many=True, write_only=True, required=False)

    def create(self, validated_data):
        from django.db import transaction
        import uuid
        import re

        students_data = validated_data.pop('students', [])
        teacher = self.context['request'].user

        with transaction.atomic():
            # Generate a unique class code: s<semester><cleaned_topic>
            sem = validated_data['semester'].strip()
            # Extract digits from semester (e.g. "Semester 7" -> "7")
            digits = re.sub(r'[^0-9]', '', sem)
            clean_sem = digits if digits else re.sub(r'[^a-zA-Z0-9]', '', sem).lower()
            
            # Try to extract the topic from "Sem X - Topic"
            topic = validated_data['name']
            if ' - ' in topic:
                topic = topic.split(' - ', 1)[1]
            
            # Clean topic: remove spaces and non-alphanumeric, convert to lowercase
            clean_topic = re.sub(r'[^a-zA-Z0-9]', '', topic).lower()
            
            # Use first 4 characters of the topic for brevity
            topic_abbr = clean_topic[:4] if len(clean_topic) > 4 else clean_topic
            
            base_code = f"s{clean_sem}{topic_abbr}"
            
            # Ensure it is unique by checking DB, append short uuid if needed
            final_code = base_code
            if Class.objects.filter(class_code__iexact=final_code).exists():
                final_code = f"{base_code}{uuid.uuid4().hex[:4]}"
            
            # Create the class
            class_obj = Class.objects.create(
                teacher=teacher,
                class_code=final_code,
                class_name=validated_data['name'],
                semester=validated_data['semester']
            )

            # Create student enrollments
            created_students = []
            for student_data in students_data:
                # Generate unique username from email
                email = student_data['email']
                username = email.split('@')[0]
                base_username = username
                counter = 1
                while User.objects.filter(username=username).exists():
                    username = f"{base_username}{counter}"
                    counter += 1
                
                # Create User
                user = User.objects.create_user(
                    username=username,
                    email=email,
                    role='student',
                    password=student_data['password']
                )
                
                # Create StudentProfile
                StudentProfile.objects.create(
                    student=user,
                    roll_no=student_data['rollNo']
                )
                
                # Create Enrollment
                Enrollment.objects.create(
                    class_obj=class_obj,
                    student=user
                )
                
                created_students.append(user)

            return {
                'class': class_obj,
                'students': created_students
            }


class CreateSessionSerializer(serializers.Serializer):
    """Serializer for creating attendance session"""
    class_id = serializers.IntegerField()
    duration_minutes = serializers.IntegerField(min_value=1, max_value=300)
    class_type = serializers.CharField(required=False, default='online')
    board_type = serializers.CharField(required=False, default='whiteboard')
    
    def validate_class_id(self, value):
        """Check if class exists and belongs to teacher"""
        teacher = self.context['request'].user
        try:
            class_obj = Class.objects.get(id=value, teacher=teacher)
        except Class.DoesNotExist:
            raise serializers.ValidationError("Class not found or you don't have permission.")
        return value


class SessionSerializer(serializers.ModelSerializer):
    """Serializer for attendance session details"""
    class_code = serializers.CharField(source='class_obj.class_code', read_only=True)
    class_name = serializers.CharField(source='class_obj.class_name', read_only=True)
    semester = serializers.CharField(source='class_obj.semester', read_only=True)
    teacher_name = serializers.CharField(source='teacher.username', read_only=True)
    is_active = serializers.ReadOnlyField()
    qr_data = serializers.SerializerMethodField()
    
    class Meta:
        model = AttendanceSession
        fields = [
            'id', 'session_id', 'class_code', 'class_name', 'semester',
            'teacher_name', 'start_time', 'end_time',  # ✅ REMOVE start_time_ist, end_time_ist
            'duration_minutes', 'status', 'is_active', 'qr_data', 'created_at',
            'class_type', 'board_type', 'pattern_code', 'instruction_card', 'shape_data'
        ]
    
    def get_qr_data(self, obj):
        """Return QR code data as JSON"""
        try:
            return json.loads(obj.qr_code_data)
        except:
            return obj.qr_code_data
    
    # ✅ REMOVE get_start_time_ist() and get_end_time_ist() methods completely

class AttendanceRecordSerializer(serializers.ModelSerializer):
    """Serializer for attendance records"""
    student_name = serializers.CharField(source='student.username', read_only=True)
    student_email = serializers.CharField(source='student.email', read_only=True)
    roll_no = serializers.SerializerMethodField()
    
    class Meta:
        model = AttendanceRecord
        fields = ['id', 'student_name', 'student_email', 'roll_no', 'status', 'marked_at', 'verification_score', 'verification_reasons']
    
    def get_roll_no(self, obj):
        try:
            return obj.student.student_profile.roll_no
        except:
            return 'N/A'
        

class TeacherAttendanceHistorySerializer(serializers.ModelSerializer):
    """Serializer for teacher viewing attendance records"""
    student_name = serializers.CharField(source='student.username', read_only=True)
    student_email = serializers.CharField(source='student.email', read_only=True)
    roll_no = serializers.SerializerMethodField()
    class_code = serializers.CharField(source='session.class_obj.class_code', read_only=True)
    class_name = serializers.CharField(source='session.class_obj.class_name', read_only=True)
    semester = serializers.CharField(source='session.class_obj.semester', read_only=True)
    session_date = serializers.DateTimeField(source='session.start_time', read_only=True)
    
    class Meta:
        model = AttendanceRecord
        fields = [
            'id', 'student_name', 'student_email', 'roll_no',
            'class_code', 'class_name', 'semester',
            'session_date', 'status', 'marked_at'
        ]
    
    def get_roll_no(self, obj):
        try:
            return obj.student.student_profile.roll_no
        except:
            return 'N/A'


class UpdateAttendanceStatusSerializer(serializers.Serializer):
    """Serializer for updating attendance status"""
    status = serializers.ChoiceField(choices=['present', 'absent'])

# Add this near MyTokenObtainPairSerializer if you want to customize JWT login

class MyTokenObtainPairSerializer(TokenObtainPairSerializer):
    
    username_field = 'email'
    
    @classmethod
    def get_token(cls, user):
        """Generate JWT token with custom claims"""
        token = super().get_token(user)
        # Add custom claims
        token['role'] = user.role
        token['username'] = user.username
        token['email'] = user.email  
        return token

    def validate(self, attrs):
        """Authenticate user and return tokens + user data"""
        data = super().validate(attrs)
        # Add user data to response
        data['user'] = UserSerializer(self.user).data
        return data

class AnnouncementSerializer(serializers.ModelSerializer):
    teacher_name = serializers.CharField(source='teacher.username', read_only=True)
    teacher_first_name = serializers.CharField(source='teacher.first_name', read_only=True)
    target_class_name = serializers.CharField(source='target_class.class_name', read_only=True, default=None)
    target_class_code = serializers.CharField(source='target_class.class_code', read_only=True, default=None)
    target_student_name = serializers.CharField(source='target_student.username', read_only=True, default=None)

    class Meta:
        model = Announcement
        fields = [
            'id', 'teacher', 'teacher_name', 'teacher_first_name',
            'target_type', 'target_class', 'target_class_name', 'target_class_code',
            'target_student', 'target_student_name',
            'message', 'is_urgent', 'attendance_threshold',
            'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'teacher', 'created_at', 'updated_at']
