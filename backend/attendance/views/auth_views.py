from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.decorators import api_view, permission_classes
from django.contrib.auth import get_user_model

from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from ..serializers import RegistrationSerializer, UserSerializer

User = get_user_model()



class RegisterView(generics.CreateAPIView):
    """Public endpoint for new user registration"""
    permission_classes = (permissions.AllowAny,)
    serializer_class = RegistrationSerializer


class MeView(generics.RetrieveAPIView):
    """Returns details about currently authenticated user"""
    permission_classes = (permissions.IsAuthenticated,)
    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user


class MyTokenObtainPairSerializer(TokenObtainPairSerializer):
    @classmethod
    def get_token(cls, user):
        """Generate JWT token with custom claims"""
        token = super().get_token(user)
        # Add custom claims
        token['role'] = user.role
        token['username'] = user.username
        return token

    def validate(self, attrs):
        """Authenticate user and return tokens + user data"""
        #Step 1: Validate credentials
        data = super().validate(attrs)
        # Add user data to response
        data['user'] = UserSerializer(self.user).data
        return data


class MyTokenObtainPairView(TokenObtainPairView):
    """Custom token view using our serializer"""
    serializer_class = MyTokenObtainPairSerializer


@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def ping(request):
    return Response({"status": "ok", "message": "Server is running!"})
