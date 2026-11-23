import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../data/models/book.dart';
import '../design/palette.dart';
import '../design/tokens.dart';

/// Couverture de livre avec relief (dos, reflet, ombre portée).
///
/// Les images sont décodées à la taille d'affichage ([cacheWidth]) pour
/// garder une empreinte mémoire faible dans les grandes bibliothèques.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    required this.width,
    this.heroTag,
    this.showProgress = false,
    this.elevation = 1,
  });

  final Book book;
  final double width;
  final Object? heroTag;
  final bool showProgress;

  /// 0 = plat, 1 = normal, 2 = mis en avant.
  final double elevation;

  static const aspect = 1.5;

  @override
  Widget build(BuildContext context) {
    final height = width * aspect;
    final palette = LireoPalette.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    Widget face = book.coverPath != null
        ? Image.file(
            File(book.coverPath!),
            width: width,
            height: height,
            fit: BoxFit.cover,
            // Arrondi à 64 px : grille, étagères et fiche partagent la même image décodée.
            cacheWidth: ((width * dpr) / 64).ceil() * 64,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, sync) {
              if (sync) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: Motion.scaled(context, Motion.medium),
                curve: Motion.curve,
                child: child,
              );
            },
            errorBuilder: (_, _, _) => GeneratedCover(book: book, width: width),
          )
        : GeneratedCover(book: book, width: width);

    face = Stack(
      fit: StackFit.expand,
      children: [
        face,
        // Dos du livre : ombre + reflet pour l'effet de profondeur.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              stops: [0, 0.035, 0.06, 0.1, 1],
              colors: [Color(0x55000000), Color(0x22FFFFFF), Color(0x00FFFFFF), Color(0x18000000), Color(0x00000000)],
            ),
          ),
        ),
        if (showProgress && book.progress > 0)
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: book.progress,
                minHeight: 3,
                backgroundColor: Colors.black.withValues(alpha: 0.35),
                color: palette.accent,
              ),
            ),
          ),
      ],
    );

    final shadowAlpha = palette.isDark ? 0.6 : 0.28;
    Widget cover = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: Radii.cover,
        boxShadow: elevation == 0
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: shadowAlpha * 0.6),
                  blurRadius: 3 * elevation,
                  offset: Offset(1, 1.5 * elevation),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: shadowAlpha * 0.5),
                  blurRadius: 14 * elevation,
                  offset: Offset(3 * elevation, 8 * elevation),
                ),
              ],
      ),
      child: ClipRRect(borderRadius: Radii.cover, child: face),
    );

    if (heroTag != null) cover = Hero(tag: heroTag!, child: cover);
    return Semantics(label: 'Couverture de ${book.title}', image: true, child: cover);
  }
}

/// Couverture typographique générée pour les fichiers qui n'en ont pas.
/// La teinte « toile reliée » est dérivée du titre : stable d'un lancement à l'autre.
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({super.key, required this.book, required this.width});

  final Book book;
  final double width;

  static const _cloths = [
    (Color(0xFF6B2D2D), Color(0xFFE9C987)), // bordeaux / or
    (Color(0xFF233A52), Color(0xFFE2C68C)), // marine
    (Color(0xFF2F4A3A), Color(0xFFE5CF95)), // forêt
    (Color(0xFF8A5A2B), Color(0xFFF6E3B8)), // cognac
    (Color(0xFF3D3A4F), Color(0xFFD9C08A)), // ardoise
    (Color(0xFF5A2F4A), Color(0xFFEACB98)), // prune
    (Color(0xFFE8DCC4), Color(0xFF5A3B22)), // lin clair
    (Color(0xFF1F1F1F), Color(0xFFD8B26A)), // noir
  ];

  @override
  Widget build(BuildContext context) {
    final seed = book.title.codeUnits.fold(7, (a, c) => (a * 31 + c) & 0x7fffffff);
    final (bg, ink) = _cloths[seed % _cloths.length];
    final small = width < 90;
    return Container(
      color: bg,
      padding: EdgeInsets.fromLTRB(width * 0.14, width * 0.16, width * 0.1, width * 0.12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: ink.withValues(alpha: 0.55), width: small ? 0.6 : 1),
        ),
        child: Padding(
          padding: EdgeInsets.all(width * 0.06),
          child: Column(
            children: [
              Container(height: 1, width: width * 0.2, color: ink.withValues(alpha: 0.7)),
              SizedBox(height: width * 0.08),
              Expanded(
                child: Center(
                  child: Text(
                    book.title,
                    textAlign: TextAlign.center,
                    maxLines: small ? 4 : 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: Fonts.display,
                      fontWeight: FontWeight.w600,
                      fontSize: (width * 0.13).clamp(8, 26),
                      height: 1.12,
                      color: ink,
                    ),
                  ),
                ),
              ),
              if (book.author.isNotEmpty && !small)
                Text(
                  book.author.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Fonts.ui,
                    fontSize: (width * 0.065).clamp(6, 12),
                    letterSpacing: 1.1,
                    color: ink.withValues(alpha: 0.85),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
