import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'dart:ui_web' as ui;
import '../services/web_camera_service.dart';
import '../../core/theme/app_ui.dart';

/// Web camera capture dialog
/// Shows webcam preview and capture button
class WebCameraDialog extends StatefulWidget {
  const WebCameraDialog({
    super.key,
    required this.onPhotoCapture,
    this.studentName = 'Student',
    this.subjectName = 'Subject',
  });

  final Function(Uint8List photoBytes) onPhotoCapture;
  final String studentName;
  final String subjectName;

  @override
  State<WebCameraDialog> createState() => _WebCameraDialogState();
}

class _WebCameraDialogState extends State<WebCameraDialog> {
  bool _cameraReady = false;
  bool _isCapturing = false;
  String _statusMessage = 'Initializing camera...';

  static const String _videoId = 'webcam-video';
  static const String _canvasId = 'webcam-canvas';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      setState(() => _statusMessage = 'Requesting camera permission...');

      // Check permission
      final hasPermission = await WebCameraService.requestCameraPermission();
      if (!hasPermission) {
        if (!mounted) return;
        setState(() => _statusMessage = 'Camera not supported in this browser');
        return;
      }

      // Create elements
      WebCameraService.createVideoElement(
        videoElementId: _videoId,
        width: 640,
        height: 480,
      );

      WebCameraService.createCanvasElement(
        canvasElementId: _canvasId,
      );

      // Start stream
      await WebCameraService.startWebcamStream(
        videoElementId: _videoId,
        facingMode: true, // User-facing camera
      );

      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _statusMessage = 'Camera ready - Click capture to take photo';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Camera error: $e');
    }
  }

  Future<void> _capturePhoto() async {
    try {
      setState(() {
        _isCapturing = true;
        _statusMessage = 'Capturing photo...';
      });

      // Capture from webcam
      final photoBytes = await WebCameraService.capturePhotoFromWebcam();

      setState(() => _statusMessage = 'Compressing photo...');

      // Compress
      final compressed = await WebCameraService.compressPhotoToUnder1MB(photoBytes);

      // Call callback
      widget.onPhotoCapture(compressed);

      if (!mounted) return;

      // Close dialog
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _statusMessage = 'Capture failed: $e';
      });
    }
  }

  @override
  void dispose() {
    // Stop webcam
    WebCameraService.stopWebcamStream(videoElementId: _videoId);
    // Don't cleanup elements here - let dialog close first
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 700.w,
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.camera_alt, color: AppTheme.primaryBlue, size: 24),
                SizedBox(width: 12.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Capture Entry Photo',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    Text(
                      '${widget.studentName} - ${widget.subjectName}',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppTheme.textGray,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 20.h),

            // Video preview area
            if (_cameraReady)
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: Container(
                  width: double.infinity,
                  height: 400.h,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: AppTheme.primaryBlue, width: 2),
                  ),
                  child: HtmlElementView(
                    viewType: _videoId,
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                height: 400.h,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.primaryBlue),
                      SizedBox(height: 16.h),
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppTheme.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(height: 16.h),

            // Status message
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: _isCapturing
                    ? AppTheme.accentSaffron.withValues(alpha: 0.1)
                    : _cameraReady
                        ? AppTheme.primaryGreen.withValues(alpha: 0.1)
                        : AppTheme.accentRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: Text(
                _statusMessage,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: _isCapturing
                      ? AppTheme.accentSaffron
                      : _cameraReady
                          ? AppTheme.primaryGreen
                          : AppTheme.accentRed,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 20.h),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Cancel button
                TextButton(
                  onPressed: _isCapturing ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppTheme.textGray,
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                // Capture button
                ElevatedButton.icon(
                  onPressed: _cameraReady && !_isCapturing ? _capturePhoto : null,
                  icon: const Icon(Icons.camera),
                  label: Text(
                    _isCapturing ? 'Capturing...' : 'Capture Photo',
                    style: TextStyle(fontSize: 13.sp),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    disabledBackgroundColor: AppTheme.dividerColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
