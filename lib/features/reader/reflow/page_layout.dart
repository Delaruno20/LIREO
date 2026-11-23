import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../../formats/document/flow_document.dart';
import '../model/reader_prefs.dart';

/// Élément positionné sur une page.
sealed class PageItem {
  PageItem(this.rect);

  /// Zone occupée, en coordonnées de page.
  final Rect rect;
}

/// Portion visible d'un paragraphe.
///
/// Le paragraphe est mis en page une seule fois dans [painter] ; chaque page
/// n'en affiche qu'une tranche de lignes ([clipTop]..[clipBottom]). Ainsi la
/// justification et les coupures de lignes restent identiques d'une page à
/// l'autre, sans recalcul.
class TextItem extends PageItem {
  TextItem({
    required Rect rect,
    required this.painter,
    required this.clipTop,
    required this.block,
    required this.prefix,
    required this.start,
    required this.end,
  }) : super(rect);

  final TextPainter painter;
  final double clipTop;
  final TextBlock block;

  /// Caractères ajoutés en tête pour l'alinéa (absents du texte du chapitre).
  final int prefix;

  /// Plage visible, en offsets de chapitre.
  final int start;
  final int end;

  double get clipBottom => clipTop + rect.height;

  int toLocal(int chapterOffset) => (chapterOffset - block.start + prefix).clamp(0, painter.plainText.length);
  int toChapter(int local) => block.start + math.max(0, local - prefix).clamp(0, block.length);

  /// Point de page → offset de chapitre.
  int offsetAt(Offset pagePoint) {
    final local = pagePoint - rect.topLeft + Offset(0, clipTop);
    return toChapter(painter.getPositionForOffset(local).offset);
  }

  /// Rectangles (coordonnées de page) couvrant une plage de chapitre.
  List<Rect> rectsFor(int from, int to) {
    final s = math.max(from, start), e = math.min(to, end);
    if (s >= e) return const [];
    final boxes = painter.getBoxesForSelection(TextSelection(baseOffset: toLocal(s), extentOffset: toLocal(e)));
    final shift = rect.topLeft - Offset(0, clipTop);
    return [
      for (final b in boxes)
        if (b.bottom > clipTop + 0.5 && b.top < clipBottom - 0.5) b.toRect().shift(shift),
    ];
  }
}

class ImageItem extends PageItem {
  ImageItem(super.rect, this.image, this.offset);
  final ui.Image image;
  final int offset;
}

class RuleItem extends PageItem {
  RuleItem(super.rect, this.offset);
  final int offset;
}

class PageLayout {
  PageLayout({required this.chapter, required this.index, required this.items, required this.start, required this.end, required this.usedHeight});

  final int chapter;
  final int index;
  final List<PageItem> items;

  /// Plage du chapitre couverte par la page [start, end).
  final int start;
  final int end;
  final double usedHeight;

  bool contains(int offset) => offset >= start && offset < end;

  int? offsetAt(Offset p) {
    for (final item in items) {
      if (item is TextItem && item.rect.inflate(4).contains(p)) return item.offsetAt(p);
    }
    // Point dans une marge : élément le plus proche verticalement.
    TextItem? best;
    var bestDist = double.infinity;
    for (final item in items.whereType<TextItem>()) {
      final d = (item.rect.center.dy - p.dy).abs();
      if (d < bestDist) {
        bestDist = d;
        best = item;
      }
    }
    if (best == null) return null;
    final clamped = Offset(p.dx.clamp(best.rect.left, best.rect.right), p.dy.clamp(best.rect.top + 1, best.rect.bottom - 1));
    return best.offsetAt(clamped);
  }

  /// Lien éventuel sous le point (href).
  String? linkAt(Offset p) {
    for (final item in items) {
      if (item is TextItem && item.rect.contains(p)) {
        final offset = item.offsetAt(p);
        var pos = item.block.start;
        for (final run in item.block.runs) {
          if (offset >= pos && offset < pos + run.text.length) return run.href;
          pos += run.text.length;
        }
      }
    }
    return null;
  }

  List<Rect> rectsFor(int from, int to) => [
        for (final item in items)
          if (item is TextItem) ...item.rectsFor(from, to),
      ];
}

class ChapterLayout {
  ChapterLayout(this.chapter, this.pages, this._images, this._painters);

  final FlowChapter chapter;
  final List<PageLayout> pages;
  final List<ui.Image> _images;
  final List<TextPainter> _painters;

  int pageFor(int offset) {
    for (var i = pages.length - 1; i >= 0; i--) {
      if (pages[i].start <= offset) return i;
    }
    return 0;
  }

  void dispose() {
    for (final i in _images) {
      i.dispose();
    }
    for (final p in _painters) {
      p.dispose();
    }
  }
}

/// Paramètres de mise en page d'un chapitre.
class LayoutSpec {
  const LayoutSpec({required this.pageSize, required this.prefs, required this.textScaler, this.footerHeight = 0, this.continuous = false});

  final Size pageSize;
  final ReaderPrefs prefs;
  final TextScaler textScaler;
  final double footerHeight;

  /// Mode défilement : pas de marges verticales entre les segments.
  final bool continuous;

  double get contentWidth => math.max(120, pageSize.width - prefs.marginH * 2);
  double get contentHeight =>
      math.max(160, pageSize.height - (continuous ? 0 : prefs.marginV * 2 + footerHeight));

  @override
  bool operator ==(Object other) =>
      other is LayoutSpec &&
      other.pageSize == pageSize &&
      other.prefs.layoutKey == prefs.layoutKey &&
      other.prefs.textColor == prefs.textColor &&
      other.textScaler == textScaler &&
      other.continuous == continuous &&
      other.footerHeight == footerHeight;

  @override
  int get hashCode => Object.hash(pageSize, prefs.layoutKey, prefs.textColor, textScaler, continuous, footerHeight);
}

/// Découpe un chapitre en pages.
class Paginator {
  Paginator(this.spec, {this.linkColor});

  final LayoutSpec spec;
  final Color? linkColor;
  final _painters = <TextPainter>[];

  ReaderPrefs get prefs => spec.prefs;

  static const _headingScale = [1.75, 1.45, 1.25, 1.12, 1.05, 1.0];

  Future<ChapterLayout> layout(FlowChapter chapter, Future<ui.Image?> Function(String key, int maxWidth) loadImage) async {
    // Images décodées à la taille d'affichage.
    // Une même source (ornement répété) n'est décodée qu'une fois.
    final images = <int, ui.Image>{};
    final bySource = <String, ui.Image?>{};
    for (var i = 0; i < chapter.blocks.length; i++) {
      final b = chapter.blocks[i];
      if (b is ImageBlock) {
        final img = bySource.containsKey(b.source)
            ? bySource[b.source]
            : bySource[b.source] = await loadImage(b.source, (spec.contentWidth * 2).round());
        if (img != null) images[i] = img;
      }
    }
    _painters.clear();
    final pages = await _paginate(chapter, images);
    return ChapterLayout(chapter, pages, bySource.values.whereType<ui.Image>().toList(), List.of(_painters));
  }

  /// Budget de calcul par image : au-delà, la pagination rend la main au
  /// moteur pour qu'un chapitre géant ne fige pas l'interface.
  static const _sliceBudget = Duration(milliseconds: 6);

  Future<List<PageLayout>> _paginate(FlowChapter chapter, Map<int, ui.Image> images) async {
    final slice = Stopwatch()..start();
    final width = spec.contentWidth;
    final height = spec.contentHeight;
    final left = prefs.marginH;
    final top = spec.continuous ? 0.0 : prefs.marginV;
    final fs = prefs.fontSize;

    final pages = <PageLayout>[];
    var items = <PageItem>[];
    var y = 0.0;
    var pageStart = 0;
    var lastEnd = 0;

    void newPage(int nextStart) {
      pages.add(PageLayout(
        chapter: chapter.index,
        index: pages.length,
        items: items,
        start: pageStart,
        end: math.max(nextStart, pageStart + 1),
        usedHeight: y,
      ));
      items = [];
      y = 0;
      pageStart = nextStart;
    }

    FlowBlock? previous;
    for (var bi = 0; bi < chapter.blocks.length; bi++) {
      if (slice.elapsed > _sliceBudget) {
        await Future<void>.delayed(Duration.zero);
        slice.reset();
      }
      final block = chapter.blocks[bi];
      switch (block) {
        case TextBlock():
          final (gapBefore, gapAfter) = _gaps(block, previous);
          if (y > 0) y += gapBefore;
          final inset = _leftInset(block);
          final (painter, prefix) = _painter(block, previous, width - inset);
          final lines = painter.computeLineMetrics();
          var li = 0;
          while (li < lines.length) {
            if (y >= height - 1 && items.isNotEmpty) newPage(_lineStart(painter, lines[li], block, prefix));
            final lineTop = lines[li].baseline - lines[li].ascent;
            var fit = 0;
            while (li + fit < lines.length) {
              final l = lines[li + fit];
              if (l.baseline + l.descent - lineTop > height - y + 0.5) break;
              fit++;
            }
            if (fit == 0) {
              if (items.isEmpty) {
                fit = 1; // ligne plus haute que la page : affichée quand même
              } else {
                newPage(_lineStart(painter, lines[li], block, prefix));
                continue;
              }
            }
            final last = lines[li + fit - 1];
            final clipBottom = last.baseline + last.descent;
            final start = _lineStart(painter, lines[li], block, prefix);
            final end = li + fit < lines.length ? _lineStart(painter, lines[li + fit], block, prefix) : block.start + block.length;
            items.add(TextItem(
              rect: Rect.fromLTWH(left + inset, top + y, painter.width, clipBottom - lineTop),
              painter: painter,
              clipTop: lineTop,
              block: block,
              prefix: prefix,
              start: start,
              end: end,
            ));
            y += clipBottom - lineTop;
            lastEnd = end;
            li += fit;
            if (li < lines.length) newPage(_lineStart(painter, lines[li], block, prefix));
          }
          y += gapAfter;
        case ImageBlock():
          final img = images[bi];
          if (img == null) break;
          final maxH = height * 0.94;
          // Petites images (lettrines, ornements) : pas d'agrandissement excessif.
          final scale = math.min(math.min(width / img.width, maxH / img.height), 1.6);
          final w = img.width * scale, h = img.height * scale;
          if (y > 0 && y + h > height) newPage(block.start);
          if (y > 0) y += fs * 0.4;
          items.add(ImageItem(Rect.fromLTWH(left + (width - w) / 2, top + y, w, h), img, block.start));
          y += h + fs * 0.6;
          lastEnd = block.start + 1;
        case RuleBlock():
          final h = fs * prefs.lineHeight * 1.4;
          if (y > 0 && y + h > height) newPage(block.start);
          items.add(RuleItem(Rect.fromLTWH(left, top + y, width, h), block.start));
          y += h;
          lastEnd = block.start + 1;
      }
      previous = block;
    }
    if (items.isNotEmpty || pages.isEmpty) newPage(math.max(lastEnd, chapter.length));
    return pages;
  }

  int _lineStart(TextPainter painter, ui.LineMetrics line, TextBlock block, int prefix) {
    final pos = painter.getPositionForOffset(Offset(0.5, line.baseline - line.ascent / 2));
    final range = painter.getLineBoundary(pos);
    return block.start + math.max(0, range.start - prefix);
  }

  double _leftInset(TextBlock b) => switch (b.kind) {
        BlockKind.quote => prefs.fontSize * 1.4,
        BlockKind.listItem => prefs.fontSize * 0.9 * b.level.clamp(1, 4),
        _ => 0,
      };

  (double, double) _gaps(TextBlock b, FlowBlock? previous) {
    final fs = prefs.fontSize;
    final para = prefs.paragraphSpacing * fs;
    if (b.kind == BlockKind.heading) {
      final big = b.level <= 2;
      return (fs * (big ? 1.8 : 1.2), fs * (big ? 1.0 : 0.6));
    }
    if (b.kind == BlockKind.listItem) return (para * 0.3, para * 0.3);
    return (0, para);
  }

  (TextPainter, int) _painter(TextBlock block, FlowBlock? previous, double width) {
    final base = prefs.baseStyle();
    var style = base;
    var align = prefs.justify ? TextAlign.justify : TextAlign.start;
    var prefix = '';
    switch (block.kind) {
      case BlockKind.heading:
        final scale = _headingScale[(block.level - 1).clamp(0, 5)];
        style = base.copyWith(fontSize: prefs.fontSize * scale, fontWeight: FontWeight.w700, height: 1.25);
        align = block.level <= 2 ? TextAlign.center : TextAlign.start;
      case BlockKind.quote:
        style = base.copyWith(fontStyle: FontStyle.italic);
      case BlockKind.preformatted:
        style = base.copyWith(fontFamily: 'monospace', fontSize: prefs.fontSize * 0.82, height: 1.35);
        align = TextAlign.start;
      case BlockKind.centered:
        align = TextAlign.center;
      case BlockKind.listItem:
        align = TextAlign.start;
      case BlockKind.paragraph:
        final afterHeading = previous is! TextBlock || previous.kind == BlockKind.heading || previous.kind == BlockKind.centered;
        if (prefs.indent > 0 && !afterHeading) {
          final em = prefs.indent.floor();
          prefix = ' ' * em + (prefs.indent - em >= 0.5 ? ' ' : '');
        }
    }

    final spans = <InlineSpan>[
      if (prefix.isNotEmpty) TextSpan(text: prefix),
      for (final run in block.runs) TextSpan(text: run.text, style: _runStyle(run, style)),
    ];
    final painter = TextPainter(
      text: TextSpan(style: style, children: spans),
      textAlign: align,
      textDirection: TextDirection.ltr,
      textScaler: spec.textScaler,
    )..layout(maxWidth: width);
    _painters.add(painter);
    return (painter, prefix.length);
  }

  TextStyle? _runStyle(InlineRun run, TextStyle base) {
    if (run.style == 0 && run.href == null) return null;
    var s = const TextStyle();
    if (run.has(InlineStyle.bold)) s = s.copyWith(fontWeight: FontWeight.w700);
    if (run.has(InlineStyle.italic)) s = s.copyWith(fontStyle: FontStyle.italic);
    final decorations = <TextDecoration>[
      if (run.has(InlineStyle.underline) || run.href != null) TextDecoration.underline,
      if (run.has(InlineStyle.strike)) TextDecoration.lineThrough,
    ];
    if (decorations.isNotEmpty) {
      s = s.copyWith(
        decoration: TextDecoration.combine(decorations),
        decorationColor: (run.href != null ? linkColor : null) ?? base.color?.withValues(alpha: 0.5),
      );
    }
    if (run.href != null && linkColor != null) s = s.copyWith(color: linkColor);
    if (run.has(InlineStyle.superscript) || run.has(InlineStyle.subscript)) {
      s = s.copyWith(fontSize: (base.fontSize ?? 16) * 0.68);
    }
    if (run.has(InlineStyle.small)) s = s.copyWith(fontSize: (base.fontSize ?? 16) * 0.85);
    if (run.has(InlineStyle.code)) s = s.copyWith(fontFamily: 'monospace', fontSize: (base.fontSize ?? 16) * 0.86);
    return s;
  }
}
