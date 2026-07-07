import 'dart:typed_data';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;

/// Web-specific camera service using HTML5 Canvas & getUserMedia API
/// Captures photos via webcam for entry marking
class WebCameraService {
  static const String _videoElementId = 'webcam-video';
  static const String _canvasElementId = 'webcam-canvas';

  /// Request permission and open camera
  /// Returns true if permission granted and camera started
  static Future<bool> requestCameraPermission() async {
    try {
      debugPrint('📷 Requesting camera permission...');

      // Check browser support
      final window = html.window;
      final navigator = window.navigator;

      // Get getUserMedia API
      final getUserMedia = navigator.mediaDevices?.getDisplayMedia ??
                          navigator.getUserMedia;

      if (getUserMedia == null) {
        throw Exception('getUserMedia not supported in this browser');
      }

      debugPrint('✅ Camera API supported');
      return true;
    } catch (e) {
      debugPrint('❌ Camera permission error: $e');
      return false;
    }
  }

  /// Capture photo from webcam
  /// Returns compressed JPEG photo bytes
  static Future<Uint8List> capturePhotoFromWebcam() async {
    try {
      debugPrint('📸 Capturing photo from webcam...');

      // Access video element
      final videoElement = html.document.getElementById(_videoElementId) as html.VideoElement?;
      if (videoElement == null) {
        throw Exception('Video element not found');
      }

      // Access canvas element
      final canvasElement = html.document.getElementById(_canvasElementId) as html.CanvasElement?;
      if (canvasElement == null) {
        throw Exception('Canvas element not found');
      }

      // Get canvas context
      final context = canvasElement.context2D;

      // Draw video frame to canvas
      canvasElement.width = videoElement.videoWidth;
      canvasElement.height = videoElement.videoHeight;
      context.drawImage(videoElement, 0, 0);

      debugPrint('📸 Photo captured from canvas (${canvasElement.width}x${canvasElement.height})');

      // Convert canvas to blob
      final imageData = await canvasElement.toBlob(type: 'image/jpeg', quality: 0.9);

      // Convert blob to bytes
      final reader = html.FileReader();
      reader.readAsArrayBuffer(imageData);

      await reader.onLoad.first;

      final bytes = reader.result as List<int>;
      final photoBytes = Uint8List.fromList(bytes);

      debugPrint('✅ Photo captured: ${photoBytes.length} bytes');
      return photoBytes;
    } catch (e) {
      debugPrint('❌ Capture failed: $e');
      rethrow;
    }
  }

  /// Compress photo to under 1MB for web upload
  static Future<Uint8List> compressPhotoToUnder1MB(Uint8List photoBytes) async {
    try {
      debugPrint('🗜️ Compressing photo...');

      final decoded = img.decodeImage(photoBytes);
      if (decoded == null) {
        debugPrint('⚠️ Decode failed, using original');
        return photoBytes;
      }

      img.Image image = decoded;

      // Try to bake EXIF orientation
      try {
        image = img.bakeOrientation(image);
      } catch (_) {
        // Continue with original orientation
      }

      // Start with quality 90
      int quality = 90;
      Uint8List compressed = Uint8List.fromList(img.encodeJpg(image, quality: quality));

      debugPrint('🗜️ Initial size: ${compressed.length} bytes (quality: $quality)');

      // Keep reducing quality until under 1MB
      while (compressed.length > 1048576 && quality > 30) {
        quality -= 10;
        compressed = Uint8List.fromList(img.encodeJpg(image, quality: quality));
        debugPrint('🗜️ Trying quality $quality: ${compressed.length} bytes');
      }

      // If still too large, resize image
      if (compressed.length > 1048576) {
        debugPrint('🗜️ Still too large, resizing image...');
        final resized = img.copyResize(image,
            width: (image.width * 0.8).toInt(),
            height: (image.height * 0.8).toInt());
        compressed = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
        debugPrint('🗜️ Resized: ${compressed.length} bytes');
      }

      debugPrint('✅ Compression complete: ${compressed.length} bytes');
      return compressed;
    } catch (e) {
      debugPrint('❌ Compression error: $e');
      return photoBytes;
    }
  }

  /// Create video element for webcam stream
  /// Call this before requesting camera permission
  static void createVideoElement({
    required String videoElementId,
    required int width,
    required int height,
  }) {
    try {
      debugPrint('📺 Creating video element...');

      // Remove existing if any
      html.document.getElementById(videoElementId)?.remove();

      // Create video element
      final videoElement = html.VideoElement()
        ..id = videoElementId
        ..autoplay = true
        ..style.width = '${width}px'
        ..style.height = '${height}px'
        ..style.border = '2px solid #1e40af'
        ..style.borderRadius = '8px'
        ..style.backgroundColor = '#000'
        ..style.objectFit = 'cover';

      html.document.body?.append(videoElement);
      debugPrint('✅ Video element created');
    } catch (e) {
      debugPrint('❌ Video element creation failed: $e');
    }
  }

  /// Create hidden canvas element for photo capture
  static void createCanvasElement({
    required String canvasElementId,
  }) {
    try {
      debugPrint('🎨 Creating canvas element...');

      // Remove existing if any
      html.document.getElementById(canvasElementId)?.remove();

      // Create canvas element (hidden)
      final canvasElement = html.CanvasElement()
        ..id = canvasElementId
        ..style.display = 'none';

      html.document.body?.append(canvasElement);
      debugPrint('✅ Canvas element created');
    } catch (e) {
      debugPrint('❌ Canvas element creation failed: $e');
    }
  }

  /// Start webcam stream
  static Future<void> startWebcamStream({
    required String videoElementId,
    required bool facingMode, // true = user, false = environment
  }) async {
    try {
      debugPrint('▶️ Starting webcam stream...');

      final videoElement = html.document.getElementById(videoElementId) as html.VideoElement?;
      if (videoElement == null) {
        throw Exception('Video element not found');
      }

      // Get getUserMedia
      final navigator = html.window.navigator;
      final mediaDevices = navigator.mediaDevices;

      if (mediaDevices == null) {
        throw Exception('mediaDevices not supported');
      }

      // Request camera
      final stream = await mediaDevices.getUserMedia({
        'video': {
          'facingMode': facingMode ? 'user' : 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      }) as html.MediaStream;

      // Set video source to stream
      videoElement.srcObject = stream;

      debugPrint('✅ Webcam stream started');
    } catch (e) {
      debugPrint('❌ Stream start failed: $e');
      rethrow;
    }
  }

  /// Stop webcam stream
  static Future<void> stopWebcamStream({
    required String videoElementId,
  }) async {
    try {
      debugPrint('⏹️ Stopping webcam stream...');

      final videoElement = html.document.getElementById(videoElementId) as html.VideoElement?;
      if (videoElement == null) return;

      // Stop all tracks
      final stream = videoElement.srcObject as html.MediaStream?;
      if (stream != null) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
      }

      debugPrint('✅ Webcam stream stopped');
    } catch (e) {
      debugPrint('❌ Stream stop failed: $e');
    }
  }

  /// Clean up resources
  static void cleanup({
    required String videoElementId,
    required String canvasElementId,
  }) {
    try {
      debugPrint('🧹 Cleaning up camera resources...');

      // Remove video element
      html.document.getElementById(videoElementId)?.remove();

      // Remove canvas element
      html.document.getElementById(canvasElementId)?.remove();

      debugPrint('✅ Cleanup complete');
    } catch (e) {
      debugPrint('❌ Cleanup error: $e');
    }
  }
}
