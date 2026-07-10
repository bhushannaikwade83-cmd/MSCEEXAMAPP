import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/session_service.dart';
import '../../core/theme/app_ui.dart';
import 'web_home_screen.dart';

class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({Key? key}) : super(key: key);

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final valid = await SessionService.isSessionValid();
    if (valid && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WebHomeScreen()),
      );
    }
  }

  Future<void> _login() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'Enter PIN');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('center_users')
          .select('id, center_id, center_code, center_name')
          .eq('pin', pin)
          .single();

      if (!mounted) return;

      // Save session
      await SessionService.saveCenter(
        centerId: response['center_id'],
        centerCode: response['center_code'],
        centerName: response['center_name'],
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WebHomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Invalid PIN or connection error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryBlueDark, // Use AppTheme colors
      body: Center(
        child: SizedBox(
          width: 400.w,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  height: 80.h,
                  width: 80.w,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset(
                    'assets/msce_attendance_app_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                SizedBox(height: 30.h),

                // Title
                Text(
                  'GCC TBC EXAMS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10.h),
                Text(
                  'Exam Center Login',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14.sp,
                  ),
                ),
                SizedBox(height: 40.h),

                // PIN Input
                TextField(
                  controller: _pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20.sp, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: 'Enter PIN',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 20.w,
                      vertical: 16.h,
                    ),
                  ),
                ),
                SizedBox(height: 20.h),

                // Error message
                if (_error != null)
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 12.sp,
                      ),
                    ),
                  ),
                SizedBox(height: 20.h),

                // Login Button
                ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    padding: EdgeInsets.symmetric(
                      horizontal: 40.w,
                      vertical: 14.h,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 20.w,
                          height: 20.h,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Text(
                          'LOGIN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }
}
