import 'dart:ui' show Rect;

import 'package:camera/camera.dart' show CameraImage;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    show InputImageRotation;

/// Web/stub AntiSpoofService — no TFLite (dart:ffi) dependency.
///
/// Mirrors the public API of `anti_spoof_service.dart`. Reports
/// `allModelsFailed = true` so callers gracefully skip PAD entirely
/// (same code path as when no model asset could be loaded on device).
class AntiSpoofService {
  static const double liveThreshold = 0.85;
  static const double strictStreamLiveThreshold = 0.56;
  static const double strictStreamSpoofThreshold = 0.40;

  static bool get isModelLoaded => false;
  static bool get allModelsFailed => true;
  static bool get useCaptureTimePadOnly => false;
  static bool get supportsStreamPad => false;
  static bool get captureTimePadOnly => false;

  static bool passesAttendanceCheck(AntiSpoofResult result) => true;

  static bool passesStrictAutoScan(AntiSpoofResult result) => true;

  static bool isImmediateSpoof(AntiSpoofResult result) => false;

  static double spoofConfidence(AntiSpoofResult result) =>
      result.isReal ? 0.0 : (1.0 - result.confidence).clamp(0.0, 1.0);

  static bool shouldRejectAutoScanCapture(AntiSpoofResult result) => false;

  static Future<void> ensureLoaded() async {}

  static Future<void> initializeForAutoScan() async {}

  static Future<void> initialize() async {}

  static Future<void> retryInitialize() async {}

  static Future<AntiSpoofResult?> checkSpoofFromCameraFrame(
    CameraImage image,
    Rect analysisBox, {
    InputImageRotation rotation = InputImageRotation.rotation270deg,
  }) async {
    // No PAD model on this platform.
    return null;
  }

  static Future<AntiSpoofResult> checkSpoofForAutoScan(String photoPath) async {
    return AntiSpoofResult(
      isReal: true,
      confidence: 1.0,
      reason: 'PAD unavailable on this platform',
    );
  }

  static Future<AntiSpoofResult> checkSpoof(String photoPath) async {
    return AntiSpoofResult(
      isReal: true,
      confidence: 1.0,
      reason: 'PAD unavailable on this platform',
    );
  }

  static void dispose() {}
}

class AntiSpoofResult {
  final bool isReal;
  final double confidence;
  final String reason;

  AntiSpoofResult({
    required this.isReal,
    required this.confidence,
    required this.reason,
  });
}
