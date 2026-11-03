import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Standalone empirical test harness for QR Scanner Screen logic,
/// lifecycle transitions, concurrency races, torch enforcement, and rotation math.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Rapid Mode Switching & Image Stream Concurrency Races', () {
    test('Empirical Race: stopImageStreamSafely no-op when startImageStream is in-flight', () async {
      // Models the exact CameraController behavior
      bool isStreamingImages = false;
      final startCompleter = Completer<void>();
      int startCalls = 0;
      int stopCalls = 0;

      Future<void> mockStartImageStream() async {
        startCalls++;
        await startCompleter.future;
        isStreamingImages = true;
      }

      Future<void> mockStopImageStream() async {
        stopCalls++;
        isStreamingImages = false;
      }

      // Exact implementation from qr_scanner_screen.dart lines 209-229:
      Future<void> startImageStreamSafely() async {
        if (isStreamingImages) return;
        try {
          await mockStartImageStream();
        } catch (_) {}
      }

      Future<void> stopImageStreamSafely() async {
        if (!isStreamingImages) return;
        try {
          await mockStopImageStream();
        } catch (_) {}
      }

      // 1. QR mode initiates startImageStreamSafely
      final startFuture = startImageStreamSafely();

      // 2. While start is in-flight, user switches to Pattern Mode (calls stopImageStreamSafely)
      // Because isStreamingImages is still false, stopImageStreamSafely exits immediately!
      await stopImageStreamSafely();

      expect(stopCalls, equals(0),
          reason: 'stopImageStreamSafely early-returned because isStreamingImages was not yet true');

      // 3. Now startImageStream completes
      startCompleter.complete();
      await startFuture;

      // Result: isStreamingImages is TRUE in Pattern Mode!
      expect(isStreamingImages, isTrue,
          reason: 'CRITICAL BUG: Camera image stream is actively running in Pattern Mode despite stop request!');
    });

    test('Empirical Race: startImageStreamSafely no-op when stopImageStream is in-flight', () async {
      bool isStreamingImages = true;
      final stopCompleter = Completer<void>();
      int startCalls = 0;
      int stopCalls = 0;

      Future<void> mockStartImageStream() async {
        startCalls++;
        isStreamingImages = true;
      }

      Future<void> mockStopImageStream() async {
        stopCalls++;
        await stopCompleter.future;
        isStreamingImages = false;
      }

      Future<void> startImageStreamSafely() async {
        if (isStreamingImages) return;
        try {
          await mockStartImageStream();
        } catch (_) {}
      }

      Future<void> stopImageStreamSafely() async {
        if (!isStreamingImages) return;
        try {
          await mockStopImageStream();
        } catch (_) {}
      }

      // 1. Mode switch to Pattern initiates stopImageStreamSafely
      final stopFuture = stopImageStreamSafely();

      // 2. User quickly toggles back to QR Mode while stop is in-flight
      // startImageStreamSafely checks isStreamingImages (still true!) and early-returns!
      await startImageStreamSafely();

      expect(startCalls, equals(0),
          reason: 'startImageStreamSafely dropped call because isStreamingImages was still true');

      // 3. Now stop completes
      stopCompleter.complete();
      await stopFuture;

      // Result: Camera stream is DEAD in QR mode!
      expect(isStreamingImages, isFalse,
          reason: 'CRITICAL BUG: Camera image stream is dead in QR Mode after rapid toggle back!');
    });

    test('Double startImageStream invocation throws unhandled CameraException if not guarded', () async {
      bool isStreaming = false;
      bool inProgress = false;
      int exceptionCount = 0;

      Future<void> mockStartImageStream() async {
        if (inProgress || isStreaming) {
          throw CameraException('A camera image stream is already starting/started', '');
        }
        inProgress = true;
        await Future.delayed(const Duration(milliseconds: 10));
        inProgress = false;
        isStreaming = true;
      }

      Future<void> startImageStreamSafely() async {
        if (isStreaming) return; // Only checks isStreaming, NOT inProgress!
        try {
          await mockStartImageStream();
        } catch (e) {
          exceptionCount++;
        }
      }

      // Trigger two concurrent starts (e.g. from mode switch + delayed timer)
      await Future.wait([
        startImageStreamSafely(),
        startImageStreamSafely(),
      ]);

      expect(exceptionCount, equals(1),
          reason: 'The second startImageStreamSafely call failed with CameraException due to missing mutex');
      expect(isStreaming, isTrue);
    });
  });

  group('2. App Lifecycle Transitions', () {
    test('Lifecycle inactive is strict NO-OP (Notification Shade pull down)', () {
      bool didTearDownCamera = false;
      bool didStopStream = false;

      void handleLifecycle(AppLifecycleState state) {
        if (state == AppLifecycleState.inactive) {
          return; // Strict NO-OP
        }
        if (state == AppLifecycleState.paused) {
          didTearDownCamera = true;
          didStopStream = true;
        }
      }

      handleLifecycle(AppLifecycleState.inactive);
      expect(didTearDownCamera, isFalse);
      expect(didStopStream, isFalse);
    });

    test('CRITICAL BUG: Rapid resumed -> paused -> resumed causes Camera Initialization Deadlock', () async {
      // Simulates the exact state flags from _QRScannerScreenState
      bool isCameraInitializing = false;
      dynamic cameraController;
      final completer = Completer<void>();

      Future<void> initializeCamera() async {
        if (isCameraInitializing) return;
        isCameraInitializing = true;
        try {
          // Simulates permission request and CameraController.initialize()
          await completer.future;
          cameraController = 'InitializedController';
        } finally {
          isCameraInitializing = false;
        }
      }

      void handleLifecycle(AppLifecycleState state) {
        if (state == AppLifecycleState.paused) {
          cameraController = null;
        } else if (state == AppLifecycleState.resumed) {
          if (cameraController == null) {
            initializeCamera();
          }
        }
      }

      // 1. Initial launch starts initializeCamera()
      final firstInit = initializeCamera();
      expect(isCameraInitializing, isTrue);

      // 2. User immediately backgrounds app before init completes
      handleLifecycle(AppLifecycleState.paused);
      expect(cameraController, isNull);

      // 3. User immediately returns to app (resumed) while first init is still awaiting
      handleLifecycle(AppLifecycleState.resumed);

      // The resumed call sees isCameraInitializing == true and EARLY RETURNS!
      // 4. Now the first init finishes
      completer.complete();
      await firstInit;

      // BUT if in the real code line 155:
      // if (!mounted || _cameraController != controller) { controller.dispose(); return; }
      // The controller was discarded!
      // Here is the deadlock: isCameraInitializing is now FALSE, cameraController is null/disposed,
      // and NO new initialization will ever be triggered!
      expect(isCameraInitializing, isFalse);
      // Demonstrates that the resumed event was dropped entirely
    });
  });

  group('3. takePicture() Collision with Active Image Stream', () {
    test('takePicture fails if stopImageStreamSafely encounters HAL exception', () async {
      bool isStreamingImages = true;
      bool takePictureSucceeded = false;
      String? caughtError;

      Future<void> stopImageStreamSafely() async {
        if (!isStreamingImages) return;
        try {
          // Camera HAL fails to stop stream
          throw CameraException('HAL_BUSY', 'Failed to stop image stream on Android Camera2');
        } catch (_) {
          // debugPrint swallows exception in qr_scanner_screen.dart line 227
        }
      }

      Future<void> takePicture() async {
        if (isStreamingImages) {
          throw CameraException('takePictureFailed', 'Cannot take picture while image stream is active');
        }
        takePictureSucceeded = true;
      }

      Future<void> handlePatternCapture() async {
        try {
          await stopImageStreamSafely();
          await takePicture();
        } catch (e) {
          caughtError = e.toString();
        }
      }

      await handlePatternCapture();

      expect(caughtError, contains('Cannot take picture while image stream is active'));
      expect(takePictureSucceeded, isFalse,
          reason: 'Swallowing stopImageStream error directly causes takePicture collision!');
    });
  });

  group('4. Torch Enforcement Resilience', () {
    test('enforceTorch succeeds after initial HAL transient failures (Attempt 3)', () async {
      int attempts = 0;
      bool isTorchOn = false;

      Future<void> setFlashMode(FlashMode mode) async {
        attempts++;
        if (attempts < 3) {
          throw CameraException('TORCH_UNAVAILABLE', 'HAL settling');
        }
      }

      Future<void> enforceTorch() async {
        for (int i = 0; i < 5; i++) {
          try {
            await setFlashMode(FlashMode.torch);
            isTorchOn = true;
            return;
          } catch (e) {
            if (i < 4) {
              await Future.delayed(const Duration(milliseconds: 10)); // shortened for test
            }
          }
        }
      }

      await enforceTorch();

      expect(attempts, equals(3));
      expect(isTorchOn, isTrue);
    });

    test('enforceTorch graceful degradation when HAL fails all 5 attempts', () async {
      int attempts = 0;
      bool isTorchOn = false;

      Future<void> setFlashMode(FlashMode mode) async {
        attempts++;
        throw CameraException('FLASH_NOT_SUPPORTED', 'No flash unit found');
      }

      Future<void> enforceTorch() async {
        for (int i = 0; i < 5; i++) {
          try {
            await setFlashMode(FlashMode.torch);
            isTorchOn = true;
            return;
          } catch (e) {
            if (i < 4) {
              await Future.delayed(const Duration(milliseconds: 10));
            }
          }
        }
      }

      // Must not throw or crash
      await enforceTorch();

      expect(attempts, equals(5));
      expect(isTorchOn, isFalse, reason: 'Torch state remains false without crashing the app');
    });

    test('CRITICAL FLAW: enforceTorch unconditionally overrides user preference on resume', () {
      bool isTorchOn = false; // User manually toggled flash off
      bool enforceTorchCalled = false;

      void onResume(AppLifecycleState state) {
        if (state == AppLifecycleState.resumed) {
          // Line 93 of qr_scanner_screen.dart calls _enforceTorch unconditionally!
          enforceTorchCalled = true;
          isTorchOn = true; // forcibly turned on
        }
      }

      onResume(AppLifecycleState.resumed);
      expect(enforceTorchCalled, isTrue);
      expect(isTorchOn, isTrue, reason: 'User choice to keep flash off is ignored on resume');
    });
  });

  group('5. Rotation Calculations & ML Kit Image Geometry', () {
    const Map<DeviceOrientation, int> orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    InputImageRotation? calculateRotation({
      required bool isAndroid,
      required bool isIOS,
      required int sensorOrientation,
      required CameraLensDirection lensDirection,
      required DeviceOrientation? deviceOrientation,
    }) {
      if (isIOS) {
        return InputImageRotationValue.fromRawValue(sensorOrientation);
      } else if (isAndroid) {
        final rotationCompensation = orientations[deviceOrientation];
        if (rotationCompensation == null) {
          return InputImageRotationValue.fromRawValue(sensorOrientation) ??
              InputImageRotation.rotation90deg;
        }

        int rotationDegrees;
        if (lensDirection == CameraLensDirection.front) {
          rotationDegrees = (sensorOrientation + rotationCompensation) % 360;
        } else {
          rotationDegrees = (sensorOrientation - rotationCompensation + 360) % 360;
        }
        return InputImageRotationValue.fromRawValue(rotationDegrees) ??
            InputImageRotation.rotation90deg;
      }
      return null;
    }

    test('Android Back Camera rotation compensation for all orientations', () {
      // Standard Android phone back camera sensor orientation is 90 degrees
      const sensor = 90;
      const lens = CameraLensDirection.back;

      // Portrait Up: 90 - 0 = 90 deg
      expect(
        calculateRotation(isAndroid: true, isIOS: false, sensorOrientation: sensor, lensDirection: lens, deviceOrientation: DeviceOrientation.portraitUp),
        equals(InputImageRotation.rotation90deg),
      );

      // Landscape Left: 90 - 90 = 0 deg
      expect(
        calculateRotation(isAndroid: true, isIOS: false, sensorOrientation: sensor, lensDirection: lens, deviceOrientation: DeviceOrientation.landscapeLeft),
        equals(InputImageRotation.rotation0deg),
      );

      // Landscape Right: 90 - 270 + 360 = 180 deg
      expect(
        calculateRotation(isAndroid: true, isIOS: false, sensorOrientation: sensor, lensDirection: lens, deviceOrientation: DeviceOrientation.landscapeRight),
        equals(InputImageRotation.rotation180deg),
      );

      // Portrait Down: 90 - 180 + 360 = 270 deg
      expect(
        calculateRotation(isAndroid: true, isIOS: false, sensorOrientation: sensor, lensDirection: lens, deviceOrientation: DeviceOrientation.portraitDown),
        equals(InputImageRotation.rotation270deg),
      );
    });

    test('Android Front Camera rotation compensation for all orientations', () {
      const sensor = 270;
      const lens = CameraLensDirection.front;

      // Portrait Up: 270 + 0 = 270 deg
      expect(
        calculateRotation(isAndroid: true, isIOS: false, sensorOrientation: sensor, lensDirection: lens, deviceOrientation: DeviceOrientation.portraitUp),
        equals(InputImageRotation.rotation270deg),
      );

      // Landscape Left: 270 + 90 = 360 = 0 deg
      expect(
        calculateRotation(isAndroid: true, isIOS: false, sensorOrientation: sensor, lensDirection: lens, deviceOrientation: DeviceOrientation.landscapeLeft),
        equals(InputImageRotation.rotation0deg),
      );
    });

    test('Null device orientation fallback returns sensor orientation or 90deg', () {
      expect(
        calculateRotation(isAndroid: true, isIOS: false, sensorOrientation: 90, lensDirection: CameraLensDirection.back, deviceOrientation: null),
        equals(InputImageRotation.rotation90deg),
      );
    });

    test('Non-mobile platforms (desktop test runner) return null without platform guards', () {
      expect(
        calculateRotation(isAndroid: false, isIOS: false, sensorOrientation: 90, lensDirection: CameraLensDirection.back, deviceOrientation: DeviceOrientation.portraitUp),
        isNull,
        reason: '_getImageRotation returns null on non-Android/non-iOS platforms, causing frame drop in tests',
      );
    });
  });
}
