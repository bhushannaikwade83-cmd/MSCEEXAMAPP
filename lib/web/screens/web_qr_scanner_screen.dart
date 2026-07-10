import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_ui.dart';
import '../../models/exam_student.dart';
import '../../services/msce_student_service.dart';
import '../../services/session_service.dart';
import 'web_qr_search_screen.dart';
import 'web_student_subjects_screen.dart';

/// Web QR Code Scanner - delegates to QR search screen
/// Alternative to mobile camera-based QR scanner
class WebQrCodeScannerScreen extends StatefulWidget {
  const WebQrCodeScannerScreen({super.key});

  @override
  State<WebQrCodeScannerScreen> createState() => _WebQrCodeScannerScreenState();
}

class _WebQrCodeScannerScreenState extends State<WebQrCodeScannerScreen> {
  final MsceStudentService _studentService = MsceStudentService();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _searching = false;
  String? _centerId;
  String? _centerCode;
  String? _error;
  ExamStudent? _foundStudent;

  @override
  void initState() {
    super.initState();
    _initializeCenter();
  }

  Future<void> _initializeCenter() async {
    final center = await SessionService.getCenter();
    if (!mounted) return;

    if (center == null) {
      setState(() => _error = 'Center not configured');
      return;
    }

    setState(() {
      _centerId = center['id'];
      _centerCode = center['code'];
      _error = null;
    });
  }

  Future<void> _searchStudent(String query) async {
    if (query.isEmpty) {
      setState(() {
        _foundStudent = null;
        _error = null;
      });
      return;
    }

    if (_centerId == null || _centerCode == null) {
      setState(() => _error = 'Center not initialized');
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      // Search by name, seat, or ID
      final students = await _studentService.loadFromExamStudentsTable(
        centerId: _centerId!,
        centerCode: _centerCode,
        search: query,
      );

      if (!mounted) return;

      if (students.isEmpty) {
        setState(() {
          _foundStudent = null;
          _error = 'No student found matching "$query"';
        });
      } else {
        setState(() {
          _foundStudent = students.first;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Search error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  void _openStudentSubjects() {
    if (_foundStudent == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebStudentSubjectsScreen(student: _foundStudent!),
      ),
    );
  }

  void _openQrSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WebQrSearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Code Scanner'),
        elevation: 0,
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 600.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Info Card
                  Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade900,
                          size: 24.sp,
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Text(
                            'Search for a student by name, seat number, or scan a QR code.',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24.h),

                  // Search Field
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      labelText: 'Search Student',
                      hintText: 'Enter name, seat number, or paste QR value',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {
                                  _foundStudent = null;
                                  _error = null;
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.dividerColor,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.dividerColor,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryBlue,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: _searchStudent,
                  ),

                  SizedBox(height: 16.h),

                  // QR Search Button
                  SizedBox(
                    height: 48.h,
                    child: OutlinedButton.icon(
                      onPressed: _openQrSearch,
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Scan QR Code'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryBlue,
                        side: const BorderSide(
                          color: AppTheme.primaryBlue,
                          width: 2,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 24.h),

                  // Search Results
                  if (_searching)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.h),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          SizedBox(height: 12.h),
                          Text(
                            'Searching...',
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_error != null)
                    Container(
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
                              _error!,
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.red.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_foundStudent != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: EdgeInsets.all(16.w),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            border: Border.all(color: Colors.green),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Student Found',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade900,
                                ),
                              ),
                              SizedBox(height: 12.h),
                              Text(
                                _foundStudent!.name,
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade900,
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                'Seat: ${_foundStudent!.seatNo}',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16.h),
                        SizedBox(
                          height: 56.h,
                          child: ElevatedButton.icon(
                            onPressed: _openStudentSubjects,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('View Subjects'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (_searchCtrl.text.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 32.h),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search,
                            size: 48.sp,
                            color: Colors.grey.shade400,
                          ),
                          SizedBox(height: 12.h),
                          Text(
                            'Enter a search query to find students',
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
