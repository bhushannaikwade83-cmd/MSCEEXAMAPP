import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme.dart';
import '../core/supabase_client.dart';
import '../models/exam_student.dart';
import '../services/session_service.dart';
import 'student_subjects_screen.dart';

/// QR Code Scanner - Updated for actual exam_students schema
/// Scans QR codes containing seat_no or student_id
/// Shows all subjects for the student across all exam dates
class QrCodeScannerScreen extends StatefulWidget {
  const QrCodeScannerScreen({super.key});

  @override
  State<QrCodeScannerScreen> createState() => _QrCodeScannerScreenState();
}

class _QrCodeScannerScreenState extends State<QrCodeScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController();

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

  /// Fetch student by scanning QR code value
  /// QR contains: URL with encryptstudentId, seat_no, or student_id
  /// Returns ExamStudent with all subjects
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
      print('🔗 QR contains URL: $searchValue');

      try {
        final uri = Uri.parse(searchValue);
        print('📋 URL Parameters: ${uri.queryParameters}');

        // Try different parameter names
        String? encryptedId = uri.queryParameters['encryptstudentId'] ??
            uri.queryParameters['encriptstudentId'] ??  // Try with typo
            uri.queryParameters['studentId'] ??
            uri.queryParameters['student_id'] ??
            uri.queryParameters['id'];

        if (encryptedId != null && encryptedId.isNotEmpty) {
          searchValue = encryptedId;
          print('✅ Extracted encrypted ID: $searchValue');
        } else {
          // Try to extract any numeric value (like seat number)
          final numericMatch = RegExp(r'\d{10,}').firstMatch(searchValue);
          if (numericMatch != null) {
            searchValue = numericMatch.group(0)!;
            print('✅ Extracted numeric value: $searchValue');
          } else {
            print('❌ Could not extract ID from parameters: ${uri.queryParameters}');
            throw Exception('Could not extract student ID from QR URL. Parameters: ${uri.queryParameters}');
          }
        }
      } catch (e) {
        print('❌ Parse error: $e');
        throw Exception('Failed to parse QR URL: $e');
      }
    }

    print('🔍 Searching for student with: $searchValue');

    // Try multiple search strategies
    List<dynamic>? rows;

    // 1. Try by qr_code_value (encrypted ID or URL)
    try {
      final query = supabase
          .from('exam_students')
          .select()
          .eq('centre_code', _centerCode!)
          .eq('qr_code_value', searchValue);
      rows = await query;
      if ((rows as List).isNotEmpty) {
        print('✅ Found by qr_code_value');
      }
    } catch (e) {
      print('❌ Search by qr_code_value failed: $e');
    }

    // 2. Try by seat_no (if numeric and not found yet)
    if (rows == null || (rows as List).isEmpty) {
      if (RegExp(r'^\d+$').hasMatch(searchValue)) {
        try {
          final query = supabase
              .from('exam_students')
              .select()
              .eq('centre_code', _centerCode!)
              .ilike('seat_no', '%$searchValue%');
          rows = await query;
          if ((rows as List).isNotEmpty) {
            print('✅ Found by seat_no');
          }
        } catch (_) {}
      }
    }

    // 3. Try by exam_student_id (UUID)
    if (rows == null || (rows as List).isEmpty) {
      try {
        final query = supabase
            .from('exam_students')
            .select()
            .eq('centre_code', _centerCode!)
            .eq('exam_student_id', searchValue);
        rows = await query;
        if ((rows as List).isNotEmpty) {
          print('✅ Found by exam_student_id');
        }
      } catch (_) {}
    }

    if (rows == null || (rows as List).isEmpty) {
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

    // ✅ Fetch ALL subjects for this STUDENT by institute_id + student_name + centre_code
    print('🔍 QR Scanner: Fetching ALL subjects for institute_id=$instituteId, student_name=$studentName, centre_code=$_centerCode');

    final allSubjectsQuery = supabase
        .from('exam_students')
        // ✅ Include sr_no for display in StudentSubjectsScreen
        .select('id, subject_name, exam_date, start_time, exam_student_id, seat_no, sr_no, batch, entry_photo_url, is_enabled')
        .eq('institute_id', instituteId)
        .eq('student_name', studentName)
        .eq('centre_code', _centerCode!);

    final allSubjectRows = await allSubjectsQuery;
    print('✅ QR Scanner: Found ${allSubjectRows.length} subject rows for student=$studentName');

    for (final raw in allSubjectRows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      print('  📚 Subject: ${row['subject_name']} | exam_student_id: ${row['exam_student_id']} | Date: ${row['exam_date']} | Time: ${row['start_time']}');
    }

    final subjects = <String>[];

    for (final raw in allSubjectRows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final subjectName = row['subject_name']?.toString() ??
                          row['subject_code']?.toString() ?? '';
      if (subjectName.isNotEmpty && !subjects.contains(subjectName)) {
        subjects.add(subjectName);
        print('  ✅ Added subject: $subjectName');
      }
    }
    print('✅ QR Scanner: Total unique subjects: ${subjects.length}');

    // ✅ Get first exam_student_id for creating ExamStudent object
    final firstExamStudentId = firstRow['exam_student_id']?.toString() ?? '';

    // ✅ Create ExamStudent object - StudentSubjectsScreen will load full exam_students rows
    return ExamStudent(
      id: firstExamStudentId,  // ✅ Use first exam_student_id
      seatNo: firstRow['seat_no']?.toString() ?? '',
      name: studentName,
      examTime: DateTime.now(),
      passportPhotoUrl: photoUrl.isNotEmpty ? photoUrl : null,
      subjects: subjects,  // ✅ All subject names
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

      // Navigate to student subjects screen
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => StudentSubjectsScreen(student: student),
        ),
      );

      // Reset scanner after navigation back
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = null;
        });
        await _cameraController.start();
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

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Student QR Code'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
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
                        const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'Camera Error: ${error.toString()}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => _cameraController.start(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                // Overlay with scanning guide
                _buildScannerOverlay(),
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

  Widget _buildScannerOverlay() {
    const cutOutSize = 280.0;

    return Stack(
      children: [
        // Dimmed areas
        Container(
          decoration: ShapeDecoration(
            shape: QrScannerOverlayShape(
              borderColor: AppColors.primary,
              borderRadius: 10,
              borderLength: 30,
              borderWidth: 4,
              cutOutSize: cutOutSize,
            ),
          ),
        ),
        // Instructions
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      ],
    );
  }
}

/// Custom shape for QR scanner overlay
class QrScannerOverlayShape extends ShapeBorder {
  QrScannerOverlayShape({
    this.borderColor = Colors.white,
    this.borderWidth = 3,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 0.5),
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRect(rect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final cutOutRect = Rect.fromLTWH(
      rect.center.dx - cutOutSize / 2,
      rect.center.dy - cutOutSize / 2,
      cutOutSize,
      cutOutSize,
    );

    _paintOverlay(canvas, rect, cutOutRect);
    _paintBorders(canvas, cutOutRect);
  }

  void _paintBorders(Canvas canvas, Rect cutOutRect) {
    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;

    // Top-left corner
    canvas.drawLine(
      Offset(cutOutRect.left, cutOutRect.top + borderLength),
      Offset(cutOutRect.left, cutOutRect.top),
      paint,
    );
    canvas.drawLine(
      Offset(cutOutRect.left, cutOutRect.top),
      Offset(cutOutRect.left + borderLength, cutOutRect.top),
      paint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(cutOutRect.right - borderLength, cutOutRect.top),
      Offset(cutOutRect.right, cutOutRect.top),
      paint,
    );
    canvas.drawLine(
      Offset(cutOutRect.right, cutOutRect.top),
      Offset(cutOutRect.right, cutOutRect.top + borderLength),
      paint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(cutOutRect.right, cutOutRect.bottom - borderLength),
      Offset(cutOutRect.right, cutOutRect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(cutOutRect.right, cutOutRect.bottom),
      Offset(cutOutRect.right - borderLength, cutOutRect.bottom),
      paint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(cutOutRect.left + borderLength, cutOutRect.bottom),
      Offset(cutOutRect.left, cutOutRect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(cutOutRect.left, cutOutRect.bottom),
      Offset(cutOutRect.left, cutOutRect.bottom - borderLength),
      paint,
    );
  }

  void _paintOverlay(Canvas canvas, Rect rect, Rect cutOutRect) {
    final paint = Paint()..color = overlayColor;

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(rect),
        Path()..addRRect(RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius))),
      ),
      paint,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      overlayColor: overlayColor,
      borderRadius: borderRadius * t,
      borderLength: borderLength * t,
      cutOutSize: cutOutSize * t,
    );
  }
}
