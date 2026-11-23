import 'package:material_ui/material_ui.dart';

import 'palette.dart';

/// Thèmes événementiels : appliqués automatiquement pendant la période de
/// l'événement (si l'option est activée), ou forcés depuis l'écran Thèmes.
enum SeasonalEvent {
  newYear(
    label: 'Bonne Année',
    title: 'Bonne Année',
    message: 'Que cette nouvelle année soit remplie de belles histoires',
    period: '31 déc. – 15 janv.',
    emoji: '✨',
  ),
  cameroonYouth(
    label: 'Fête de la Jeunesse',
    title: 'Cameroon Youth Day',
    message: 'Célébrons la jeunesse, l\'unité et le potentiel du Cameroun !',
    period: '4 – 14 févr.',
    emoji: '⭐',
  ),
  easter(
    label: 'Pâques',
    title: 'Joyeuses Pâques !',
    message: 'Que cette fête soit remplie de lecture et de bonheur',
    period: 'Semaine sainte – lundi de Pâques',
    emoji: '🌸',
  ),
  fetMusique(
    label: 'Fête de la Musique',
    title: 'Fête de la Musique',
    message: 'La musique, une histoire à partager…',
    period: '14 – 22 juin',
    emoji: '🎵',
  ),
  christmas(
    label: 'Noël',
    title: 'Joyeux Noël',
    message: 'Que la magie des livres éclaire vos fêtes',
    period: '1er – 30 déc.',
    emoji: '❄️',
  );

  const SeasonalEvent({
    required this.label,
    required this.title,
    required this.message,
    required this.period,
    required this.emoji,
  });

  /// Nom court (galerie de thèmes).
  final String label;

  /// Titre de la bannière d'accueil.
  final String title;
  final String message;

  /// Période d'activation, lisible.
  final String period;
  final String emoji;

  /// Événement en cours à la date [now], ou `null` hors période.
  static SeasonalEvent? activeOn(DateTime now) {
    final d = DateTime(now.year, now.month, now.day);
    final sunday = easterSunday(d.year);
    // Dimanche des Rameaux → lundi de Pâques.
    if (!d.isBefore(sunday.subtract(const Duration(days: 7))) &&
        !d.isAfter(sunday.add(const Duration(days: 1)))) {
      return SeasonalEvent.easter;
    }
    return switch ((d.month, d.day)) {
      (12, 31) || (1, <= 15) => SeasonalEvent.newYear,
      (12, _) => SeasonalEvent.christmas,
      (2, >= 4 && <= 14) => SeasonalEvent.cameroonYouth,
      (6, >= 14 && <= 22) => SeasonalEvent.fetMusique,
      _ => null,
    };
  }

  /// Dimanche de Pâques (calendrier grégorien, algorithme de Meeus/Jones/Butcher).
  static DateTime easterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = (h + l - 7 * m + 114) % 31 + 1;
    return DateTime(year, month, day);
  }

  LireoPalette get palette => switch (this) {
        newYear => _newYear,
        cameroonYouth => _cameroonYouth,
        easter => _easter,
        fetMusique => _fetMusique,
        christmas => _christmas,
      };

  /// Dégradé de fond de la bannière d'accueil.
  List<Color> get bannerGradient => switch (this) {
        newYear => const [Color(0xFF2A1F0E), Color(0xFF0B0906)],
        cameroonYouth => const [Color(0xFF1F7A3A), Color(0xFFE88A1A)],
        easter => const [Color(0xFFF6E3F0), Color(0xFFFFF4D8)],
        fetMusique => const [Color(0xFF4A2468), Color(0xFFE5743A)],
        christmas => const [Color(0xFF3A0E14), Color(0xFF0F2A1C)],
      };

  /// Couleur du titre de la bannière (lisible sur [bannerGradient]).
  Color get bannerTitle => switch (this) {
        newYear => const Color(0xFFF3D38A),
        cameroonYouth => const Color(0xFFFCD116),
        easter => const Color(0xFF8E3FA8),
        fetMusique => const Color(0xFFFFD08A),
        christmas => const Color(0xFFF0C87A),
      };

  Color get bannerText => this == easter ? const Color(0xFF4A3B52) : const Color(0xFFFFF8EC);

  static const _newYear = LireoPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0B0906),
    surface: Color(0xFF18140D),
    surfaceAlt: Color(0xFF261F13),
    primary: Color(0xFFE2B55C),
    onPrimary: Color(0xFF1A1206),
    accent: Color(0xFFF3D38A),
    text: Color(0xFFF6EEDC),
    textMuted: Color(0xFFAA9A7C),
    divider: Color(0xFF2E2617),
    shelfTop: Color(0xFF8A6A32),
    shelfFront: Color(0xFF4A391C),
    shadow: Color(0xCC000000),
  );

  static const _christmas = LireoPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0E1913),
    surface: Color(0xFF16241C),
    surfaceAlt: Color(0xFF1F3127),
    primary: Color(0xFFD02A38),
    onPrimary: Color(0xFFFFF7F0),
    accent: Color(0xFFE3B65E),
    text: Color(0xFFF4EEE3),
    textMuted: Color(0xFFA7B3A5),
    divider: Color(0xFF26382D),
    shelfTop: Color(0xFF8A5530),
    shelfFront: Color(0xFF5A341C),
    shadow: Color(0xCC000000),
  );

  static const _easter = LireoPalette(
    brightness: Brightness.light,
    background: Color(0xFFFBF5EA),
    surface: Color(0xFFFFFCF6),
    surfaceAlt: Color(0xFFF2E8DA),
    primary: Color(0xFF8A55BE),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFE9B03E),
    text: Color(0xFF2D2433),
    textMuted: Color(0xFF786C7E),
    divider: Color(0xFFEADFCF),
    shelfTop: Color(0xFFC99A64),
    shelfFront: Color(0xFF9B6E40),
    shadow: Color(0x332D2433),
  );

  static const _fetMusique = LireoPalette(
    brightness: Brightness.dark,
    background: Color(0xFF1B1227),
    surface: Color(0xFF261A36),
    surfaceAlt: Color(0xFF33244A),
    primary: Color(0xFFF28B30),
    onPrimary: Color(0xFF1E1206),
    accent: Color(0xFFE06AAE),
    text: Color(0xFFF7EEF4),
    textMuted: Color(0xFFB4A5C2),
    divider: Color(0xFF3A2B50),
    shelfTop: Color(0xFF9A5E34),
    shelfFront: Color(0xFF603A20),
    shadow: Color(0xCC000000),
  );

  static const _cameroonYouth = LireoPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0D3720),
    surface: Color(0xFF14462A),
    surfaceAlt: Color(0xFF1B5534),
    primary: Color(0xFFF28C1E),
    onPrimary: Color(0xFF1C1206),
    accent: Color(0xFFFCD116),
    text: Color(0xFFF8F4E4),
    textMuted: Color(0xFFB6CCB4),
    divider: Color(0xFF225F3B),
    shelfTop: Color(0xFFC9822E),
    shelfFront: Color(0xFF8F5A1C),
    shadow: Color(0xCC000000),
  );
}
