import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_ui.dart';
import '../core/supabase_client.dart';
import '../models/exam_student.dart';
import '../presentation/widgets/secure_network_image.dart';
import 'exam_subject_camera_screen.dart';

/// Updated StudentSubjectsScreen
/// Shows one student with all their subjects
/// Each subject shows: seat_no, exam_date, time, batch, entry button
class StudentSubjectsScreen extends StatefulWidget {
  const StudentSubjectsScreen({super.key, required this.student});

  final ExamStudent student;

  @override
  State<StudentSubjectsScreen> createState() => _StudentSubjectsScreenState();
}

class _StudentSubjectsScreenState extends State<StudentSubjectsScreen> {
  List<Map<String, dynamic>> _subjectDetails = [];
  bool _loading = true;
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _loadSubjectDetails();
  }

  /// Fetch all exam_students rows for this student
  /// Groups by subject with seat, time, batch info
  Future<void> _loadSubjectDetails() async {
    try {
      // Fetch all subjects for this student from exam_students table
      final rows = await supabase
          .from('exam_students')
          .select()
          .eq('exam_student_id', widget.student.id);

      if (!mounted) return;

      setState(() {
        _subjectDetails = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading subjects: $e'), backgroundColor: AppTheme.accentRed),
      );
    }
  }

  Future<void> _onEntryTap(Map<String, dynamic> subject) async {
    final examStudentId = subject['id']?.toString() ?? '';
    final subjectCode = subject['subject_code']?.toString() ?? '';
    final studentName = widget.student.name;

    if (examStudentId.isEmpty) return;

    final photo = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(
        builder: (_) => ExamSubjectCameraScreen(
          studentName: studentName,
          subjectName: subjectCode,
        ),
      ),
    );

    if (photo == null || !mounted) return;

    setState(() => _saving.add(examStudentId));

    try {
      // Upload photo to storage or save URL
      final photoUrl = photo.path;

      // Update exam_students row with attendance
      await supabase
          .from('exam_students')
          .update({
            'entry_photo_url': photoUrl,
            'entry_photo_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', examStudentId);

      if (!mounted) return;

      setState(() {
        _saving.remove(examStudentId);
        // Update the subject details locally
        final idx = _subjectDetails.indexWhere((s) => s['id'] == examStudentId);
        if (idx >= 0) {
          _subjectDetails[idx]['entry_photo_url'] = photoUrl;
          _subjectDetails[idx]['entry_photo_at'] = DateTime.now().toUtc().toIso8601String();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Entry marked for $subjectCode'),
          backgroundColor: AppTheme.primaryGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving.remove(examStudentId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      appBar: AppBar(
        title: Text('Student Subjects', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w800)),
        backgroundColor: AppTheme.primaryBlueDark,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : Column(
              children: [
                // Student Header
                _buildStudentHeader(),
                Divider(height: 1, color: AppTheme.dividerColor),
                // Subjects List
                Expanded(
                  child: _subjectDetails.isEmpty
                      ? Center(
                          child: Text('No subjects found', style: TextStyle(fontSize: 14.sp)),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 88.h),
                          itemCount: _subjectDetails.length,
                          itemBuilder: (_, i) => _buildSubjectRow(_subjectDetails[i], i < _subjectDetails.length - 1),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStudentHeader() {
    final hasPhoto = widget.student.passportPhotoUrl != null && widget.student.passportPhotoUrl!.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Student Name
          Text(
            widget.student.name,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 12.h),
          // Student Photo
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 110,
              height: 140,
              child: hasPhoto
                  ? SecureNetworkImage(
                      cacheKey: 'student_face_${widget.student.id}',
                      imageUrl: widget.student.passportPhotoUrl!,
                      width: 110,
                      height: 140,
                      fit: BoxFit.cover,
                      placeholder: ColoredBox(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                      errorWidget: _photoPlaceholder(width: 110, height: 140),
                    )
                  : _photoPlaceholder(width: 110, height: 140),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectRow(Map<String, dynamic> subject, bool showDivider) {
    final subjectCode = subject['subject_code']?.toString() ?? '—';
    final seatNo = subject['seat_no']?.toString() ?? '—';
    final examDate = subject['exam_date']?.toString() ?? '—';
    final startTime = subject['start_time']?.toString() ?? '—';
    final batch = subject['batch']?.toString() ?? '—';
    final examStudentId = subject['id']?.toString() ?? '';
    final isMarked = subject['entry_photo_url'] != null;
    final isSaving = _saving.contains(examStudentId);

    String formatTime(String? time) {
      if (time == null || time.isEmpty) return '—';
      try {
        final parsed = DateTime.parse('2000-01-01 ${time.split('+').first.split('-').first.trim()}');
        return DateFormat('hh:mm a').format(parsed);
      } catch (_) {
        return time.split('+').first.trim();
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subject Code
            Text(
              subjectCode,
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
            ),
            SizedBox(height: 8.h),
            // Details Row 1: Seat & Batch
            Row(
              children: [
                Icon(Icons.event_seat, size: 14, color: AppTheme.textGray),
                SizedBox(width: 4.w),
                Text('Seat: $seatNo', style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
                SizedBox(width: 12.w),
                Icon(Icons.groups, size: 14, color: AppTheme.textGray),
                SizedBox(width: 4.w),
                Text('Batch: $batch', style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
              ],
            ),
            SizedBox(height: 6.h),
            // Details Row 2: Date & Time
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: AppTheme.textGray),
                SizedBox(width: 4.w),
                Text(examDate, style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
                SizedBox(width: 12.w),
                Icon(Icons.access_time, size: 14, color: AppTheme.textGray),
                SizedBox(width: 4.w),
                Text(formatTime(startTime), style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
              ],
            ),
            SizedBox(height: 10.h),
            // Entry Photo Box (if marked)
            if (isMarked && subject['entry_photo_url'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: double.infinity,
                  height: 100.h,
                  child: SecureNetworkImage(
                    cacheKey: 'entry_${subject['id']}',
                    imageUrl: subject['entry_photo_url'],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (isMarked) SizedBox(height: 10.h),
            // Entry Button
            SizedBox(
              width: double.infinity,
              height: 56.h,
              child: isSaving
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue),
                    )
                  : ElevatedButton.icon(
                      onPressed: () => _onEntryTap(subject),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isMarked ? AppTheme.primaryGreen : AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                      icon: Icon(isMarked ? Icons.check_circle : Icons.camera_alt, size: 24),
                      label: Text(
                        isMarked ? 'Marked ✓' : 'Entry',
                        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
                      ),
                    ),
            ),
            if (showDivider) ...[
              SizedBox(height: 12.h),
              Divider(height: 1, color: AppTheme.dividerColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder({double width = 110, double height = 140}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.person, size: height * 0.5, color: AppTheme.primaryBlue),
    );
  }
}
