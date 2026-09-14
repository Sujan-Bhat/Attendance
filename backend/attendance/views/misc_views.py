from django.http import JsonResponse
from rest_framework import permissions
from rest_framework.decorators import api_view, permission_classes



@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def assetlinks_json(request):
    """
    Serve the assetlinks.json file required for Android App Links (Deep Linking).
    """
    from django.http import JsonResponse
    return JsonResponse([{
        "relation": ["delegate_permission/common.handle_all_urls"],
        "target": {
            "namespace": "android_app",
            "package_name": "com.example.attendance_app",
            "sha256_cert_fingerprints": [
                "87:17:E3:5D:41:92:69:09:62:28:72:43:E3:68:77:C8:BF:2C:F4:BA:97:47:37:DE:B4:52:D2:4D:6B:94:83:C9"
            ]
        }
    }], safe=False)
