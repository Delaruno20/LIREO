import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'palette.dart';
import 'tokens.dart';

/// Construit un [ThemeData] Material 3 cohérent à partir d'une [LireoPalette].
ThemeData buildTheme(LireoPalette p) {
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.accent,
    onSecondary: p.onPrimary,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: p.surface,
    onSurface: p.text,
    surfaceContainerHighest: p.surfaceAlt,
    onSurfaceVariant: p.textMuted,
    outline: p.divider,
    outlineVariant: p.divider,
  );

  TextStyle ui(double size, FontWeight w, {Color? c, double? h, double? ls}) => TextStyle(
        fontFamily: Fonts.ui,
        fontSize: size,
        fontWeight: w,
        color: c ?? p.text,
        height: h,
        letterSpacing: ls,
      );
  TextStyle display(double size, FontWeight w) => TextStyle(
        fontFamily: Fonts.display,
        fontSize: size,
        fontWeight: w,
        color: p.text,
        height: 1.15,
      );

  final textTheme = TextTheme(
    displayLarge: display(40, FontWeight.w600),
    displayMedium: display(32, FontWeight.w600),
    displaySmall: display(28, FontWeight.w600),
    headlineLarge: display(26, FontWeight.w600),
    headlineMedium: display(23, FontWeight.w600),
    headlineSmall: display(20, FontWeight.w600),
    titleLarge: ui(19, FontWeight.w600, ls: -0.2),
    titleMedium: ui(16, FontWeight.w600),
    titleSmall: ui(14, FontWeight.w600),
    bodyLarge: ui(16, FontWeight.w400, h: 1.45),
    bodyMedium: ui(14, FontWeight.w400, h: 1.45),
    bodySmall: ui(12.5, FontWeight.w400, c: p.textMuted, h: 1.35),
    labelLarge: ui(14, FontWeight.w600),
    labelMedium: ui(12.5, FontWeight.w500),
    labelSmall: ui(11, FontWeight.w500, c: p.textMuted, ls: 0.2),
  );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.md));

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    fontFamily: Fonts.ui,
    textTheme: textTheme,
    dividerColor: p.divider,
    splashFactory: InkSparkle.splashFactory,
    extensions: [p],
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      systemOverlayStyle: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: shape,
    ),
    dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: p.textMuted,
      textColor: p.text,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      minVerticalPadding: 10,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        minimumSize: const Size(48, 52),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: p.divider),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.primary),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: p.text, minimumSize: const Size(44, 44)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceAlt.withValues(alpha: p.isDark ? 0.8 : 0.7),
      hintStyle: textTheme.bodyMedium?.copyWith(color: p.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radii.md), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radii.md), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radii.md),
        borderSide: BorderSide(color: p.primary, width: 1.4),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surfaceAlt,
      selectedColor: p.primary,
      labelStyle: textTheme.labelMedium,
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: p.onPrimary),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBackgroundColor: p.surface,
      showDragHandle: true,
      dragHandleColor: p.divider,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radii.lg)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.lg)),
      titleTextStyle: textTheme.headlineSmall,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.isDark ? p.surfaceAlt : p.text,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: p.isDark ? p.text : p.background),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.md)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.primary,
      inactiveTrackColor: p.divider,
      thumbColor: p.primary,
      overlayColor: p.primary.withValues(alpha: 0.12),
      trackHeight: 3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.onPrimary : p.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.primary : p.surfaceAlt,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: p.primary,
        selectedForegroundColor: p.onPrimary,
        side: BorderSide(color: p.divider),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.primary,
      linearTrackColor: p.divider,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
