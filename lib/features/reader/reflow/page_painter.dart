import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../../data/models/library_models.dart';
import '../model/reader_prefs.dart';
import 'page_layout.dart';

/// Informations contextuelles dessinées avec la page.
class PageDecor {
  const PageDecor({
    this.highlights = const [],
    this.bookmarked = false,
    this.footerLeft = '',
    this.footerRight = '',
    this.accent = const Color(0xFFC0392B),
  });

  /// Surlignages du chapitre (seuls ceux qui touchent la page sont dessinés).
  final List<Annotation> highlights;
  final bool bookmarked;
  final String footerLeft;
  final String footerRight;
  final Color accent;
}

/// Plage temporaire surlignée par-dessus la page (sélection, TTS, recherche).
class OverlayRange {
  const OverlayRange(this.start, this.end, this.color, {this.underline = false});
  final int start;
  final int end;
  final Color color;
  final bool underline;
}

abstract final class PagePainter {
  static const footerHeight = 26.0;

  /// Enregistre la page dans une [ui.Picture] réutilisable (animations, cache).
  static ui.Picture record(PageLayout page, Size size, ReaderPrefs prefs, PageDecor decor) {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder), page, size, prefs, decor);
    return recorder.endRecording();
  }

  static void paint(Canvas canvas, PageLayout page, Size size, ReaderPrefs prefs, PageDecor decor, {bool background = true}) {
    if (background) canvas.drawRect(Offset.zero & size, Paint()..color = prefs.background);

    // Surlignages persistants sous le texte.
    for (final h in decor.highlights) {
      if (h.start.chapter != page.chapter && h.end.chapter != page.chapter) continue;
      final from = h.start.chapter == page.chapter ? h.start.offset : 0;
      final to = h.end.chapter == page.chapter ? h.end.offset : page.end;
      if (to <= page.start || from >= page.end) continue;
      final color = Color(h.color).withValues(alpha: prefs.isDarkSurface ? 0.38 : 0.45);
      final paint = Paint()..color = color;
      for (final r in page.rectsFor(from, to)) {
        canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(1), const Radius.circular(3)), paint);
      }
      if (h.note.isNotEmpty) {
        final rects = page.rectsFor(from, to);
        if (rects.isNotEmpty) {
          final r = rects.last;
          canvas.drawCircle(Offset(r.right + 4, r.top + 2), 3, Paint()..color = Color(h.color));
        }
      }
    }

    for (final item in page.items) {
      switch (item) {
        case TextItem():
          canvas.save();
          canvas.clipRect(item.rect.inflate(2).copyWith(top: item.rect.top, bottom: item.rect.bottom));
          item.painter.paint(canvas, item.rect.topLeft - Offset(0, item.clipTop));
          canvas.restore();
        case ImageItem():
          final src = Rect.fromLTWH(0, 0, item.image.width.toDouble(), item.image.height.toDouble());
          canvas.drawImageRect(item.image, src, item.rect, Paint()..filterQuality = FilterQuality.medium);
        case RuleItem():
          _ornament(canvas, item.rect, prefs.textColor);
      }
    }

    if (decor.bookmarked) {
      final x = size.width - prefs.marginH * 0.5 - 14;
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + 16, 0)
        ..lineTo(x + 16, 30)
        ..lineTo(x + 8, 24)
        ..lineTo(x, 30)
        ..close();
      canvas.drawPath(path, Paint()..color = decor.accent);
    }

    if (prefs.showProgressFooter && (decor.footerLeft.isNotEmpty || decor.footerRight.isNotEmpty)) {
      final style = TextStyle(
        fontFamily: 'Inter',
        fontSize: 11,
        color: prefs.textColor.withValues(alpha: 0.5),
        letterSpacing: 0.2,
      );
      final y = size.height - prefs.marginV * 0.5 - footerHeight / 2;
      final right = TextPainter(text: TextSpan(text: decor.footerRight, style: style), textDirection: TextDirection.ltr)..layout();
      final left = TextPainter(
        text: TextSpan(text: decor.footerLeft, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: (size.width - prefs.marginH * 2 - right.width - 16).clamp(0, double.infinity));
      left.paint(canvas, Offset(prefs.marginH, y - left.height / 2));
      right.paint(canvas, Offset(size.width - prefs.marginH - right.width, y - right.height / 2));
      left.dispose();
      right.dispose();
    }
  }

  static void paintOverlay(Canvas canvas, PageLayout page, List<OverlayRange> ranges) {
    for (final r in ranges) {
      final paint = Paint()..color = r.color;
      for (final rect in page.rectsFor(r.start, r.end)) {
        if (r.underline) {
          canvas.drawRect(Rect.fromLTWH(rect.left, rect.bottom - 2, rect.width, 2), paint);
        } else {
          canvas.drawRect(rect, paint);
        }
      }
    }
  }

  static void _ornament(Canvas canvas, Rect r, Color color) {
    final c = r.center;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx - 42, c.dy), Offset(c.dx - 9, c.dy), paint);
    canvas.drawLine(Offset(c.dx + 9, c.dy), Offset(c.dx + 42, c.dy), paint);
    final diamond = Path()
      ..moveTo(c.dx, c.dy - 4)
      ..lineTo(c.dx + 4, c.dy)
      ..lineTo(c.dx, c.dy + 4)
      ..lineTo(c.dx - 4, c.dy)
      ..close();
    canvas.drawPath(diamond, paint);
  }
}

extension on Rect {
  Rect copyWith({double? top, double? bottom}) => Rect.fromLTRB(left, top ?? this.top, right, bottom ?? this.bottom);
}
