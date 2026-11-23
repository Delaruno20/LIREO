import 'package:material_ui/material_ui.dart';

/// Identifiants stables des thèmes (persistés dans les préférences).
enum ThemePreset {
  warmLibrary('Warm Library'),
  oledMidnight('OLED Midnight'),
  paper('Paper'),
  neutralGrey('Gris neutre'),
  sage('Vert sauge'),
  sepia('Sépia'),
  custom('Personnalisé');

  const ThemePreset(this.label);
  final String label;
}

/// Palette sémantique de LIREO, exposée via [ThemeExtension].
///
/// Tous les écrans lisent leurs couleurs ici : aucune couleur codée en dur
/// dans les widgets, pour que chaque thème reste cohérent.
@immutable
class LireoPalette extends ThemeExtension<LireoPalette> {
  const LireoPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.text,
    required this.textMuted,
    required this.divider,
    required this.shelfTop,
    required this.shelfFront,
    required this.shadow,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color text;
  final Color textMuted;
  final Color divider;
  final Color shelfTop;
  final Color shelfFront;
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  /// Couleur de verre dépoli pour les barres flottantes.
  Color get glass => surface.withValues(alpha: isDark ? 0.72 : 0.78);

  static const warmLibrary = LireoPalette(
    brightness: Brightness.light,
    background: Color(0xFFF6EFE4),
    surface: Color(0xFFFCF8F1),
    surfaceAlt: Color(0xFFEFE4D3),
    primary: Color(0xFFA0683A),
    onPrimary: Color(0xFFFFF9F0),
    accent: Color(0xFFD4A65A),
    text: Color(0xFF2E1F14),
    textMuted: Color(0xFF7D6A58),
    divider: Color(0xFFE4D6C2),
    shelfTop: Color(0xFFC79A6B),
    shelfFront: Color(0xFF9C6E45),
    shadow: Color(0x402E1F14),
  );

  static const oledMidnight = LireoPalette(
    brightness: Brightness.dark,
    background: Color(0xFF080808),
    surface: Color(0xFF161514),
    surfaceAlt: Color(0xFF221F1C),
    primary: Color(0xFFD9A55B),
    onPrimary: Color(0xFF1A1208),
    accent: Color(0xFFE8BE78),
    text: Color(0xFFF2ECE2),
    textMuted: Color(0xFF9C948A),
    divider: Color(0xFF242322),
    shelfTop: Color(0xFF2B2826),
    shelfFront: Color(0xFF1B1918),
    shadow: Color(0xCC000000),
  );

  static const paper = LireoPalette(
    brightness: Brightness.light,
    background: Color(0xFFFBF8F1),
    surface: Color(0xFFFFFDF8),
    surfaceAlt: Color(0xFFF1ECE0),
    primary: Color(0xFF8A6A45),
    onPrimary: Color(0xFFFFFDF8),
    accent: Color(0xFFB08A5C),
    text: Color(0xFF1F1D1A),
    textMuted: Color(0xFF6E6A62),
    divider: Color(0xFFE7E1D3),
    shelfTop: Color(0xFFD9CDB6),
    shelfFront: Color(0xFFB8A684),
    shadow: Color(0x331F1D1A),
  );

  static const neutralGrey = LireoPalette(
    brightness: Brightness.light,
    background: Color(0xFFF2F2F1),
    surface: Color(0xFFFBFBFA),
    surfaceAlt: Color(0xFFE6E6E4),
    primary: Color(0xFF4E5257),
    onPrimary: Color(0xFFFBFBFA),
    accent: Color(0xFFB59A6A),
    text: Color(0xFF1C1D1F),
    textMuted: Color(0xFF6B6E73),
    divider: Color(0xFFDDDDDA),
    shelfTop: Color(0xFFBDBDB8),
    shelfFront: Color(0xFF8F8F8A),
    shadow: Color(0x331C1D1F),
  );

  static const sage = LireoPalette(
    brightness: Brightness.light,
    background: Color(0xFFEEF1E8),
    surface: Color(0xFFF8FAF4),
    surfaceAlt: Color(0xFFDFE6D4),
    primary: Color(0xFF5E7552),
    onPrimary: Color(0xFFF8FAF4),
    accent: Color(0xFFC2A15E),
    text: Color(0xFF1E261A),
    textMuted: Color(0xFF66725F),
    divider: Color(0xFFD5DDCB),
    shelfTop: Color(0xFFB7A684),
    shelfFront: Color(0xFF8B7A58),
    shadow: Color(0x331E261A),
  );

  static const sepia = LireoPalette(
    brightness: Brightness.light,
    background: Color(0xFFF1E4CC),
    surface: Color(0xFFF8EEDB),
    surfaceAlt: Color(0xFFE6D4B4),
    primary: Color(0xFF8B5E34),
    onPrimary: Color(0xFFF8EEDB),
    accent: Color(0xFFB98A48),
    text: Color(0xFF3B2A1A),
    textMuted: Color(0xFF7A6248),
    divider: Color(0xFFDCC7A3),
    shelfTop: Color(0xFFB98C5E),
    shelfFront: Color(0xFF8A6239),
    shadow: Color(0x403B2A1A),
  );

  /// Construit une palette personnalisée à partir de trois choix utilisateur.
  factory LireoPalette.custom({
    required Color accent,
    required Color background,
    required bool dark,
  }) {
    final text = dark ? const Color(0xFFF0EBE3) : const Color(0xFF231A12);
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    return LireoPalette(
      brightness: dark ? Brightness.dark : Brightness.light,
      background: background,
      surface: mix(background, dark ? Colors.white : Colors.white, dark ? 0.06 : 0.5),
      surfaceAlt: mix(background, dark ? Colors.white : Colors.black, dark ? 0.11 : 0.06),
      primary: accent,
      onPrimary: accent.computeLuminance() > 0.45 ? const Color(0xFF1A1208) : Colors.white,
      accent: mix(accent, Colors.white, 0.25),
      text: text,
      textMuted: mix(text, background, 0.42),
      divider: mix(background, text, 0.1),
      shelfTop: mix(background, accent, 0.45),
      shelfFront: mix(background, accent, 0.7),
      shadow: dark ? const Color(0xCC000000) : const Color(0x40000000),
    );
  }

  static LireoPalette of(BuildContext context) =>
      Theme.of(context).extension<LireoPalette>() ?? warmLibrary;

  static LireoPalette forPreset(ThemePreset preset) => switch (preset) {
        ThemePreset.warmLibrary => warmLibrary,
        ThemePreset.oledMidnight => oledMidnight,
        ThemePreset.paper => paper,
        ThemePreset.neutralGrey => neutralGrey,
        ThemePreset.sage => sage,
        ThemePreset.sepia => sepia,
        ThemePreset.custom => warmLibrary,
      };

  @override
  LireoPalette copyWith({Color? primary, Color? accent}) => LireoPalette(
        brightness: brightness,
        background: background,
        surface: surface,
        surfaceAlt: surfaceAlt,
        primary: primary ?? this.primary,
        onPrimary: onPrimary,
        accent: accent ?? this.accent,
        text: text,
        textMuted: textMuted,
        divider: divider,
        shelfTop: shelfTop,
        shelfFront: shelfFront,
        shadow: shadow,
      );

  @override
  LireoPalette lerp(ThemeExtension<LireoPalette>? other, double t) {
    if (other is! LireoPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return LireoPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      accent: l(accent, other.accent),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      divider: l(divider, other.divider),
      shelfTop: l(shelfTop, other.shelfTop),
      shelfFront: l(shelfFront, other.shelfFront),
      shadow: l(shadow, other.shadow),
    );
  }
}
