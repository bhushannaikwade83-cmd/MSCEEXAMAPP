import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_ui.dart';
import '../../models/exam_batch.dart';
import '../../models/exam_student.dart';
import '../../services/exam_data_service.dart';
import '../../services/session_service.dart';
import 'web_student_subjects_screen.dart';

class WebStudentCardsScreen extends StatefulWidget {
  const WebStudentCardsScreen({super.key, required this.batch});

  final ExamBatch batch;

  @override
  State<WebStudentCardsScreen> createState() => _WebStudentCardsScreenState();
}

class _WebStudentCardsScreenState extends State<WebStudentCardsScreen> {
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
    final isMobile = MediaQuery.of(context).size.width < 600;
    final crossAxisCount = isMobile ? 1 : (MediaQuery.of(context).size.width < 1200 ? 2 : 3);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.batch.label),
        elevation: 0,
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  child: Text(
                    'Tap a student → compare seated person with passport photo → mark present.',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.all(16.w),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 0.68,
                      crossAxisSpacing: 12.w,
                      mainAxisSpacing: 12.w,
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
                              builder: (_) =>
                                  WebStudentSubjectsScreen(student: s),
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
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.grey.shade100,
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
              child: Text(
                'Passport photo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryBlue,
                ),
              ),
            ),
            Expanded(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: student.passportPhotoUrl != null &&
                        student.passportPhotoUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: student.passportPhotoUrl!,
                        cacheKey: student.id ?? student.seatNo,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        errorWidget: (_, _, _) => const _PhotoPlaceholder(),
                      )
                    : const _PhotoPlaceholder(),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(8.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.sp,
                    ),
                  ),
                  Text(
                    student.seatNo,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Mark Entry',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
      child: Icon(
        Icons.person_outline,
        size: 40.sp,
        color: Colors.grey.shade400,
      ),
    );
  }
}
