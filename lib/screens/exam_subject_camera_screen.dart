import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../core/camera_lens_utils.dart';
import '../core/camera_stream_pipeline.dart';
import '../services/anti_spoof_service_stub.dart'
    if (dart.library.io) '../services/anti_spoof_service.dart';
import '../services/distance_check_service.dart' show DistanceStatus;
import '../services/location_service.dart';
import '../services/pre_capture_liveness_tracker.dart';
import '../services/session_monitor.dart';

/// Simple blink-to-capture camera screen for exam subject entry.
/// Returns [XFile] via Navigator.pop when a live face is captured.
class ExamSubjectCameraScreen extends StatefulWidget {
  const ExamSubjectCameraScreen({
    super.key,
    required this.studentName,
    required this.subjectName,
  });

  final String studentName;
  final String subjectName;

  @override
  State<ExamSubjectCameraScreen> createState() => _ExamSubjectCameraScreenState();
}

class _ExamSubjectCameraScreenState extends State<ExamSubjectCameraScreen> {
  final PreCaptureLivenessTracker _livenessTracker = PreCaptureLivenessTracker(
    requiredBlinks: 0,  // ✅ NO blinks required
    screenSpoofFramesRequired: 2,
    minPadLiveStreak: 3,
    enableStreamPad: false,
    enableStreamScreenSpoof: false,
    requireLiveFaceBeforeLiveness: false,
  );

  late CameraController _cameraController;
  FaceDetector? _faceDetector;
  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;
  bool _isStreaming = false;
  bool _isInitializing = true;
  bool _isCapturing = false;
  bool _capturePending = false;
  bool _isProcessingFrame = false;

  DistanceStatus _distanceStatus = DistanceStatus.noFace;
  bool _canCapture = false;
  String _livenessMessage = 'Face detected - Tap to capture';
  Rect? _faceRect;  // ✅ Store current face rectangle for overlay

  DateTime? _lastFrameProcessed;
  static const Duration _frameGap = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    AntiSpoofService.initialize();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }
      _selectedCameraIndex = preferredBackCameraIndex(_availableCameras);
      if (_selectedCameraIndex < 0 || _selectedCameraIndex >= _availableCameras.length) {
        _selectedCameraIndex = 0;
      }
      await _initController(_availableCameras[_selectedCameraIndex]);

      // Web: no ML Kit / image stream support in browsers — plain preview
      // with a manual capture button instead.
      if (!kIsWeb) {
        _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.accurate,  // ✅ Changed from .fast to .accurate
            enableClassification: true,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _isInitializing = false;
          if (kIsWeb) {
            _canCapture = true;
            _livenessMessage = 'Position the face and tap Capture';
          }
        });
        _startStream();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Camera error: $e')));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _initController(CameraDescription cam) async {
    _cameraController = CameraController(
      cam,
      ResolutionPreset.high,  // ✅ Changed from .low to .high for better quality
      enableAudio: false,
      imageFormatGroup: kIsWeb
          ? ImageFormatGroup.jpeg
          : (Platform.isAndroid
              ? ImageFormatGroup.nv21
              : ImageFormatGroup.bgra8888),
    );
    await _cameraController.initialize();

    if (kIsWeb) {
      // Web: focus/exposure modes are unsupported in browsers — best effort.
      try {
        await _cameraController.setFocusMode(FocusMode.auto);
        await _cameraController.setExposureMode(ExposureMode.auto);
      } catch (_) {}
    } else {
      // ✅ Enable autofocus for sharp images
      await _cameraController.setFocusMode(FocusMode.auto);

      // ✅ Set exposure mode to auto for proper brightness
      await _cameraController.setExposureMode(ExposureMode.auto);
    }
  }

  Future<void> _toggleCamera() async {
    if (_availableCameras.length < 2) return;
    setState(() => _isInitializing = true);
    if (_isStreaming) {
      await _cameraController.stopImageStream();
      _isStreaming = false;
    }
    await _cameraController.dispose();
    _selectedCameraIndex =
        toggleFacingCameraIndex(_availableCameras, _selectedCameraIndex);
    await _initController(_availableCameras[_selectedCameraIndex]);
    if (mounted) {
      setState(() => _isInitializing = false);
      _livenessTracker.reset();
      _startStream();
    }
  }

  void _startStream() {
    // Web: camera image streaming + ML Kit are unavailable; capture stays
    // manual (_canCapture is set to true after init).
    if (kIsWeb) return;
    if (_isStreaming) return;
    _isStreaming = true;
    _cameraController.startImageStream((CameraImage image) async {
      final now = DateTime.now();
      if (_isCapturing ||
          _capturePending ||
          _isProcessingFrame ||
          (_lastFrameProcessed != null &&
              now.difference(_lastFrameProcessed!) < _frameGap)) return;
      _lastFrameProcessed = now;
      _isProcessingFrame = true;
      try {
        final mlInput = CameraStreamPipeline.mlKitInput(_cameraController, image);
        if (mlInput == null) return;

        final rotation = mlInput.rotation;
        final faces = await _faceDetector!.processImage(mlInput.inputImage);
        if (!mounted) return;

        if (faces.isEmpty) {
          _livenessTracker.reset();
          setState(() {
            _distanceStatus = DistanceStatus.noFace;
            _canCapture = false;
            _livenessMessage = 'No face detected';
            _faceRect = null;  // ✅ Clear face rect
          });
          return;
        }

        final double displayWidth =
            (rotation.rawValue == 90 || rotation.rawValue == 270)
                ? image.height.toDouble()
                : image.width.toDouble();
        final double displayHeight =
            (rotation.rawValue == 90 || rotation.rawValue == 270)
                ? image.width.toDouble()
                : image.height.toDouble();

        final face = faces.first;

        // ✅ NO AUTO-CAPTURE: Just check face quality, wait for manual tap
        final live = _livenessTracker.evaluate(
          image: image,
          face: face,
          displayWidth: displayWidth,
          displayHeight: displayHeight,
        );

        // ✅ Map face rect to display coordinates for overlay
        final faceRectForDisplay = _mapFaceRectToScreen(
          face: face,
          displayWidth: displayWidth,
          displayHeight: displayHeight,
          cameraImage: image,
        );

        setState(() {
          _distanceStatus = live.distanceStatus;
          _canCapture = live.canCapture;  // ✅ Can capture when face is good
          _livenessMessage = live.livenessMessage;
          _faceRect = faceRectForDisplay;  // ✅ Store for overlay drawing
        });
      } catch (e) {
        if (kDebugMode) debugPrint('Frame error: $e');
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  Future<void> _finishCapture(CameraImage image, dynamic faceRect) async {
    if (_isCapturing) return;
    _capturePending = false;
    setState(() => _isCapturing = true);

    try {
      final liveOk = await _livenessTracker.verifyFrameIsLive(image, faceRect);
      if (!liveOk) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Screen or video detected. Use a live face.')),
          );
        }
        _resetUi();
        return;
      }

      SessionMonitor.beginSuppressResumeLock();
      if (_isStreaming) {
        await _cameraController.stopImageStream();
        _isStreaming = false;
      }
      final photo = await _cameraController.takePicture();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      SessionMonitor.endSuppressResumeLock();

      if (!mounted) return;
      Navigator.pop(context, photo);
    } catch (e) {
      SessionMonitor.endSuppressResumeLock();
      if (kDebugMode) debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      }
      _resetUi(restartStream: true);
    }
  }

  void _resetUi({bool restartStream = false}) {
    if (!mounted) return;
    setState(() {
      _isCapturing = false;
      _capturePending = false;
      _faceRect = null;
    });
    if (restartStream && !_isStreaming && _cameraController.value.isInitialized) {
      _startStream();
    }
  }

  // ✅ Map face rectangle from camera buffer to screen display coordinates
  // ✅ Accounts for the 0.8 aspect ratio centered frame
  Rect _mapFaceRectToScreen({
    required Face face,
    required double displayWidth,
    required double displayHeight,
    required CameraImage cameraImage,
  }) {
    // Get the preview size
    final previewWidth = _cameraController.value.previewSize?.width ?? 1920.0;
    final previewHeight = _cameraController.value.previewSize?.height ?? 1080.0;

    // Scale from camera image to preview
    final scaleX = previewWidth / cameraImage.width;
    final scaleY = previewHeight / cameraImage.height;

    // Get face rect in preview coordinates
    var left = face.boundingBox.left * scaleX;
    var top = face.boundingBox.top * scaleY;
    var right = face.boundingBox.right * scaleX;
    var bottom = face.boundingBox.bottom * scaleY;

    // Add padding to make box BIGGER
    const padding = 40.0;
    left = (left - padding).clamp(0, previewWidth);
    top = (top - padding).clamp(0, previewHeight);
    right = (right + padding).clamp(0, previewWidth);
    bottom = (bottom + padding).clamp(0, previewHeight);

    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  void dispose() {
    if (_isStreaming) {
      _isStreaming = false;
      _cameraController.stopImageStream();
    }
    _cameraController.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  Color get _statusColor {
    if (_isCapturing || _capturePending) return Colors.blue;
    if (_canCapture) return Colors.green;
    if (_distanceStatus == DistanceStatus.noFace) return Colors.orange;
    return Colors.yellow;
  }

  String get _statusText {
    if (_isCapturing) return 'Capturing…';
    if (_canCapture) return '✅ Ready - Tap Capture button';
    if (_distanceStatus == DistanceStatus.noFace) return 'No face detected';
    if (_distanceStatus == DistanceStatus.tooFar) return 'Move closer (3 feet)';
    if (_distanceStatus == DistanceStatus.tooClosed) return 'Move back';
    return 'Position your face';
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || !_cameraController.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.subjectName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        // ✅ Explicit back button
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.studentName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            Text(widget.subjectName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          if (_availableCameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: _isCapturing ? null : _toggleCamera,
            ),
        ],
      ),
      body: Stack(
        children: [
          // ✅ CAMERA PREVIEW - No distortion
          Center(
            child: AspectRatio(
              aspectRatio: 0.8,  // 4:5 aspect ratio
              child: Container(
                color: Colors.black,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: CameraPreview(_cameraController),
                ),
              ),
            ),
          ),
          // ✅ Simple face detection frame (like normal camera)
          if (_faceRect != null)
            Center(
              child: AspectRatio(
                aspectRatio: 0.8,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _canCapture ? Colors.green : Colors.yellow,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          // Top overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Position your face in the frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ✅ Bottom manual capture button
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: _isCapturing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : ElevatedButton.icon(
                      onPressed: _canCapture && !_isCapturing
                          ? () async {
                              if (_isStreaming) {
                                await _cameraController.stopImageStream();
                                _isStreaming = false;
                              }
                              setState(() => _isCapturing = true);
                              try {
                                // ✅ Get current location
                                final location = await LocationService.getCurrentLocation();
                                final lat = location?['latitude'] as double?;
                                final lng = location?['longitude'] as double?;
                                final timestamp = DateTime.now();

                                // ✅ Capture photo
                                final photo = await _cameraController.takePicture();

                                if (mounted) {
                                  // ✅ Pass photo with location and timestamp
                                  Navigator.pop(context, {
                                    'photo': photo,
                                    'latitude': lat,
                                    'longitude': lng,
                                    'timestamp': timestamp,
                                  });
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Capture failed: $e')),
                                  );
                                }
                                _resetUi(restartStream: true);
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canCapture ? Colors.green : Colors.grey,
                        disabledBackgroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      ),
                      icon: const Icon(Icons.camera, color: Colors.white),
                      label: const Text(
                        'Capture',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ✅ Custom painter for drawing face detection rectangle overlay with ROUNDED CORNERS
class FaceRectPainter extends CustomPainter {
  final Rect faceRect;
  final Color color;
  final double strokeWidth;
  final double cornerRadius;  // ✅ Rounded corners radius

  FaceRectPainter({
    required this.faceRect,
    required this.color,
    this.strokeWidth = 3,
    this.cornerRadius = 24,  // ✅ Nice rounded corners
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ✅ Draw rounded rectangle frame around face with BIG ROUNDED CORNERS
    final rrect = RRect.fromRectAndRadius(faceRect, Radius.circular(cornerRadius));
    canvas.drawRRect(rrect, paint);

    // ✅ Optional: Draw corner brackets with rounded corners
    final cornerLength = 24.0;
    final cornerPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth + 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Top-left corner bracket
    canvas.drawLine(
      Offset(faceRect.left, faceRect.top + cornerLength),
      Offset(faceRect.left, faceRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(faceRect.left, faceRect.top),
      Offset(faceRect.left + cornerLength, faceRect.top),
      cornerPaint,
    );

    // Top-right corner bracket
    canvas.drawLine(
      Offset(faceRect.right - cornerLength, faceRect.top),
      Offset(faceRect.right, faceRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(faceRect.right, faceRect.top),
      Offset(faceRect.right, faceRect.top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner bracket
    canvas.drawLine(
      Offset(faceRect.left, faceRect.bottom - cornerLength),
      Offset(faceRect.left, faceRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(faceRect.left, faceRect.bottom),
      Offset(faceRect.left + cornerLength, faceRect.bottom),
      cornerPaint,
    );

    // Bottom-right corner bracket
    canvas.drawLine(
      Offset(faceRect.right - cornerLength, faceRect.bottom),
      Offset(faceRect.right, faceRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(faceRect.right, faceRect.bottom - cornerLength),
      Offset(faceRect.right, faceRect.bottom),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(FaceRectPainter oldDelegate) {
    return oldDelegate.faceRect != faceRect ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}
