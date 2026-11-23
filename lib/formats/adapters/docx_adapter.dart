import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../document/flow_document.dart';
import '../metadata/book_metadata.dart';
import 'text_adapters.dart';

/// Documents Word (.docx) et OpenDocument texte (.odt).
///
/// Les deux formats sont des archives ZIP contenant du XML : on extrait les
/// paragraphes, titres, styles gras/italique/souligné et images.
abstract final class OfficeAdapter {
  static String _read(Archive a, String name) {
    final f = a.find(name);
    return f == null ? '' : utf8.decode(f.readBytes() ?? Uint8List(0), allowMalformed: true);
  }

  static BookMetadata metadata(Uint8List bytes, String format) {
    final archive = ZipDecoder().decodeBytes(bytes);
    String field(XmlDocument? d, String name) =>
        d?.findAllElements(name, namespaceUri: '*').firstOrNull?.innerText.trim() ?? '';
    XmlDocument? meta;
    final metaXml = format == 'odt' ? _read(archive, 'meta.xml') : _read(archive, 'docProps/core.xml');
    if (metaXml.isNotEmpty) meta = XmlDocument.parse(metaXml);
    final book = open(bytes, format, '');
    final chars = book.chapters.fold<int>(0, (a, c) => a + c.length);
    final firstImage = book.chapters.expand((c) => c.blocks).whereType<ImageBlock>().firstOrNull;
    return BookMetadata(
      title: field(meta, 'title'),
      author: field(meta, format == 'odt' ? 'initial-creator' : 'creator').isNotEmpty
          ? field(meta, format == 'odt' ? 'initial-creator' : 'creator')
          : field(meta, 'creator'),
      description: field(meta, 'description'),
      language: field(meta, 'language'),
      categories: field(meta, 'subject').isEmpty ? const [] : [field(meta, 'subject')],
      coverBytes: firstImage == null ? null : book.resources[firstImage.source],
      pageCount: (chars / BookMetadata.charsPerPage).ceil(),
    );
  }

  static MemoryReflowableBook open(Uint8List bytes, String format, String fallbackTitle) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final resources = <String, Uint8List>{};
    final blocks = format == 'odt' ? _odt(archive, resources) : _docx(archive, resources);
    return MemoryReflowableBook(
      chapters: splitIntoChapters(blocks, maxLevel: 1, fallbackTitle: fallbackTitle),
      resources: resources,
    );
  }

  // ------------------------------------------------------------- DOCX

  static List<FlowBlock> _docx(Archive archive, Map<String, Uint8List> resources) {
    final rels = <String, String>{};
    final relsXml = _read(archive, 'word/_rels/document.xml.rels');
    if (relsXml.isNotEmpty) {
      for (final r in XmlDocument.parse(relsXml).findAllElements('Relationship', namespaceUri: '*')) {
        final id = r.getAttribute('Id'), target = r.getAttribute('Target');
        if (id != null && target != null) rels[id] = p.posix.normalize(p.posix.join('word', target));
      }
    }
    final doc = XmlDocument.parse(_read(archive, 'word/document.xml'));
    final body = doc.findAllElements('body', namespaceUri: '*').firstOrNull;
    if (body == null) return const [];
    final out = <FlowBlock>[];
    for (final para in body.findAllElements('p', namespaceUri: '*')) {
      final style = para
              .findElements('pPr', namespaceUri: '*')
              .firstOrNull
              ?.findElements('pStyle', namespaceUri: '*')
              .firstOrNull
              ?.attributes
              .where((a) => a.localName == 'val')
              .firstOrNull
              ?.value
              .toLowerCase() ??
          '';
      final centered = para.findAllElements('jc', namespaceUri: '*').any((j) => j.attributes.any((a) => a.localName == 'val' && a.value == 'center'));
      final runs = <InlineRun>[];
      for (final r in para.findAllElements('r', namespaceUri: '*')) {
        final rPr = r.findElements('rPr', namespaceUri: '*').firstOrNull;
        bool on(String tag) {
          final e = rPr?.findElements(tag, namespaceUri: '*').firstOrNull;
          if (e == null) return false;
          final v = e.attributes.where((a) => a.localName == 'val').firstOrNull?.value;
          return v == null || (v != '0' && v != 'false' && v != 'none');
        }

        var s = 0;
        if (on('b')) s |= InlineStyle.bold;
        if (on('i')) s |= InlineStyle.italic;
        if (on('u')) s |= InlineStyle.underline;
        if (on('strike')) s |= InlineStyle.strike;
        final buf = StringBuffer();
        for (final c in r.childElements) {
          switch (c.localName) {
            case 't':
              buf.write(c.innerText);
            case 'tab':
              buf.write('\t');
            case 'br':
              buf.write('\n');
            case 'drawing' || 'pict':
              for (final blip in c.findAllElements('blip', namespaceUri: '*')) {
                final id = blip.attributes.where((a) => a.localName == 'embed').firstOrNull?.value;
                final target = id == null ? null : rels[id];
                final data = target == null ? null : archive.find(target)?.readBytes();
                if (target != null && data != null) {
                  resources[target] = data;
                  if (runs.isNotEmpty || buf.isNotEmpty) {
                    runs.add(InlineRun(buf.toString(), style: s));
                    buf.clear();
                    out.add(TextBlock(List.of(runs)));
                    runs.clear();
                  }
                  out.add(ImageBlock(target));
                }
              }
          }
        }
        if (buf.isNotEmpty) runs.add(InlineRun(buf.toString(), style: s));
      }
      if (runs.isEmpty) continue;
      final headingLevel = switch (style) {
        'title' => 1,
        _ when style.startsWith('heading') => int.tryParse(style.replaceAll(RegExp(r'\D'), '')) ?? 1,
        _ when style.startsWith('titre') => int.tryParse(style.replaceAll(RegExp(r'\D'), '')) ?? 1,
        _ => 0,
      };
      out.add(TextBlock(
        runs,
        kind: headingLevel > 0
            ? BlockKind.heading
            : (centered ? BlockKind.centered : (style.contains('quote') || style.contains('citation') ? BlockKind.quote : BlockKind.paragraph)),
        level: headingLevel,
      ));
    }
    return out;
  }

  // -------------------------------------------------------------- ODT

  static List<FlowBlock> _odt(Archive archive, Map<String, Uint8List> resources) {
    final doc = XmlDocument.parse(_read(archive, 'content.xml'));
    final text = doc.findAllElements('text', namespaceUri: '*').where((e) => e.parentElement?.localName == 'body').firstOrNull;
    if (text == null) return const [];
    final out = <FlowBlock>[];
    void walk(XmlElement el) {
      for (final c in el.childElements) {
        switch (c.localName) {
          case 'h':
            final level = int.tryParse(c.attributes.where((a) => a.localName == 'outline-level').firstOrNull?.value ?? '') ?? 1;
            out.add(TextBlock([InlineRun(c.innerText.trim())], kind: BlockKind.heading, level: level));
          case 'p':
            for (final img in c.findAllElements('image', namespaceUri: '*')) {
              final href = img.attributes.where((a) => a.localName == 'href').firstOrNull?.value;
              final data = href == null ? null : archive.find(href)?.readBytes();
              if (href != null && data != null) {
                resources[href] = data;
                out.add(ImageBlock(href));
              }
            }
            final t = c.innerText.trim();
            if (t.isNotEmpty) out.add(TextBlock([InlineRun(t)]));
          case 'list' || 'list-item' || 'section' || 'table' || 'table-row' || 'table-cell':
            walk(c);
        }
      }
    }

    walk(text);
    return out;
  }
}
