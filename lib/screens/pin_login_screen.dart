import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../services/location_service.dart';
import '../services/pin_service.dart';
import '../services/session_service.dart';
import 'center_login_screen.dart';
import 'home_screen.dart';

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  final TextEditingController _pinController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = '';
  bool _showPin = false;
  String? _savedPin;
  String? _centreId;

  @override
  void initState() {
    super.initState();
    _loadSavedPin();
  }

  Future<void> _loadSavedPin() async {
    final pin = await SessionService.getPin();
    final centre = await SessionService.getCenter();
    print('🔐 DEBUG: Loaded PIN from SessionService: $pin');
    if (mounted) {
      setState(() {
        _savedPin = pin;
        _centreId = centre?['id'];
      });
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _onPinInput(String value) {
    // Only allow digits and max 4 characters
    if (value.length > 4) {
      _pinController.text = value.substring(0, 4);
      return;
    }

    setState(() {
      _errorMessage = '';
    });

    // Auto-verify if 4 digits entered (only if PIN is loaded)
    if (value.length == 4 && _savedPin != null) {
      _verifyPin();
    }
  }

  Future<void> _verifyPin() async {
    if (_isLoading || _pinController.text.length != 4) return;

    setState(() => _isLoading = true);

    final enteredPin = _pinController.text.trim();

    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    print('🔐 DEBUG: Verifying PIN - Entered: $enteredPin, Saved: $_savedPin, Match: ${enteredPin == _savedPin}');

    if (enteredPin == _savedPin) {
      print('✅ DEBUG: PIN match verified!');
      // ✅ Correct PIN - Save session date (expires after midnight)
      await SessionService.saveSessionDate();

      // Correct PIN - Save location in background silently
      final centre = await SessionService.getCenter();

      // Save location in background (no UI feedback)
      if (centre != null) {
        unawaited(
          () async {
            await LocationService.getCurrentLocation().then((location) {
              if (location != null) {
                LocationService.saveLoginLocation(
                  centreId: centre['id']!,
                  centreCode: centre['code'] ?? '',
                  latitude: location['latitude']!,
                  longitude: location['longitude']!,
                );
              }
            }).catchError((_) {
              // Silently ignore errors
            });
          }(),
        );
      }

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text("PIN Verified Successfully!"),
            ],
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        // ✅ Go to HomeScreen
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      }
    } else {
      // Wrong PIN
      setState(() {
        _errorMessage = 'Wrong PIN!';
        _pinController.clear();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 20.h),

              // Title
              Text(
                'Quick Login',
                style: TextStyle(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF212121),
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 12.h),

              // Subtitle
              Text(
                'Enter your 4-digit PIN',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: const Color(0xFF757575),
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 40.h),

              // Info Card
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  border: Border.all(color: Colors.blue, width: 2),
                  borderRadius: BorderRadius.circular(12.w),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue, size: 24),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        'Quick PIN entry for fast login on this device.',
                        style: TextStyle(
                          color: Colors.blue.withOpacity(0.8),
                          fontSize: 13.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 40.h),

              // PIN Input Field
              TextField(
                controller: _pinController,
                obscureText: !_showPin,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: _onPinInput,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  labelText: 'Enter PIN',
                  prefixIcon: const Icon(Icons.lock, color: Color(0xFF2196F3)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPin ? Icons.visibility : Icons.visibility_off,
                      color: const Color(0xFF2196F3),
                    ),
                    onPressed: () => setState(() => _showPin = !_showPin),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.w),
                    borderSide: const BorderSide(color: Color(0xFF2196F3), width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.w),
                    borderSide: const BorderSide(color: Color(0xFF2196F3), width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  counterText: '',
                  helperText: 'Digits only (4 required)',
                  helperStyle: const TextStyle(color: Color(0xFF757575)),
                ),
                style: TextStyle(fontSize: 32.sp, letterSpacing: 8),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 12.h),

              // Error Message
              if (_errorMessage.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935).withOpacity(0.1),
                    border: Border.all(color: const Color(0xFFE53935)),
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFE53935), size: 20),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: TextStyle(
                            color: const Color(0xFFE53935),
                            fontSize: 13.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              SizedBox(height: 40.h),

              // Loading Indicator
              if (_isLoading)
                Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF2196F3)),
                      SizedBox(height: 16.h),
                      Text(
                        'Verifying PIN...',
                        style: TextStyle(
                          color: const Color(0xFF757575),
                          fontSize: 14.sp,
                        ),
                      ),
                    ],
                  ),
                ),

              SizedBox(height: 24.h),

              // Footer - Change Centre button
              Container(
                padding: EdgeInsets.symmetric(vertical: 16.h),
                child: SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Change Centre & PIN?'),
                          content: const Text('You will need to enter username and password for a different centre.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () async {
                                // ✅ Close dialog first
                                Navigator.pop(ctx);

                                // ✅ Get centre before clearing (to clear center-specific PIN)
                                final centre = await SessionService.getCenter();
                                if (centre != null) {
                                  await PinService.clearPinForCenter(centre['id']!);
                                }

                                // ✅ Clear device-local PIN and session
                                await SessionService.clearPin();
                                await SessionService.clearSessionDate();
                                await SessionService.clear();

                                if (mounted) {
                                  // ✅ Go back to CenterLoginScreen
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const CenterLoginScreen(),
                                    ),
                                    (_) => false,
                                  );
                                }
                              },
                              child: const Text('Change Centre'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Change Centre'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                  ),
                ),
              ),

              // Security Info
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.w),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_outline, color: Colors.amber, size: 20),
                        SizedBox(width: 8.w),
                        Text(
                          'Security Tips',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                            fontSize: 13.sp,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      '• Use this PIN on secure devices only\n'
                      '• Don\'t share your PIN with others\n'
                      '• Change centre to reset PIN',
                      style: TextStyle(
                        color: Colors.amber.withOpacity(0.8),
                        fontSize: 12.sp,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
