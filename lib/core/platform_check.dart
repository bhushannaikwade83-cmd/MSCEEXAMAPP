import 'package:flutter/foundation.dart';

/// Platform detection utilities
/// Use these to conditionally load native-only features

bool get isWeb => kIsWeb;
bool get isMobile => !kIsWeb;
bool get isNative => !kIsWeb;

String get platformName {
  if (kIsWeb) return 'Web';
  return 'Mobile/Native';
}
