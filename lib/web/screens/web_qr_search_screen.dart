import 'dart:convert' show jsonDecode;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_ui.dart';
import '../../core/supabase_client.dart';
import '../../models/exam_student.dart';
import '../../services/session_service.dart';
import 'web_student_subjects_screen.dart';

/// Web version of QR Scanner - Manual search instead of scanning
/// Allows searching by seat number or QR code value
class WebQrSearchScreen extends StatefulWidget {
  const WebQrSearchScreen({super.key});

  @override
  State<WebQrSearchScreen> createState() => _WebQrSearchScreenState();
}

class _WebQrSearchScreenState extends State<WebQrSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String? _errorMessage;
  String? _centreCode;

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
      _centreCode = center['code'];
      _errorMessage = null;
    });
  }

  /// Search for student by seat number or QR code value
  Future<void> _searchStudent(String searchValue) async {
    if (searchValue.trim().isEmpty) {
      setState(() => _errorMessage = 'Enter seat number or QR code');
      return;
    }

    if (_centreCode == null) {
      setState(() => _errorMessage = 'Center not configured');
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      debugPrint('🔍 Searching for: $searchValue');

      var searchQuery = searchValue.trim();

      // Fetch from exam_students table
      List<dynamic>? rows;

      // 1. Try by qr_code_value
      try {
        rows = await supabase
            .from('exam_students')
            .select()
            .eq('centre_code', _centreCode!)
            .eq('qr_code_value', searchQuery);

        if ((rows as List).isNotEmpty) {
          debugPrint('✅ Found by qr_code_value');
        }
      } catch (e) {
        debugPrint('⚠️ QR code search failed: $e');
      }

      // 2. Try by seat_no if numeric
      if (rows == null || (rows as List).isEmpty) {
        if (RegExp(r'^\d+$').hasMatch(searchQuery)) {
          try {
            rows = await supabase
                .from('exam_students')
                .select()
                .eq('centre_code', _centreCode!)
                .ilike('seat_no', '%$searchQuery%');

            if ((rows as List).isNotEmpty) {
              debugPrint('✅ Found by seat_no');
            }
          } catch (e) {
            debugPrint('⚠️ Seat number search failed: $e');
          }
        }
      }

      // 3. Try by exam_student_id (UUID)
      if (rows == null || (rows as List).isEmpty) {
        try {
          rows = await supabase
              .from('exam_students')
              .select()
              .eq('centre_code', _centreCode!)
              .eq('exam_student_id', searchQuery);

          if ((rows as List).isNotEmpty) {
            debugPrint('✅ Found by exam_student_id');
          }
        } catch (e) {
          debugPrint('⚠️ ID search failed: $e');
        }
      }

      if (rows == null || (rows as List).isEmpty) {
        setState(() => _errorMessage = 'Student not found');
        return;
      }

      // Get unique student
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
        setState(() => _errorMessage = 'Could not identify student');
        return;
      }

      final firstRow = studentRows[0];
      final studentName = firstRow['student_name']?.toString() ?? 'Unknown';
      final photoUrl = firstRow['photo_url']?.toString() ?? '';
      final firstExamStudentId = firstRow['exam_student_id']?.toString() ?? '';

      // Fetch all subjects for this student
      final allSubjectRows = await supabase
          .from('exam_students')
          .select()
          .eq('student_name', studentName)
          .eq('centre_code', _centreCode!);

      debugPrint('✅ Found ${allSubjectRows.length} subjects for $studentName');

      final subjects = <String>[];
      for (final raw in allSubjectRows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final subjectName = row['subject_name']?.toString() ??
                           row['subject_code']?.toString() ?? '';
        if (subjectName.isNotEmpty && !subjects.contains(subjectName)) {
          subjects.add(subjectName);
        }
      }

      // Create ExamStudent object
      final student = ExamStudent(
        id: firstExamStudentId,
        seatNo: firstRow['seat_no']?.toString() ?? '',
        name: studentName,
        examTime: DateTime.now(),
        passportPhotoUrl: photoUrl.isNotEmpty ? photoUrl : null,
        subjects: subjects,
        isMarked: false,
      );

      if (!mounted) return;

      // Navigate to subject screen
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => WebStudentSubjectsScreen(student: student),
        ),
      );

      // Clear search after navigation back
      if (mounted) {
        _searchController.clear();
        setState(() => _errorMessage = null);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
      debugPrint('❌ Search error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Student'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _centreCode == null
          ? _buildErrorState()
          : SingleChildScrollView(
              padding: EdgeInsets.all(20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: AppTheme.dividerColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Find Student',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'Enter seat number or paste QR code value',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: AppTheme.textGray,
                          ),
                        ),
                        SizedBox(height: 16.h),
                        TextField(
                          controller: _searchController,
                          enabled: !_isSearching,
                          decoration: InputDecoration(
                            hintText: 'e.g., 1001 or 10111-2026-1001-...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 12.h,
                            ),
                          ),
                          onSubmitted: _isSearching
                              ? null
                              : (value) => _searchStudent(value),
                        ),
                        SizedBox(height: 16.h),
                        SizedBox(
                          width: double.infinity,
                          height: 48.h,
                          child: ElevatedButton.icon(
                            onPressed: _isSearching
                                ? null
                                : () => _searchStudent(_searchController.text),
                            icon: _isSearching
                                ? SizedBox(
                                    width: 20.w,
                                    height: 20.w,
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.search),
                            label: Text(
                              _isSearching ? 'Searching...' : 'Search',
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                              ),
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

                  // Error message
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(color: AppTheme.accentRed),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: AppTheme.accentRed,
                            size: 20,
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppTheme.accentRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: 20.h),

                  // Help section
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    padding: EdgeInsets.all(16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to Search',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        _helpItem('Seat Number', 'Enter just the seat number (e.g., 1001)'),
                        SizedBox(height: 6.h),
                        _helpItem('QR Code', 'Scan QR code and paste the full code value'),
                        SizedBox(height: 6.h),
                        _helpItem('Student ID', 'Enter exam_student_id if available'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: AppTheme.accentRed,
          ),
          SizedBox(height: 16.h),
          Text(
            _errorMessage ?? 'Center not configured',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16.sp, color: AppTheme.accentRed),
          ),
          SizedBox(height: 24.h),
          ElevatedButton(
            onPressed: _initializeCenter,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _helpItem(String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '•',
          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
              ),
              Text(
                description,
                style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
