import 'package:flutter/material.dart';

/// The classic BPM Counter green on pure black.
abstract final class BpmColors {
  static const green = Color(0xFF5CB85C);
  static const greenBright = Color(0xFF7CDB7C);
  static const background = Colors.black;
  static const surface = Color(0xFF0D110D);
  static const surfaceHigh = Color(0xFF162016);
  static const outline = Color(0xFF2A3A2A);
  static const textMuted = Color(0xFF9DB09D);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: BpmColors.green, brightness: Brightness.dark)
      .copyWith(
        primary: BpmColors.green,
        onPrimary: Colors.black,
        secondary: BpmColors.greenBright,
        surface: BpmColors.background,
        onSurface: Colors.white,
        onSurfaceVariant: BpmColors.textMuted,
        surfaceContainerLowest: BpmColors.background,
        surfaceContainerLow: BpmColors.surface,
        surfaceContainer: BpmColors.surface,
        surfaceContainerHigh: BpmColors.surfaceHigh,
        surfaceContainerHighest: BpmColors.surfaceHigh,
        outline: BpmColors.outline,
        outlineVariant: BpmColors.outline,
      );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: BpmColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: BpmColors.background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: BpmColors.surface,
      indicatorColor: BpmColors.green.withValues(alpha: 0.25),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelMedium),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: BpmColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    cardTheme: const CardThemeData(
      color: BpmColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: BpmColors.outline),
      ),
    ),
    sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.onDrag),
  );
}

/// Numbers that don't wobble while they change.
const tabularFigures = [FontFeature.tabularFigures()];
