import 'package:flutter/material.dart';

abstract final class ProvidentiaColors {
  static const Color canvas = Color(0xFFFBF8EC);
  static const Color surface = Color(0xFFFFFDF7);
  static const Color surfaceStrong = Color(0xFFFFFFFF);
  static const Color forest = Color(0xFF14551F);
  static const Color fresh = Color(0xFF2F8A2A);
  static const Color greenDark = Color(0xFF246F22);
  static const Color mint = Color(0xFFE8F3DD);
  static const Color text = Color(0xFF102714);
  static const Color muted = Color(0xFF726E62);
  static const Color line = Color(0xFFE8E1CE);
  static const Color warning = Color(0xFFE76F00);
  static const Color warningSurface = Color(0xFFFFF7E6);
  static const Color focus = Color(0xFF0B63CE);
}

abstract final class ProvidentiaTheme {
  static ThemeData light({bool highContrast = false}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: ProvidentiaColors.fresh,
      brightness: Brightness.light,
      primary: highContrast
          ? ProvidentiaColors.forest
          : ProvidentiaColors.fresh,
      onPrimary: Colors.white,
      surface: ProvidentiaColors.surface,
      onSurface: ProvidentiaColors.text,
      error: const Color(0xFFB3261E),
    );
    final outlineWidth = highContrast ? 2.0 : 1.0;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ProvidentiaColors.canvas,
      focusColor: ProvidentiaColors.focus,
      fontFamily: 'sans-serif',
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: ProvidentiaColors.forest,
          fontSize: 36,
          height: 1.08,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: TextStyle(
          color: ProvidentiaColors.forest,
          fontSize: 28,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        titleLarge: TextStyle(
          color: ProvidentiaColors.forest,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: ProvidentiaColors.text,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(
          color: ProvidentiaColors.text,
          fontSize: 16,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          color: ProvidentiaColors.muted,
          fontSize: 14,
          height: 1.4,
        ),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: ProvidentiaColors.surfaceStrong,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x1F173D2A),
        elevation: highContrast ? 0 : 5,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: highContrast
                ? ProvidentiaColors.forest
                : ProvidentiaColors.line,
            width: outlineWidth,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: ProvidentiaColors.surfaceStrong,
        indicatorColor: ProvidentiaColors.mint,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? ProvidentiaColors.forest
                : ProvidentiaColors.muted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          );
        }),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: ProvidentiaColors.surfaceStrong,
        indicatorColor: ProvidentiaColors.mint,
        selectedIconTheme: IconThemeData(color: ProvidentiaColors.forest),
        selectedLabelTextStyle: TextStyle(
          color: ProvidentiaColors.forest,
          fontWeight: FontWeight.w800,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          overlayColor: const WidgetStatePropertyAll(Color(0x1AFFFFFF)),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: ProvidentiaColors.focus, width: 3);
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          foregroundColor: const WidgetStatePropertyAll(
            ProvidentiaColors.forest,
          ),
          side: WidgetStateProperty.resolveWith((states) {
            return BorderSide(
              color: states.contains(WidgetState.focused)
                  ? ProvidentiaColors.focus
                  : ProvidentiaColors.fresh,
              width: states.contains(WidgetState.focused) ? 3 : outlineWidth,
            );
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      dividerColor: ProvidentiaColors.line,
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: ProvidentiaColors.forest,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: TextStyle(color: Colors.white),
      ),
    );
  }
}
