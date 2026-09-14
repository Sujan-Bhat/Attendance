from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.decorators import api_view, permission_classes
from django.contrib.auth import get_user_model

from ..models import Announcement, AttendanceRecord, AttendanceSession
from ..serializers import AnnouncementSerializer

User = get_user_model()




@api_view(['GET', 'POST'])
@permission_classes([permissions.IsAuthenticated])
def announcements_list_create(request):
    """Get or Create announcements"""
    user = request.user
    
    if request.method == 'POST':
        if user.role != 'teacher':
            return Response({'error': 'Only teachers can create announcements'}, status=status.HTTP_403_FORBIDDEN)
        
        serializer = AnnouncementSerializer(data=request.data)
        if serializer.is_valid():
            announcement = serializer.save(sender=user)
            
            # Resolve target recipients
            target_type = announcement.target_type
            
            if target_type == 'class':
                target_class = announcement.target_class
                if not target_class:
                    announcement.delete()
                    return Response({'error': 'Target class is required for class announcements'}, status=status.HTTP_400_BAD_REQUEST)
                enrolled_students = User.objects.filter(enrolled_classes__class_obj=target_class)
                announcement.recipients.set(enrolled_students)
                
            elif target_type == 'individual':
                student_id = request.data.get('target_student_id')
                if not student_id:
                    announcement.delete()
                    return Response({'error': 'Target student is required for individual announcements'}, status=status.HTTP_400_BAD_REQUEST)
                try:
                    student = User.objects.get(id=student_id, role='student')
                except User.DoesNotExist:
                    announcement.delete()
                    return Response({'error': 'Student not found'}, status=status.HTTP_404_NOT_FOUND)
                announcement.recipients.add(student)
                
            elif target_type == 'low_attendance':
                target_class = announcement.target_class
                threshold = announcement.min_attendance_threshold
                if not target_class or threshold is None:
                    announcement.delete()
                    return Response({'error': 'Target class and min attendance threshold are required'}, status=status.HTTP_400_BAD_REQUEST)
                
                enrolled_users = User.objects.filter(enrolled_classes__class_obj=target_class)
                total_sessions = AttendanceSession.objects.filter(class_obj=target_class).count()
                
                recipients_list = []
                for student in enrolled_users:
                    if total_sessions > 0:
                        present_count = AttendanceRecord.objects.filter(
                            session__class_obj=target_class,
                            student=student,
                            status='present'
                        ).count()
                        rate = (present_count / total_sessions) * 100
                    else:
                        rate = 100.0
                        
                    if rate < threshold:
                        recipients_list.append(student)
                
                announcement.recipients.set(recipients_list)
                
            return Response(AnnouncementSerializer(announcement).data, status=status.HTTP_201_CREATED)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    else:
        if user.role == 'teacher':
            announcements = Announcement.objects.filter(sender=user)
        else:
            announcements = Announcement.objects.filter(recipients=user)
            
        serializer = AnnouncementSerializer(announcements, many=True)
        return Response(serializer.data)


@api_view(['PUT', 'DELETE'])
@permission_classes([permissions.IsAuthenticated])
def announcement_detail(request, pk):
    try:
        announcement = Announcement.objects.get(pk=pk)
    except Announcement.DoesNotExist:
        return Response({'error': 'Announcement not found'}, status=status.HTTP_404_NOT_FOUND)
        
    if announcement.sender != request.user:
        return Response({'error': 'You do not have permission to modify this announcement'}, status=status.HTTP_403_FORBIDDEN)
        
    if request.method == 'PUT':
        serializer = AnnouncementSerializer(announcement, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
    elif request.method == 'DELETE':
        announcement.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

