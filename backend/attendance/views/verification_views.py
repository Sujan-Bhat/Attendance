import json

import cv2
import numpy as np
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.decorators import api_view, permission_classes
from django.contrib.auth import get_user_model
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from ..models import Class, Enrollment, AttendanceSession, AttendanceRecord

User = get_user_model()


import os
import base64
import numpy as np
import cv2
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.conf import settings

FACE_DATA_DIR = os.path.join(settings.BASE_DIR, 'face_data')
os.makedirs(FACE_DATA_DIR, exist_ok=True)

try:
    from insightface.app import FaceAnalysis
    # Initialize the app once at startup
    face_app = FaceAnalysis(name='buffalo_s', providers=['CPUExecutionProvider'])
    face_app.prepare(ctx_id=0, det_size=(160, 160))
except Exception as e:
    face_app = None
    print("InsightFace init failed:", e)




@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def upload_reference_image(request, session_id):
    """Teacher uploads the reference pattern image for pattern session"""
    user = request.user
    
    if user.role != 'teacher':
        return Response(
            {'error': 'Only teachers can upload reference images'},
            status=status.HTTP_403_FORBIDDEN
        )
        
    try:
        session = AttendanceSession.objects.get(
            session_id=session_id,
            teacher=user
        )
    except AttendanceSession.DoesNotExist:
        return Response(
            {'error': 'Session not found'},
            status=status.HTTP_404_NOT_FOUND
        )
        
    if 'reference_image' not in request.FILES:
        return Response(
            {'error': 'No image provided'},
            status=status.HTTP_400_BAD_REQUEST
        )
        
    ref_file = request.FILES['reference_image']
    
    from attendance.verification import verify_teacher_reference
    
    try:
        ref_bytes = ref_file.read()
        ref_file.seek(0) # Reset pointer so Django can save it
        
        success, message = verify_teacher_reference(ref_bytes, session.pattern_code, session.shape_data)
        if not success:
            return Response(
                {'error': message},
                status=status.HTTP_400_BAD_REQUEST
            )
            
    except Exception as e:
        return Response(
            {'error': f'Failed to process image: {str(e)}'},
            status=status.HTTP_400_BAD_REQUEST
        )
        
    session.reference_image = ref_file
    session.save()
    
    return Response({
        'message': 'Reference image verified and uploaded successfully'
    })

@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def verify_image(request):
    """Student verifies attendance with a live photo and focal distance."""
    user = request.user

    if user.role != 'student':
        return Response(
            {'error': 'Only students can verify attendance'},
            status=status.HTTP_403_FORBIDDEN
        )

    session_id = request.data.get('session_id')
    focal_distance = request.data.get('focal_distance')
    student_image = request.FILES.get('student_image')
    
    flash_fired_str = request.data.get('flash_fired', 'false').lower()
    flash_fired = flash_fired_str in ['true', '1', 'yes']

    if not session_id:
        return Response({'error': 'session_id is required'}, status=status.HTTP_400_BAD_REQUEST)
    if student_image is None:
        return Response({'error': 'student_image is required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        session = AttendanceSession.objects.get(session_id=session_id)
    except AttendanceSession.DoesNotExist:
        return Response(
            {'error': 'Session not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    if session.status != 'active':
        return Response({'error': 'This session has ended'}, status=status.HTTP_400_BAD_REQUEST)

    if not session.is_active:
        return Response(
            {'error': f'Session expired at {session.end_time.strftime("%I:%M %p")}'},
            status=status.HTTP_400_BAD_REQUEST
        )

    if not Enrollment.objects.filter(class_obj=session.class_obj, student=user).exists():
        return Response(
            {'error': f'You are not enrolled in {session.class_obj.class_code}'},
            status=status.HTTP_403_FORBIDDEN
        )

    try:
        if session.class_type == 'pattern':
            if not session.pattern_code:
                return Response(
                    {'error': 'Session has no pattern code for verification'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            if not session.reference_image:
                return Response(
                    {'error': 'Teacher has not uploaded the reference image yet'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        existing_record = AttendanceRecord.objects.filter(session=session, student=user).first()
        if existing_record:
            if existing_record.status == 'pending_review':
                # Allow the student to retry scanning if their previous attempt failed verification
                existing_record.delete()
            else:
                return Response({
                    'error': 'Attendance already marked',
                    'marked_at': existing_record.marked_at,
                    'status': existing_record.status
                }, status=status.HTTP_400_BAD_REQUEST)

        from attendance.verification import verify_offline_code, validate_focal_distance
        
        is_valid_distance, distance_result = validate_focal_distance(focal_distance)
        if not is_valid_distance:
            return Response({'error': distance_result}, status=status.HTTP_400_BAD_REQUEST)

        # Extract BLE Mesh Proofs
        ble_hop_count = request.data.get('ble_hop_count')
        ble_rssi = request.data.get('ble_rssi')
        
        verification_reasons_dict = {}
        if ble_hop_count is not None and ble_rssi is not None:
            verification_reasons_dict['ble_verified'] = True
            try:
                verification_reasons_dict['ble_hop_count'] = int(ble_hop_count)
                verification_reasons_dict['ble_rssi'] = int(float(ble_rssi))
            except (ValueError, TypeError):
                pass
        else:
            return Response({
                'error': 'Proxy attendance detected: BLE verification missing. Ensure Bluetooth is on and you are near the teacher.',
                'status': 'proxy_detected'
            }, status=status.HTTP_400_BAD_REQUEST)

        matched, final_score, reasons = verify_offline_code(
            session.pattern_code, session.reference_image, student_image, flash_fired
        )
        
        if matched:
            verification_reasons_dict['ai_verified'] = True
            verification_reasons_dict['ai_score'] = final_score
        
        verification_reasons_dict['reasons'] = reasons

        # Penalize score slightly for higher hop counts (further from teacher)
        if 'ble_hop_count' in verification_reasons_dict:
            score_penalty = verification_reasons_dict['ble_hop_count'] * 0.05
            final_score = max(0.0, final_score - score_penalty)

        status_val = 'present' if matched else 'pending_review'

        record = AttendanceRecord.objects.create(
            session=session,
            student=user,
            status=status_val,
            verification_score=final_score,
            verification_reasons=json.dumps(verification_reasons_dict)
        )

        if not matched:
            return Response({
                'status': 'pending_review',
                'score': final_score,
                'reasons': reasons,
                'message': f'Verification failed. Marked for manual review. Reasons: {", ".join(reasons)}'
            }, status=status.HTTP_200_OK)

        return Response({
            'status': 'pass',
            'score': final_score,
            'message': f'Attendance verified for {session.class_obj.class_code}',
            'focal_distance': distance_result,
            'marked_at': record.marked_at,
        }, status=status.HTTP_201_CREATED)
    except Exception as e:
        import traceback
        return Response({'error': f"Backend Error: {str(e)}", 'trace': traceback.format_exc()}, status=status.HTTP_400_BAD_REQUEST)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def sync_offline_pattern(request):
    """Student syncs an offline pattern scan."""
    user = request.user
    if user.role != 'student':
        return Response({'error': 'Only students can sync attendance'}, status=status.HTTP_403_FORBIDDEN)

    timestamp_str = request.data.get('timestamp')
    student_image = request.FILES.get('student_image')

    if not timestamp_str or not student_image:
        return Response({'error': 'timestamp and student_image are required'}, status=status.HTTP_400_BAD_REQUEST)

    scan_time = parse_datetime(timestamp_str)
    if not scan_time:
        return Response({'error': 'Invalid timestamp format'}, status=status.HTTP_400_BAD_REQUEST)

    # Find the session active at that time for this student
    enrolled_class_ids = Enrollment.objects.filter(student=user).values_list('class_obj_id', flat=True)
    
    session = AttendanceSession.objects.filter(
        class_obj_id__in=enrolled_class_ids,
        class_type='pattern',
        start_time__lte=scan_time,
        end_time__gte=scan_time
    ).order_by('-start_time').first()

    if not session:
        return Response({'error': f'No active pattern session found for you at {scan_time.strftime("%I:%M %p")}'}, status=status.HTTP_404_NOT_FOUND)

    # Check 24-hour expiration for offline pattern syncs
    time_diff = timezone.now() - session.start_time
    if time_diff.total_seconds() > (24 * 3600):
        return Response(
            {'error': 'Sync window expired. Attendance must be synced within 24 hours.'},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        if not session.reference_image:
            return Response({'error': 'Teacher has not uploaded the reference image yet'}, status=status.HTTP_400_BAD_REQUEST)

        existing_record = AttendanceRecord.objects.filter(session=session, student=user).first()
        if existing_record:
            if existing_record.status not in ['absent', 'pending_review']:
                return Response({'error': 'Attendance already marked', 'marked_at': existing_record.marked_at, 'status': existing_record.status}, status=status.HTTP_400_BAD_REQUEST)

        # Extract BLE Mesh Proofs
        ble_hop_count = request.data.get('ble_hop_count')
        ble_rssi = request.data.get('ble_rssi')
        
        verification_reasons_dict = {}
        if ble_hop_count is not None and ble_rssi is not None:
            verification_reasons_dict['ble_verified'] = True
            try:
                verification_reasons_dict['ble_hop_count'] = int(ble_hop_count)
                verification_reasons_dict['ble_rssi'] = int(float(ble_rssi))
            except (ValueError, TypeError):
                pass
        else:
            return Response({
                'error': 'Proxy attendance detected: BLE verification missing. Ensure Bluetooth is on and you are near the teacher.',
                'status': 'proxy_detected'
            }, status=status.HTTP_400_BAD_REQUEST)

        from attendance.verification import verify_offline_code
        
        # Focal distance not recorded offline, pass default or assume None
        matched, final_score, reasons = verify_offline_code(
            session.pattern_code, session.reference_image, student_image, False
        )
        
        if matched:
            verification_reasons_dict['ai_verified'] = True
            verification_reasons_dict['ai_score'] = final_score
        
        verification_reasons_dict['reasons'] = reasons

        # Penalize score slightly for higher hop counts (further from teacher)
        if 'ble_hop_count' in verification_reasons_dict:
            score_penalty = verification_reasons_dict['ble_hop_count'] * 0.05
            final_score = max(0.0, final_score - score_penalty)

        status_val = 'present' if matched else 'pending_review'

        if existing_record:
            existing_record.status = status_val
            existing_record.verification_score = final_score
            existing_record.verification_reasons = json.dumps(verification_reasons_dict)
            existing_record.save()
            record = existing_record
        else:
            record = AttendanceRecord.objects.create(
                session=session,
                student=user,
                status=status_val,
                verification_score=final_score,
                verification_reasons=json.dumps(verification_reasons_dict)
            )

        if scan_time:
            AttendanceRecord.objects.filter(id=record.id).update(marked_at=scan_time)
            record.refresh_from_db()

        if not matched:
            return Response({'status': 'pending_review', 'message': f'Verification failed. Marked for manual review. Reasons: {", ".join(reasons)}'}, status=status.HTTP_200_OK)

        return Response({'status': 'pass', 'message': f'Offline attendance synced for {session.class_obj.class_code}'}, status=status.HTTP_201_CREATED)
    except Exception as e:
        import traceback
        return Response({'error': f"Backend Error: {str(e)}", 'trace': traceback.format_exc()}, status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def register_face(request):
    try:
        base64_img = request.data.get('image')
        if not base64_img:
            return Response({'error': 'No image provided'}, status=400)
            
        # Decode base64
        img_data = base64.b64decode(base64_img)
        np_arr = np.frombuffer(img_data, np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        
        if face_app is None:
            return Response({'error': 'InsightFace AI model failed to load on the server. Please restart Django.'}, status=500)
            
        faces = face_app.get(img)
        if len(faces) == 0:
            return Response({'error': 'No face detected in the image.'}, status=400)
            
        embedding = faces[0].embedding
        user_id = request.user.id
        
        # Save to disk
        file_path = os.path.join(FACE_DATA_DIR, f"{user_id}.npy")
        np.save(file_path, embedding)
        
        return Response({'success': True, 'message': 'Face registered successfully!'})
    except Exception as e:
        return Response({'error': str(e)}, status=500)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def verify_face_auth(request):
    try:
        base64_img = request.data.get('image')
        if not base64_img:
            return Response({'error': 'No image provided'}, status=400)
            
        # Decode base64
        img_data = base64.b64decode(base64_img)
        np_arr = np.frombuffer(img_data, np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        
        if face_app is None:
            return Response({'error': 'InsightFace AI model failed to load on the server. Please restart Django.'}, status=500)
            
        faces = face_app.get(img)
        if len(faces) == 0:
            return Response({'error': 'No face detected.'}, status=400)
            
        # Ensure detection confidence is adequate (insightface provides det_score)
        if hasattr(faces[0], 'det_score') and faces[0].det_score < 0.6:
            return Response({'error': 'Face detection confidence too low.'}, status=400)

        live_embedding = faces[0].embedding
        user_id = request.user.id

        file_path = os.path.join(FACE_DATA_DIR, f"{user_id}.npy")
        if not os.path.exists(file_path):
            return Response({'error': 'No registered face found.'}, status=404)

        saved_embedding = np.load(file_path)

        # Calculate Cosine Similarity (already normalized)
        similarity = np.dot(live_embedding, saved_embedding) / (np.linalg.norm(live_embedding) * np.linalg.norm(saved_embedding))

        print(f"Face Similarity Score: {similarity}", flush=True)

        # Balanced threshold to reduce false positives while allowing genuine matches
        is_match = bool(similarity > 0.75)

        return Response({'success': is_match, 'similarity': float(similarity)})
    except Exception as e:
        return Response({'error': str(e)}, status=500)
