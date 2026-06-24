import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/services.dart';

import '../core/production_face_recognition_constants.dart';
import 'anti_spoof_service.dart';

/// RAM / CPU tuning for institute phones (2–16 GB). Camera ML is throttled on
/// all Android to limit heat; 2–4 GB get the strictest limits.
class DevicePerformanceService {
  static const MethodChannel _channel = MethodChannel('msce/device_performance');

  static bool _initialized = false;

  /// ≤3 GB RAM or Android low-RAM flag.
  static bool isLowRamDevice = false;

  /// ≤4 GB RAM.
  static bool isConstrainedDevice = false;

  static int? memoryClassMb;
  static int? largeMemoryClassMb;
  static int? totalRamMb;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getDeviceProfile');
      memoryClassMb = (raw?['memoryClassMb'] as num?)?.toInt();
      largeMemoryClassMb = (raw?['largeMemoryClassMb'] as num?)?.toInt();
      totalRamMb = (raw?['totalRamMb'] as num?)?.toInt();

      final flaggedLowRam = raw?['isLowRamDevice'] == true;
      final totalRamLooksLow = totalRamMb != null && totalRamMb! <= 3072;
      final totalRamConstrained = totalRamMb != null && totalRamMb! <= 4096;
      final heapLooksLow = memoryClassMb != null && memoryClassMb! <= 192;

      isLowRamDevice = flaggedLowRam || totalRamLooksLow || heapLooksLow;
      isConstrainedDevice = isLowRamDevice || totalRamConstrained || heapLooksLow;

      if (kDebugMode) {
        debugPrint(
          '📱 Device profile: lowRam=$isLowRamDevice, constrained=$isConstrainedDevice, '
          'memoryClassMb=$memoryClassMb, totalRamMb=$totalRamMb, '
          'streamGap=${streamFrameMinGap.inMilliseconds}ms, streamPad=$enableStreamPadOnLivePreview',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Device performance probe unavailable: $e');
      }
      isConstrainedDevice = true;
    }
  }

  static int get imageCacheItems =>
      isLowRamDevice ? 24 : (isConstrainedDevice ? 40 : 120);

  static int get imageCacheBytes => isLowRamDevice
      ? 12 * 1024 * 1024
      : (isConstrainedDevice ? 20 * 1024 * 1024 : 60 * 1024 * 1024);

  static bool get skipHeavyWarmup => isLowRamDevice || isConstrainedDevice;

  static bool get useLowCameraPreset => isLowRamDevice && !Platform.isAndroid;

  // Always low on Android — medium causes camera session config failures
  // on Samsung devices (broken pipe / ERROR_GRAPH_CONFIG errors).
  static ResolutionPreset get streamCameraResolution {
    if (Platform.isAndroid) return ResolutionPreset.low;
    return useLowCameraPreset ? ResolutionPreset.low : ResolutionPreset.medium;
  }

  /// Enable stream PAD when model supports it (same as MSCEAPP2 attendance).
  static bool get enableStreamPadOnLivePreview => AntiSpoofService.supportsStreamPad;

  static bool get enableStreamPadOnRegistration => false;

  /// Frame gap tuned for blink detection: a natural blink lasts ~150-250ms.
  /// At 450ms gap there was ~50% chance of missing the closed-eye frame entirely.
  /// 200ms gap (~5fps) reliably catches blinks without excessive CPU load.
  static Duration get streamFrameMinGap {
    if (isLowRamDevice) return const Duration(milliseconds: 400);
    if (isConstrainedDevice) return const Duration(milliseconds: 280);
    if (Platform.isAndroid) return const Duration(milliseconds: 200);
    return const Duration(milliseconds: 150);
  }

  static int get minRecognitionIntervalMs {
    if (isLowRamDevice) return 1200;
    if (isConstrainedDevice) return 950;
    if (Platform.isAndroid) return 750;
    return ProductionFaceRecognitionConstants.minRecognitionIntervalMs;
  }

  static int get padFrameModulo {
    if (Platform.isAndroid) {
      if (isLowRamDevice) return 24;
      if (isConstrainedDevice) return 18;
      return 12;
    }
    return isLowRamDevice ? 12 : 6;
  }

  static int get uiUpdateMinGapMs {
    if (Platform.isAndroid) {
      if (isLowRamDevice) return 320;
      if (isConstrainedDevice) return 260;
      return 200;
    }
    if (isLowRamDevice) return 240;
    return 120;
  }

  static int get minCleanLiveFramesBeforeCapture {
    if (isLowRamDevice) return 2;
    if (isConstrainedDevice) return 2;
    return 2; // 2×200ms = 400ms post-blink delay (was 3×450ms = 1.35s)
  }

  static int get minPerfectFramesToProceed {
    if (isLowRamDevice) return 2;
    if (isConstrainedDevice) return 2;
    return Platform.isAndroid ? 2 : 5;
  }

  static Duration get backgroundStatsPollInterval {
    if (isLowRamDevice) return const Duration(seconds: 60);
    if (isConstrainedDevice) return const Duration(seconds: 45);
    return const Duration(seconds: 20);
  }

  static bool get enableLandmarksOnStream => !isLowRamDevice && !isConstrainedDevice;

  static bool get enableFaceTrackingOnStream => !isLowRamDevice;

  /// Classification needed for eye-open probability (blink detection).
  /// Always enabled — blink detection requires it.
  static bool get enableClassificationOnStream => true;

  /// Slower ML Kit passes on Android miss fast blinks unless thresholds relax.
  static bool get relaxedStreamBlinkDetection =>
      Platform.isAndroid || isConstrainedDevice;

  static Duration get deferredWarmCacheDelay {
    if (isLowRamDevice) return const Duration(seconds: 8);
    if (isConstrainedDevice) return const Duration(seconds: 5);
    return Duration.zero;
  }

  static Duration get deferredModelLoadDelay {
    if (isLowRamDevice) return const Duration(seconds: 2);
    if (isConstrainedDevice) return const Duration(seconds: 1);
    return const Duration(milliseconds: 400);
  }
}
