import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/theme.dart';
import '../models/exam_student.dart';
import '../services/exam_data_service.dart';
import '../services/session_service.dart';

/// Staff compares seated student to passport photo — no automatic face matching.
class MarkEntryScreen extends StatefulWidget {
  const MarkEntryScreen({super.key, required this.student});

  final ExamStudent student;

  @override
  State<MarkEntryScreen> createState() => _MarkEntryScreenState();
}

class _MarkEntryScreenState extends State<MarkEntryScreen> {
  final _data = ExamDataService();
  bool _busy = false;
  String? _status;

  CameraController? _camera;
  bool _showCamera = false;
  bool _camLoading = false;
  String? _capturedPath;

  Future<void> _toggleCamera() async {
    if (_showCamera) {
      await _camera?.dispose();
      _camera = null;
      setState(() => _showCamera = false);
      return;
    }
    setState(() => _camLoading = true);
    try {
      final cams = await availableCameras();
      final cam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      _camera = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
      await _camera!.initialize();
      setState(() {
        _showCamera = true;
        _camLoading = false;
      });
    } catch (e) {
      setState(() {
        _camLoading = false;
        _status = 'Camera: $e';
      });
    }
  }

  Future<void> _capturePhoto() async {
    if (_camera == null || !_camera!.value.isInitialized) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/present_${widget.student.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final shot = await _camera!.takePicture();
    await File(shot.path).copy(path);
    setState(() => _capturedPath = path);
  }

  Future<void> _confirmPresent() async {
    setState(() {
      _busy = true;
      _status = 'Marking attendance…';
    });

    final center = await SessionService.getCenter();
    if (center == null) return;

    try {
      await _data.markAttendance(
        centerId: center['id']!,
        studentId: widget.student.id,
        presentPhotoPath: _capturedPath,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marked present'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _status = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    return Scaffold(
      appBar: AppBar(title: Text(s.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Is the student seated in the hall the same person as in the passport photo?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'No automatic comparison — you confirm by looking.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 20),
          Text(s.rollNumber, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 3),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: s.passportPhotoUrl != null && s.passportPhotoUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: s.passportPhotoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            const Center(child: CircularProgressIndicator()),
                        errorWidget: (_, _, _) => const _NoPhoto(),
                      )
                    : const _NoPhoto(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Passport photo (allotted)',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _camLoading ? null : _toggleCamera,
            icon: Icon(_showCamera ? Icons.close : Icons.camera_alt_outlined),
            label: Text(_showCamera ? 'Hide camera' : 'Optional: photo of seated student'),
          ),
          if (_showCamera && _camera != null && _camera!.value.isInitialized) ...[
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: _camera!.value.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CameraPreview(_camera!),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _capturePhoto,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Capture seated student (optional)'),
            ),
            if (_capturedPath != null)
              const Text('Photo saved with this mark', style: TextStyle(fontSize: 12, color: AppColors.success)),
          ],
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.accent)),
          ],
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _busy ? null : _confirmPresent,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.how_to_reg),
            label: Text(_busy ? 'Please wait…' : 'Yes — same student, mark present'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel — not the same / not seated'),
          ),
        ],
      ),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 4),
            Text('No passport photo', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
