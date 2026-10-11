import requests
import json
import io

base_url = "http://localhost:8000/api/v1"

# 1. Login as Admin/Teacher to create a session
t_login = requests.post(f"{base_url}/auth/token/", json={"email": "teacher@example.com", "password": "password123"})
t_token = t_login.json().get('access')
t_headers = {"Authorization": f"Bearer {t_token}"}

# Get class list
classes = requests.get(f"{base_url}/classes/", headers=t_headers).json()
class_id = classes[0]['id']

# Create session
session_data = {
    "class_obj_id": class_id,
    "class_type": "offline",
    "duration_minutes": 60,
    "pattern_code": "TESTING"
}
sess_resp = requests.post(f"{base_url}/sessions/create/", headers=t_headers, json=session_data)
print("Create session:", sess_resp.status_code)
session_id = sess_resp.json()['session_id']

# 2. Login as student
s_login = requests.post(f"{base_url}/auth/token/", json={"email": "student@example.com", "password": "password123"})
s_token = s_login.json().get('access')
s_headers = {"Authorization": f"Bearer {s_token}"}

# 3. Verify as student
dummy_image = io.BytesIO(b"fake image data")
dummy_image.name = "dummy.jpg"

files = {
    'student_image': ('dummy.jpg', dummy_image, 'image/jpeg')
}
data = {
    'session_id': session_id,
    'focal_distance': '1.0'
}

print("Verifying image...")
verify_resp = requests.post(f"{base_url}/sessions/verify-image/", headers=s_headers, files=files, data=data)
print(f"Status Code: {verify_resp.status_code}")
print("Response text:")
print(verify_resp.text)
