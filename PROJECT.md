# Project: Flutter Attendance Mobile App Camera Modernization

## Architecture
- **Framework**: Flutter (Dart SDK ^3.9.2), Android/iOS target.
- **Frontend App**: `frontend/attendance_app`
- **Key Modules**:
  - `screens/student/qr_scanner_screen.dart`: Main scanning UI for student attendance, currently hosting dual modes: QR Scan mode and Pattern Scan mode.
  - `services/attendance_service.dart`: Backend API integration for marking attendance and image verification.
  - `services/ble_mesh_service.dart`: Proximity verification via BLE Mesh before submitting attendance.
  - `services/session_service.dart`: Fetches active attendance sessions.
  - `services/sync_service.dart`: Offline queuing and local SQLite storage for deferred sync.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Exploration & Dependency Audit | Analyze `qr_scanner_screen.dart`, `pubspec.yaml`, Android build setup, and formulate conversion strategy | none | DONE |
| 2 | Unified Camera & ML Kit Migration | Migrate from `mobile_scanner` to `CameraController` + `google_mlkit_barcode_scanning`, single session, seamless mode switch, persistent torch | M1 | DONE |
| 3 | Lifecycle & Background Hardening | Handle Android lifecycle states (notification pull / inactive vs paused) to eliminate stutter | M2 | DONE |
| 4 | Verification & Release Build | `flutter analyze` zero errors, `flutter build apk --release` successful build | M3 | DONE |
| 5 | Multi-agent Review & Forensic Audit | Reviewers, Challengers, and Forensic Auditor verification | M4 | DONE |

## Interface Contracts
### CameraController ↔ BarcodeScanner
- Single `CameraController` initialized with `ResolutionPreset.veryHigh` or `ResolutionPreset.high`, `enableAudio: false`.
- `FlashMode.torch` enforced on initialization and preserved across mode switches.
- In QR Mode: `startImageStream((CameraImage image) => _processCameraImage(image))`.
- Frame throttle / Mutex: `_isDetecting` boolean prevents queued frame backlog.
- Frame conversion: Convert `CameraImage` planes to `InputImage` with appropriate rotation and format.
- In Pattern Mode: Preview displays live `CameraPreview(_cameraController!)`; picture capture temporarily stops or coordinates image stream, invokes `takePicture()`, and maintains torch.

## Code Layout
- `frontend/attendance_app/lib/screens/student/qr_scanner_screen.dart`: Refactored camera and scanner UI.
- `frontend/attendance_app/pubspec.yaml`: Dependencies list.
- `frontend/attendance_app/android/app/src/main/AndroidManifest.xml`: Permissions and hardware feature declarations.
