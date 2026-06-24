import 'package:flutter/material.dart';

/// Responsive utility class for handling different screen sizes.
class Responsive {
  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;

  static double height(BuildContext context) => MediaQuery.sizeOf(context).height;

  static double vw(BuildContext context, double percent) {
    final p = percent.clamp(0.0, 100.0);
    return width(context) * (p / 100.0);
  }

  static double vh(BuildContext context, double percent) {
    final p = percent.clamp(0.0, 100.0);
    return height(context) * (p / 100.0);
  }

  static bool isMobile(BuildContext context) => width(context) < 600;

  static bool isTablet(BuildContext context) => width(context) >= 600 && width(context) < 1200;

  static bool isDesktop(BuildContext context) => width(context) >= 1200;

  static EdgeInsets padding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final horizontal = (w * 0.05).clamp(16.0, 40.0);
    final vertical = isDesktop(context)
        ? 20.0
        : isTablet(context)
            ? 16.0
            : 12.0;
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  }

  static double contentMaxWidth(BuildContext context, {double mobile = 560, double tablet = 720}) {
    final w = MediaQuery.sizeOf(context).width;
    if (isDesktop(context)) return tablet;
    if (isTablet(context)) return tablet.clamp(0.0, w);
    return mobile.clamp(0.0, w);
  }

  static TextScaler appTextScaler(BuildContext context) {
    final current = MediaQuery.textScalerOf(context);
    return current.clamp(minScaleFactor: 0.95, maxScaleFactor: 1.15);
  }
}

extension ResponsiveViewport on BuildContext {
  double contentMaxWidth({double mobile = 560, double tablet = 720}) =>
      Responsive.contentMaxWidth(this, mobile: mobile, tablet: tablet);
}
