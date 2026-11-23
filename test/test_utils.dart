import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Construit un EPUB 3 minimal mais complet en mémoire.
Uint8List buildEpub({
  String title = 'Le Petit Livre',
  String author = 'Jeanne Auteur',
  List<(String, String)> chapters = const [
    ('Chapitre I', '<p>Il était une <em>fois</em> un hobbit.</p><p>Il vivait dans un trou.</p>'),
    ('Chapitre II', '<p id="suite">La suite <a href="ch1.xhtml">retour</a>.</p>'),
  ],
  List<String> subjects = const ['Fantasy'],
  Uint8List? cover,
}) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.add(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  if (cover != null) archive.add(ArchiveFile('OEBPS/cover.png', cover.length, cover));
  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
  final items = StringBuffer();
  final spine = StringBuffer();
  final nav = StringBuffer();
  for (var i = 0; i < chapters.length; i++) {
    items.writeln('<item id="ch$i" href="ch$i.xhtml" media-type="application/xhtml+xml"/>');
    spine.writeln('<itemref idref="ch$i"/>');
    nav.writeln('<li><a href="ch$i.xhtml">${chapters[i].$1}</a></li>');
    add('OEBPS/ch$i.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>${chapters[i].$1}</title></head>
<body><h1>${chapters[i].$1}</h1>${chapters[i].$2}</body></html>''');
  }
  add('OEBPS/nav.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
<nav epub:type="toc"><ol>$nav</ol></nav></body></html>''');
  add('OEBPS/content.opf', '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">urn:test</dc:identifier>
    <dc:title>$title</dc:title>
    <dc:creator>$author</dc:creator>
    <dc:publisher>Éditions Test</dc:publisher>
    <dc:language>fr</dc:language>
    ${subjects.map((s) => '<dc:subject>$s</dc:subject>').join()}
    <dc:description>&lt;p&gt;Une aventure.&lt;/p&gt;</dc:description>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    ${cover != null ? '<item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>' : ''}
    $items
  </manifest>
  <spine>$spine</spine>
</package>''');
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
