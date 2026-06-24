import 'package:flutter/material.dart';

import '../services/pin_service.dart';
import '../services/session_service.dart';
import '../screens/center_login_screen.dart';
import '../screens/home_screen.dart';
import '../screens/pin_setup_screen.dart';

/// Routes centre staff after password login or on cold start.
class PostLoginNavigator {
  static Future<void> continueSetup(BuildContext context, {String? centerId}) async {
    final id = centerId ?? (await SessionService.getCenter())?['id'];
    if (id == null || id.isEmpty) {
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const CenterLoginScreen()),
        (_) => false,
      );
      return;
    }

    final hasPin = await PinService.hasPinForCenter(id);
    if (!context.mounted) return;

    if (!hasPin) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => PinSetupScreen(centerId: id, fromLogin: true),
        ),
        (_) => false,
      );
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }
}
