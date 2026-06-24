import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
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
import 'services/device_performance_service.dart';
import 'services/face_recognition_service.dart';
import 'services/post_login_navigator.dart';
import 'services/session_service.dart';

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
      child: const _Bootstrap(),
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
    if (!mounted) return;

    if (center == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CenterLoginScreen()),
      );
      return;
    }

    if (!mounted) return;
    await PostLoginNavigator.continueSetup(context, centerId: center['id']!);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
