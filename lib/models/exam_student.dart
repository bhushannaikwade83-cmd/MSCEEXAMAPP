/// [passportPhotoUrl] — passport-size photo; staff visually confirms seated student matches.
class ExamStudent {
  ExamStudent({
    required this.id,
    required this.seatNo,
    required this.name,
    required this.examTime,
    this.passportPhotoUrl,
    this.isMarked = false,
    this.subjects = const [],
  });

  final String id;
  final String seatNo;
  final String name;
  final DateTime examTime;
  final String? passportPhotoUrl;
  final bool isMarked;
  /// All subjects this student is registered for at this exam centre.
  final List<String> subjects;

  static List<String> _parseSubjects(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    if (raw is String && raw.isNotEmpty) return [raw];
    return [];
  }

  factory ExamStudent.fromMap(Map<String, dynamic> row, {bool marked = false}) {
    // seat_no is the primary field; roll_number is legacy fallback.
    final seatNo = row['seat_no']?.toString().trim() ?? '';
    final rollNumberFallback = row['roll_number']?.toString().trim() ?? '';

    // Batch time: prefer exam_date + start_time; exam_time is a legacy fallback
    // (dropped after migration 007 runs).
    DateTime examTime = DateTime.now();
    final examDate = row['exam_date']?.toString();
    final startTime = row['start_time']?.toString();
    if (examDate != null && examDate.isNotEmpty &&
        startTime != null && startTime.isNotEmpty) {
      final cleaned = startTime.split('+').first.split('-').first.trim();
      examTime = DateTime.tryParse('${examDate}T$cleaned') ?? DateTime.now();
    } else if (row['exam_time'] != null) {
      examTime = DateTime.tryParse(row['exam_time'].toString()) ?? DateTime.now();
    }

    // photo_url is merged by ExamDataService from students.face_photo_url.
    // subjects is merged from students.subjects / students.subject.
    return ExamStudent(
      id: row['id'] as String,
      seatNo: seatNo.isNotEmpty ? seatNo : rollNumberFallback,
      name: row['student_name']?.toString() ?? '',
      examTime: examTime,
      passportPhotoUrl: row['photo_url']?.toString(),
      isMarked: marked,
      subjects: _parseSubjects(row['subjects'] ?? row['subject']),
    );
  }
}
