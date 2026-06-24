import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../core/camera_lens_utils.dart';
import '../core/camera_stream_pipeline.dart';
import '../services/anti_spoof_service.dart';
import '../services/distance_check_service.dart' show DistanceStatus;
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
    requiredBlinks: 1,
    screenSpoofFramesRequired: 2,
    minPadLiveStreak: 3,
    enableStreamPad: false,
    enableStreamScreenSpoof: false,
    requireLiveFaceBeforeLiveness: false,
  );

  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;
  bool _isStreaming = false;
  bool _isInitializing = true;
  bool _isCapturing = false;
  bool _capturePending = false;
  bool _isProcessingFrame = false;

  DistanceStatus _distanceStatus = DistanceStatus.noFace;
  bool _canCapture = false;
  String _livenessMessage = 'Blink your eyes to capture';

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

      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableClassification: true,
        ),
      );

      if (mounted) {
        setState(() => _isInitializing = false);
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
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await _cameraController.initialize();
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
        final faces = await _faceDetector.processImage(mlInput.inputImage);
        if (!mounted) return;

        if (faces.isEmpty) {
          _livenessTracker.reset();
          setState(() {
            _distanceStatus = DistanceStatus.noFace;
            _canCapture = false;
            _livenessMessage = 'No face detected';
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

        if (_capturePending && _livenessTracker.mayCaptureNow) {
          final faceRect = PreCaptureLivenessTracker.mapFaceRectToCameraBuffer(
            image: image,
            face: face,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
          );
          await _finishCapture(image, faceRect);
          return;
        }

        final live = _livenessTracker.evaluate(
          image: image,
          face: face,
          displayWidth: displayWidth,
          displayHeight: displayHeight,
        );

        setState(() {
          _distanceStatus = live.distanceStatus;
          _canCapture = live.canCapture && _livenessTracker.mayCaptureNow;
          _livenessMessage = live.livenessMessage;
        });

        if (_canCapture && !_isCapturing && !_capturePending) {
          final faceRect = PreCaptureLivenessTracker.mapFaceRectToCameraBuffer(
            image: image,
            face: face,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
          );
          setState(() => _capturePending = true);
          if (_livenessTracker.mayCaptureNow) {
            await _finishCapture(image, faceRect);
          }
        }
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
    });
    if (restartStream && !_isStreaming && _cameraController.value.isInitialized) {
      _startStream();
    }
  }

  @override
  void dispose() {
    if (_isStreaming) {
      _isStreaming = false;
      _cameraController.stopImageStream();
    }
    _cameraController.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Color get _statusColor {
    if (_isCapturing || _capturePending) return Colors.blue;
    if (_canCapture) return Colors.green;
    if (_distanceStatus == DistanceStatus.noFace) return Colors.orange;
    return Colors.yellow;
  }

  String get _statusText {
    if (_isCapturing || _capturePending) return 'Capturing…';
    if (_canCapture) return '✅ Blink detected! Capturing…';
    if (_distanceStatus == DistanceStatus.noFace) return 'No face detected';
    if (_distanceStatus == DistanceStatus.tooFar) return 'Move closer';
    if (_distanceStatus == DistanceStatus.tooClosed) return 'Move back';
    return _livenessMessage;
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
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cameraController.value.previewSize?.width ?? 1920,
                height: _cameraController.value.previewSize?.height ?? 1080,
                child: CameraPreview(_cameraController),
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
                  if (!_canCapture && _distanceStatus != DistanceStatus.noFace) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Blinks: ${_livenessTracker.blinksDetected}/1',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Bottom capture button (manual fallback)
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: (_isCapturing || _capturePending)
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'Blink to auto-capture',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
