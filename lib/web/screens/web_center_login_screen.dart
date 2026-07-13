import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_ui.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import 'web_pin_setup_screen.dart';
import 'web_home_screen.dart';

class WebCenterLoginScreen extends StatefulWidget {
  const WebCenterLoginScreen({super.key});

  @override
  State<WebCenterLoginScreen> createState() => _WebCenterLoginScreenState();
}

class _WebCenterLoginScreenState extends State<WebCenterLoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();

  bool _busy = false;
  bool _passwordVisible = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;

    setState(() => _busy = true);
    final result = await _auth.login(user, pass);
    if (!mounted) return;

    if (!result.ok || result.centerId == null) {
      setState(() => _busy = false);
      _showSnackbar(result.message ?? 'Login failed', success: false);
      return;
    }

    await SessionService.saveCenter(
      centerId: result.centerId!,
      centerCode: result.code ?? '',
      centerName: result.name ?? '',
      msceInstituteId: result.msceInstituteId,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    // For web, go directly to PIN setup
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => WebPinSetupScreen(
            centerId: result.centerId!,
            fromLogin: true,
          ),
        ),
        (_) => false,
      );
    }
  }

  void _showSnackbar(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_outline : Icons.error_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: success ? AppTheme.primaryGreen : AppTheme.accentRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
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
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 560.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 20.h),

                  // Logo Section
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 80.w,
                          height: 80.w,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16.r),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.35),
                                blurRadius: 22,
                                offset: const Offset(0, 7),
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            color: AppTheme.primaryBlue,
                            size: 50,
                          ),
                        ),
                        SizedBox(height: 14.h),
                        Text(
                          'GCC TBC EXAMS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.primaryBlue,
                            fontSize: 25.sp,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Center Login',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textGray,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 40.h),

                  // Login Card
                  Container(
                    padding: EdgeInsets.all(20.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 4.w,
                                height: 22.h,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppTheme.primaryBlueLight,
                                      AppTheme.primaryBlueDark
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                  'Secure Login  |  सुरक्षित लॉगिन',
                                  style: TextStyle(
                                    color: AppTheme.primaryBlue,
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 6.h),
                          const Divider(color: AppTheme.dividerColor, thickness: 1),
                          SizedBox(height: 18.h),

                          if (!isSupabaseEnvConfigured)
                            Container(
                              margin: EdgeInsets.only(bottom: 14.h),
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                              decoration: BoxDecoration(
                                color: AppTheme.accentRed.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppTheme.accentRed.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: AppTheme.accentRed, size: 16),
                                  SizedBox(width: 8.w),
                                  Expanded(
                                    child: Text(
                                      'Add SUPABASE_URL and SUPABASE_ANON_KEY in app_config.env',
                                      style: TextStyle(
                                        color: AppTheme.accentRed,
                                        fontSize: 11.sp,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Username field
                          TextFormField(
                            controller: _userCtrl,
                            decoration: InputDecoration(
                              labelText: 'Login  |  लॉगिन',
                              hintText: 'Centre username',
                              prefixIcon: const Icon(Icons.person_outline_rounded),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppTheme.dividerColor,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppTheme.dividerColor,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppTheme.primaryBlue,
                                  width: 2,
                                ),
                              ),
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Login is required';
                              }
                              return null;
                            },
                          ),

                          SizedBox(height: 14.h),

                          // Password field
                          TextFormField(
                            controller: _passCtrl,
                            obscureText: !_passwordVisible,
                            decoration: InputDecoration(
                              labelText: 'Password  |  पासवर्ड',
                              hintText: '••••••••',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _passwordVisible
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppTheme.textGray,
                                ),
                                onPressed: () =>
                                    setState(() => _passwordVisible = !_passwordVisible),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppTheme.dividerColor,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppTheme.dividerColor,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppTheme.primaryBlue,
                                  width: 2,
                                ),
                              ),
                            ),
                            onFieldSubmitted: (_) => _submit(),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Password is required';
                              }
                              return null;
                            },
                          ),

                          SizedBox(height: 24.h),

                          // Login Button
                          SizedBox(
                            height: 52.h,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.login_rounded, color: Colors.white),
                                        SizedBox(width: 8.w),
                                        Text(
                                          'LOGIN  |  लॉगिन',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13.sp,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),

                          SizedBox(height: 14.h),

                          // Security chips
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 10.w,
                            runSpacing: 8.h,
                            children: [
                              _securityChip(Icons.lock_rounded, 'Encrypted', AppTheme.primaryGreen),
                              _securityChip(Icons.shield_rounded, 'Govt Portal', AppTheme.primaryBlue),
                              _securityChip(Icons.verified_user_rounded, 'Secure', AppTheme.accentSaffron),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _securityChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12.sp, color: color),
        SizedBox(width: 3.w),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5.sp,
            color: AppTheme.textGray,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
