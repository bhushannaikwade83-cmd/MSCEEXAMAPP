import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';

import '../core/face_matching_thresholds.dart';
import '../core/supabase_client.dart';
import '../core/theme/app_ui.dart';
import 'face_recognition_service.dart';

class ExamEntryResult {
  const ExamEntryResult.success({this.score, this.message = 'Entry marked'})
      : ok = true;

  const ExamEntryResult.fail(this.message)
      : ok = false,
        score = null;

  final bool ok;
  final String message;
  final double? score;
}

class ExamEntryService {
  Future<ExamEntryResult> markEntry({
    required BuildContext context,
    required String centerId,
    required String instituteId,
    required String studentId,
    required String srNo,
    required String studentName,
    required String photoPath,
    bool skipVerify = false,
    double? preVerifiedScore,
    bool examStrictEntry = true,
    Set<String>? rosterStudentIds,
    bool pipelineVerified = false,
    double? latitude,
    double? longitude,
    DateTime? entryTimestamp,
  }) async {
    if (!isSupabaseConfigured) {
      return const ExamEntryResult.fail('Backend not configured');
    }

    double? score = preVerifiedScore;

    final pipelineScoreOk = pipelineVerified &&
        preVerifiedScore != null &&
        preVerifiedScore >=
            FaceMatchingThresholds.EXAM_ENTRY_VERIFICATION_THRESHOLD * 100;

    if (!skipVerify && !pipelineScoreOk) {
      await FaceRecognitionService.initialize();
      final verify = await FaceRecognitionService.verifyStudent(
        photoPath,
        instituteId,
        srNo,
        expectedStudentRowId: studentId,
        examStrictEntry: examStrictEntry,
        rosterStudentIds: rosterStudentIds,
      );

      if (!verify.isMatch) {
        if (!examStrictEntry &&
            verify.requiresManualConfirmation &&
            context.mounted) {
          final ok = await _confirmManual(context, studentName, verify.similarityPercent);
          if (!ok) {
            return ExamEntryResult.fail(verify.message.isNotEmpty ? verify.message : 'Not confirmed');
          }
        } else {
          if (kDebugMode) {
            debugPrint('❌ Exam entry face verify: ${verify.message}');
          }
          return ExamEntryResult.fail(
            verify.message.isNotEmpty ? verify.message : 'Face did not match',
          );
        }
      } else {
        score = verify.similarityPercent;
      }
    } else if (pipelineScoreOk && kDebugMode) {
      debugPrint(
        '✅ Exam entry: using pipeline face score '
        '${preVerifiedScore!.toStringAsFixed(0)}% (skip re-verify on capture photo)',
      );
    }

    try {
      await _saveExamMark(
        centerId: centerId,
        studentId: studentId,
        photoPath: photoPath,
        score: score,
        latitude: latitude,
        longitude: longitude,
        entryTimestamp: entryTimestamp,
      );
      if (kDebugMode) debugPrint('✅ Exam entry saved for student $studentId with location ($latitude, $longitude)');
      return ExamEntryResult.success(score: score);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Exam entry save failed: $e');
      return ExamEntryResult.fail(_friendlySaveError(e));
    }
  }

  /// Save / update a per-subject entry mark with LOCATION DATA.
  ///
  /// [subjectCode] is optional. When supplied the upsert is keyed on
  /// (center_id, exam_msce_student_id, subject_code) so each subject gets its
  /// own row. Requires the `subject_code` column to exist in
  /// `exam_attendance_marks` — run the migration:
  ///   ALTER TABLE exam_attendance_marks ADD COLUMN IF NOT EXISTS subject_code TEXT;
  Future<ExamEntryResult> markSubjectEntry({
    required String centerId,
    required String studentId,
    required String photoPath,
    required String subjectCode,
    double? latitude,
    double? longitude,
    DateTime? entryTimestamp,
    String? seatNo,  // ✅ For verification
  }) async {
    if (!isSupabaseConfigured) {
      return const ExamEntryResult.fail('Backend not configured');
    }
    try {
      await _saveExamMark(
        centerId: centerId,
        studentId: studentId,
        photoPath: photoPath,
        score: null,
        subjectCode: subjectCode,
        latitude: latitude,
        longitude: longitude,
        entryTimestamp: entryTimestamp,
        seatNo: seatNo,
      );
      return const ExamEntryResult.success();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Subject entry save failed: $e');
      return ExamEntryResult.fail(_friendlySaveError(e));
    }
  }

  /// Load all per-subject marks for a student.
  /// Returns map of subject_code → {marked_at, present_photo_path}.
  Future<Map<String, Map<String, dynamic>>> loadSubjectMarks({
    required String centerId,
    required String studentId,
  }) async {
    if (!isSupabaseConfigured) return {};
    try {
      final rows = await supabase
          .from('exam_attendance_marks')
          .select('id, subject_code, marked_at, present_photo_path, exam_entry_photo_url')
          .eq('center_id', centerId)
          .eq('exam_msce_student_id', studentId);

      final out = <String, Map<String, dynamic>>{};
      for (final raw in rows as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final code = m['subject_code']?.toString() ?? '';
        if (code.isNotEmpty) out[code] = m;
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('loadSubjectMarks error (column may not exist yet): $e');
      return {};
    }
  }

  Future<void> _saveExamMark({
    required String centerId,
    required String studentId,
    required String photoPath,
    required double? score,
    String? subjectCode,
    double? latitude,
    double? longitude,
    DateTime? entryTimestamp,
    String? seatNo,
  }) async {
    // ✅ Save directly to exam_students table with location data
    final now = DateTime.now();

    // ✅ Indian timezone (IST = UTC+5:30) - NO UTC conversion
    final entryTime = entryTimestamp ?? now;
    final photoTime = now;

    final payload = <String, dynamic>{
      'entry_photo_url': photoPath,  // ✅ Photo URL
      'entry_at': entryTime.toIso8601String(),  // ✅ Entry time in IST (local time, NOT UTC)
      'entry_photo_at': photoTime.toIso8601String(),  // ✅ Photo capture time in IST
      'entry_latitude': latitude,  // ✅ Latitude
      'entry_longitude': longitude,  // ✅ Longitude
      'is_enabled': true,
      if (seatNo != null && seatNo.isNotEmpty) 'seat_no': seatNo,  // ✅ Seat number
    };

    // ✅ UPDATE: Use subject_name (not subject_code) + exam_student_id for matching
    // This matches ALL exam_students rows for this student + subject_name combination
    if (subjectCode != null && subjectCode.isNotEmpty) {
      await supabase
          .from('exam_students')
          .update(payload)
          .eq('exam_student_id', studentId)
          .eq('subject_name', subjectCode);

      if (kDebugMode) {
        debugPrint('✅ HomeScreen saved: student=$studentId, subject=$subjectCode, photo=$photoPath, lat=$latitude, lng=$longitude');
      }
    } else {
      // Fallback: Update all subjects for this student if no subject specified
      await supabase
          .from('exam_students')
          .update(payload)
          .eq('exam_student_id', studentId);
    }
  }

  String _friendlySaveError(Object e) {
    final msg = e.toString();
    if (msg.contains('row-level security') || msg.contains('42501')) {
      return 'Could not save entry — database permission denied. Run migration 005 on Supabase.';
    }
    if (msg.contains('42P10') || msg.contains('ON CONFLICT')) {
      return 'Could not save entry — run latest Supabase migrations for exam_attendance_marks.';
    }
    if (msg.contains('exam_msce_student_id') && msg.contains('column')) {
      return 'Could not save entry — run Supabase migration 002 (exam_msce_student_id column).';
    }
    return msg.split('\n').first;
  }

  Future<bool> _confirmManual(
    BuildContext context,
    String name,
    double? score,
  ) async {
    final pct = score != null ? '${score.toStringAsFixed(0)}%' : '—';
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm entry'),
            content: Text(
              'Face match is uncertain ($pct) for $name.\n'
              'Confirm this is the same student?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                child: const Text('Confirm entry'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
