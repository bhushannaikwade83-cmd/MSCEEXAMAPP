import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_ui.dart';
import '../../models/exam_student.dart';
import '../../services/session_service.dart';
import 'web_qr_search_screen.dart';
import 'web_student_subjects_screen.dart';

/// Web camera QR scanner.
///
/// Opens the device camera (rear on phones), scans the student QR code,
/// looks the student up (same logic as the native scanner) and opens
/// [WebStudentSubjectsScreen] where entry marking works as usual.
/// A manual-search fallback is offered if the camera is unavailable.
class WebQrCameraScannerScreen extends StatefulWidget {
  const WebQrCameraScannerScreen({super.key});

  @override
  State<WebQrCameraScannerScreen> createState() =>
      _WebQrCameraScannerScreenState();
}

class _WebQrCameraScannerScreenState extends State<WebQrCameraScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController(
    facing: CameraFacing.back, // Rear camera for scanning student cards
  );

  bool _isProcessing = false;
  String? _errorMessage;
  String? _centerId;
  String? _centerCode;

  @override
  void initState() {
    super.initState();
    _initializeCenter();
  }

  Future<void> _initializeCenter() async {
    final center = await SessionService.getCenter();
    if (!mounted) return;

    if (center == null) {
      setState(() => _errorMessage = 'Center not configured');
      return;
    }

    setState(() {
      _centerId = center['id'];
      _centerCode = center['code'];
      _errorMessage = null;
    });
  }

  /// Fetch student by scanned QR value.
  /// QR contains: URL with encryptstudentId, seat_no, or student_id.
  /// (Same lookup strategy as the native QrCodeScannerScreen.)
  Future<ExamStudent?> _fetchStudentByQr(String qrValue) async {
    if (_centerId == null || _centerCode == null) {
      throw Exception('Center not initialized');
    }

    var searchValue = qrValue.trim();
    if (searchValue.isEmpty) {
      throw Exception('Invalid QR code: empty value');
    }

    // If QR contains URL, extract encrypted ID or any numeric part
    if (searchValue.startsWith('http')) {
      try {
        final uri = Uri.parse(searchValue);

        String? encryptedId = uri.queryParameters['encryptstudentId'] ??
            uri.queryParameters['encriptstudentId'] ?? // Try with typo
            uri.queryParameters['studentId'] ??
            uri.queryParameters['student_id'] ??
            uri.queryParameters['id'];

        if (encryptedId != null && encryptedId.isNotEmpty) {
          searchValue = encryptedId;
        } else {
          final numericMatch = RegExp(r'\d{10,}').firstMatch(searchValue);
          if (numericMatch != null) {
            searchValue = numericMatch.group(0)!;
          } else {
            throw Exception(
                'Could not extract student ID from QR URL. Parameters: ${uri.queryParameters}');
          }
        }
      } catch (e) {
        throw Exception('Failed to parse QR URL: $e');
      }
    }

    // Try multiple search strategies
    List<dynamic>? rows;

    // 1. Try by qr_code_value (encrypted ID or URL)
    try {
      rows = await supabase
          .from('exam_students')
          .select()
          .eq('centre_code', _centerCode!)
          .eq('qr_code_value', searchValue);
    } catch (_) {}

    // 2. Try by seat_no (if numeric and not found yet)
    if (rows == null || rows.isEmpty) {
      if (RegExp(r'^\d+$').hasMatch(searchValue)) {
        try {
          rows = await supabase
              .from('exam_students')
              .select()
              .eq('centre_code', _centerCode!)
              .ilike('seat_no', '%$searchValue%');
        } catch (_) {}
      }
    }

    // 3. Try by exam_student_id (UUID)
    if (rows == null || rows.isEmpty) {
      try {
        rows = await supabase
            .from('exam_students')
            .select()
            .eq('centre_code', _centerCode!)
            .eq('exam_student_id', searchValue);
      } catch (_) {}
    }

    if (rows == null || rows.isEmpty) {
      throw Exception('Student not found. Searched for: $searchValue');
    }

    // Group by exam_student_id to get unique student
    final studentRows = <Map<String, dynamic>>[];
    final examStudentIds = <String>{};

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final examStudentId = row['exam_student_id']?.toString() ?? '';
      if (examStudentId.isNotEmpty && !examStudentIds.contains(examStudentId)) {
        examStudentIds.add(examStudentId);
        studentRows.add(row);
      }
    }

    if (studentRows.isEmpty) {
      throw Exception('Could not identify student');
    }

    final firstRow = studentRows[0];
    final studentName = firstRow['student_name']?.toString() ?? 'Unknown';
    final photoUrl = firstRow['photo_url']?.toString() ?? '';
    final instituteId = firstRow['institute_id']?.toString() ?? '';

    // Fetch ALL subjects for this student
    final allSubjectRows = await supabase
        .from('exam_students')
        .select(
            'id, subject_name, exam_date, start_time, exam_student_id, seat_no, sr_no, batch, entry_photo_url, is_enabled')
        .eq('institute_id', instituteId)
        .eq('student_name', studentName)
        .eq('centre_code', _centerCode!);

    final subjects = <String>[];
    for (final raw in allSubjectRows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final subjectName = row['subject_name']?.toString() ??
          row['subject_code']?.toString() ??
          '';
      if (subjectName.isNotEmpty && !subjects.contains(subjectName)) {
        subjects.add(subjectName);
      }
    }

    final firstExamStudentId = firstRow['exam_student_id']?.toString() ?? '';

    return ExamStudent(
      id: firstExamStudentId,
      seatNo: firstRow['seat_no']?.toString() ?? '',
      name: studentName,
      examTime: DateTime.now(),
      passportPhotoUrl: photoUrl.isNotEmpty ? photoUrl : null,
      subjects: subjects,
      isMarked: false,
    );
  }

  Future<void> _handleQrCode(String qrValue) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final student = await _fetchStudentByQr(qrValue);

      if (!mounted) return;

      if (student == null) {
        setState(() => _isProcessing = false);
        _showErrorDialog('Student Not Found', 'Could not fetch student details');
        return;
      }

      // Pause camera while on the subjects screen
      try {
        await _cameraController.stop();
      } catch (_) {}

      if (!mounted) return;

      // Navigate to student subjects screen (Mark Entry works as usual)
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => WebStudentSubjectsScreen(student: student),
        ),
      );

      // Reset scanner after navigation back
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = null;
        });
        try {
          await _cameraController.start();
        } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString();
      });
      _showErrorDialog('Scan Error', e.toString());
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _openManualSearch() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WebQrSearchScreen()),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Student QR Code'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Search manually',
            icon: const Icon(Icons.keyboard),
            onPressed: _openManualSearch,
          ),
        ],
      ),
      body: _errorMessage != null && _centerId == null
          ? _buildErrorState()
          : Stack(
              children: [
                // Scanner view
                MobileScanner(
                  controller: _cameraController,
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null) {
                        _handleQrCode(barcode.rawValue!);
                        break;
                      }
                    }
                  },
                  errorBuilder: (context, error) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.camera_alt_outlined,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'Camera Error: $error\n\n'
                            'Allow camera access in the browser, or use manual search.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: () => _cameraController.start(),
                              child: const Text('Retry'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: _openManualSearch,
                              child: const Text('Search manually'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Scanning guide overlay
                Center(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.primaryBlue, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Position QR code within frame',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                // Processing indicator
                if (_isProcessing)
                  Container(
                    color: Colors.black.withValues(alpha: 0.6),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Processing...',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Unknown error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.red),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _initializeCenter,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
