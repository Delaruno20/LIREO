import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../document/flow_document.dart';
import '../metadata/book_metadata.dart';
import 'text_adapters.dart';

/// FictionBook 2 (.fb2) : XML avec images embarquées en base64.
abstract final class Fb2Adapter {
  static XmlDocument _parse(Uint8List bytes) {
    // L'encodage est déclaré dans le prologue XML (souvent windows-1251).
    final head = latin1.decode(bytes.sublist(0, bytes.length.clamp(0, 200)));
    final enc = RegExp(r'encoding="([^"]+)"').firstMatch(head)?.group(1)?.toLowerCase() ?? 'utf-8';
    final text = enc.contains('utf') ? decodeText(bytes) : latin1.decode(bytes);
    return XmlDocument.parse(text);
  }

  static String? _href(XmlElement e) {
    for (final a in e.attributes) {
      if (a.localName == 'href') return a.value.startsWith('#') ? a.value.substring(1) : a.value;
    }
    return null;
  }

  static Map<String, Uint8List> _binaries(XmlDocument doc) => {
        for (final b in doc.findAllElements('binary', namespaceUri: '*'))
          if (b.getAttribute('id') != null)
            b.getAttribute('id')!: base64.decode(b.innerText.replaceAll(RegExp(r'\s'), '')),
      };

  static BookMetadata metadata(Uint8List bytes) {
    final doc = _parse(bytes);
    final info = doc.findAllElements('title-info', namespaceUri: '*').firstOrNull;
    String t(XmlElement? parent, String name) =>
        parent?.findAllElements(name, namespaceUri: '*').firstOrNull?.innerText.trim() ?? '';
    final authors = info?.findElements('author', namespaceUri: '*').map((a) {
          final parts = [t(a, 'first-name'), t(a, 'middle-name'), t(a, 'last-name')].where((s) => s.isNotEmpty);
          return parts.isEmpty ? t(a, 'nickname') : parts.join(' ');
        }).where((s) => s.isNotEmpty).toList() ??
        const [];
    Uint8List? cover;
    final coverImage = info?.findAllElements('coverpage', namespaceUri: '*').firstOrNull?.findAllElements('image', namespaceUri: '*').firstOrNull;
    if (coverImage != null) {
      final id = _href(coverImage);
      cover = id == null ? null : _binaries(doc)[id];
    }
    final textLength = doc.findAllElements('body', namespaceUri: '*').fold<int>(0, (a, b) => a + b.innerText.length);
    return BookMetadata(
      title: t(info, 'book-title'),
      author: authors.join(', '),
      publisher: t(doc.findAllElements('publish-info', namespaceUri: '*').firstOrNull, 'publisher'),
      description: t(info, 'annotation'),
      language: t(info, 'lang'),
      categories: info?.findElements('genre', namespaceUri: '*').map((g) => g.innerText.trim().replaceAll('_', ' ')).take(3).toList() ?? const [],
      coverBytes: cover,
      pageCount: (textLength / BookMetadata.charsPerPage).ceil(),
    );
  }

  static ReflowableBook open(Uint8List bytes, String fallbackTitle) {
    final doc = _parse(bytes);
    final chapters = <FlowChapter>[];
    for (final body in doc.findAllElements('body', namespaceUri: '*')) {
      final sections = body.findElements('section', namespaceUri: '*').toList();
      if (sections.isEmpty) {
        final blocks = <FlowBlock>[];
        _convert(body, blocks, 1);
        chapters.add(FlowChapter(index: chapters.length, title: fallbackTitle, blocks: blocks));
        continue;
      }
      // Contenu avant la première section (titre du livre, épigraphe).
      final intro = <FlowBlock>[];
      for (final child in body.childElements) {
        if (child.localName == 'section') break;
        _convertElement(child, intro, 1);
      }
      if (intro.isNotEmpty) chapters.add(FlowChapter(index: chapters.length, title: '', blocks: intro));
      for (final s in sections) {
        final blocks = <FlowBlock>[];
        _convert(s, blocks, 1);
        final title = s.findElements('title', namespaceUri: '*').firstOrNull?.innerText.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
        chapters.add(FlowChapter(index: chapters.length, title: title, blocks: blocks));
      }
    }
    return MemoryReflowableBook(chapters: chapters, resources: _binaries(doc));
  }

  static void _convert(XmlElement parent, List<FlowBlock> out, int depth) {
    for (final child in parent.childElements) {
      _convertElement(child, out, depth);
    }
  }

  static void _convertElement(XmlElement e, List<FlowBlock> out, int depth) {
    final anchors = e.getAttribute('id') != null ? [(e.getAttribute('id')!, 0)] : const <(String, int)>[];
    switch (e.localName) {
      case 'title':
        for (final p in e.findElements('p', namespaceUri: '*')) {
          out.add(TextBlock(_inline(p), kind: BlockKind.heading, level: depth.clamp(1, 6), anchors: anchors));
        }
      case 'subtitle':
        out.add(TextBlock(_inline(e), kind: BlockKind.heading, level: (depth + 2).clamp(1, 6)));
      case 'p':
        out.add(TextBlock(_inline(e), anchors: anchors));
      case 'v' || 'text-author':
        out.add(TextBlock(_inline(e), kind: BlockKind.centered));
      case 'empty-line':
        out.add(RuleBlock());
      case 'image':
        final id = _href(e);
        if (id != null) out.add(ImageBlock(id));
      case 'epigraph' || 'cite' || 'annotation':
        final inner = <FlowBlock>[];
        _convert(e, inner, depth);
        for (final b in inner) {
          out.add(b is TextBlock && b.kind == BlockKind.paragraph
              ? TextBlock(b.runs.map((r) => InlineRun(r.text, style: r.style | InlineStyle.italic)).toList(), kind: BlockKind.quote)
              : b);
        }
      case 'section':
        _convert(e, out, depth + 1);
      case 'poem' || 'stanza':
        _convert(e, out, depth);
      default:
        if (e.innerText.trim().isNotEmpty) _convert(e, out, depth);
    }
  }

  static List<InlineRun> _inline(XmlElement e, [int style = 0]) {
    final runs = <InlineRun>[];
    for (final node in e.children) {
      if (node is XmlText || node is XmlCDATA) {
        final t = node.value!.replaceAll(RegExp(r'\s+'), ' ');
        if (t.isNotEmpty) runs.add(InlineRun(t, style: style));
      } else if (node is XmlElement) {
        final s = switch (node.localName) {
          'strong' => style | InlineStyle.bold,
          'emphasis' => style | InlineStyle.italic,
          'strikethrough' => style | InlineStyle.strike,
          'sup' => style | InlineStyle.superscript,
          'sub' => style | InlineStyle.subscript,
          'code' => style | InlineStyle.code,
          _ => style,
        };
        if (node.localName == 'a') {
          final href = _href(node);
          runs.addAll(_inline(node, s).map((r) => InlineRun(r.text, style: r.style, href: href == null ? null : '#$href')));
        } else {
          runs.addAll(_inline(node, s));
        }
      }
    }
    if (runs.isNotEmpty) {
      runs[0] = InlineRun(runs[0].text.trimLeft(), style: runs[0].style, href: runs[0].href);
      final l = runs.length - 1;
      runs[l] = InlineRun(runs[l].text.trimRight(), style: runs[l].style, href: runs[l].href);
    }
    return runs;
  }
}
