import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../core/theme/app_ui.dart';
import '../services/pin_service.dart';
import '../services/session_service.dart';
import '../services/post_login_navigator.dart';
import 'home_screen.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({
    super.key,
    required this.centerId,
    this.fromLogin = false,
  });

  final String centerId;
  final bool fromLogin;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();

  String _step = 'enter';
  String? _enteredPin;
  bool _showPin = false;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _pinController.addListener(() => setState(() {}));
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onPinInput(String value) {
    if (value.length > 4) {
      final ctrl = _step == 'enter' ? _pinController : _confirmController;
      ctrl.text = value.substring(0, 4);
      return;
    }
    setState(() => _error = '');
    if (value.length == 4) {
      if (_step == 'enter') {
        _proceedToConfirm();
      } else {
        _validateAndSave();
      }
    }
  }

  void _proceedToConfirm() {
    final pin = _pinController.text.trim();
    if (!PinService.isValidLength(pin)) {
      setState(() => _error = 'PIN must be 4 digits');
      return;
    }
    if (PinService.isWeakPin(pin)) {
      setState(() => _error = 'Choose a stronger PIN (avoid 1234, 1111, etc.)');
      return;
    }
    setState(() {
      _enteredPin = pin;
      _step = 'confirm';
      _confirmController.clear();
      _error = '';
    });
  }

  Future<void> _validateAndSave() async {
    final confirm = _confirmController.text.trim();
    if (!PinService.isValidLength(confirm)) {
      setState(() => _error = 'PIN must be 4 digits');
      return;
    }
    if (_enteredPin != confirm) {
      setState(() {
        _error = 'PINs do not match. Try again.';
        _confirmController.clear();
      });
      return;
    }
    await _savePin(_enteredPin!);
  }

  Future<void> _savePin(String pin) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // ✅ Save to PinService (center-specific)
      await PinService.savePin(centerId: widget.centerId, pin: pin);

      // ✅ Also save to SessionService (device-local for quick login)
      await SessionService.savePin(pin);

      // ✅ Save session date (marks login for today)
      await SessionService.saveSessionDate();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('4-Digit PIN set successfully'),
            ],
          ),
          backgroundColor: AppTheme.accentGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      // ✅ Go directly to HomeScreen (bypass continueSetup which would redirect to PIN login)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Failed to save PIN: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundGrey,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const GovPortalHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(24.w),
                  child: GovElevatedCard(
                    padding: EdgeInsets.all(20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8.r),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.pin_rounded, color: AppTheme.primaryBlue, size: 22.sp),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Text(
                                _step == 'enter'
                                    ? 'Create 4-Digit PIN  |  पिन तयार करा'
                                    : 'Confirm PIN  |  पिन पुष्टी करा',
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          _step == 'enter'
                              ? 'You will use this PIN for quick access on this device.'
                              : 'Re-enter your PIN to confirm.',
                          style: TextStyle(fontSize: 12.sp, color: AppTheme.textGray),
                        ),
                        SizedBox(height: 20.h),
                        Container(
                          padding: EdgeInsets.all(14.w),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: AppTheme.primaryBlue, size: 20),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                  _step == 'enter'
                                      ? 'Choose any 4 digits. Avoid obvious patterns like 1234 or 1111.'
                                      : 'Both entries must match exactly.',
                                  style: TextStyle(fontSize: 12.sp, color: AppTheme.primaryBlue),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 28.h),
                        TextField(
                          controller: _step == 'enter' ? _pinController : _confirmController,
                          obscureText: !_showPin,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: _onPinInput,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32.sp,
                            letterSpacing: 8,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryBlue,
                          ),
                          decoration: InputDecoration(
                            labelText: _step == 'enter' ? 'Enter PIN' : 'Confirm PIN',
                            prefixIcon: const Icon(Icons.lock, color: AppTheme.primaryBlue),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPin ? Icons.visibility_off : Icons.visibility,
                                color: AppTheme.primaryBlue,
                              ),
                              onPressed: () => setState(() => _showPin = !_showPin),
                            ),
                            counterText: '',
                            helperText: 'Digits only (4 required)',
                          ),
                        ),
                        if (_error.isNotEmpty) ...[
                          SizedBox(height: 12.h),
                          Container(
                            padding: EdgeInsets.all(12.w),
                            decoration: BoxDecoration(
                              color: AppTheme.accentRed.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.accentRed.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: AppTheme.accentRed, size: 18),
                                SizedBox(width: 8.w),
                                Expanded(
                                  child: Text(
                                    _error,
                                    style: TextStyle(color: AppTheme.accentRed, fontSize: 12.sp),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        SizedBox(height: 28.h),
                        if (_step == 'enter')
                          SizedBox(
                            height: 52.h,
                            child: ElevatedButton(
                              onPressed: _pinController.text.length == 4 ? _proceedToConfirm : null,
                              child: const Text('Next'),
                            ),
                          )
                        else ...[
                          SizedBox(
                            height: 52.h,
                            child: ElevatedButton(
                              onPressed: _saving || _confirmController.text.length != 4
                                  ? null
                                  : _validateAndSave,
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGreen),
                              child: _saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Save PIN'),
                            ),
                          ),
                          SizedBox(height: 10.h),
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _step = 'enter';
                                _pinController.clear();
                                _confirmController.clear();
                                _enteredPin = null;
                                _error = '';
                              });
                            },
                            child: const Text('Change PIN'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
