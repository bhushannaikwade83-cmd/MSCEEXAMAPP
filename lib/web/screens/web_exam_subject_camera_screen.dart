import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_ui.dart';
import '../services/web_camera_service.dart';

/// Web version of exam subject camera screen
/// Captures photo from webcam for entry marking
class WebExamSubjectCameraScreen extends StatefulWidget {
  const WebExamSubjectCameraScreen({
    super.key,
    required this.studentName,
    required this.subjectName,
  });

  final String studentName;
  final String subjectName;

  @override
  State<WebExamSubjectCameraScreen> createState() =>
      _WebExamSubjectCameraScreenState();
}

class _WebExamSubjectCameraScreenState
    extends State<WebExamSubjectCameraScreen> {
  bool _cameraReady = false;
  bool _isCapturing = false;
  String? _error;
  Uint8List? _capturedPhoto;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      debugPrint('📷 Initializing web camera...');

      // Create video and canvas elements for web
      WebCameraService.createVideoElement(
        videoElementId: 'exam-webcam-video',
        width: 640,
        height: 480,
      );

      WebCameraService.createCanvasElement(
        canvasElementId: 'exam-webcam-canvas',
      );

      // Request permission and start stream
      final hasPermission = await WebCameraService.requestCameraPermission();
      if (!hasPermission) {
        if (mounted) {
          setState(() => _error = 'Camera permission denied');
        }
        return;
      }

      await WebCameraService.startWebcamStream(
        videoElementId: 'exam-webcam-video',
        facingMode: true, // Front camera
      );

      if (mounted) {
        setState(() => _cameraReady = true);
      }
    } catch (e) {
      debugPrint('❌ Camera init error: $e');
      if (mounted) {
        setState(() => _error = 'Camera error: $e');
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (!_cameraReady) return;

    setState(() => _isCapturing = true);

    try {
      debugPrint('📸 Capturing photo...');

      // Capture from webcam
      Uint8List photoBytes =
          await WebCameraService.capturePhotoFromWebcam();

      // Compress photo to under 1MB
      photoBytes =
          await WebCameraService.compressPhotoToUnder1MB(photoBytes);

      setState(() => _capturedPhoto = photoBytes);
      debugPrint('✅ Photo captured: ${photoBytes.length} bytes');
    } catch (e) {
      debugPrint('❌ Capture error: $e');
      if (mounted) {
        setState(() => _error = 'Failed to capture photo: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  void _retakePhoto() {
    setState(() => _capturedPhoto = null);
  }

  void _confirmCapture() {
    if (_capturedPhoto == null) return;

    WebCameraService.cleanup(
      videoElementId: 'exam-webcam-video',
      canvasElementId: 'exam-webcam-canvas',
    );

    Navigator.pop(context, {
      'photoBytes': _capturedPhoto,
      'timestamp': DateTime.now(),
    });
  }

  @override
  void dispose() {
    WebCameraService.cleanup(
      videoElementId: 'exam-webcam-video',
      canvasElementId: 'exam-webcam-canvas',
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Capture Entry Photo'),
        elevation: 0,
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            WebCameraService.cleanup(
              videoElementId: 'exam-webcam-video',
              canvasElementId: 'exam-webcam-canvas',
            );
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: _capturedPhoto != null
            ? _buildPhotoReview()
            : _buildCameraView(),
      ),
    );
  }

  Widget _buildCameraView() {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 800.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 20.h),

              // Info Card
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16.w),
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Student: ${widget.studentName}',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Subject: ${widget.subjectName}',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 20.h),

              if (_error != null)
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16.w),
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 20.sp,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          _error ?? '',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (!_cameraReady)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        color: AppTheme.primaryBlue,
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        'Initializing camera...',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        height: 400.h,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primaryBlue,
                            width: 2,
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Camera feed will be rendered here via HtmlElementView in web
                            Center(
                              child: Text(
                                'Webcam feed will appear here',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.sp,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 20.h),
                      SizedBox(
                        width: double.infinity,
                        height: 56.h,
                        child: ElevatedButton.icon(
                          onPressed: _isCapturing ? null : _capturePhoto,
                          icon: _isCapturing
                              ? SizedBox(
                                  width: 20.w,
                                  height: 20.w,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.camera_alt),
                          label: Text(
                            _isCapturing ? 'Capturing...' : 'Capture Photo',
                            style: TextStyle(fontSize: 16.sp),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              SizedBox(height: 20.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoReview() {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 800.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 20.h),

              // Photo Display
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16.w),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Container(
                      color: Colors.grey.shade100,
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      child: Text(
                        'Captured Photo',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ),
                    Image.memory(
                      _capturedPhoto!,
                      height: 400.h,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24.h),

              // Buttons
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 56.h,
                      child: ElevatedButton.icon(
                        onPressed: _confirmCapture,
                        icon: const Icon(Icons.check_circle),
                        label: Text(
                          'Use This Photo',
                          style: TextStyle(fontSize: 16.sp),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    SizedBox(
                      height: 56.h,
                      child: OutlinedButton.icon(
                        onPressed: _retakePhoto,
                        icon: const Icon(Icons.camera_alt),
                        label: Text(
                          'Retake Photo',
                          style: TextStyle(fontSize: 16.sp),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryBlue,
                          side: const BorderSide(
                            color: AppTheme.primaryBlue,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 20.h),
            ],
          ),
        ),
      ),
    );
  }
}
