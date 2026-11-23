import 'package:flutter_test/flutter_test.dart';
import 'package:lireo/data/models/book.dart';
import 'package:lireo/features/reader/model/reader_prefs.dart';
import 'package:lireo/features/reader/reflow/page_layout.dart';
import 'package:lireo/features/reader/reflow/reflow_controller.dart';
import 'package:lireo/formats/document/flow_document.dart';
import 'package:material_ui/material_ui.dart';

FlowChapter _chapter(int index, int paragraphs) => FlowChapter(index: index, title: 'Chapitre $index', blocks: [
      TextBlock([InlineRun('Chapitre $index')], kind: BlockKind.heading, level: 1),
      for (var i = 0; i < paragraphs; i++)
        TextBlock([InlineRun('Paragraphe $i. ${'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' * 6}')]),
    ]);

void main() {
  const spec = LayoutSpec(pageSize: Size(360, 640), prefs: ReaderPrefs(), textScaler: TextScaler.noScaling, footerHeight: 26);

  test('les pages couvrent tout le chapitre, sans trou ni chevauchement', () async {
    final chapter = _chapter(0, 40);
    final layout = await Paginator(spec).layout(chapter, (_, _) async => null);
    expect(layout.pages.length, greaterThan(3));
    expect(layout.pages.first.start, 0);
    for (var i = 1; i < layout.pages.length; i++) {
      expect(layout.pages[i].start, layout.pages[i - 1].end, reason: 'page $i');
    }
    expect(layout.pages.last.end, greaterThanOrEqualTo(chapter.length - 1));
    for (final p in layout.pages) {
      expect(p.usedHeight, lessThanOrEqualTo(spec.contentHeight + 0.5));
    }
    // Un offset retombe sur la bonne page.
    final mid = layout.pages[2].start + 5;
    expect(layout.pageFor(mid), 2);
    layout.dispose();
  });

  test('un paragraphe coupé garde le même TextPainter (justification stable)', () async {
    final layout = await Paginator(spec).layout(_chapter(0, 40), (_, _) async => null);
    final firstItems = layout.pages[0].items.whereType<TextItem>().toList();
    final secondItems = layout.pages[1].items.whereType<TextItem>().toList();
    final split = firstItems.last.block == secondItems.first.block;
    if (split) {
      expect(identical(firstItems.last.painter, secondItems.first.painter), isTrue);
      expect(secondItems.first.clipTop, greaterThan(0));
    }
    layout.dispose();
  });

  test('le contrôleur navigue entre chapitres et conserve la position au changement de police', () async {
    final book = MemoryReflowableBook(chapters: [_chapter(0, 12), _chapter(1, 12), _chapter(2, 12)]);
    final c = ReflowController(book);
    await c.open(const BookLocation(chapter: 1, offset: 900));
    await c.setSpec(spec);
    expect(c.chapter, 1);
    expect(c.currentPage!.contains(900) || c.currentPage!.start <= 900, isTrue);

    final before = c.locator;
    await c.setSpec(LayoutSpec(pageSize: spec.pageSize, prefs: const ReaderPrefs(fontSize: 26), textScaler: TextScaler.noScaling));
    expect(c.currentPage!.start, lessThanOrEqualTo(before.offset));
    expect(c.currentPage!.end, greaterThan(before.offset));

    // Fin du chapitre 1 → début du chapitre 2.
    while (c.chapter == 1) {
      expect(await c.turn(1), isTrue);
    }
    expect(c.chapter, 2);
    expect(c.page, 0);
    expect(await c.turn(-1), isTrue);
    expect(c.chapter, 1);
    expect(c.progress, inInclusiveRange(0.33, 0.67));
    c.dispose();
  });
}
