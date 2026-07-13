import 'dart:convert' show base64Decode;
import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;

/// Web-specific camera service using HTML5 video/canvas & getUserMedia API.
/// Captures photos via webcam for entry marking.
///
/// IMPORTANT implementation notes:
/// - Elements are kept as direct Dart references (in [_videos]/[_canvases]).
///   `document.getElementById` CANNOT be used: HtmlElementView inserts the
///   video inside Flutter's shadow DOM where getElementById never finds it.
/// - A platform view type may only be registered once per app session, so
///   registration is guarded; the factory returns the CURRENT element.
class WebCameraService {
  static const String _videoElementId = 'webcam-video';
  static const String _canvasElementId = 'webcam-canvas';

  /// Live element references, keyed by element id.
  static final Map<String, html.VideoElement> _videos = {};
  static final Map<String, html.CanvasElement> _canvases = {};

  /// View types already registered with the platform view registry.
  static final Set<String> _registeredViewTypes = {};

  /// Request permission and open camera
  /// Returns true if permission granted and camera started
  static Future<bool> requestCameraPermission() async {
    try {
      debugPrint('📷 Requesting camera permission...');

      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception('mediaDevices not supported in this browser');
      }

      debugPrint('✅ Camera API supported');
      return true;
    } catch (e) {
      debugPrint('❌ Camera permission error: $e');
      return false;
    }
  }

  /// Capture photo from webcam.
  /// Returns JPEG photo bytes.
  static Future<Uint8List> capturePhotoFromWebcam({
    String videoElementId = _videoElementId,
    String canvasElementId = _canvasElementId,
  }) async {
    try {
      debugPrint('📸 Capturing photo from webcam...');

      final videoElement = _videos[videoElementId];
      if (videoElement == null) {
        throw Exception('Video element not found');
      }

      final canvasElement = _canvases[canvasElementId];
      if (canvasElement == null) {
        throw Exception('Canvas element not found');
      }

      // Wait for the stream to actually deliver frames.
      await _waitForVideoReady(videoElement);

      // Draw current video frame to canvas
      canvasElement.width = videoElement.videoWidth;
      canvasElement.height = videoElement.videoHeight;
      canvasElement.context2D.drawImage(videoElement, 0, 0);

      debugPrint(
          '📸 Photo captured from canvas (${canvasElement.width}x${canvasElement.height})');

      // Encode via data URL (synchronous & reliable across browsers)
      final dataUrl = canvasElement.toDataUrl('image/jpeg', 0.92);
      final base64Data = dataUrl.substring(dataUrl.indexOf(',') + 1);
      final photoBytes = base64Decode(base64Data);

      debugPrint('✅ Photo captured: ${photoBytes.length} bytes');
      return photoBytes;
    } catch (e) {
      debugPrint('❌ Capture failed: $e');
      rethrow;
    }
  }

  /// Waits until the video has real dimensions (frames flowing).
  static Future<void> _waitForVideoReady(html.VideoElement video) async {
    if (video.videoWidth > 0 && video.videoHeight > 0) return;
    for (int i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (video.videoWidth > 0 && video.videoHeight > 0) return;
    }
    throw Exception('Camera stream did not start (no video frames)');
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
      Uint8List compressed =
          Uint8List.fromList(img.encodeJpg(image, quality: quality));

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

      // Stop any previous stream on this id before replacing the element.
      _stopTracks(_videos[videoElementId]);

      // Create video element.
      // muted + playsinline are REQUIRED for autoplay on iOS Safari.
      final videoElement = html.VideoElement()
        ..id = videoElementId
        ..autoplay = true
        ..muted = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#000'
        ..style.objectFit = 'cover'
        ..style.display = 'block';
      videoElement.setAttribute('muted', '');
      videoElement.setAttribute('autoplay', '');
      videoElement.setAttribute('playsinline', 'true');

      _videos[videoElementId] = videoElement;

      // Register with Flutter's view factory for HtmlElementView.
      // A view type can only be registered ONCE per app session; the factory
      // returns whatever the CURRENT element for this id is.
      if (!_registeredViewTypes.contains(videoElementId)) {
        ui.platformViewRegistry.registerViewFactory(
          videoElementId,
          (int viewId) => _videos[videoElementId] ?? html.VideoElement(),
        );
        _registeredViewTypes.add(videoElementId);
      }

      debugPrint('✅ Video element created and registered');
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
      // Canvas does not need to be attached to the DOM to draw/encode.
      _canvases[canvasElementId] = html.CanvasElement();
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

      final videoElement = _videos[videoElementId];
      if (videoElement == null) {
        throw Exception(
            'Video element not found — call createVideoElement first');
      }

      final mediaDevices = html.window.navigator.mediaDevices;
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
      });

      // Set video source to stream and start playback
      videoElement.srcObject = stream;
      try {
        await videoElement.play();
      } catch (_) {
        // Autoplay policies may reject play(); the muted+autoplay attributes
        // let the browser start playback once the element is displayed.
      }

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
      _stopTracks(_videos[videoElementId]);
      debugPrint('✅ Webcam stream stopped');
    } catch (e) {
      debugPrint('❌ Stream stop failed: $e');
    }
  }

  static void _stopTracks(html.VideoElement? videoElement) {
    if (videoElement == null) return;
    final stream = videoElement.srcObject;
    if (stream is html.MediaStream) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
    }
    videoElement.srcObject = null;
  }

  /// Clean up resources
  static void cleanup({
    required String videoElementId,
    required String canvasElementId,
  }) {
    try {
      debugPrint('🧹 Cleaning up camera resources...');
      _stopTracks(_videos[videoElementId]);
      _videos.remove(videoElementId)?.remove();
      _canvases.remove(canvasElementId);
      debugPrint('✅ Cleanup complete');
    } catch (e) {
      debugPrint('❌ Cleanup error: $e');
    }
  }
}
