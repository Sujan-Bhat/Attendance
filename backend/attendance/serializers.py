from rest_framework import serializers
from django.contrib.auth import get_user_model, authenticate
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError

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
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("A user with this email already exists.")
        return value
    
    def validate(self, data):
        if data['password'] != data['password2']:
            raise serializers.ValidationError({"password2": "Password fields didn't match."})
        try:
            validate_password(data['password'])
        except DjangoValidationError as e:
            raise serializers.ValidationError({"password": list(e.messages)})
        return data
    
    def create(self, validated_data):
        validated_data.pop('password2', None)
        password = validated_data.pop('password')
        user = User(**validated_data)
        user.set_password(password)
        
        if user.role == 'admin':
            user.is_staff = True
            user.is_superuser = False
        
        user.save()
        return user


class LoginSerializer(serializers.Serializer):
    """ Serializer for user login """
    username = serializers.CharField(required=True)
    password = serializers.CharField(required=True, write_only=True)

    def validate(self, data):
        username = data.get('username')
        password = data.get('password')

        if username and password:
            user = authenticate(username=username, password=password)
            if user:
                if user.is_active:
                    data['user'] = user
                else:
                    raise serializers.ValidationError("User account is disabled.")
            else:
                raise serializers.ValidationError("Invalid username or password.")
        else:
            raise serializers.ValidationError("Username and password are required.")

        return data

