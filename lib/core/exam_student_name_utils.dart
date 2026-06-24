/// Normalize full name for roster ↔ MSCE student matching.
String normalizeExamStudentFullName(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Build compare key: institute + normalized full name.
String examStudentRosterKey(String instituteId, String fullName) {
  return '${instituteId.trim()}|${normalizeExamStudentFullName(fullName)}';
}

/// Full name from MSCE `students` row (first/middle/last, else `name`).
String msceStudentFullName(Map<String, dynamic> row) {
  final fn = row['first_name']?.toString().trim() ?? '';
  final mn = row['middle_name']?.toString().trim() ?? '';
  final ln = row['last_name']?.toString().trim() ?? '';
  if (fn.isNotEmpty || mn.isNotEmpty || ln.isNotEmpty) {
    return normalizeExamStudentFullName('$fn $mn $ln');
  }
  return normalizeExamStudentFullName(row['name']?.toString() ?? '');
}
