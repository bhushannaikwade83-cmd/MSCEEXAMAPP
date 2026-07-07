import 'dart:typed_data';
import 'dart:convert' show jsonDecode;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import '../../core/theme/app_ui.dart';
import '../../core/supabase_client.dart';
import '../../models/exam_student.dart';
import '../../presentation/widgets/secure_network_image.dart';
import '../../services/session_service.dart';
import '../../services/cache_clear_service.dart';
import '../services/web_storage_service.dart';
import 'web_camera_dialog.dart';

/// WEB VERSION - StudentSubjectsScreen
/// Uses WebStorageService for entry photo uploads
/// Shows one student with all their subjects
class WebStudentSubjectsScreen extends StatefulWidget {
  const WebStudentSubjectsScreen({super.key, required this.student});

  final ExamStudent student;

  @override
  State<WebStudentSubjectsScreen> createState() => _WebStudentSubjectsScreenState();
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

  /// Fetch all exam_students rows for this student
  /// Groups by subject with seat, time, batch info
  /// ✅ SORTED by exam_date + start_time (earliest first)
  Future<void> _loadSubjectDetails() async {
    try {
      // ✅ First get centre_code from session
      final center = await SessionService.getCenter();
      final centreCode = center?['code']?.toString() ?? '';

      if (centreCode.isEmpty && !mounted) return;

      // Fetch all subjects for this student from exam_students table
      final rows = await supabase
          .from('exam_students')
          .select()
          .eq('student_name', widget.student.name)
          .eq('centre_code', centreCode);

      if (!mounted) return;

      print('✅ WebStudentSubjectsScreen: Loaded ${rows.length} subjects for ${widget.student.name}');

      // ✅ Sort by exam_date + start_time (earliest first)
      final sortedRows = List<Map<String, dynamic>>.from(rows as List);
      sortedRows.sort((a, b) {
        final dateA = a['exam_date']?.toString() ?? '';
        final dateB = b['exam_date']?.toString() ?? '';
        final timeA = a['start_time']?.toString() ?? '';
        final timeB = b['start_time']?.toString() ?? '';

        final parsedA = DateTime.tryParse('${dateA}T${timeA.split('+').first.split('-').first.trim()}') ?? DateTime.now();
        final parsedB = DateTime.tryParse('${dateB}T${timeB.split('+').first.split('-').first.trim()}') ?? DateTime.now();

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
        SnackBar(content: Text('Error loading subjects: $e'), backgroundColor: AppTheme.accentRed),
      );
    }
  }

  Future<void> _onEntryTap(Map<String, dynamic> subject) async {
    // ✅ Clear cache before marking entry
    await CacheClearService.clearAllCaches();

    final examStudentId = subject['id']?.toString() ?? '';
    final subjectName = subject['subject_name']?.toString() ??
                       subject['subject_code']?.toString() ??
                       subject['subject']?.toString() ??
                       '';
    final studentName = widget.student.name;

    if (examStudentId.isEmpty || subjectName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subject info missing'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // ✅ Show camera dialog
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => WebCameraDialog(
        studentName: studentName,
        subjectName: subjectName,
        onPhotoCapture: (photoBytes) async {
          // ✅ Upload captured photo
          await _uploadCapturedPhoto(
            examStudentId: examStudentId,
            subjectName: subjectName,
            photoBytes: photoBytes,
            subject: subject,
          );
        },
      ),
    );
  }

  /// Upload the captured photo to B2 via API
  Future<void> _uploadCapturedPhoto({
    required String examStudentId,
    required String subjectName,
    required List<int> photoBytes,
    required Map<String, dynamic> subject,
  }) async {
    try {
      final seatNo = subject['seat_no']?.toString() ?? '';

      if (seatNo.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Seat number missing'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      // Get centre code from session
      final center = await SessionService.getCenter();
      final centreCode = center?['code']?.toString() ?? '';

      if (centreCode.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Centre not configured'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      if (!mounted) return;

      setState(() => _saving.add(examStudentId));

      try {
        // ✅ Upload via API
        final uploadResult = await WebStorageService.uploadEntryPhotoWeb(
          centreCode: centreCode,
          folderYear: DateTime.now().year.toString(),
          seatNo: seatNo,
          subject: subjectName,
          date: DateTime.now().toIso8601String().split('T').first,
          photoBytes: photoBytes,
        );

        final photoUrl = uploadResult['url'] ?? '';
        if (photoUrl.isEmpty) {
          throw Exception('No URL returned from upload');
        }

        debugPrint('✅ Upload successful: $photoUrl');

        // ✅ Update database
        await supabase
            .from('exam_students')
            .update({
              'entry_photo_url': photoUrl,
              'entry_at': DateTime.now().toIso8601String(),
              'entry_photo_at': DateTime.now().toIso8601String(),
              'is_enabled': true,
            })
            .eq('id', examStudentId);

        if (!mounted) return;

        setState(() {
          _saving.remove(examStudentId);
          // Update the subject details locally
          final idx = _subjectDetails.indexWhere((s) => s['id'] == examStudentId);
          if (idx >= 0) {
            _subjectDetails[idx]['entry_photo_url'] = photoUrl;
            _subjectDetails[idx]['entry_photo_at'] = DateTime.now().toIso8601String();
          }
        });

        // ✅ AUTO-ENABLE next subject if exists
        if (examStudentId.isNotEmpty && _subjectDetails.length > 1) {
          final currentIdx = _subjectDetails.indexWhere((s) => s['id'] == examStudentId);
          if (currentIdx >= 0 && currentIdx < _subjectDetails.length - 1) {
            final nextSubject = _subjectDetails[currentIdx + 1];
            final nextSubjectId = nextSubject['id']?.toString() ?? '';

            if (nextSubjectId.isNotEmpty) {
              try {
                // ✅ Set is_enabled=true for next subject
                await supabase
                    .from('exam_students')
                    .update({'is_enabled': true})
                    .eq('id', nextSubjectId);
                debugPrint('✅ Next subject auto-enabled: $nextSubjectId');

                if (mounted) {
                  setState(() {
                    _subjectDetails[currentIdx + 1]['is_enabled'] = true;
                  });
                }
              } catch (e) {
                debugPrint('⚠️ Could not auto-enable next subject: $e');
              }
            }
          }
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Entry marked for $subjectName'),
            backgroundColor: AppTheme.primaryGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _saving.remove(examStudentId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Upload failed: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
  }

  /// ✅ Compress photo to under 1MB
  Future<Uint8List> _compressPhotoToUnder1MB(Uint8List photoBytes) async {
    try {
      final decoded = img.decodeImage(photoBytes);
      if (decoded == null) return photoBytes;

      img.Image image = decoded;
      try {
        image = img.bakeOrientation(image);
      } catch (_) {}

      int quality = 90;
      Uint8List compressed = Uint8List.fromList(img.encodeJpg(image, quality: quality));

      while (compressed.length > 1048576 && quality > 30) {
        quality -= 10;
        compressed = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      }

      if (compressed.length > 1048576) {
        final resized = img.copyResize(image,
            width: (image.width * 0.8).toInt(),
            height: (image.height * 0.8).toInt());
        compressed = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
      }

      return compressed;
    } catch (e) {
      debugPrint('⚠️ Compression error: $e');
      return photoBytes;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      appBar: AppBar(
        title: Text('Student Subjects (WEB)', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w800)),
        backgroundColor: AppTheme.primaryBlueDark,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : Column(
              children: [
                _buildStudentHeader(),
                Divider(height: 1, color: AppTheme.dividerColor),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 110,
              height: 140,
              child: hasPhoto
                  ? SecureNetworkImage(
                      // ✅ Always fetch fresh profile photo (no caching)
                      cachePhotos: false,
                      cacheKey: 'student_face_${widget.student.id}',
                      imageUrl: widget.student.passportPhotoUrl!,
                      width: 110,
                      height: 140,
                      fit: BoxFit.cover,
                    )
                  : _photoPlaceholder(width: 110, height: 140),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectRow(Map<String, dynamic> subject, bool showDivider) {
    final subjectName = subject['subject_name']?.toString() ?? subject['subject_code']?.toString() ?? '—';
    final seatNo = subject['seat_no']?.toString() ?? '—';
    final srNo = subject['sr_no']?.toString() ?? '—';  // ✅ Get SR NO from database
    final examDate = subject['exam_date']?.toString() ?? '—';
    final startTime = subject['start_time']?.toString() ?? '—';
    final batch = subject['batch']?.toString() ?? '—';
    final examStudentId = subject['id']?.toString() ?? '';
    final isMarked = subject['entry_photo_url'] != null;

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
          color: isMarked ? AppTheme.primaryGreen.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subjectName.toUpperCase(),
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: isMarked ? AppTheme.primaryGreen : AppTheme.textGray,
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Icon(Icons.event_seat, size: 14, color: AppTheme.textGray),
                SizedBox(width: 4.w),
                Text('Seat: $seatNo', style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
                SizedBox(width: 12.w),
                // ✅ SR NO from database
                Icon(Icons.assignment, size: 14, color: AppTheme.textGray),
                SizedBox(width: 4.w),
                Text('SR: $srNo', style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
              ],
            ),
            SizedBox(height: 6.h),
            Row(
              children: [
                Icon(Icons.groups, size: 14, color: AppTheme.textGray),
                SizedBox(width: 4.w),
                Text('Batch: $batch', style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
              ],
            ),
            SizedBox(height: 6.h),
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
            // ✅ Entry Photo Box (if marked)
            if (isMarked && subject['entry_photo_url'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: double.infinity,
                  height: 300.h,  // ✅ Increased for better visibility
                  child: SecureNetworkImage(
                    // ✅ ALWAYS FRESH: Disable cache for entry photos
                    cachePhotos: false,
                    cacheKey: 'entry_${subject['id']}_${subject['entry_photo_url']?.hashCode ?? ''}',
                    imageUrl: subject['entry_photo_url'],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (isMarked) SizedBox(height: 10.h),
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
