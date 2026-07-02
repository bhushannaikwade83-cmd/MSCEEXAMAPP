import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../core/supabase_client.dart';
import '../core/theme/app_ui.dart';
import '../core/utils/responsive.dart';
import '../services/auth_service.dart';
import '../services/post_login_navigator.dart';
import '../services/session_service.dart';
import '../services/location_service.dart';
import 'pin_login_screen.dart';

class CenterLoginScreen extends StatefulWidget {
  const CenterLoginScreen({super.key});

  @override
  State<CenterLoginScreen> createState() => _CenterLoginScreenState();
}

class _CenterLoginScreenState extends State<CenterLoginScreen>
    with TickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();

  bool _busy = false;
  bool _passwordVisible = false;
  bool _buttonPressed = false;

  late AnimationController _masterController;
  late AnimationController _buttonPulseController;
  late Animation<double> _logoFlip;
  late Animation<double> _screenFade;
  late Animation<double> _cardTiltX;
  late Animation<double> _cardSlideY;
  late Animation<double> _cardFade;
  late Animation<double> _buttonPulse;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _masterController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _buttonPulseController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat(reverse: true);

    _screenFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0, 0.15, curve: Curves.easeIn),
      ),
    );
    _logoFlip = Tween<double>(begin: -math.pi / 2, end: 0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.05, 0.35, curve: Curves.elasticOut),
      ),
    );
    _cardFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.35, 0.55, curve: Curves.easeIn),
      ),
    );
    _cardTiltX = Tween<double>(begin: -0.18, end: 0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic),
      ),
    );
    _cardSlideY = Tween<double>(begin: 45, end: 0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic),
      ),
    );
    _buttonPulse = Tween<double>(begin: 1, end: 1.028).animate(
      CurvedAnimation(parent: _buttonPulseController, curve: Curves.easeInOut),
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _masterController.forward();
    });
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _masterController.dispose();
    _buttonPulseController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Check location permission first
    final hasLocationAccess = await LocationService.requestLocationPermission();
    if (!hasLocationAccess) {
      if (!mounted) return;
      _showSnackbar('📍 Location access required - Please enable in Settings', success: false);
      return;
    }

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

    // ✅ Save location in background (no UI feedback)
    final location = await LocationService.getCurrentLocation();
    if (location != null) {
      unawaited(
        LocationService.saveLoginLocation(
          centreId: result.centerId!,
          centreCode: result.code ?? '',
          latitude: location['latitude']!,
          longitude: location['longitude']!,
        ),
      );
    }

    if (!mounted) return;
    setState(() => _busy = false);
    await PostLoginNavigator.continueSetup(context, centerId: result.centerId!);
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
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: _masterController,
          builder: (context, _) {
            return Opacity(
              opacity: _screenFade.value.clamp(0, 1),
              child: Column(
                children: [
                  const GovPortalHeader(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxWidth = context.contentMaxWidth(
                          mobile: 560,
                          tablet: 760,
                        );
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            Responsive.padding(context).horizontal,
                            20.h,
                            Responsive.padding(context).horizontal,
                            MediaQuery.viewInsetsOf(context).bottom + 16.h,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight - 20.h,
                                maxWidth: maxWidth,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildLogoSection(),
                                  SizedBox(height: 20.h),
                                  _buildLoginCard(),
                                  SizedBox(height: 24.h),
                                  const GovPortalFooter(),
                                  SizedBox(height: 16.h),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    final viewportH = MediaQuery.sizeOf(context).height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final logoH = viewportH * 0.18;
        final logoW = (logoH * AppUI.appLogoAspectRatio)
            .clamp(0.0, constraints.maxWidth * 0.88);
        return Column(
          children: [
            SizedBox(height: 8.h),
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateY(_logoFlip.value),
              child: Center(
                child: Container(
                  width: logoW,
                  height: logoH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16.r),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.35),
                        blurRadius: 22,
                        offset: const Offset(0, 7),
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.r),
                    child: Padding(
                      padding: EdgeInsets.all(logoH * 0.06),
                      child: AppUI.dualBrandLogos(mainHeight: logoH * 0.72),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              AppUI.loginAppTitle,
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
              AppUI.loginSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textGray,
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoginCard() {
    return Opacity(
      opacity: _cardFade.value.clamp(0, 1),
      child: Transform(
        alignment: Alignment.topCenter,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX(_cardTiltX.value)
          // ignore: deprecated_member_use
          ..translate(0.0, _cardSlideY.value),
        child: GovElevatedCard(
          padding: EdgeInsets.all(20.w),
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
                          colors: [AppTheme.primaryBlueLight, AppTheme.primaryBlueDark],
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
                      border: Border.all(color: AppTheme.accentRed.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppTheme.accentRed, size: 16),
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
                _buildTextField(
                  controller: _userCtrl,
                  icon: Icons.person_outline_rounded,
                  label: 'Login  |  लॉगिन',
                  hint: 'Centre username',
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Login is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 14.h),
                _buildTextField(
                  controller: _passCtrl,
                  icon: Icons.lock_outline_rounded,
                  label: 'Password  |  पासवर्ड',
                  hint: '••••••••',
                  isPassword: true,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 24.h),
                _buildLoginButton(),
                SizedBox(height: 14.h),
                _buildSecurityInfoRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    bool isPassword = false,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !_passwordVisible,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: TextStyle(
        color: AppTheme.textDark,
        fontSize: 14.sp,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 19.sp, color: AppTheme.textGray),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppTheme.textGray,
                  size: 19.sp,
                ),
                onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.accentRed, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
        labelStyle: TextStyle(fontSize: 12.5.sp, color: AppTheme.textGray),
        hintStyle: TextStyle(fontSize: 13.sp, color: AppTheme.textLightGray),
      ),
      validator: validator,
    );
  }

  Widget _buildLoginButton() {
    return AnimatedBuilder(
      animation: _buttonPulseController,
      builder: (_, child) {
        return GestureDetector(
          onTapDown: (_) => setState(() => _buttonPressed = true),
          onTapUp: (_) {
            setState(() => _buttonPressed = false);
            if (!_busy) _submit();
          },
          onTapCancel: () => setState(() => _buttonPressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: double.infinity,
            height: 52.h,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              // ignore: deprecated_member_use
              ..translate(0.0, _buttonPressed ? 3.0 : 0.0)
              // ignore: deprecated_member_use
              ..scale(_buttonPressed ? 0.97 : (_busy ? 1.0 : _buttonPulse.value)),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: _buttonPressed || _busy
                  ? const LinearGradient(
                      colors: [AppTheme.primaryBlueDark, AppTheme.primaryBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [AppTheme.primaryBlueLight, AppTheme.primaryBlueDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: _buttonPressed
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.45),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: AppTheme.primaryBlueDark.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        child: _busy
            ? Center(
                child: SizedBox(
                  width: 24.w,
                  height: 24.w,
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login_rounded, color: Colors.white, size: 20.sp),
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
    );
  }

  Widget _buildSecurityInfoRow() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10.w,
      runSpacing: 8.h,
      children: [
        _securityChip(Icons.lock_rounded, 'Encrypted', AppTheme.primaryGreen),
        _securityChip(Icons.shield_rounded, 'Govt Portal', AppTheme.primaryBlue),
        _securityChip(Icons.verified_user_rounded, 'Secure', AppTheme.accentSaffron),
      ],
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
