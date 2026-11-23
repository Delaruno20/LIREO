import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lireo/formats/adapters/epub_adapter.dart';
import 'package:lireo/formats/adapters/fb2_adapter.dart';
import 'package:lireo/formats/adapters/image_book.dart';
import 'package:lireo/formats/adapters/mobi_adapter.dart';
import 'package:lireo/formats/adapters/text_adapters.dart';
import 'package:lireo/formats/document/flow_document.dart';
import 'package:lireo/formats/document/html_converter.dart';
import 'package:lireo/formats/format_registry.dart';

import 'test_utils.dart';

void main() {
  group('HtmlFlowConverter', () {
    test('convertit blocs, styles en ligne, ancres et images', () {
      final blocks = HtmlFlowConverter.parse(
        '<h2 id="t">Titre</h2><p>Un <b>mot</b> et <i>un autre</i>.</p>'
        '<blockquote><p>Citation</p></blockquote><img src="a.png"/><hr/><ul><li>Un</li><li>Deux</li></ul>',
        resolveImage: (s) => 'img/$s',
      );
      final texts = blocks.whereType<TextBlock>().toList();
      expect(texts.first.kind, BlockKind.heading);
      expect(texts.first.level, 2);
      expect(texts.first.anchors.first.$1, 't');
      expect(texts[1].plainText, 'Un mot et un autre.');
      expect(texts[1].runs.firstWhere((r) => r.text == 'mot').has(InlineStyle.bold), isTrue);
      expect(texts[2].kind, BlockKind.quote);
      expect(blocks.whereType<ImageBlock>().single.source, 'img/a.png');
      expect(blocks.whereType<RuleBlock>(), hasLength(1));
      expect(texts.where((t) => t.kind == BlockKind.listItem).map((t) => t.plainText), ['•  Un', '•  Deux']);
    });

    test('normalise les espaces blancs', () {
      final blocks = HtmlFlowConverter.parse('<p>  Bonjour \n   le   monde  </p>');
      expect((blocks.single as TextBlock).plainText, 'Bonjour le monde');
    });
  });

  group('FlowChapter', () {
    test('calcule les offsets et retrouve le bloc par offset', () {
      final c = FlowChapter(index: 0, title: '', blocks: [
        TextBlock([const InlineRun('abc')]),
        TextBlock([const InlineRun('defgh')], anchors: const [('x', 2)]),
      ]);
      expect(c.blocks[1].start, 4);
      expect(c.text, 'abc\ndefgh\n');
      expect(c.blockIndexAt(5), 1);
      expect(c.anchors['x'], 6);
    });
  });

  group('EPUB', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('lireo_epub'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('lit métadonnées, spine, TOC et chapitres', () async {
      final file = File('${dir.path}/book.epub')..writeAsBytesSync(buildEpub());
      final book = await EpubBook.open(file.path);
      final pkg = await EpubPackage.openFile(file.path);
      expect(pkg.metadata.title, 'Le Petit Livre');
      expect(pkg.metadata.author, 'Jeanne Auteur');
      expect(pkg.metadata.publisher, 'Éditions Test');
      expect(pkg.metadata.description, 'Une aventure.');
      expect(pkg.metadata.categories, ['Fantasy']);
      expect(book.chapterCount, 2);
      expect(book.toc.map((t) => t.title), ['Chapitre I', 'Chapitre II']);
      final ch = await book.loadChapter(0);
      expect(ch.title, 'Chapitre I');
      expect(ch.text, contains('Il était une fois un hobbit.'));
      final ch2 = await book.loadChapter(1);
      expect(ch2.anchors.containsKey('suite'), isTrue);
      expect(book.resolveLink(1, 'ch0.xhtml'), (0, null));
      await book.close();
      await pkg.close();
    });

    test('le registre extrait les métadonnées dans un isolate', () async {
      final file = File('${dir.path}/book.epub')..writeAsBytesSync(buildEpub(title: 'Isolé'));
      final meta = await FormatRegistry.extractMetadata(file.path, FormatRegistry.forPath(file.path)!);
      expect(meta.title, 'Isolé');
      expect(meta.pageCount, greaterThan(0));
    });
  });

  group('TXT / Markdown', () {
    test('détecte les chapitres et les paragraphes', () {
      final text = 'Chapitre 1\n\nPremier paragraphe\nsur deux lignes.\n\nDeuxième.\n\nChapitre 2\n\nFin.';
      final book = TxtAdapter.open(Uint8List.fromList(utf8.encode(text)), 'T') as MemoryReflowableBook;
      expect(book.chapterCount, 2);
      expect(book.chapters[0].title, 'Chapitre 1');
      expect(book.chapters[0].text, contains('Premier paragraphe sur deux lignes.'));
      expect(book.toc.map((t) => t.title), ['Chapitre 1', 'Chapitre 2']);
    });

    test('décode Latin-1 et UTF-16', () {
      expect(decodeText(Uint8List.fromList(latin1.encode('Élève'))), 'Élève');
      final utf16 = [0xFF, 0xFE, ...'Hé'.codeUnits.expand((c) => [c & 0xFF, c >> 8])];
      expect(decodeText(Uint8List.fromList(utf16)), 'Hé');
    });

    test('Markdown : titres et emphase', () {
      final book = MarkdownAdapter.open(Uint8List.fromList(utf8.encode('# Titre\n\nDu **gras**.\n\n# Deux\n\nTexte')), 'M')
          as MemoryReflowableBook;
      expect(book.chapterCount, 2);
      final para = book.chapters[0].blocks.whereType<TextBlock>().firstWhere((b) => b.kind == BlockKind.paragraph);
      expect(para.runs.any((r) => r.text == 'gras' && r.has(InlineStyle.bold)), isTrue);
    });
  });

  group('FB2', () {
    const fb2 = '''<?xml version="1.0" encoding="utf-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
 <description><title-info><genre>sf</genre><author><first-name>Ada</first-name><last-name>Lovelace</last-name></author>
 <book-title>Machines</book-title><lang>fr</lang><coverpage><image l:href="#c.png"/></coverpage></title-info></description>
 <body><section><title><p>Un</p></title><p>Du <strong>texte</strong>.</p></section>
 <section><title><p>Deux</p></title><p>Encore.</p></section></body>
 <binary id="c.png" content-type="image/png">iVBORw0KGgo=</binary>
</FictionBook>''';

    test('métadonnées et couverture', () {
      final meta = Fb2Adapter.metadata(Uint8List.fromList(utf8.encode(fb2)));
      expect(meta.title, 'Machines');
      expect(meta.author, 'Ada Lovelace');
      expect(meta.coverBytes, isNotNull);
    });

    test('sections en chapitres', () {
      final book = Fb2Adapter.open(Uint8List.fromList(utf8.encode(fb2)), 'x') as MemoryReflowableBook;
      expect(book.chapters.map((c) => c.title), ['Un', 'Deux']);
      expect(book.chapters[0].text, contains('Du texte.'));
    });
  });

  group('MOBI', () {
    test('décompression PalmDOC (littéraux, espace+car, références)', () {
      final out = MobiFile.palmDocDecompress(Uint8List.fromList([0x61, 0x62, 0x63, 0x80, 0x18, 0xC1, 0x02, 0x7A, 0x7A]));
      expect(latin1.decode(out), 'abcabc Azz');
    });

    test('lit un livre non compressé avec EXTH', () {
      final book = MobiAdapter.open(_buildMobi('<html><body><h1>Titre</h1><p>Bonjour le monde.</p></body></html>'), 'f');
      final meta = MobiAdapter.metadata(_buildMobi('<p>x</p>'));
      expect(meta.title, 'Mon MOBI');
      expect(meta.author, 'Auteur Mobi');
      expect(book.chapterCount, 1);
    });

    test('refuse les livres protégés par DRM', () {
      expect(() => MobiAdapter.open(_buildMobi('<p>x</p>', encryption: 2), 'f'), throwsA(isA<MobiException>()));
    });
  });

  test('tri naturel des pages de BD', () {
    final names = ['p10.jpg', 'p2.jpg', 'p1.jpg']..sort(naturalCompare);
    expect(names, ['p1.jpg', 'p2.jpg', 'p10.jpg']);
  });

  test('le registre ne déclare que des formats réellement gérés', () {
    expect(FormatRegistry.isSupported('a.EPUB'), isTrue);
    expect(FormatRegistry.isSupported('a.cbr'), isFalse);
    expect(FormatRegistry.isSupported('a.djvu'), isFalse);
  });
}

/// Fabrique un fichier MOBI minimal (texte non compressé, UTF-8, EXTH).
Uint8List _buildMobi(String html, {int encryption = 0}) {
  final text = utf8.encode(html);
  final b = BytesBuilder();
  void u16(BytesBuilder o, int v) => o.add([(v >> 8) & 0xFF, v & 0xFF]);
  void u32(BytesBuilder o, int v) => o.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);

  // EXTH : 100 = auteur, 503 = titre.
  final exth = BytesBuilder();
  final records = [(100, utf8.encode('Auteur Mobi')), (503, utf8.encode('Mon MOBI'))];
  final exthBody = BytesBuilder();
  for (final (type, data) in records) {
    u32(exthBody, type);
    u32(exthBody, data.length + 8);
    exthBody.add(data);
  }
  final body = exthBody.takeBytes();
  exth.add(ascii.encode('EXTH'));
  u32(exth, body.length + 12);
  u32(exth, records.length);
  exth.add(body);
  final exthBytes = exth.takeBytes();

  const mobiHeaderLength = 232;
  final r0 = BytesBuilder();
  u16(r0, 1); // compression : aucune
  u16(r0, 0);
  u32(r0, text.length);
  u16(r0, 1); // 1 enregistrement de texte
  u16(r0, 4096);
  u16(r0, encryption);
  u16(r0, 0);
  final mobi = Uint8List(mobiHeaderLength);
  final view = ByteData.sublistView(mobi);
  mobi.setAll(0, ascii.encode('MOBI'));
  view.setUint32(4, mobiHeaderLength);
  view.setUint32(8, 2);
  view.setUint32(12, 65001);
  final fullName = utf8.encode('Nom complet');
  view.setUint32(68, 16 + mobiHeaderLength + exthBytes.length); // fullNameOffset (record0 + 84)
  view.setUint32(72, fullName.length);
  view.setUint32(92, 0xFFFFFFFF); // firstImageIndex (record0 + 108)
  view.setUint32(112, 0x40); // EXTH présent (record0 + 128)
  r0.add(mobi);
  r0.add(exthBytes);
  r0.add(fullName);
  final record0 = r0.takeBytes();

  final header = Uint8List(78);
  header.setAll(0, ascii.encode('Test'));
  header.setAll(60, ascii.encode('BOOKMOBI'));
  ByteData.sublistView(header).setUint16(76, 2);
  b.add(header);
  final offset0 = 78 + 2 * 8 + 2;
  u32(b, offset0);
  u32(b, 0);
  u32(b, offset0 + record0.length);
  u32(b, 1);
  b.add([0, 0]);
  b.add(record0);
  b.add(text);
  return b.takeBytes();
}
