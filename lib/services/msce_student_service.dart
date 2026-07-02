import '../core/exam_student_name_utils.dart';
import '../core/supabase_client.dart';
import '../core/student_face_embedding_utils.dart';
import 'exam_centre_student_cache.dart';
import 'storage_service.dart';
import 'student_face_match_index.dart';
import 'api_cache_service.dart';

class MsceStudent {
  MsceStudent({
    required this.id,
    required this.name,
    required this.lastName,
    required this.srNo,
    required this.photoUrl,
    this.photoVersion,
    required this.hasFaceEmbedding,
    this.instituteId,
    this.userId,
    this.firstName,
    this.middleName,
    this.year,
    this.subject,
    this.examRollNumber,
    this.entryMarked = false,
    this.entryPhotoUrl,
    this.entryMarkedAt,
    this.faceMatchScore,
    this.rosterMatched = true,
    this.subjects = const [],  // ✅ NEW: All exam_students rows (all subjects)
  });

  final String id;
  final String name;
  final String lastName;
  final String srNo;
  final String photoUrl;
  final String? photoVersion;
  final bool hasFaceEmbedding;
  final String? instituteId;
  final String? userId;
  final String? firstName;
  final String? middleName;
  final String? year;
  final String? subject;
  final String? examRollNumber;
  final bool entryMarked;
  final String? entryPhotoUrl;
  final DateTime? entryMarkedAt;
  final double? faceMatchScore;
  final bool rosterMatched;
  final List<Map<String, dynamic>> subjects;  // ✅ NEW: All subject rows for this student

  String get displayName => name.trim().isNotEmpty ? name.trim() : 'Unknown';

  String get rollLabel => (examRollNumber?.trim().isNotEmpty == true)
      ? examRollNumber!.trim()
      : '—';
}

class ExamCenterRosterEntry {
  ExamCenterRosterEntry({
    required this.id,
    required this.instituteId,
    required this.fullName,
    this.msceStudentId,
    this.examRollNumber,
  });

  final String id;
  final String instituteId;
  final String fullName;
  final String? msceStudentId;
  final String? examRollNumber;
}

class MsceStudentLoadResult {
  const MsceStudentLoadResult({
    required this.students,
    this.unmatchedRoster = const [],
    this.rosterCount = 0,
  });

  final List<MsceStudent> students;
  final List<ExamCenterRosterEntry> unmatchedRoster;
  final int rosterCount;

  bool get hasRoster => rosterCount > 0;
  Set<String> get allottedStudentIds => students.map((s) => s.id).toSet();
}

class MsceStudentService {
  static const _detailCols =
      'id,institute_id,name,first_name,middle_name,last_name,sr_no,user_id,year,subject,subjects,face_photo_url,photo_version,photo_thumbnail,face_photo_changed_once,face_embedding';

  /// Load allotted students with MSCE photo + face_embedding (cached for entry compare).
  ///
  /// Priority: [centerCode] → `students.exam_centre_code`, then roster table fallback.
  Future<MsceStudentLoadResult> loadStudentsForCenter({
    required String centerId,
    String? centerCode,
    String? instituteId,
    String search = '',
  }) async {
    if (!isSupabaseConfigured) {
      return const MsceStudentLoadResult(students: []);
    }

    final code = centerCode?.trim() ?? '';
    if (code.isNotEmpty) {
      final byCode = await _loadStudentsByCentreCode(
        centerCode: code,
        instituteId: instituteId?.trim(),
      );
      if (byCode.isNotEmpty) {
        return _finalizeStudentLoad(
          centerId: centerId,
          matchedRows: byCode,
          rosterCount: byCode.length,
          search: search,
        );
      }
    }

    final roster = await _loadRoster(centerId);
    if (roster.isEmpty) {
      ExamCentreStudentCache.clear();
      return const MsceStudentLoadResult(students: [], rosterCount: 0);
    }

    final msceByKey = await _fetchMsceStudentsForRoster(roster);

    final matchedRows = <Map<String, dynamic>>[];
    final unmatched = <ExamCenterRosterEntry>[];
    final linkUpdates = <Map<String, dynamic>>[];
    final examRollByStudentId = <String, String?>{};

    for (final entry in roster) {
      final key = examStudentRosterKey(entry.instituteId, entry.fullName);
      Map<String, dynamic>? row = msceByKey[key];

      if (row == null && entry.msceStudentId != null && entry.msceStudentId!.isNotEmpty) {
        row = msceByKey['id:${entry.msceStudentId}'];
      }

      if (row == null) {
        unmatched.add(entry);
        continue;
      }

      final studentId = row['id']?.toString() ?? '';
      if (studentId.isEmpty) {
        unmatched.add(entry);
        continue;
      }

      if (entry.msceStudentId != studentId) {
        linkUpdates.add({
          'id': entry.id,
          'exam_msce_student_id': studentId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      matchedRows.add(row);
      examRollByStudentId[studentId] = entry.examRollNumber;
    }

    if (linkUpdates.isNotEmpty) {
      await _persistRosterLinks(linkUpdates);
    }

    return _finalizeStudentLoad(
      centerId: centerId,
      matchedRows: matchedRows,
      rosterCount: roster.length,
      search: search,
      unmatchedRoster: unmatched,
      examRollByStudentId: examRollByStudentId,
    );
  }

  Future<MsceStudentLoadResult> _finalizeStudentLoad({
    required String centerId,
    required List<Map<String, dynamic>> matchedRows,
    required int rosterCount,
    required String search,
    List<ExamCenterRosterEntry> unmatchedRoster = const [],
    Map<String, String?> examRollByStudentId = const {},
  }) async {
    final marks = await _entryMarksByStudent(centerId);

    final matched = matchedRows
        .map(
          (row) => _mapRow(
            row,
            marks: marks,
            examRollNumber: examRollByStudentId[row['id']?.toString() ?? ''],
          ),
        )
        .toList();

    await _signPhotoUrls(matchedRows);

    ExamCentreStudentCache.setForCenter(centerId: centerId, studentRows: matchedRows);
    await StudentFaceMatchIndex.warmCacheFromRows(matchedRows);

    matched.sort((a, b) {
      final lc = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
      if (lc != 0) return lc;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final signedById = {for (final r in matchedRows) r['id']?.toString() ?? '': r};
    for (var i = 0; i < matched.length; i++) {
      final id = matched[i].id;
      final signedUrl = signedById[id]?['face_photo_url']?.toString() ?? matched[i].photoUrl;

      // Auto-assign SR No based on sorted position (001, 002, 003, ...)
      final autoSrNo = (i + 1).toString().padLeft(3, '0');

      if (signedUrl != matched[i].photoUrl) {
        matched[i] = MsceStudent(
          id: matched[i].id,
          name: matched[i].name,
          lastName: matched[i].lastName,
          srNo: autoSrNo, // Use auto-numbered SR No
          photoUrl: signedUrl,
          photoVersion: matched[i].photoVersion,
          hasFaceEmbedding: matched[i].hasFaceEmbedding,
          instituteId: matched[i].instituteId,
          userId: matched[i].userId,
          firstName: matched[i].firstName,
          middleName: matched[i].middleName,
          year: matched[i].year,
          subject: matched[i].subject,
          examRollNumber: matched[i].examRollNumber,
          entryMarked: matched[i].entryMarked,
          entryPhotoUrl: matched[i].entryPhotoUrl,
          entryMarkedAt: matched[i].entryMarkedAt,
          faceMatchScore: matched[i].faceMatchScore,
        );
      } else {
        // Update srNo even if photoUrl didn't change
        matched[i] = MsceStudent(
          id: matched[i].id,
          name: matched[i].name,
          lastName: matched[i].lastName,
          srNo: autoSrNo,
          photoUrl: matched[i].photoUrl,
          photoVersion: matched[i].photoVersion,
          hasFaceEmbedding: matched[i].hasFaceEmbedding,
          instituteId: matched[i].instituteId,
          userId: matched[i].userId,
          firstName: matched[i].firstName,
          middleName: matched[i].middleName,
          year: matched[i].year,
          subject: matched[i].subject,
          examRollNumber: matched[i].examRollNumber,
          entryMarked: matched[i].entryMarked,
          entryPhotoUrl: matched[i].entryPhotoUrl,
          entryMarkedAt: matched[i].entryMarkedAt,
          faceMatchScore: matched[i].faceMatchScore,
        );
      }
    }

    final token = search.trim().replaceAll(',', ' ').replaceAll(RegExp(r'[%_]'), '').toLowerCase();
    final filtered = token.isEmpty
        ? matched
        : matched.where((s) {
            final hay =
                '${s.name} ${s.lastName} ${s.srNo} ${s.userId ?? ''} ${s.examRollNumber ?? ''}'
                    .toLowerCase();
            return hay.contains(token);
          }).toList();

    return MsceStudentLoadResult(
      students: filtered,
      unmatchedRoster: unmatchedRoster,
      rosterCount: rosterCount,
    );
  }

  Future<List<Map<String, dynamic>>> _loadStudentsByCentreCode({
    required String centerCode,
    String? instituteId,
  }) async {
    // Load from exam_students table (same as QR scan)
    final examStudentsRows = await supabase
        .from('exam_students')
        .select('exam_student_id, student_name, seat_no, photo_url, subject_name, centre_code')
        .eq('centre_code', centerCode)
        .order('student_name');

    // Group by student to get unique students
    final Map<String, Map<String, dynamic>> studentMap = {};

    for (final row in examStudentsRows as List) {
      final studentId = row['exam_student_id']?.toString() ?? '';
      final studentName = row['student_name']?.toString() ?? '';
      final photoUrl = row['photo_url']?.toString();

      if (studentId.isEmpty || studentName.isEmpty) continue;

      if (!studentMap.containsKey(studentId)) {
        studentMap[studentId] = {
          'id': studentId,
          'name': studentName,
          'face_photo_url': photoUrl,
          'photo_version': '0',
          'institute_id': instituteId ?? '',
          'exam_centre_code': centerCode,
        };
      }
    }

    return studentMap.values.toList();
  }

  Future<void> _signPhotoUrls(List<Map<String, dynamic>> rows) async {
    // B2 URLs from edge function are already public, no signing needed
    // This method is kept for compatibility but does nothing now
    return;
  }

  Future<List<ExamCenterRosterEntry>> _loadRoster(String centerId) async {
    final rows = await supabase
        .from('exam_centre_student_roster')
        .select('id, exam_msce_institute_id, exam_student_full_name, exam_msce_student_id, exam_roll_number')
        .eq('centre_id', centerId)
        .order('exam_student_full_name');

    return [
      for (final raw in rows as List)
        ExamCenterRosterEntry(
          id: (raw as Map)['id']?.toString() ?? '',
          instituteId: raw['exam_msce_institute_id']?.toString() ?? '',
          fullName: raw['exam_student_full_name']?.toString() ?? '',
          msceStudentId: raw['exam_msce_student_id']?.toString(),
          examRollNumber: raw['exam_roll_number']?.toString(),
        ),
    ];
  }

  Future<Map<String, Map<String, dynamic>>> _fetchMsceStudentsForRoster(
    List<ExamCenterRosterEntry> roster,
  ) async {
    final linkedIds = roster
        .map((e) => e.msceStudentId)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();

    if (linkedIds.isNotEmpty) {
      return _fetchMsceStudentsByIds(linkedIds);
    }

    final instituteIds = roster.map((r) => r.instituteId).where((s) => s.isNotEmpty).toSet().toList();
    return _fetchMsceStudentsByInstitute(instituteIds);
  }

  Future<Map<String, Map<String, dynamic>>> _fetchMsceStudentsByIds(Set<String> ids) async {
    if (ids.isEmpty) return {};

    final out = <String, Map<String, dynamic>>{};
    final idList = ids.toList();
    const chunk = 80;

    for (var i = 0; i < idList.length; i += chunk) {
      final slice = idList.sublist(i, i + chunk > idList.length ? idList.length : i + chunk);
      final rows = await supabase.from('students').select(_detailCols).inFilter('id', slice);

      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString() ?? '';
        final instituteId = row['institute_id']?.toString() ?? '';
        if (id.isEmpty) continue;

        final key = instituteId.isNotEmpty
            ? examStudentRosterKey(instituteId, msceStudentFullName(row))
            : id;
        out.putIfAbsent(key, () => row);
        out['id:$id'] = row;
      }
    }
    return out;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchMsceStudentsByInstitute(
    List<String> instituteIds,
  ) async {
    if (instituteIds.isEmpty) return {};

    final rows = await supabase
        .from('students')
        .select(_detailCols)
        .inFilter('institute_id', instituteIds);

    final out = <String, Map<String, dynamic>>{};
    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = row['id']?.toString() ?? '';
      final instituteId = row['institute_id']?.toString() ?? '';
      if (id.isEmpty || instituteId.isEmpty) continue;

      final key = examStudentRosterKey(instituteId, msceStudentFullName(row));
      out.putIfAbsent(key, () => row);
      out['id:$id'] = row;
    }
    return out;
  }

  Future<void> _persistRosterLinks(List<Map<String, dynamic>> updates) async {
    try {
      for (final patch in updates) {
        final id = patch['id']?.toString();
        if (id == null || id.isEmpty) continue;
        await supabase.from('exam_centre_student_roster').update({
          'exam_msce_student_id': patch['exam_msce_student_id'],
          'updated_at': patch['updated_at'],
        }).eq('id', id);
      }
    } catch (_) {}
  }

  Future<Map<String, Map<String, dynamic>>> _entryMarksByStudent(String centerId) async {
    final rows = await supabase
        .from('exam_attendance_marks')
        .select('exam_msce_student_id, marked_at, exam_entry_photo_url, present_photo_path, exam_face_match_score')
        .eq('centre_id', centerId)
        .not('exam_msce_student_id', 'is', null);

    final out = <String, Map<String, dynamic>>{};
    for (final raw in rows as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final sid = m['exam_msce_student_id']?.toString() ?? '';
      if (sid.isNotEmpty) out[sid] = m;
    }
    return out;
  }

  MsceStudent _mapRow(
    Map<String, dynamic> row, {
    required Map<String, Map<String, dynamic>> marks,
    String? examRollNumber,
  }) {
    final id = row['id']?.toString() ?? '';
    final mark = marks[id];
    final entryUrl = mark?['exam_entry_photo_url']?.toString() ??
        mark?['present_photo_path']?.toString();
    DateTime? markedAt;
    final markedRaw = mark?['marked_at']?.toString();
    if (markedRaw != null && markedRaw.isNotEmpty) {
      markedAt = DateTime.tryParse(markedRaw);
    }

    final subjects = row['subjects'];
    String? subject = row['subject']?.toString();
    if ((subject == null || subject.isEmpty) && subjects is List && subjects.isNotEmpty) {
      subject = subjects.first?.toString();
    }

    return MsceStudent(
      id: id,
      name: row['name']?.toString() ?? '',
      lastName: row['last_name']?.toString() ?? '',
      srNo: row['sr_no']?.toString() ?? '',
      photoUrl: row['face_photo_url']?.toString() ?? '',
      photoVersion: row['photo_version']?.toString(),
      hasFaceEmbedding: studentHasNonEmptyFaceEmbedding(row['face_embedding']),
      instituteId: row['institute_id']?.toString(),
      userId: row['user_id']?.toString(),
      firstName: row['first_name']?.toString(),
      middleName: row['middle_name']?.toString(),
      year: row['year']?.toString(),
      subject: subject,
      examRollNumber: examRollNumber,
      entryMarked: mark != null,
      entryPhotoUrl: entryUrl,
      entryMarkedAt: markedAt,
      faceMatchScore: (mark?['exam_face_match_score'] as num?)?.toDouble(),
    );
  }


  /// Load students directly from exam_students table
  /// Groups all subjects per student, stores all exam_students rows
  Future<List<MsceStudent>> loadFromExamStudentsTable({
    required String centerId,
    String? centerCode,
    String search = '',
  }) async {
    if (!isSupabaseConfigured) return [];
    try {
      // ✅ Check cache first (saves egress)
      final cacheKey = 'exam_students_${centerCode ?? centerId}_$search';
      final cached = await ApiCacheService.getCachedResponse(cacheKey);
      if (cached != null && cached is List) {
        print('✅ CACHE HIT: Using cached students (saves egress)');
        return _processExamStudents(cached.cast<Map<String, dynamic>>());
      }

      print('🔍 DEBUG: Querying exam_students for centre_code=$centerCode, centerId=$centerId');
      var query = supabase.from('exam_students').select();
      if (centerCode != null && centerCode.isNotEmpty) {
        query = query.eq('centre_code', centerCode);
        print('✅ DEBUG: Filter by centre_code=$centerCode');
      } else {
        query = query.eq('centre_id', centerId);
      }
      if (search.isNotEmpty) {
        query = query.ilike('student_name', '%${search.trim()}%');
      }

      // ✅ Order by seat_no for consistent data (photo linked to seat_no)
      final rows = await query.order('seat_no', ascending: true);
      print('📊 DEBUG: Got ${rows.length} exam_students rows');

      // ✅ Cache the response (24 hour TTL)
      await ApiCacheService.cacheResponse(
        key: cacheKey,
        data: rows,
        ttl: const Duration(hours: 24),
      );
      print('💾 CACHED: Saved ${rows.length} rows to local cache');

      // ✅ Group ALL subjects by STUDENT NAME (not exam_student_id - same student may have different IDs per subject)
      final studentMap = <String, List<Map<String, dynamic>>>{};
      final studentIdMap = <String, String>{};  // Map to store first exam_student_id for each student

      // ✅ Log seat-photo mapping for debugging
      final photoDebug = <String, String>{};

      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final studentName = row['student_name']?.toString() ?? '';
        final examStudentId = row['exam_student_id']?.toString() ?? '';
        final seatNo = row['seat_no']?.toString() ?? '';
        final photoUrl = row['entry_photo_url']?.toString() ?? '';

        if (photoUrl.isNotEmpty) {
          photoDebug[seatNo] = photoUrl;
        }

        if (studentName.isNotEmpty) {
          studentMap.putIfAbsent(studentName, () => []).add(row);
          // Store first exam_student_id for this student
          if (!studentIdMap.containsKey(studentName)) {
            studentIdMap[studentName] = examStudentId;
          }
        }
      }

      if (photoDebug.isNotEmpty) {
        print('✅ Photos by seat: $photoDebug');
      }

      // Create MsceStudent objects with ALL subjects
      final students = <MsceStudent>[];
      for (final studentName in studentMap.keys) {
        final subjectRows = studentMap[studentName]!;
        final firstRow = subjectRows.first;  // Use first row for student info
        final examStudentId = studentIdMap[studentName] ?? '';

        // Parse surname from student_name for sorting
        final fullName = firstRow['student_name']?.toString() ?? 'Unknown';
        final nameParts = fullName.trim().split(RegExp(r'\s+'));
        final lastName = nameParts.length > 1 ? nameParts.last : '';

        students.add(MsceStudent(
          id: examStudentId,
          name: fullName,
          lastName: lastName,  // ✅ Extract surname for sorting
          srNo: firstRow['sr_no']?.toString() ?? '',
          photoUrl: firstRow['photo_url']?.toString() ?? '',
          hasFaceEmbedding: firstRow['face_embedding'] != null,
          entryMarked: subjectRows.any((r) => r['entry_photo_url'] != null),
          entryPhotoUrl: subjectRows.firstWhere(
            (r) => r['entry_photo_url'] != null,
            orElse: () => {},
          )['entry_photo_url']?.toString(),
          entryMarkedAt: subjectRows
              .firstWhere(
                (r) => r['entry_photo_at'] != null,
                orElse: () => {},
              )['entry_photo_at'] != null
              ? DateTime.tryParse(
                  subjectRows
                      .firstWhere(
                        (r) => r['entry_photo_at'] != null,
                        orElse: () => {},
                      )['entry_photo_at']
                      .toString())
              : null,
          subjects: subjectRows,  // ✅ Store ALL subject rows
        ));
      }

      // Fetch student photos from students table (master source)
      final studentIds = students.map((s) => s.id).toList();
      final photoMap = <String, String>{};
      if (studentIds.isNotEmpty) {
        try {
          final studentRows = await supabase
              .from('students')
              .select('id, face_photo_url')
              .inFilter('id', studentIds);
          for (final row in studentRows as List) {
            final id = row['id']?.toString() ?? '';
            final photoUrl = row['face_photo_url']?.toString();
            if (id.isNotEmpty && photoUrl != null && photoUrl.isNotEmpty) {
              photoMap[id] = photoUrl;
            }
          }
          print('📸 Fetched photos for ${photoMap.length} students from students table');
        } catch (e) {
          print('⚠️ Could not fetch photos from students table: $e');
        }
      }

      // Sort by surname (ascending), then by name
      students.sort((a, b) {
        final lc = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
        if (lc != 0) return lc;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      // Auto-assign SR No based on sorted position (001, 002, 003, ...)
      for (var i = 0; i < students.length; i++) {
        final autoSrNo = (i + 1).toString().padLeft(3, '0');
        // Use photo from students table if available, fallback to exam_students
        final finalPhotoUrl = photoMap[students[i].id] ?? students[i].photoUrl;

        students[i] = MsceStudent(
          id: students[i].id,
          name: students[i].name,
          lastName: students[i].lastName,
          srNo: autoSrNo,  // ✅ Use auto-numbered SR No
          photoUrl: finalPhotoUrl,  // ✅ Use photo from students table
          photoVersion: students[i].photoVersion,
          hasFaceEmbedding: students[i].hasFaceEmbedding,
          instituteId: students[i].instituteId,
          userId: students[i].userId,
          firstName: students[i].firstName,
          middleName: students[i].middleName,
          year: students[i].year,
          subject: students[i].subject,
          examRollNumber: students[i].examRollNumber,
          entryMarked: students[i].entryMarked,
          entryPhotoUrl: students[i].entryPhotoUrl,
          entryMarkedAt: students[i].entryMarkedAt,
          faceMatchScore: students[i].faceMatchScore,
          subjects: students[i].subjects,
        );
      }

      print('✅ DEBUG: Returning ${students.length} unique students (sorted by surname, auto-numbered)');
      return students;
    } catch (e) {
      print('❌ DEBUG ERROR: $e');
      return [];
    }
  }

  /// Helper: Process exam_students rows into MsceStudent objects
  List<MsceStudent> _processExamStudents(List<Map<String, dynamic>> rows) {
    final studentMap = <String, List<Map<String, dynamic>>>{};
    final studentIdMap = <String, String>{};

    for (final row in rows) {
      final studentName = row['student_name']?.toString() ?? '';
      final examStudentId = row['exam_student_id']?.toString() ?? '';

      if (studentName.isNotEmpty) {
        studentMap.putIfAbsent(studentName, () => []).add(row);
        if (!studentIdMap.containsKey(studentName)) {
          studentIdMap[studentName] = examStudentId;
        }
      }
    }

    final students = <MsceStudent>[];
    for (final studentName in studentMap.keys) {
      final subjectRows = studentMap[studentName]!;
      final firstRow = subjectRows.first;
      final examStudentId = studentIdMap[studentName] ?? '';

      final fullName = firstRow['student_name']?.toString() ?? 'Unknown';
      final nameParts = fullName.trim().split(RegExp(r'\s+'));
      final lastName = nameParts.length > 1 ? nameParts.last : '';

      students.add(MsceStudent(
        id: examStudentId,
        name: fullName,
        lastName: lastName,
        srNo: firstRow['sr_no']?.toString() ?? '',
        photoUrl: firstRow['photo_url']?.toString() ?? '',
        hasFaceEmbedding: firstRow['face_embedding'] != null,
        entryMarked: subjectRows.any((r) => r['entry_photo_url'] != null),
        subjects: subjectRows,
      ));
    }

    return students;
  }

}
