import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/constants.dart';
import '../../core/theme/app_ui.dart';
import '../../services/gps_service.dart';
import '../../services/session_service.dart';
import 'web_home_screen.dart';

/// Web version of GPS setup - shows placeholder since web cannot access device GPS
class WebGpsSetupScreen extends StatefulWidget {
  const WebGpsSetupScreen({
    super.key,
    required this.centerId,
    this.fromLogin = false,
    this.isMandatory = false,
  });

  final String centerId;
  final bool fromLogin;
  final bool isMandatory;

  @override
  State<WebGpsSetupScreen> createState() => _WebGpsSetupScreenState();
}

class _WebGpsSetupScreenState extends State<WebGpsSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(
    text: kExamFenceRadiusMeters.toStringAsFixed(0),
  );
  final _gps = GpsService();

  bool _loading = false;
  bool _hasLocation = false;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final cfg = await _gps.fetchConfig(widget.centerId);
    if (cfg?.lat != null && cfg?.lng != null) {
      setState(() {
        _latCtrl.text = cfg!.lat!.toStringAsFixed(6);
        _lngCtrl.text = cfg.lng!.toStringAsFixed(6);
        _hasLocation = true;
        _isLocked = cfg.locked;
      });
    }
  }

  void _onManualEntry() {
    // Manual entry for testing - allow editing if not locked
    if (!_isLocked) {
      _latCtrl.clear();
      _lngCtrl.clear();
      setState(() => _hasLocation = false);
    }
  }

  Future<void> _saveAndContinue() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) {
      _snack('Please enter valid latitude and longitude values.', success: false);
      return;
    }

    setState(() => _loading = true);
    final err = await _gps.saveAndLock(
      centerId: widget.centerId,
      latitude: lat,
      longitude: lng,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _hasLocation = err == null;
      _isLocked = err == null;
    });

    if (err != null) {
      _snack(err, success: false);
      return;
    }

    _snack('GPS settings saved!', success: true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // Go to home screen
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WebHomeScreen()),
      (_) => false,
    );
  }

  void _snack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
          ],
        ),
        backgroundColor: success ? AppTheme.accentGreen : AppTheme.accentRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(seconds: success ? 4 : 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20.w),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 600.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: EdgeInsets.all(20.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(12.r),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Icon(Icons.info_outline, color: AppTheme.primaryBlue, size: 28.sp),
                        ),
                        SizedBox(width: 16.w),
                        Expanded(
                          child: Text(
                            'Set your exam centre GPS zone. Attendance is allowed only within the locked radius.\n\n'
                            'Note: Web version requires manual coordinate entry (desktop GPS not available).',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: AppTheme.textGray,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24.h),

                  // Web Platform Notice
                  Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.orange, width: 2),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_rounded, color: Colors.orange, size: 24),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Web Version',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                  fontSize: 13.sp,
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                'GPS is not available in web browsers. Enter coordinates manually or use the mobile app to set GPS.',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 12.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24.h),

                  Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.blue, width: 2),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock, color: Colors.blue, size: 24),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Radius fixed at ${kExamFenceRadiusMeters.toStringAsFixed(0)} m',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                  fontSize: 15.sp,
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                'Attendance may only be marked within this radius. This cannot be changed.',
                                style: TextStyle(
                                  color: Colors.blue.withValues(alpha: 0.85),
                                  fontSize: 12.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_isLocked) ...[
                    SizedBox(height: 16.h),
                    Container(
                      padding: EdgeInsets.all(16.w),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.orange, width: 2),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock, color: Colors.orange, size: 24),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Text(
                              'Location locked. Contact admin to unlock for changes.',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  SizedBox(height: 24.h),

                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Centre Coordinates',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 16.h),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _latCtrl,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Latitude',
                                  prefixIcon: Icon(Icons.map_outlined),
                                  helperText: 'Enter decimal format',
                                ),
                                enabled: !_isLocked,
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: TextFormField(
                                controller: _lngCtrl,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Longitude',
                                  prefixIcon: Icon(Icons.map_outlined),
                                  helperText: 'Enter decimal format',
                                ),
                                enabled: !_isLocked,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16.h),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isLocked ? null : _onManualEntry,
                            icon: const Icon(Icons.edit_location),
                            label: const Text('Clear & Enter Manually'),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 16.h),
                              side: const BorderSide(color: AppTheme.primaryBlue),
                              foregroundColor: AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                        SizedBox(height: 24.h),
                        Text(
                          'Allowed Radius',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 16.h),
                        TextFormField(
                          controller: _radiusCtrl,
                          decoration: InputDecoration(
                            labelText: 'Radius in Meters',
                            prefixIcon: const Icon(Icons.radar_outlined),
                            helperText:
                                'Fixed at ${kExamFenceRadiusMeters.toStringAsFixed(0)} m for all exam centres.',
                          ),
                          enabled: false,
                          readOnly: true,
                        ),
                        SizedBox(height: 32.h),
                        SizedBox(
                          height: 56.h,
                          child: ElevatedButton(
                            onPressed: (_loading || _isLocked) ? null : _saveAndContinue,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _isLocked ? Colors.grey : AppTheme.primaryBlue,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _isLocked ? 'Location Locked' : 'Save Configuration',
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
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
}
