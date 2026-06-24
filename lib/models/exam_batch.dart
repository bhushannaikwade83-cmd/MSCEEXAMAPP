import 'package:intl/intl.dart';

/// One-hour exam slot derived from student [examTime].
class ExamBatch {
  ExamBatch({
    required this.start,
    required this.end,
    required this.label,
    required this.studentCount,
  });

  final DateTime start;
  final DateTime end;
  final String label;
  final int studentCount;

  static ExamBatch fromHour(DateTime examTime, int count) {
    final local = examTime.toLocal();
    final start = DateTime(local.year, local.month, local.day, local.hour);
    final end = start.add(const Duration(hours: 1));
    final fmt = DateFormat('h:mm a');
    return ExamBatch(
      start: start,
      end: end,
      label: '${fmt.format(start)} – ${fmt.format(end)}',
      studentCount: count,
    );
  }
}
