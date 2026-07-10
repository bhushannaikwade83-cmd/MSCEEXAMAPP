import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_ui.dart';
import '../../models/exam_student.dart';
import '../../services/exam_data_service.dart';
import '../../services/session_service.dart';

/// Web Mark Entry Screen
/// Staff compares seated student to passport photo — no automatic face matching.
class WebMarkEntryScreen extends StatefulWidget {
  const WebMarkEntryScreen({super.key, required this.student});

  final ExamStudent student;

  @override
  State<WebMarkEntryScreen> createState() => _WebMarkEntryScreenState();
}

class _WebMarkEntryScreenState extends State<WebMarkEntryScreen> {
  final _data = ExamDataService();
  bool _busy = false;
  String? _status;

  Future<void> _confirmPresent() async {
    setState(() {
      _busy = true;
      _status = 'Marking attendance…';
    });

    final center = await SessionService.getCenter();
    if (center == null) return;

    try {
      await _data.markAttendance(
        centerId: center['id']!,
        studentId: widget.student.id,
        presentPhotoPath: null, // Web version doesn't require photo path
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marked present'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _status = e.toString();
      });
    }
  }

  void _confirmAbsent() {
    setState(() {
      _busy = true;
      _status = 'Marking absent…';
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pop(context, false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.name),
        elevation: 0,
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 500.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Is the student seated in the hall the same person as in the passport photo?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'No automatic comparison — you confirm by looking.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  SizedBox(height: 24.h),

                  // Seat Number
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Seat: ${s.seatNo}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),

                  SizedBox(height: 24.h),

                  // Passport Photo
                  Text(
                    'Passport Photo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Container(
                    constraints: BoxConstraints(maxWidth: 220.w),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppTheme.primaryBlue,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: s.passportPhotoUrl != null &&
                              s.passportPhotoUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: s.passportPhotoUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              errorWidget: (_, _, _) => const _NoPhoto(),
                            )
                          : const _NoPhoto(),
                    ),
                  ),

                  SizedBox(height: 32.h),

                  // Instructions
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange.shade800,
                              size: 18.sp,
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              'Manual Verification',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          '1. Compare the photo with the seated student\n'
                          '2. Verify identity visually\n'
                          '3. Select "Mark Present" or "Mark Absent"',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.orange.shade800,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24.h),

                  if (_status != null) ...[
                    Text(
                      _status!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    SizedBox(height: 12.h),
                  ],

                  // Action Buttons
                  SizedBox(
                    height: 52.h,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _confirmPresent,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Mark Present'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ),

                  SizedBox(height: 12.h),

                  SizedBox(
                    height: 52.h,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _confirmAbsent,
                      icon: const Icon(Icons.close_circle),
                      label: const Text('Mark Absent'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(
                          color: Colors.red,
                          width: 2,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 20.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              size: 48.sp,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: 8.h),
            Text(
              'No photo',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
