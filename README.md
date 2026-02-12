# Attendance Management System

A comprehensive attendance tracking system built with **Django REST Framework** (Backend) and **Flutter** (Frontend), using **PostgreSQL** database and **Docker** for containerization.

##  Features

###  Teacher Features
-  Create and manage classes
-  Generate QR codes for attendance sessions
-  Real-time session monitoring with countdown timer
-  View attendance reports and analytics
-  Manage student enrollments
-  Export attendance data

###  Student Features
- Scan QR codes to mark attendance
- View enrolled classes
- Check attendance history
- Real-time attendance status

###  Authentication & Authorization
- JWT-based authentication
- Role-based access control (Student, Teacher, Admin)
- Secure password hashing

---

##  Tech Stack

### Backend
- **Framework**: Django 5.2.7
- **API**: Django REST Framework 3.16.1
- **Database**: PostgreSQL 15
- **Authentication**: JWT (djangorestframework-simplejwt)
- **QR Code**: qrcode 7.4.2 + Pillow 10.4.0

### Frontend
- **Framework**: Flutter 3.x
- **State Management**: StatefulWidget
- **HTTP Client**: Dio
- **Storage**: Flutter Secure Storage
- **QR Code**: qr_flutter

### DevOps
- **Containerization**: Docker & Docker Compose
- **Database Management**: pgAdmin 4
- **Version Control**: Git

---

## Prerequisites

Before you begin, ensure you have the following installed:

| Tool | Version | Download Link |
|------|---------|---------------|
| **Git** | Latest | [Download](https://git-scm.com/downloads) |
| **Docker Desktop** | Latest | [Download](https://www.docker.com/products/docker-desktop) |
| **Flutter SDK** | 3.0+ | [Download](https://flutter.dev/docs/get-started/install) |
| **Code Editor** | VS Code recommended | [Download](https://code.visualstudio.com/) |

### Verify Installations

```bash
# Check Git
git --version

# Check Docker
docker --version
docker-compose --version

# Check Flutter
flutter doctor
```

---

##  Quick Start Guide

### **Step 1: Clone the Repository**

```bash
git clone https://github.com/Sujan-Bhat/attendance.git
cd attendance
```

### **Step 2: Backend Setup**

#### 2.1 Create Environment File

```bash
cp backend/.env.example backend/.env
```

#### 2.2 Configure `.env` File

Edit `backend/.env`:

SECRET_KEY=dev-secret-change-me
DATABASE_URL=postgres://postgres:postgres@db:5432/attend_db
DJANGO_DEBUG=True



#### 2.3 Start Docker Services

```bash
# Build and start containers
docker-compose up -d --build

# Verify containers are running
docker-compose ps
```

**Expected Output:**
```
NAME                COMMAND                  STATUS              PORTS
attendance-db-1     "docker-entrypoint.s…"   Up (healthy)        0.0.0.0:5433->5432/tcp
attendance-web-1    "bash -c 'python man…"   Up                  0.0.0.0:8000->8000/tcp
attendance-pgadmin  "/entrypoint.sh"         Up                  0.0.0.0:5050->80/tcp
```

#### 2.4 Run Database Migrations

```bash
docker-compose exec web python manage.py makemigrations
docker-compose exec web python manage.py migrate
```

#### 2.5 Create Admin User

```bash
docker-compose exec web python manage.py createsuperuser
```

Enter credentials:
- **Username**: admin
- **Email**: admin@example.com
- **Password**: (choose a strong password)

#### 2.6 Verify Backend

Open in browser:
- **API Ping**: http://localhost:8000/api/v1/ping/
- **Admin Panel**: http://localhost:8000/admin/
- **pgAdmin**: http://localhost:5050/

---

### **Step 3: Frontend Setup**

#### 3.1 Navigate to Flutter Project

```bash
cd frontend/attendance_app
```

#### 3.2 Install Dependencies

```bash
flutter pub get
```

#### 3.3 Run Flutter App

```bash
# Web Browser
flutter run -d chrome

# Android Emulator
flutter run -d android

# iOS Simulator (Mac only)
flutter run -d ios
```

---

##  Project Structure

```
attendance/
│
├── backend/                          # Django Backend
│   ├── attend_backend/              # Project Configuration
│   │   ├── settings.py              # Django settings
│   │   ├── urls.py                  # Main URL routing
│   │   └── wsgi.py                  # WSGI config
│   │
│   ├── attendance/                   # Main Application
│   │   ├── models.py                # Database models
│   │   │   ├── User                 # Custom user model
│   │   │   ├── StudentProfile       # Student details
│   │   │   ├── Class                # Class/Course model
│   │   │   ├── Enrollment           # Student enrollments
│   │   │   ├── AttendanceSession    # QR session model
│   │   │   └── AttendanceRecord     # Attendance entries
│   │   │
│   │   ├── serializers.py           # API serializers
│   │   ├── views.py                 # API endpoints
│   │   └── migrations/              # Database migrations
│   │
│   ├── requirements.txt             # Python dependencies
│   ├── Dockerfile                   # Docker config
│   └── .env                         # Environment variables
│
├── frontend/attendance_app/          # Flutter Frontend
│   ├── lib/
│   │   ├── main.dart                # App entry point
│   │   │
│   │   ├── config/
│   │   │   └── api_config.dart      # API configuration
│   │   │
│   │   ├── screens/
│   │   │   ├── auth/                # Authentication screens
│   │   │   │   ├── login_screen.dart
│   │   │   │   └── register_screen.dart
│   │   │   │
│   │   │   ├── dashboard/           # Dashboard screens
│   │   │   │   ├── teacher_dashboard.dart
│   │   │   │   └── student_dashboard.dart
│   │   │   │
│   │   │   └── teacher/             # Teacher-specific screens
│   │   │       ├── my_classes_screen.dart
│   │   │       └── session_create_screen.dart
│   │   │
│   │   ├── services/                # API Services
│   │   │   ├── auth_service.dart
│   │   │   ├── class_service.dart
│   │   │   └── session_service.dart
│   │   │
│   │   └── widgets/                 # Reusable Components
│   │       └── magical_dashboard_card.dart
│   │
│   └── pubspec.yaml                 # Flutter dependencies
│
└── docker-compose.yml               # Docker orchestration
```

---

## API Documentation

### Base URL
```
http://localhost:8000/api/v1
```

### Authentication Endpoints

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| POST | `/auth/register/` | Register new user |  |
| POST | `/auth/token/` | Login & get JWT tokens ||
| POST | `/auth/token/refresh/` | Refresh access token | |
| GET | `/auth/me/` | Get current user info | |

### Class Management

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| GET | `/classes/` | List all classes (teacher's) |  Teacher |
| POST | `/classes/` | Create new class | Teacher |
| GET | `/classes/{id}/` | Get class details |  |
| PUT | `/classes/{id}/` | Update class | Teacher |
| DELETE | `/classes/{id}/` | Delete class | Teacher |
| GET | `/classes/{id}/students/` | Get enrolled students |  Teacher |
| POST | `/classes/{id}/add-student/` | Add student to class | Teacher |
| DELETE | `/classes/{id}/remove-student/{student_id}/` | Remove student | Teacher |

### Session Management

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| POST | `/sessions/create/` | Create attendance session |  Teacher |
| GET | `/sessions/active/` | Get active sessions |  Teacher |
| GET | `/sessions/{session_id}/` | Get session details |  Teacher |
| POST | `/sessions/{session_id}/mark/` | Mark attendance (student) |  Student |
| POST | `/sessions/{session_id}/end/` | End session |  Teacher |



---

##  Docker Commands Reference

### Basic Commands

```bash
# Start all services
docker-compose up 

# Stop all services
docker-compose down

# Rebuild and start
docker-compose up -d --build

# View logs
docker-compose logs -f
docker-compose logs -f web    # Backend logs only
docker-compose logs -f db     # Database logs only

# Check container status
docker-compose ps

# Restart a specific service
docker-compose restart web
```

### Database Commands

```bash
# Run migrations
docker-compose exec web python manage.py makemigrations
docker-compose exec web python manage.py migrate

# Check migration status
docker-compose exec web python manage.py showmigrations

# Create superuser
docker-compose exec web python manage.py createsuperuser

# Access Django shell
docker-compose exec web python manage.py shell

# Access PostgreSQL shell
docker-compose exec db psql -U postgres -d attend_db
```

### Cleanup Commands

```bash
# Stop and remove containers
docker-compose down
```



##  Database Schema

### Users Table
```sql
- id (PK)
- username (unique)
- email (unique)
- password (hashed)
- role (student/teacher/admin)
- first_name
- last_name
- is_active
- date_joined
```

### Classes Table
```sql
- id (PK)
- class_code (unique)
- class_name
- semester
- teacher_id (FK -> Users)
- created_at
- updated_at
```

### AttendanceSessions Table
```sql
- id (PK)
- session_id (UUID, unique)
- class_id (FK -> Classes)
- teacher_id (FK -> Users)
- start_time
- end_time
- duration_minutes
- qr_code_data (JSON)
- status (active/expired/completed)
```

### AttendanceRecords Table
```sql
- id (PK)
- session_id (FK -> AttendanceSessions)
- student_id (FK -> Users)
- marked_at
- status (present/absent)
```

---



---

## Contributing

We welcome contributions! 
Please open a pull request for fixes or improvements.
For larger changes, start a discussion first.

Please follow these steps:

### 1. Fork the Repository

Click the "Fork" button on GitHub

### 2. Clone Your Fork

```bash
git clone https://github.com/YOUR_USERNAME/attendance.git
cd attendance
```

### 3. Create a Feature Branch

```bash
git checkout -b feature/amazing-feature
```

### 4. Make Your Changes

- Write clean, documented code
- Follow existing code style
- Add tests for new features

### 5. Commit Your Changes

```bash
git add .
git commit -m "Add: amazing feature description"
```

**Commit Message Convention**:
- `Add:` New feature
- `Fix:` Bug fix
- `Update:` Code improvement
- `Docs:` Documentation changes
- `Test:` Adding tests

### 6. Push to Your Fork

```bash
git push origin feature/amazing-feature
```

### 7. Create Pull Request

Go to the original repository and click "New Pull Request"

## 📱 Mobile App Installation

### Building APK for Android

```bash
cd frontend/attendance_app

# Debug build (for testing)
flutter build apk --debug

# Release build (for production)
flutter build apk --release

# Install on connected device
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### APK Locations
- Debug: `build/app/outputs/flutter-apk/app-debug.apk`
- Release: `build/app/outputs/flutter-apk/app-release.apk`

---

## Troubleshooting

### Backend Issues

**Port 8000 already in use:**
```bash
sudo lsof -i :8000
sudo kill -9 <PID>
```

**Database connection failed:**
```bash
docker-compose down
docker-compose up -d db
# Wait 10 seconds, then:
docker-compose up web
```

### Frontend Issues

**Flutter dependencies error:**
```bash
cd frontend/attendance_app
flutter clean
flutter pub get
```

**Android build fails:**
```bash
cd android
./gradlew clean
cd ..
flutter build apk --debug
```

**NDK license error:**
```bash
# Accept Android SDK licenses
yes | sdkmanager --licenses

# Or manually create license file
sudo mkdir -p /usr/lib/android-sdk/licenses
echo "24333f8a63b6825ea9c5514f83c2829b004d1fee" | sudo tee /usr/lib/android-sdk/licenses/android-sdk-license
```

### Docker Issues

**Container fails to start:**
```bash
docker-compose down
docker system prune -a  # Warning: removes all unused images
docker-compose up --build
```

**pgAdmin not accessible:**
```bash
# Check pgAdmin logs
docker-compose logs pgadmin

# Restart pgAdmin
docker-compose restart pgadmin
```

---

## Security Notes

### For Production Deployment:

1. **Change SECRET_KEY** in `.env`:
   ```bash
   python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
   ```

2. **Set DEBUG=False** in production

3. **Use strong database passwords**

4. **Enable HTTPS** for API endpoints

5. **Configure CORS** properly:
   ```python
   # backend/attend_backend/settings.py
   CORS_ALLOWED_ORIGINS = [
       "https://yourdomain.com",
   ]
   ```

6. **Use environment variables** for sensitive data (never commit `.env` files)

---

## Admin Panel Access

After creating superuser, access:

**Django Admin**: http://localhost:8000/admin/

Available sections:
- **Users**: Manage all users (students, teachers, admins)
- **Classes**: View and manage all classes
- **Enrollments**: Student class enrollments
- **Attendance sessions**: QR code sessions
- **Attendance records**: All marked attendance

---

## API Testing

### Using cURL

```bash
# Register a user
curl -X POST http://localhost:8000/api/v1/auth/register/ \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "securepass123",
    "role": "student"
  }'

# Login
curl -X POST http://localhost:8000/api/v1/auth/token/ \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "securepass123"
  }'

# Use the access token
curl -X GET http://localhost:8000/api/v1/auth/me/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Using Postman

1. Import API collection (create a `postman_collection.json`)
2. Set base URL: `http://localhost:8000/api/v1`
3. Add Authorization header with JWT token

---

## Mobile App Features

### QR Code Scanning
- Real-time QR code detection
- Automatic attendance marking
- Session validation
- Duplicate scan prevention

### Dashboard
- Attendance history
- Enrolled classes
- Session status
- Profile management

---



## Acknowledgments

- Django REST Framework documentation
- Flutter documentation
- Docker documentation
- QR code libraries contributors



