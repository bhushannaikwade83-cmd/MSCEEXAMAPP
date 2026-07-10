import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'config/apply_network_overrides_stub.dart'
    if (dart.library.io) 'config/apply_network_overrides_io.dart';
import 'config/b2b_storage_config.dart';
import 'core/supabase_client.dart';
import 'core/theme/app_ui.dart';
import 'core/utils/responsive.dart';
import 'screens/center_login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/pin_login_screen.dart';
import 'services/device_performance_service.dart';
import 'services/face_recognition_service.dart';
import 'services/pin_service.dart';
import 'services/post_login_navigator.dart';
import 'services/session_service.dart';
import 'web/screens/web_login_screen.dart';
import 'web/screens/web_home_screen.dart';
import 'web/screens/web_center_login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  applySupabaseNetworkOverrides();

  try {
    await dotenv.load(fileName: 'app_config.env');
    if (kDebugMode) debugPrint('✅ Loaded app_config.env');
    B2BStorageConfig.logConfigSummary();
  } catch (e) {
    if (kDebugMode) debugPrint('⚠️ app_config.env not found: $e');
  }
  await initSupabase();
  await DevicePerformanceService.initialize();
  await FaceRecognitionService.initialize();
  runApp(const MsceExamApp());
}

class MsceExamApp extends StatelessWidget {
  const MsceExamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) {
        return MaterialApp(
          title: 'MSCE Exam Centre',
          theme: AppTheme.lightTheme,
          home: child,
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: Responsive.appTextScaler(context),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
      child: kIsWeb ? const _BootstrapWeb() : const _Bootstrap(),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
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

    // ✅ Logic:
    // 1. PIN + session valid → go to HomeScreen (already logged in today)
    // 2. PIN + session expired → go to PIN login (re-authenticate)
    // 3. Centre but no PIN → go to continueSetup (PIN setup)
    // 4. No centre → go to centre login (first time)

    // ✅ PIN exists and session is still valid today
    if (pin != null && pin.isNotEmpty && sessionValid) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
      return;
    }

    // ✅ PIN exists but session expired → go to PIN login
    if (pin != null && pin.isNotEmpty) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PinLoginScreen()),
        );
      }
      return;
    }

    // ✅ No PIN - if centre exists, continue setup (show PIN setup)
    if (center != null) {
      // Don't await, let it handle routing
      if (mounted) {
        await PostLoginNavigator.continueSetup(context, centerId: center['id']!);
      }
      return;
    }

    // ✅ No centre and no PIN - go to centre login (first time)
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CenterLoginScreen()),
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

// ✅ WEB PLATFORM BOOTSTRAP
class _BootstrapWeb extends StatefulWidget {
  const _BootstrapWeb();

  @override
  State<_BootstrapWeb> createState() => _BootstrapWebState();
}

class _BootstrapWebState extends State<_BootstrapWeb> {
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
