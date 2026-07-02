import 'dart:io';
import 'dart:typed_data';
import 'dart:convert' show base64Encode;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import '../core/theme/app_ui.dart';
import '../core/supabase_client.dart';
import '../models/exam_student.dart';
import '../presentation/widgets/secure_network_image.dart';
import '../services/storage_service.dart';
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
    // ✅ Use subject_name (primary) or subject_code (fallback)
    final subjectName = subject['subject_name']?.toString() ??
                       subject['subject_code']?.toString() ??
                       subject['subject']?.toString() ??
                       '';
    final studentName = widget.student.name;

    if (examStudentId.isEmpty || subjectName.isEmpty) {
      if (mounted) {
        debugPrint('Subject fields: ${subject.keys}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subject info missing'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // ✅ Open camera and get photo with location + timestamp
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => ExamSubjectCameraScreen(
          studentName: studentName,
          subjectName: subjectName,
        ),
      ),
    );

    if (result == null || !mounted) return;

    // ✅ Extract photo, location, and timestamp
    final photo = result['photo'] as XFile?;
    final latitude = result['latitude'] as double?;
    final longitude = result['longitude'] as double?;
    final timestamp = result['timestamp'] as DateTime?;

    if (photo == null) return;

    setState(() => _saving.add(examStudentId));

    try {
      // ✅ Get institute ID from subject (fallback to centre_id)
      final instituteId = subject['institute_id']?.toString() ?? subject['centre_id']?.toString() ?? '';
      if (instituteId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Institute ID not found'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      // ✅ Read photo bytes and compress to under 100KB
      // XFile.readAsBytes works on all platforms including web
      // (dart:io File does not exist on web).
      var photoBytes = await photo.readAsBytes();
      debugPrint('📸 Original photo size: ${(photoBytes.length / 1024).toStringAsFixed(2)} KB');

      // ✅ Compress if larger than 100KB
      if (photoBytes.length > 102400) {  // 100KB
        photoBytes = await _compressPhotoToUnder100KB(photoBytes);
        debugPrint('📸 Compressed photo size: ${(photoBytes.length / 1024).toStringAsFixed(2)} KB');
      }

      // ✅ Get seat_no FIRST (needed for upload path)
      final seatNo = subject['seat_no']?.toString() ?? '';
      if (seatNo.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Seat number not found - cannot verify'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
        setState(() => _saving.remove(examStudentId));
        return;
      }

      // Upload to B2 via Supabase Edge Function (web-safe)
      String photoUrl;
      try {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${seatNo}_entry.jpg';
        final storagePath = 'attendance/${DateTime.now().year}/$seatNo/$fileName';

        debugPrint('📤 Uploading to B2 via edge function: $storagePath');

        // Call b2-storage-proxy edge function
        final result = await supabase.functions.invoke(
          'b2-storage-proxy',
          body: {
            'action': 'uploadFile',
            'key': storagePath,
            'file': base64Encode(photoBytes),  // Base64 encode for JSON transmission
            'contentType': 'image/jpeg',
          },
        );

        if (result.data is! Map || result.data['success'] != true) {
          throw Exception('Edge function upload failed: ${result.data}');
        }

        photoUrl = result.data['publicUrl'] as String;
        debugPrint('✅ Upload successful: $photoUrl');
      } catch (e) {
        debugPrint('❌ Upload failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Photo upload failed: $e'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
        setState(() => _saving.remove(examStudentId));
        return;
      }

      // ✅ Verify seat number from database
      final examStudents = await supabase
          .from('exam_students')
          .select('id, seat_no, exam_student_id')
          .eq('id', examStudentId);

      if (examStudents.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Student subject record not found'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
        return;
      }

      // ✅ Check if seat number matches
      final dbSeatNo = examStudents[0]['seat_no']?.toString() ?? '';
      if (dbSeatNo != seatNo) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Seat mismatch! Expected: $dbSeatNo, Got: $seatNo'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
        debugPrint('❌ SEAT MISMATCH: Expected $dbSeatNo but got $seatNo');
        return;
      }

      debugPrint('✅ Seat verified: $seatNo matches database');

      // ✅ CONSISTENT: Update using subject_name + exam_student_id (SAME as HomeScreen)
      // This ensures both flows save to the exact same row
      // ✅ IST timezone (NOT UTC) - local time
      await supabase
          .from('exam_students')
          .update({
            'entry_photo_url': photoUrl,  // ✅ Photo URL
            'entry_at': (timestamp ?? DateTime.now()).toIso8601String(),  // ✅ Entry time in IST
            'entry_photo_at': DateTime.now().toIso8601String(),  // ✅ Photo capture time in IST
            'entry_latitude': latitude,  // ✅ GPS Latitude
            'entry_longitude': longitude,  // ✅ GPS Longitude
            'is_enabled': true,  // ✅ Mark as enabled (matching HomeScreen)
          })
          .eq('exam_student_id', widget.student.id)
          .eq('subject_name', subjectName);

      if (kDebugMode) {
        debugPrint('✅ QR entry saved (Seat: $seatNo verified): student=${widget.student.id}, subject=$subjectName, lat=$latitude, lng=$longitude');
      }

      if (!mounted) return;

      setState(() {
        _saving.remove(examStudentId);
        // Update the subject details locally
        final idx = _subjectDetails.indexWhere((s) => s['id'] == examStudentId);
        if (idx >= 0) {
          _subjectDetails[idx]['entry_photo_url'] = photoUrl;
          _subjectDetails[idx]['entry_photo_at'] = DateTime.now().toIso8601String();  // ✅ IST, not UTC
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
            } catch (e) {
              debugPrint('⚠️ Could not auto-enable next subject: $e');
            }
          }
        }
      }

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
          content: Text('Error: $e'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
  }

  /// ✅ Compress photo to under 100KB (same as HomeScreen)
  Future<Uint8List> _compressPhotoToUnder100KB(Uint8List photoBytes) async {
    try {
      // Decode image
      final decoded = img.decodeImage(photoBytes);
      if (decoded == null) return photoBytes;

      // ✅ Bake EXIF orientation into the pixels BEFORE re-encoding.
      // encodeJpg strips EXIF metadata; without baking first, portrait
      // photos (stored by cameras as rotated pixels + EXIF tag) would be
      // saved permanently sideways.
      img.Image image = decoded;
      try {
        image = img.bakeOrientation(image);
      } catch (_) {}

      // Start with quality 90 and reduce if needed
      int quality = 90;
      Uint8List compressed = Uint8List.fromList(img.encodeJpg(image, quality: quality));

      // Keep reducing quality until under 100KB
      while (compressed.length > 102400 && quality > 30) {
        quality -= 10;
        compressed = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      }

      // If still over 100KB, resize image
      if (compressed.length > 102400) {
        final resized = img.copyResize(image,
            width: (image.width * 0.8).toInt(),
            height: (image.height * 0.8).toInt());
        compressed = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
      }

      debugPrint('✅ Compression complete: quality=$quality, size=${(compressed.length / 1024).toStringAsFixed(2)}KB');
      return compressed;
    } catch (e) {
      debugPrint('⚠️ Compression error: $e, returning original');
      return photoBytes;
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
                          itemBuilder: (_, i) => _buildSubjectRow(
                            _subjectDetails[i],
                            i < _subjectDetails.length - 1,
                            _isSubjectEnabled(i),  // ✅ Check if enabled
                          ),
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

  Widget _buildSubjectRow(Map<String, dynamic> subject, bool showDivider, bool isEnabled) {
    final subjectName = subject['subject_name']?.toString() ?? subject['subject_code']?.toString() ?? '—';
    final seatNo = subject['seat_no']?.toString() ?? '—';
    final examDate = subject['exam_date']?.toString() ?? '—';
    final startTime = subject['start_time']?.toString() ?? '—';
    final batch = subject['batch']?.toString() ?? '—';
    final examStudentId = subject['id']?.toString() ?? '';
    final isMarked = subject['entry_photo_url'] != null;
    final isSaving = _saving.contains(examStudentId);
    final dbIsEnabled = subject['is_enabled'] ?? true;  // ✅ Read from database

    // ✅ Smart highlighting logic
    final isNextToMark = !isMarked && (isEnabled || dbIsEnabled);  // Ready to mark
    final isAlreadyMarked = isMarked;  // Already done

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
          color: isAlreadyMarked
              ? AppTheme.primaryGreen.withValues(alpha: 0.1)  // ✅ Dim marked subjects (light green)
              : isNextToMark
                  ? AppTheme.primaryBlue.withValues(alpha: 0.15)  // ✅ Highlight next to mark (light blue)
                  : Colors.white,  // Normal for disabled
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isNextToMark ? AppTheme.primaryBlue : AppTheme.dividerColor,  // ✅ Bold border for next
            width: isNextToMark ? 2 : 1,
          ),
        ),
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Subject Name (primary) or Code (fallback)
            Row(
              children: [
                Expanded(
                  child: Text(
                    subjectName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: isNextToMark ? FontWeight.w900 : FontWeight.w700,  // ✅ Bold next to mark
                      color: isAlreadyMarked
                          ? AppTheme.primaryGreen  // ✅ Green for marked
                          : isNextToMark
                              ? AppTheme.primaryBlue  // ✅ Blue highlight for next
                              : AppTheme.textGray,  // Gray for disabled
                    ),
                  ),
                ),
                if (!isEnabled || !dbIsEnabled)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: AppTheme.accentRed.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'DISABLED',
                      style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: AppTheme.accentRed),
                    ),
                  ),
              ],
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
                  height: 200.h,  // ✅ Same as HomeScreen (full width × 200h)
                  child: SecureNetworkImage(
                    cacheKey: 'entry_${subject['id']}',
                    imageUrl: subject['entry_photo_url'],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (isMarked) SizedBox(height: 10.h),
            // ✅ Entry Button - DISABLED if: marked OR (not logically enabled AND db says false)
            // If db says is_enabled=true, override logic and enable it
            Builder(
              builder: (_) {
                final canTap = !isMarked && (isEnabled || dbIsEnabled);
                return SizedBox(
              width: double.infinity,
              height: 56.h,
              child: Opacity(
                opacity: canTap ? 1.0 : 0.6,
                child: isSaving
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue),
                      )
                    : ElevatedButton.icon(
                        onPressed: canTap ? () => _onEntryTap(subject) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isMarked ? AppTheme.primaryGreen : AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          disabledBackgroundColor: AppTheme.primaryGreen,
                        ),
                        icon: Icon(isMarked ? Icons.check_circle : Icons.camera_alt, size: 24),
                        label: Text(
                          isMarked ? 'Marked ✓' : canTap ? 'Entry' : 'Disabled',
                          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
                );
              },
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

  /// ✅ Check if subject should be enabled (sequential marking logic)
  bool _isSubjectEnabled(int subjectIndex) {
    // Only 1 subject - always enabled
    if (_subjectDetails.length <= 1) return true;

    // First subject always enabled
    if (subjectIndex == 0) return true;

    // Check if previous subject is marked
    final prevSubject = _subjectDetails[subjectIndex - 1];
    final prevMarked = prevSubject['entry_photo_url'] != null;

    return prevMarked;
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
