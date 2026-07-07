import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/exam_batch.dart';
import '../models/exam_student.dart';
import '../services/exam_data_service.dart';
import '../services/session_service.dart';
import 'student_subjects_screen.dart';

class StudentCardsScreen extends StatefulWidget {
  const StudentCardsScreen({super.key, required this.batch});

  final ExamBatch batch;

  @override
  State<StudentCardsScreen> createState() => _StudentCardsScreenState();
}

class _StudentCardsScreenState extends State<StudentCardsScreen> {
  final _data = ExamDataService();
  List<ExamStudent> _students = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final center = await SessionService.getCenter();
    if (center == null) return;
    final list = await _data.loadStudentsInBatch(
      centerId: center['id']!,
      batchStart: widget.batch.start,
      centreCode: center['code'],
    );
    if (!mounted) return;
    setState(() {
      _students = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.batch.label)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(
                    'Tap a student → compare seated person with passport photo → mark present.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.68,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _students.length,
                    itemBuilder: (_, i) {
                      final s = _students[i];
                      return _StudentCard(
                        student: s,
                        onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StudentSubjectsScreen(student: s),
                                  ),
                                );
                                _load(); // refresh marks on return
                              },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student, this.onTap});

  final ExamStudent student;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: const Text(
                'Passport photo',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.primary),
              ),
            ),
            Expanded(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: student.passportPhotoUrl != null && student.passportPhotoUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: student.passportPhotoUrl!,
                        cacheKey: student.id ?? student.seatNo,  // ✅ Unique key per student
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        errorWidget: (_, _, _) => const _PhotoPlaceholder(),
                      )
                    : const _PhotoPlaceholder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    student.seatNo,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        student.isMarked ? Icons.check_circle : Icons.visibility,
                        size: 16,
                        color: student.isMarked ? AppColors.success : AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        student.isMarked ? 'Present' : 'Check & mark',
                        style: TextStyle(
                          fontSize: 11,
                          color: student.isMarked ? AppColors.success : AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: const Center(child: Icon(Icons.person, size: 48, color: Colors.grey)),
    );
  }
}
