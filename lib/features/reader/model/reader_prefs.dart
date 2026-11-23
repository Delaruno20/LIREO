import 'dart:convert';

import 'package:material_ui/material_ui.dart';

enum PageAnimation {
  curl('Page curl'),
  slide('Glissement'),
  fade('Fondu'),
  scroll('Défilement'),
  none('Aucune');

  const PageAnimation(this.label);
  final String label;
}

enum DoublePageMode {
  auto('Auto'),
  always('Toujours'),
  never('Jamais');

  const DoublePageMode(this.label);
  final String label;
}

/// Action déclenchée par un geste ou une zone de l'écran du lecteur.
enum ReaderAction {
  previousPage('Page précédente'),
  nextPage('Page suivante'),
  toggleControls('Afficher les commandes'),
  bookmark('Marque-page'),
  none('Aucune');

  const ReaderAction(this.label);
  final String label;
}

/// Fond de lecture : indépendant du thème de l'application.
class ReadingSurface {
  const ReadingSurface(this.id, this.label, this.background, this.text);
  final String id;
  final String label;
  final Color background;
  final Color text;

  static const all = [
    ReadingSurface('paper', 'Papier', Color(0xFFFBF7EE), Color(0xFF26221C)),
    ReadingSurface('cream', 'Crème', Color(0xFFF4EAD7), Color(0xFF3A2C1E)),
    ReadingSurface('sepia', 'Sépia', Color(0xFFEBD9B9), Color(0xFF4A3420)),
    ReadingSurface('sage', 'Sauge', Color(0xFFE3EADB), Color(0xFF233021)),
    ReadingSurface('grey', 'Gris', Color(0xFF3B3B3D), Color(0xFFDCDAD5)),
    ReadingSurface('night', 'Nuit', Color(0xFF1A1816), Color(0xFFCFC6B8)),
    ReadingSurface('oled', 'OLED', Color(0xFF000000), Color(0xFFB9B2A6)),
  ];

  static ReadingSurface byId(String id) => all.firstWhere((s) => s.id == id, orElse: () => all.first);
}

/// Réglages typographiques et de navigation du lecteur.
///
/// Immuable et sérialisable : un profil global, des profils nommés, et une
/// surcharge facultative par livre (stockée dans `books.reader_prefs`).
@immutable
class ReaderPrefs {
  const ReaderPrefs({
    this.fontFamily = 'Literata',
    this.fontSize = 19,
    this.lineHeight = 1.55,
    this.letterSpacing = 0,
    this.paragraphSpacing = 0.6,
    this.marginH = 26,
    this.marginV = 36,
    this.indent = 1.4,
    this.justify = true,
    this.bold = false,
    this.surfaceId = 'paper',
    this.customText,
    this.customBackground,
    this.animation = PageAnimation.curl,
    this.animationSpeed = 1.0,
    this.curlShadow = 0.6,
    this.doublePage = DoublePageMode.auto,
    this.leftTap = ReaderAction.previousPage,
    this.rightTap = ReaderAction.nextPage,
    this.centerTap = ReaderAction.toggleControls,
    this.doubleTap = ReaderAction.bookmark,
    this.volumeKeys = true,
    this.brightnessSwipe = true,
    this.keepScreenOn = true,
    this.autoScrollSpeed = 40,
    this.showProgressFooter = true,
  });

  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final double letterSpacing;

  /// En multiples de la taille de police.
  final double paragraphSpacing;
  final double marginH;
  final double marginV;

  /// Alinéa en em (0 = aucun).
  final double indent;
  final bool justify;
  final bool bold;
  final String surfaceId;
  final int? customText;
  final int? customBackground;
  final PageAnimation animation;
  final double animationSpeed;
  final double curlShadow;
  final DoublePageMode doublePage;
  final ReaderAction leftTap;
  final ReaderAction rightTap;
  final ReaderAction centerTap;
  final ReaderAction doubleTap;
  final bool volumeKeys;
  final bool brightnessSwipe;
  final bool keepScreenOn;

  /// Pixels par seconde pour le défilement automatique.
  final double autoScrollSpeed;
  final bool showProgressFooter;

  ReadingSurface get surface => ReadingSurface.byId(surfaceId);
  Color get background => customBackground != null ? Color(customBackground!) : surface.background;
  Color get textColor => customText != null ? Color(customText!) : surface.text;
  bool get isDarkSurface => background.computeLuminance() < 0.25;

  /// Paramètres qui changent la pagination (les autres sont purement visuels).
  Object get layoutKey => Object.hash(fontFamily, fontSize, lineHeight, letterSpacing, paragraphSpacing, marginH,
      marginV, indent, justify, bold);

  TextStyle baseStyle() => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: lineHeight,
        letterSpacing: letterSpacing,
        color: textColor,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      );

  ReaderPrefs copyWith({
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    double? paragraphSpacing,
    double? marginH,
    double? marginV,
    double? indent,
    bool? justify,
    bool? bold,
    String? surfaceId,
    int? customText,
    int? customBackground,
    bool clearCustomColors = false,
    PageAnimation? animation,
    double? animationSpeed,
    double? curlShadow,
    DoublePageMode? doublePage,
    ReaderAction? leftTap,
    ReaderAction? rightTap,
    ReaderAction? centerTap,
    ReaderAction? doubleTap,
    bool? volumeKeys,
    bool? brightnessSwipe,
    bool? keepScreenOn,
    double? autoScrollSpeed,
    bool? showProgressFooter,
  }) =>
      ReaderPrefs(
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
        marginH: marginH ?? this.marginH,
        marginV: marginV ?? this.marginV,
        indent: indent ?? this.indent,
        justify: justify ?? this.justify,
        bold: bold ?? this.bold,
        surfaceId: surfaceId ?? this.surfaceId,
        customText: clearCustomColors ? null : (customText ?? this.customText),
        customBackground: clearCustomColors ? null : (customBackground ?? this.customBackground),
        animation: animation ?? this.animation,
        animationSpeed: animationSpeed ?? this.animationSpeed,
        curlShadow: curlShadow ?? this.curlShadow,
        doublePage: doublePage ?? this.doublePage,
        leftTap: leftTap ?? this.leftTap,
        rightTap: rightTap ?? this.rightTap,
        centerTap: centerTap ?? this.centerTap,
        doubleTap: doubleTap ?? this.doubleTap,
        volumeKeys: volumeKeys ?? this.volumeKeys,
        brightnessSwipe: brightnessSwipe ?? this.brightnessSwipe,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        autoScrollSpeed: autoScrollSpeed ?? this.autoScrollSpeed,
        showProgressFooter: showProgressFooter ?? this.showProgressFooter,
      );

  Map<String, Object?> toJson() => {
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'letterSpacing': letterSpacing,
        'paragraphSpacing': paragraphSpacing,
        'marginH': marginH,
        'marginV': marginV,
        'indent': indent,
        'justify': justify,
        'bold': bold,
        'surfaceId': surfaceId,
        'customText': customText,
        'customBackground': customBackground,
        'animation': animation.name,
        'animationSpeed': animationSpeed,
        'curlShadow': curlShadow,
        'doublePage': doublePage.name,
        'leftTap': leftTap.name,
        'rightTap': rightTap.name,
        'centerTap': centerTap.name,
        'doubleTap': doubleTap.name,
        'volumeKeys': volumeKeys,
        'brightnessSwipe': brightnessSwipe,
        'keepScreenOn': keepScreenOn,
        'autoScrollSpeed': autoScrollSpeed,
        'showProgressFooter': showProgressFooter,
      };

  String encode() => jsonEncode(toJson());

  static ReaderPrefs decode(String? raw, {ReaderPrefs fallback = const ReaderPrefs()}) {
    if (raw == null || raw.isEmpty) return fallback;
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>, fallback: fallback);
    } catch (_) {
      return fallback;
    }
  }

  static ReaderPrefs fromJson(Map<String, dynamic> j, {ReaderPrefs fallback = const ReaderPrefs()}) {
    double d(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    bool b(String k, bool f) => j[k] as bool? ?? f;
    T e<T extends Enum>(List<T> values, String k, T f) =>
        values.firstWhere((v) => v.name == j[k], orElse: () => f);
    return ReaderPrefs(
      fontFamily: j['fontFamily'] as String? ?? fallback.fontFamily,
      fontSize: d('fontSize', fallback.fontSize),
      lineHeight: d('lineHeight', fallback.lineHeight),
      letterSpacing: d('letterSpacing', fallback.letterSpacing),
      paragraphSpacing: d('paragraphSpacing', fallback.paragraphSpacing),
      marginH: d('marginH', fallback.marginH),
      marginV: d('marginV', fallback.marginV),
      indent: d('indent', fallback.indent),
      justify: b('justify', fallback.justify),
      bold: b('bold', fallback.bold),
      surfaceId: j['surfaceId'] as String? ?? fallback.surfaceId,
      customText: (j['customText'] as num?)?.toInt(),
      customBackground: (j['customBackground'] as num?)?.toInt(),
      animation: e(PageAnimation.values, 'animation', fallback.animation),
      animationSpeed: d('animationSpeed', fallback.animationSpeed),
      curlShadow: d('curlShadow', fallback.curlShadow),
      doublePage: e(DoublePageMode.values, 'doublePage', fallback.doublePage),
      leftTap: e(ReaderAction.values, 'leftTap', fallback.leftTap),
      rightTap: e(ReaderAction.values, 'rightTap', fallback.rightTap),
      centerTap: e(ReaderAction.values, 'centerTap', fallback.centerTap),
      doubleTap: e(ReaderAction.values, 'doubleTap', fallback.doubleTap),
      volumeKeys: b('volumeKeys', fallback.volumeKeys),
      brightnessSwipe: b('brightnessSwipe', fallback.brightnessSwipe),
      keepScreenOn: b('keepScreenOn', fallback.keepScreenOn),
      autoScrollSpeed: d('autoScrollSpeed', fallback.autoScrollSpeed),
      showProgressFooter: b('showProgressFooter', fallback.showProgressFooter),
    );
  }

  @override
  bool operator ==(Object other) => other is ReaderPrefs && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

/// Profil de lecture nommé, exportable/importable en JSON.
class ReadingProfile {
  const ReadingProfile({required this.name, required this.prefs, this.format});
  final String name;
  final ReaderPrefs prefs;

  /// Si défini, appliqué automatiquement aux livres de ce format.
  final String? format;

  Map<String, Object?> toJson() => {'name': name, 'format': format, 'prefs': prefs.toJson()};

  static ReadingProfile fromJson(Map<String, dynamic> j) => ReadingProfile(
        name: j['name'] as String,
        format: j['format'] as String?,
        prefs: ReaderPrefs.fromJson(j['prefs'] as Map<String, dynamic>),
      );
}
