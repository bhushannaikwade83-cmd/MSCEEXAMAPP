import 'package:flutter/material.dart';

import '../services/post_login_navigator.dart';
import '../services/session_service.dart';
import 'screens/web_center_login_screen.dart';
import 'screens/web_home_screen.dart';
import 'screens/web_login_screen.dart';

/// ✅ WEB PLATFORM BOOTSTRAP
///
/// Lives in its own file (behind a conditional import in `main.dart`) so the
/// web-only screens — which use `dart:html` — are never compiled into
/// Android/iOS builds.
class WebBootstrap extends StatefulWidget {
  const WebBootstrap({super.key});

  @override
  State<WebBootstrap> createState() => _WebBootstrapState();
}

class _WebBootstrapState extends State<WebBootstrap> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final center = await SessionService.getCenter();
    final pin = await SessionService.getPin();
    final sessionValid = await SessionService.isSessionValid();
    if (!mounted) return;

    // ✅ Web routing logic (same as Android):
    // 1. PIN + session valid → go to WebHomeScreen
    // 2. PIN + session expired → go to WebLoginScreen (PIN re-entry)
    // 3. Centre but no PIN → go to PIN setup
    // 4. No centre → go to Centre login

    // ✅ PIN exists and session is still valid
    if (pin != null && pin.isNotEmpty && sessionValid) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => WebHomeScreen()),
        );
      }
      return;
    }

    // ✅ PIN exists but session expired → go to PIN login (re-entry)
    if (pin != null && pin.isNotEmpty) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => WebLoginScreen()),
        );
      }
      return;
    }

    // ✅ No PIN - if centre exists, continue setup (PIN setup)
    if (center != null) {
      if (mounted) {
        await PostLoginNavigator.continueSetup(context, centerId: center['id']!);
      }
      return;
    }

    // ✅ No centre and no PIN - go to centre login (first time)
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WebCenterLoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
