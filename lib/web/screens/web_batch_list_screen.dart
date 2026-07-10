import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_ui.dart';
import '../../models/exam_batch.dart';
import '../../services/exam_data_service.dart';
import '../../services/session_service.dart';
import 'web_center_login_screen.dart';
import 'web_student_cards_screen.dart';

class WebBatchListScreen extends StatefulWidget {
  const WebBatchListScreen({super.key});

  @override
  State<WebBatchListScreen> createState() => _WebBatchListScreenState();
}

class _WebBatchListScreenState extends State<WebBatchListScreen> {
  final _data = ExamDataService();
  List<ExamBatch> _batches = [];
  String? _centerName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final center = await SessionService.getCenter();
    if (center == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WebCenterLoginScreen()),
      );
      return;
    }

    final batches = await _data.loadBatches(
      center['id']!,
      centreCode: center['code'],
    );
    if (!mounted) return;
    setState(() {
      _centerName = center['name'];
      _batches = batches;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await SessionService.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WebCenterLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(_centerName ?? 'Exam Batches'),
        elevation: 0,
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _batches.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 48.sp,
                        color: Colors.grey.shade400,
                      ),
                      SizedBox(height: 16.h),
                      Text(
                        'No batches available',
                        style: TextStyle(
                          fontSize: 16.sp,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'No students allotted to this centre yet.',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.all(16.w),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 800.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Select a batch to view students',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  color: Colors.grey.shade700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 20.h),
                              ...List.generate(
                                _batches.length,
                                (i) {
                                  final b = _batches[i];
                                  return Padding(
                                    padding: EdgeInsets.only(bottom: 10.h),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  WebStudentCardsScreen(batch: b),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: EdgeInsets.all(16.w),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border.all(
                                              color: Colors.grey.shade300,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.05),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 56.w,
                                                height: 56.w,
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primaryBlue
                                                      .withOpacity(0.1),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '${b.studentCount}',
                                                    style: TextStyle(
                                                      fontSize: 20.sp,
                                                      fontWeight: FontWeight.bold,
                                                      color:
                                                          AppTheme.primaryBlue,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 16.w),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      b.label,
                                                      style: TextStyle(
                                                        fontSize: 15.sp,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    SizedBox(height: 4.h),
                                                    Text(
                                                      '1 hour batch',
                                                      style: TextStyle(
                                                        fontSize: 12.sp,
                                                        color: Colors
                                                            .grey.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Icon(Icons.chevron_right,
                                                  color: Colors.grey),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
