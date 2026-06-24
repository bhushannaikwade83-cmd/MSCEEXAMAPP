import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppUI {
  static const String portalPrimaryLine =
      'MSCE Exam Centre App  |  एमएससीई परीक्षा केंद्र अॅप';
  static const String portalSecondaryLineDefault =
      'MSCE Exam Centre Attendance System';
  static const String officialBadgeLabel = 'OFFICIAL';
  static const String footerOfficialUse = 'OFFICIAL USE ONLY';
  static const String footerCredit =
      'Powered by MSCE - Maharashtra State Council of Education';
  static const String loginAppTitle = 'Exam Centre Login';
  static const String loginSubtitle =
      'Secure attendance verification for exam centres';

  static const String appLogoAsset = 'assets/msce_attendance_app_logo.png';
  static const double appLogoAspectRatio = 1.0;

  static Widget dualBrandLogos({required double mainHeight, double partnerScale = 0.55}) {
    return Image.asset(appLogoAsset, height: mainHeight, fit: BoxFit.contain);
  }

  static const double govCardBorderRadius = 14;
  static const double govCardInnerClipRadius = 13;
  static const double govCardAccentStripWidth = 4;
  static const double tricolorStripHeight = 5;
  static const double officialBadgeCornerRadius = 6;

  static const Color tricolorSaffronStart = Color(0xFFFF6600);
  static const Color tricolorSaffronEnd = Color(0xFFFF9933);
  static const Color tricolorGreenStart = Color(0xFF006600);
  static const Color tricolorGreenEnd = Color(0xFF138808);
  static const Color officialBadgeColor = Color(0xFFE8871A);
  static const Color headerShadowColor = Color(0x44000000);
}

class AppTheme {
  static const Color primaryBlue = Color(0xFF1A3C6E);
  static const Color primaryBlueDark = Color(0xFF0F2547);
  static const Color primaryBlueLight = Color(0xFF2B5BA0);
  static const Color accentSaffron = Color(0xFFE8871A);
  static const Color primaryGreen = Color(0xFF1B5E20);
  static const Color accentGreen = Color(0xFF388E3C);
  static const Color accentRed = Color(0xFFB71C1C);
  static const Color backgroundGrey = Color(0xFFEEF2F7);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF1A1A2E);
  static const Color textGray = Color(0xFF5A6475);
  static const Color textLightGray = Color(0xFF9EA8B8);
  static const Color dividerColor = Color(0xFFDDE3EE);

  static ThemeData get lightTheme {
    return ThemeData.light(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentSaffron,
        surface: cardWhite,
        error: accentRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textDark,
      ),
      scaffoldBackgroundColor: backgroundGrey,
      textTheme: GoogleFonts.notoSansTextTheme(
        ThemeData.light(useMaterial3: true).textTheme,
      ),
      appBarTheme: AppBarTheme(
        elevation: 2,
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.notoSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.notoSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: dividerColor, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: dividerColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryBlue, width: 2.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: GoogleFonts.notoSans(fontSize: 13, color: textGray),
        hintStyle: GoogleFonts.notoSans(fontSize: 13, color: textLightGray),
        prefixIconColor: textGray,
      ),
    );
  }
}

class GovTricolorStrip extends StatelessWidget {
  const GovTricolorStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: AppUI.tricolorStripHeight,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppUI.tricolorSaffronStart, AppUI.tricolorSaffronEnd],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: AppUI.tricolorStripHeight,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
        Expanded(
          child: Container(
            height: AppUI.tricolorStripHeight,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppUI.tricolorGreenStart, AppUI.tricolorGreenEnd],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class GovPortalHeader extends StatelessWidget {
  const GovPortalHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.primaryBlueDark,
        boxShadow: [
          BoxShadow(
            color: AppUI.headerShadowColor,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GovTricolorStrip(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              child: Row(
                children: [
                  Container(
                    width: 44.r,
                    height: 44.r,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.92),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    padding: EdgeInsets.all(3.r),
                    child: Image.asset(AppUI.appLogoAsset, fit: BoxFit.contain),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppUI.portalPrimaryLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          AppUI.portalSecondaryLineDefault,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 9.5.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: AppUI.officialBadgeColor,
                      borderRadius: BorderRadius.circular(AppUI.officialBadgeCornerRadius),
                    ),
                    child: Text(
                      AppUI.officialBadgeLabel,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GovElevatedCard extends StatelessWidget {
  const GovElevatedCard({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppUI.govCardBorderRadius),
        border: Border.all(color: AppTheme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppUI.govCardInnerClipRadius),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: AppTheme.primaryBlue,
                width: AppUI.govCardAccentStripWidth,
              ),
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class GovPortalFooter extends StatelessWidget {
  const GovPortalFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: AppTheme.dividerColor)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              child: Text(
                AppUI.footerOfficialUse,
                style: TextStyle(
                  fontSize: 10.sp,
                  color: AppTheme.textLightGray,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const Expanded(child: Divider(color: AppTheme.dividerColor)),
          ],
        ),
        SizedBox(height: 10.h),
        Text(
          AppUI.footerCredit,
          style: TextStyle(
            fontSize: 11.sp,
            color: AppTheme.textLightGray,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8.h),
        const GovTricolorStrip(),
      ],
    );
  }
}
