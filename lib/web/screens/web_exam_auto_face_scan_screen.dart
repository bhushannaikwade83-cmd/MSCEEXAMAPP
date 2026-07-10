import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_ui.dart';
import '../../services/session_service.dart';

/// Web version of auto face scan screen
/// Web cannot perform automatic face detection, so shows manual entry interface
class WebExamAutoFaceScanScreen extends StatefulWidget {
  static const routeName = '/auto-face-scan';

  const WebExamAutoFaceScanScreen({
    super.key,
    this.instituteId,
    this.allowedStudentIds = const {},
  });

  final String? instituteId;
  final Set<String> allowedStudentIds;

  @override
  State<WebExamAutoFaceScanScreen> createState() =>
      _WebExamAutoFaceScanScreenState();
}

class _WebExamAutoFaceScanScreenState extends State<WebExamAutoFaceScanScreen> {
  String? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final center = await SessionService.getCenter();
    if (!mounted) return;

    if (center == null) {
      setState(() {
        _status = 'Center not configured';
        _loading = false;
      });
      return;
    }

    setState(() {
      _status = 'Ready for manual face verification';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Scan Entry'),
        elevation: 0,
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 600.w),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Not Available Card
                  Container(
                    padding: EdgeInsets.all(24.w),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_rounded,
                          size: 48.sp,
                          color: Colors.orange.shade800,
                        ),
                        SizedBox(height: 16.h),
                        Text(
                          'Automatic Face Detection',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        Text(
                          'This feature is not available on the web version.',
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: Colors.orange.shade800,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 32.h),

                  // Alternative Solutions
                  Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Available Options:',
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        _buildOption(
                          icon: Icons.camera_alt,
                          title: 'Manual Photo Capture',
                          description: 'Capture entry photos manually for verification',
                          color: Colors.blue,
                        ),
                        SizedBox(height: 10.h),
                        _buildOption(
                          icon: Icons.qr_code_2,
                          title: 'QR Code Search',
                          description: 'Search for students using QR codes or manual entry',
                          color: Colors.green,
                        ),
                        SizedBox(height: 10.h),
                        _buildOption(
                          icon: Icons.person_search,
                          title: 'Manual Student Search',
                          description: 'Find students by name or seat number',
                          color: Colors.purple,
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 32.h),

                  // Technical Details
                  ExpansionTile(
                    title: Text(
                      'Why Face Detection is Not Available on Web',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark,
                      ),
                    ),
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                        child: Text(
                          '• ML Kit face detection requires native platform access\n'
                          '• Web browsers have limited access to advanced ML libraries\n'
                          '• Web can only capture images, not process them for facial recognition\n'
                          '• Use the mobile app (iOS/Android) for automatic face-based scanning',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.grey.shade700,
                            height: 1.8,
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 32.h),

                  // Go Back Button
                  SizedBox(
                    height: 52.h,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Go Back'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 40.w,
          height: 40.w,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20.sp),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade900,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
