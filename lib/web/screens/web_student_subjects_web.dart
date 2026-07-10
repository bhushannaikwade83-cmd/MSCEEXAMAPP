import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_ui.dart';
import '../../core/supabase_client.dart';
import '../../models/exam_student.dart';
import '../../presentation/widgets/secure_network_image.dart';
import '../../services/session_service.dart';
import '../../services/cache_clear_service.dart';
import '../services/web_camera_service.dart';
import '../services/web_storage_service.dart';
import 'web_exam_subject_camera_screen.dart';

class WebStudentSubjectsScreen extends StatefulWidget {
  const WebStudentSubjectsScreen({super.key, required this.student});

  final ExamStudent student;

  @override
  State<WebStudentSubjectsScreen> createState() =>
      _WebStudentSubjectsScreenState();
}

class _WebStudentSubjectsScreenState extends State<WebStudentSubjectsScreen> {
  List<Map<String, dynamic>> _subjectDetails = [];
  bool _loading = true;
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _loadSubjectDetails();
  }

  Future<void> _loadSubjectDetails() async {
    try {
      final center = await SessionService.getCenter();
      final centreCode = center?['code']?.toString() ?? '';

      if (centreCode.isEmpty && !mounted) return;

      final rows = await supabase
          .from('exam_students')
          .select()
          .eq('student_name', widget.student.name)
          .eq('centre_code', centreCode);

      if (!mounted) return;

      print(
          '✅ WebStudentSubjectsScreen: Loaded ${rows.length} subjects for ${widget.student.name}');

      final sortedRows = List<Map<String, dynamic>>.from(rows as List);
      sortedRows.sort((a, b) {
        final dateA = a['exam_date']?.toString() ?? '';
        final dateB = b['exam_date']?.toString() ?? '';
        final timeA = a['start_time']?.toString() ?? '';
        final timeB = b['start_time']?.toString() ?? '';

        final parsedA = DateTime.tryParse(
                '${dateA}T${timeA.split('+').first.split('-').first.trim()}') ??
            DateTime.now();
        final parsedB = DateTime.tryParse(
                '${dateB}T${timeB.split('+').first.split('-').first.trim()}') ??
            DateTime.now();

        return parsedA.compareTo(parsedB);
      });

      setState(() {
        _subjectDetails = sortedRows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading subjects: $e'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
  }

  Future<void> _onEntryTap(Map<String, dynamic> subject) async {
    await CacheClearService.clearAllCaches();

    final examStudentId = subject['id']?.toString() ?? '';
    final subjectName = subject['subject_name']?.toString() ??
        subject['subject_code']?.toString() ??
        subject['subject']?.toString() ??
        '';
    final studentName = widget.student.name;

    if (examStudentId.isEmpty || subjectName.isEmpty) {
      if (mounted) {
        debugPrint('Subject fields: ${subject.keys}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subject info missing'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => WebExamSubjectCameraScreen(
          studentName: studentName,
          subjectName: subjectName,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final photoBytes = result['photoBytes'] as Uint8List?;
    final timestamp = result['timestamp'] as DateTime?;

    if (photoBytes == null) return;

    setState(() => _saving.add(examStudentId));

    try {
      final instituteId =
          subject['institute_id']?.toString() ?? subject['centre_id']?.toString() ?? '';
      if (instituteId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Institute ID not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final center = await SessionService.getCenter();
      if (center == null) return;

      final seatNo = subject['seat_no']?.toString() ?? '';
      final examDate = subject['exam_date']?.toString() ?? DateTime.now().toString().split(' ')[0];
      final dateObj = DateTime.tryParse(examDate);
      final year = dateObj?.year.toString() ?? '2026';

      // Upload photo using web storage service
      final uploadResult = await WebStorageService.uploadEntryPhotoWeb(
        centreCode: center['code'] ?? '',
        folderYear: year,
        seatNo: seatNo,
        subject: subjectName,
        date: examDate,
        photoBytes: photoBytes,
      );

      final photoUrl = uploadResult['url'] ?? '';

      // Mark entry in database
      await supabase
          .from('exam_entries')
          .insert({
            'exam_student_id': examStudentId,
            'entry_marked_at': DateTime.now().toIso8601String(),
            'entry_photo_url': photoUrl,
            'latitude': null,
            'longitude': null,
            'device_type': 'web',
          });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entry marked successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _loadSubjectDetails();
      }
    } catch (e) {
      debugPrint('Error marking entry: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _saving.remove(examStudentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.student.name),
        elevation: 0,
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 800.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Student Info Card
                      Container(
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 60.w,
                              height: 60.w,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.grey.shade200,
                              ),
                              child: widget.student.passportPhotoUrl != null &&
                                      widget.student.passportPhotoUrl!.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SecureNetworkImage(
                                        imageUrl:
                                            widget.student.passportPhotoUrl!,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Icon(
                                      Icons.person_outline,
                                      size: 30.sp,
                                      color: Colors.grey.shade400,
                                    ),
                            ),
                            SizedBox(width: 16.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.student.name,
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 4.h),
                                  Text(
                                    'Seat: ${widget.student.seatNo}',
                                    style: TextStyle(
                                      fontSize: 13.sp,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 24.h),

                      Text(
                        'Subjects (${_subjectDetails.length})',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),

                      SizedBox(height: 12.h),

                      if (_subjectDetails.isEmpty)
                        Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 32.h),
                            child: Text(
                              'No subjects available for this student',
                              style: TextStyle(
                                fontSize: 14.sp,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        )
                      else
                        ...List.generate(
                          _subjectDetails.length,
                          (i) {
                            final subject = _subjectDetails[i];
                            final examStudentId =
                                subject['id']?.toString() ?? '';
                            final isSaving = _saving.contains(examStudentId);
                            final isMarked =
                                subject['entry_marked'] == true;

                            final subjectName =
                                subject['subject_name']?.toString() ??
                                    subject['subject_code']?.toString() ??
                                    subject['subject']?.toString() ??
                                    'Unknown';

                            final seatNo =
                                subject['seat_no']?.toString() ?? 'N/A';
                            final examDate =
                                subject['exam_date']?.toString() ?? 'N/A';
                            final startTime =
                                subject['start_time']?.toString() ?? 'N/A';
                            final batch =
                                subject['batch']?.toString() ?? 'N/A';

                            return Padding(
                              padding: EdgeInsets.only(bottom: 12.h),
                              child: Container(
                                padding: EdgeInsets.all(12.w),
                                decoration: BoxDecoration(
                                  color: isMarked
                                      ? Colors.green.shade50
                                      : Colors.white,
                                  border: Border.all(
                                    color: isMarked
                                        ? Colors.green.shade300
                                        : Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            subjectName,
                                            style: TextStyle(
                                              fontSize: 14.sp,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          SizedBox(height: 6.h),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.event_seat,
                                                size: 12.sp,
                                                color: Colors.grey.shade600,
                                              ),
                                              SizedBox(width: 4.w),
                                              Text(
                                                'Seat: $seatNo',
                                                style: TextStyle(
                                                  fontSize: 11.sp,
                                                  color: Colors
                                                      .grey.shade600,
                                                ),
                                              ),
                                              SizedBox(width: 16.w),
                                              Icon(
                                                Icons.calendar_today,
                                                size: 12.sp,
                                                color: Colors.grey.shade600,
                                              ),
                                              SizedBox(width: 4.w),
                                              Text(
                                                examDate,
                                                style: TextStyle(
                                                  fontSize: 11.sp,
                                                  color: Colors
                                                      .grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 4.h),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.schedule,
                                                size: 12.sp,
                                                color: Colors.grey.shade600,
                                              ),
                                              SizedBox(width: 4.w),
                                              Text(
                                                startTime,
                                                style: TextStyle(
                                                  fontSize: 11.sp,
                                                  color: Colors
                                                      .grey.shade600,
                                                ),
                                              ),
                                              SizedBox(width: 16.w),
                                              Icon(
                                                Icons.group,
                                                size: 12.sp,
                                                color: Colors.grey.shade600,
                                              ),
                                              SizedBox(width: 4.w),
                                              Text(
                                                'Batch: $batch',
                                                style: TextStyle(
                                                  fontSize: 11.sp,
                                                  color: Colors
                                                      .grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: 12.w),
                                    ElevatedButton.icon(
                                      onPressed:
                                          isMarked || isSaving
                                              ? null
                                              : () => _onEntryTap(subject),
                                      icon: isSaving
                                          ? SizedBox(
                                              width: 16.w,
                                              height: 16.w,
                                              child: const
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(
                                                  Colors.white,
                                                ),
                                              ),
                                            )
                                          : Icon(
                                              isMarked
                                                  ? Icons.check_circle
                                                  : Icons.camera_alt,
                                            ),
                                      label: Text(
                                        isMarked ? 'Marked' : 'Entry',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isMarked
                                            ? Colors.green
                                            : AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
