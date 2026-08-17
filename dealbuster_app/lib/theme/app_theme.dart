import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// DealBuster design system — one accent, disciplined neutrals, generous space.
///
/// Palette story: deep plum-black keeps a thread back to the brand's old violet
/// heritage as a *neutral*, not a primary; coral is the single accent carrying
/// all "deal energy" (CTAs, badges, active states) so the eye never has to
/// guess what's tappable.
class AppColors {
  AppColors._();

  static const ink = Color(0xFF14121F);
  static const ink700 = Color(0xFF4B4757);
  static const ink400 = Color(0xFF8B879B);
  static const bg = Color(0xFFF7F5FA);
  static const surface = Color(0xFFFFFFFF);
  static const hairline = Color(0xFFEDEAF3);

  static const brand = Color(0xFFFF5A3C);
  static const brandDark = Color(0xFFE8431F);
  static const brandSoft = Color(0xFFFFE7E0);

  static const success = Color(0xFF1FAA6D);
  static const successSoft = Color(0xFFE3F6ED);
  static const gold = Color(0xFFFFB020);

  static const heroStart = Color(0xFF2B1055);
  static const heroEnd = Color(0xFFB2311C);
}

class AppRadius {
  AppRadius._();
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 26.0;
  static const pill = 999.0;
}

class AppSpace {
  AppSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 28.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);

    final display = GoogleFonts.sora(
      color: AppColors.ink,
      fontWeight: FontWeight.w800,
    );
    final body = GoogleFonts.inter(color: AppColors.ink);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.brand,
        onPrimary: Colors.white,
        secondary: AppColors.gold,
        surface: AppColors.surface,
        error: AppColors.brandDark,
      ),
      splashFactory: InkRipple.splashFactory,
      textTheme: TextTheme(
        displayLarge: display.copyWith(fontSize: 32, height: 1.08),
        displaySmall: display.copyWith(fontSize: 26, height: 1.1),
        headlineMedium: display.copyWith(fontSize: 20, height: 1.15),
        titleLarge: display.copyWith(fontSize: 17, height: 1.2),
        titleMedium: GoogleFonts.sora(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          height: 1.25,
        ),
        bodyLarge: body.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
        bodyMedium: body.copyWith(
          fontSize: 13,
          color: AppColors.ink700,
          height: 1.35,
        ),
        bodySmall: body.copyWith(fontSize: 12, color: AppColors.ink400),
        labelLarge: body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
        labelSmall: body.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.ink),
      dividerColor: AppColors.hairline,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          textStyle: GoogleFonts.sora(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

/// Shared soft drop shadow used across cards so elevation reads consistently.
List<BoxShadow> cardShadow({double opacity = 1}) => [
      BoxShadow(
        color: AppColors.ink.withValues(alpha: 0.06 * opacity),
        blurRadius: 24,
        offset: const Offset(0, 8),
        spreadRadius: -6,
      ),
    ];
