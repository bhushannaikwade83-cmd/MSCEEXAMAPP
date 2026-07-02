import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Stub AntiSpoofService - No TFLite dependency
/// Returns permissive defaults (all faces pass)
class AntiSpoofService {
  static const double liveThreshold = 0.85;
  static const double strictStreamLiveThreshold = 0.56;
  static const double strictStreamSpoofThreshold = 0.40;

  static bool _isInitialized = false;
  static bool _allModelsFailed = false;

  static bool get isModelLoaded => true;
  static bool get allModelsFailed => false;
  static bool get useCaptureTimePadOnly => false;
  static bool get supportsStreamPad => true;
  static bool get captureTimePadOnly => false;

  static Future<void> initialize() async {
    _isInitialized = true;
  }

  static bool passesAttendanceCheck(AntiSpoofResult result) {
    // Stub: Always pass (no TFLite model)
    return true;
  }

  static bool passesStrictAutoScan(AntiSpoofResult result) {
    // Stub: Always pass
    return true;
  }

  static bool isImmediateSpoof(AntiSpoofResult result) {
    // Stub: Never block
    return false;
  }

  static Future<AntiSpoofResult?> checkSpoofFromCameraFrame(
    CameraImage frame,
    Face face, {
    required InputImageRotation rotation,
  }) async {
    // Stub: Return safe default (face is real)
    return AntiSpoofResult(
      isReal: true,
      confidence: 0.9,
      spoof: false,
      score: 0.1,
    );
  }
}

class AntiSpoofResult {
  AntiSpoofResult({
    required this.isReal,
    required this.confidence,
    required this.spoof,
    required this.score,
  });

  final bool isReal;
  final double confidence;
  final bool spoof;
  final double score;
}
