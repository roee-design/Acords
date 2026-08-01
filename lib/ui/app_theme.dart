import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/feedback_result.dart';

/// Shared dark palette — deep slate base with turquoise + amber accents.
abstract final class AppColors {
  static const background = Color(0xFF0B1220);
  static const surface = Color(0xFF162032);
  static const surfaceElevated = Color(0xFF1E2D45);
  static const turquoise = Color(0xFF2DD4BF);
  static const turquoiseDim = Color(0xFF14B8A6);
  static const amber = Color(0xFFF59E0B);
  static const amberBright = Color(0xFFFBBF24);
  static const textPrimary = Color(0xFFF1F5F9);
  static const textMuted = Color(0xFF94A3B8);
  static const success = Color(0xFF34D399);
  static const error = Color(0xFFF87171);
  static const onPrimaryDark = Color(0xFF042F2E);
}

abstract final class AppTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.turquoise,
          secondary: AppColors.amber,
          surface: AppColors.surface,
          onPrimary: AppColors.onPrimaryDark,
          onSecondary: Color(0xFF451A03),
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textMuted,
          error: AppColors.error,
          outlineVariant: Color(0xFF334155),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: true,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surfaceElevated,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.turquoise,
            foregroundColor: AppColors.onPrimaryDark,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceElevated,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        dropdownMenuTheme: DropdownMenuThemeData(
          menuStyle: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(AppColors.surfaceElevated),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.turquoise
                : AppColors.textMuted,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.turquoise.withValues(alpha: 0.35)
                : AppColors.surfaceElevated,
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.turquoise,
        ),
        dividerColor: AppColors.textMuted.withValues(alpha: 0.25),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.turquoise.withValues(alpha: 0.18),
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: 0.5),
          height: 68,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.turquoise : AppColors.textMuted,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? AppColors.turquoise : AppColors.textMuted,
              size: 24,
            );
          }),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
          titleMedium: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: TextStyle(color: AppColors.textMuted),
        ).apply(
          bodyColor: AppColors.textMuted,
          displayColor: AppColors.textPrimary,
        ),
        visualDensity: VisualDensity.standard,
      );

  /// Decorative gradient used on hero headers.
  static LinearGradient get heroGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF132035),
          AppColors.background,
        ],
      );

  static BoxDecoration cardDecoration({Color? borderColor}) => BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor ?? AppColors.turquoise.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      );

  /// Status colors for chord feedback banners and string rows.
  static ({Color background, Color border, Color text}) feedbackColors(
    ChordMatchStatus status,
  ) {
    return switch (status) {
      ChordMatchStatus.perfect => (
          background: AppColors.success.withValues(alpha: 0.12),
          border: AppColors.success,
          text: AppColors.success,
        ),
      ChordMatchStatus.close => (
          background: AppColors.amber.withValues(alpha: 0.12),
          border: AppColors.amber,
          text: AppColors.amberBright,
        ),
      ChordMatchStatus.notDetected => (
          background: AppColors.error.withValues(alpha: 0.12),
          border: AppColors.error,
          text: AppColors.error,
        ),
      ChordMatchStatus.waiting => (
          background: AppColors.surfaceElevated,
          border: AppColors.textMuted.withValues(alpha: 0.35),
          text: AppColors.textMuted,
        ),
    };
  }
}
