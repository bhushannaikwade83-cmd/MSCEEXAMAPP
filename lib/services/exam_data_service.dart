import '../core/supabase_client.dart';
import '../models/exam_batch.dart';
import '../models/exam_student.dart';
import 'storage_service.dart';

class ExamDataService {
  /// Load exam batches for a centre.
  /// Uses [centreCode] first; falls back to [centerId] UUID.
  Future<List<ExamBatch>> loadBatches(
    String centerId, {
    String? centreCode,
  }) async {
    var q = supabase
        .from('exam_students')
        .select('exam_date, start_time, exam_time');

    final rows = centreCode != null && centreCode.isNotEmpty
        ? await q.eq('centre_code', centreCode)
        : await q.eq('center_id', centerId);

    final counts = <String, int>{};
    for (final row in rows as List) {
      final t = _rowBatchTime(row);
      if (t == null) continue;
      final key = '${t.year}-${t.month}-${t.day}-${t.hour}';
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final batches = <ExamBatch>[];
    for (final e in counts.entries) {
      final parts = e.key.split('-');
      final start = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
        int.parse(parts[3]),
      );
      batches.add(ExamBatch.fromHour(start, e.value));
    }
    batches.sort((a, b) => a.start.compareTo(b.start));
    return batches;
  }

  /// Load students in a batch window.
  /// 1. Fetches from exam_students by centre_code (or center_id fallback).
  /// 2. Batch-fetches registration photo (face_photo_url) + subjects
  ///    from the students table by matching on student_name.
  /// 3. Merges photo + subjects into each ExamStudent.
  Future<List<ExamStudent>> loadStudentsInBatch({
    required String centerId,
    required DateTime batchStart,
    String? centreCode,
  }) async {
    final batchEnd = batchStart.add(const Duration(hours: 1));

    // ── Step 1: fetch exam_students ───────────────────────────
    var q = supabase.from('exam_students').select();
    final all = centreCode != null && centreCode.isNotEmpty
        ? await q.eq('centre_code', centreCode)
        : await q.eq('center_id', centerId);

    final inBatch = (all as List).where((row) {
      final t = _rowBatchTime(row);
      if (t == null) return false;
      return !t.isBefore(batchStart) && t.isBefore(batchEnd);
    }).toList();

    inBatch.sort((a, b) {
      final sa = (a['seat_no'] ?? a['roll_number'] ?? '').toString();
      final sb = (b['seat_no'] ?? b['roll_number'] ?? '').toString();
      return sa.compareTo(sb);
    });

    // ── Step 2: batch-fetch photo + subjects from students table ──
    final names = inBatch
        .map((r) => r['student_name']?.toString().trim())
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();

    final studentLookup = <String, Map<String, dynamic>>{};
    if (names.isNotEmpty) {
      const chunkSize = 80;
      for (var i = 0; i < names.length; i += chunkSize) {
        final slice = names.sublist(
          i,
          (i + chunkSize) > names.length ? names.length : (i + chunkSize),
        );
        final rows = await supabase
            .from('students')
            .select('name, face_photo_url, photo_version, subjects, subject')
            .inFilter('name', slice);

        for (final raw in rows as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          final name = row['name']?.toString().trim() ?? '';
          if (name.isNotEmpty) studentLookup[name] = row;
        }
      }

      // Sign photo URLs for secure storage.
      await Future.wait(studentLookup.values.map((row) async {
        final raw = row['face_photo_url']?.toString() ?? '';
        if (raw.isEmpty) return;
        try {
          row['face_photo_url'] = await StorageService.ensureSignedUrl(raw);
        } catch (_) {}
      }));
    }

    // ── Step 3: fetch marks ───────────────────────────────────
    final marks = await supabase
        .from('exam_attendance_marks')
        .select('exam_msce_student_id, student_id')
        .eq('center_id', centerId);

    final markedIds = <String>{
      for (final m in marks as List) ...[
        if (m['exam_msce_student_id'] != null)
          m['exam_msce_student_id'] as String,
        if (m['student_id'] != null) m['student_id'] as String,
      ],
    };

    // ── Step 4: merge and build ExamStudent list ──────────────
    return [
      for (final row in inBatch)
        () {
          final name = row['student_name']?.toString().trim() ?? '';
          final sRow = studentLookup[name];
          final merged = Map<String, dynamic>.from(row);

          // Photo: live from students table, fallback to exam_students.photo_url
          if (sRow?['face_photo_url'] != null) {
            merged['photo_url'] = sRow!['face_photo_url'];
          }

          // Subjects: live from students table, fallback to exam_students.subjects
          if (sRow != null) {
            final liveSubjects = sRow['subjects'];
            final liveSingle = sRow['subject'];
            if (liveSubjects != null) {
              merged['subjects'] = liveSubjects;
            } else if (liveSingle != null) {
              merged['subjects'] = [liveSingle];
            }
          }

          return ExamStudent.fromMap(
            merged,
            marked: markedIds.contains(row['id'] as String),
          );
        }(),
    ];
  }

  /// Resolve batch DateTime from a row.
  /// Prefers exam_date + start_time; falls back to exam_time for legacy rows.
  static DateTime? _rowBatchTime(Map<dynamic, dynamic> row) {
    final examDate = row['exam_date']?.toString();
    final startTime = row['start_time']?.toString();
    if (examDate != null &&
        examDate.isNotEmpty &&
        startTime != null &&
        startTime.isNotEmpty) {
      final cleaned = startTime.split('+').first.split('-').first.trim();
      return DateTime.tryParse('${examDate}T$cleaned')?.toLocal();
    }
    final examTime = row['exam_time']?.toString();
    if (examTime != null && examTime.isNotEmpty) {
      return DateTime.tryParse(examTime)?.toLocal();
    }
    return null;
  }

  Future<void> markAttendance({
    required String centerId,
    required String studentId,
    String? presentPhotoPath,
  }) async {
    await supabase.from('exam_attendance_marks').upsert({
      'center_id': centerId,
      'student_id': studentId,
      'marked_at': DateTime.now().toUtc().toIso8601String(),
      'staff_confirmed': true,
      'present_photo_path': presentPhotoPath,
    });
  }
}
