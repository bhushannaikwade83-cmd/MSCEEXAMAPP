import '../core/student_face_embedding_utils.dart';

/// In-memory cache of MSCE student rows (photo + face_embedding) for the logged-in centre.
/// Populated when the home screen loads; used for face verify / auto-scan without re-fetch.
class ExamCentreStudentCache {
  ExamCentreStudentCache._();

  static String? _centerId;
  static final Map<String, Map<String, dynamic>> _byId = {};

  static bool get isLoaded => _byId.isNotEmpty;

  static String? get centerId => _centerId;

  static void clear() {
    _centerId = null;
    _byId.clear();
  }

  static void setForCenter({
    required String centerId,
    required Iterable<Map<String, dynamic>> studentRows,
  }) {
    _centerId = centerId;
    _byId.clear();
    for (final raw in studentRows) {
      final row = Map<String, dynamic>.from(raw);
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      _byId[id] = row;
    }
  }

  static Map<String, dynamic>? studentById(String studentId) {
    final id = studentId.trim();
    if (id.isEmpty) return null;
    final row = _byId[id];
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  static List<Map<String, dynamic>> allRows() =>
      _byId.values.map((r) => Map<String, dynamic>.from(r)).toList();

  /// MSCE `institute_id` from cached roster rows (authoritative for face match).
  static String? get primaryInstituteId {
    for (final raw in _byId.values) {
      final id = raw['institute_id']?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  static int get enrolledFaceCount => enrolledRowsForMatching().length;

  static List<Map<String, dynamic>> enrolledRowsForMatching({Set<String>? allowedIds}) {
    final ids = allowedIds?.where((s) => s.trim().isNotEmpty).toSet();
    final rows = ids == null || ids.isEmpty
        ? _byId.values
        : ids.map((id) => _byId[id]).whereType<Map<String, dynamic>>();

    return [
      for (final raw in rows)
        if (studentHasNonEmptyFaceEmbedding(raw['face_embedding']))
          Map<String, dynamic>.from(raw),
    ];
  }
}
