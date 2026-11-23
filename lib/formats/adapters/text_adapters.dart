import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

import '../document/flow_document.dart';
import '../document/html_converter.dart';
import '../metadata/book_metadata.dart';

/// Décode un fichier texte : UTF-8 (avec ou sans BOM), UTF-16 (BOM), sinon Latin-1.
String decodeText(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    final le = bytes[0] == 0xFF;
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add(le ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Découpe une liste de blocs en chapitres aux titres de niveau ≤ [maxLevel],
/// puis découpe les chapitres trop longs pour garder une pagination rapide.
List<FlowChapter> splitIntoChapters(List<FlowBlock> blocks, {int maxLevel = 2, String fallbackTitle = ''}) {
  final groups = <(String, List<FlowBlock>)>[];
  var current = <FlowBlock>[];
  var title = fallbackTitle;
  for (final b in blocks) {
    final isChapterHeading = b is TextBlock && b.kind == BlockKind.heading && b.level <= maxLevel;
    if (isChapterHeading && current.any((x) => x is TextBlock && x.kind != BlockKind.heading)) {
      groups.add((title, current));
      current = [];
    }
    if (isChapterHeading && (current.isEmpty || current.every((x) => x is TextBlock && x.kind == BlockKind.heading))) {
      title = b.plainText.trim();
    }
    current.add(b);
  }
  if (current.isNotEmpty) groups.add((title, current));

  const maxChars = 60000;
  final chapters = <FlowChapter>[];
  for (final (t, list) in groups) {
    var part = <FlowBlock>[];
    var size = 0;
    var partIndex = 0;
    for (final b in list) {
      part.add(b);
      size += b.length;
      if (size > maxChars) {
        chapters.add(FlowChapter(index: chapters.length, title: partIndex == 0 ? t : '', blocks: part));
        part = [];
        size = 0;
        partIndex++;
      }
    }
    if (part.isNotEmpty) {
      chapters.add(FlowChapter(index: chapters.length, title: partIndex == 0 ? t : '', blocks: part));
    }
  }
  if (chapters.isEmpty) chapters.add(FlowChapter(index: 0, title: fallbackTitle, blocks: []));
  return chapters;
}

// ------------------------------------------------------------------- TXT

abstract final class TxtAdapter {
  static final _chapterLine = RegExp(
    r'^\s*((chapitre|chapter|capítulo|capitolo|kapitel|partie|part|livre|book|prologue|épilogue|epilogue)\b.{0,60}|[IVXLC]{1,7}\.?|\d{1,3}\.?)\s*$',
    caseSensitive: false,
  );

  static List<FlowBlock> parse(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final hasBlankLines = RegExp(r'\n\s*\n').hasMatch(normalized);
    final rawParas = hasBlankLines ? normalized.split(RegExp(r'\n\s*\n')) : normalized.split('\n');
    final blocks = <FlowBlock>[];
    for (final raw in rawParas) {
      final para = hasBlankLines ? raw.split('\n').map((l) => l.trim()).join(' ').trim() : raw.trim();
      if (para.isEmpty) continue;
      final isHeading = para.length < 70 && _chapterLine.hasMatch(para);
      blocks.add(TextBlock([InlineRun(para)], kind: isHeading ? BlockKind.heading : BlockKind.paragraph, level: isHeading ? 2 : 0));
    }
    return blocks;
  }

  static ReflowableBook open(Uint8List bytes, String title) =>
      MemoryReflowableBook(chapters: splitIntoChapters(parse(decodeText(bytes)), fallbackTitle: title));

  static BookMetadata metadata(Uint8List bytes) {
    final text = decodeText(bytes);
    return BookMetadata(pageCount: (text.length / BookMetadata.charsPerPage).ceil());
  }
}

// ------------------------------------------------------------- Markdown

abstract final class MarkdownAdapter {
  static String toHtml(String source) => md.markdownToHtml(source, extensionSet: md.ExtensionSet.gitHubWeb);

  static ReflowableBook open(Uint8List bytes, String title) {
    final blocks = HtmlFlowConverter.parse(toHtml(decodeText(bytes)));
    return MemoryReflowableBook(chapters: splitIntoChapters(blocks, fallbackTitle: title));
  }

  static BookMetadata metadata(Uint8List bytes) {
    final text = decodeText(bytes);
    final h1 = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(text)?.group(1)?.trim() ?? '';
    return BookMetadata(title: h1, pageCount: (text.length / BookMetadata.charsPerPage).ceil());
  }
}

// ------------------------------------------------------------------ HTML

abstract final class HtmlAdapter {
  static ReflowableBook open(Uint8List bytes, String title) {
    final blocks = HtmlFlowConverter.parse(decodeText(bytes));
    return MemoryReflowableBook(chapters: splitIntoChapters(blocks, fallbackTitle: title));
  }

  static BookMetadata metadata(Uint8List bytes) {
    final doc = html_parser.parse(decodeText(bytes));
    String meta(String name) =>
        doc.querySelector('meta[name="$name"]')?.attributes['content']?.trim() ?? '';
    final text = doc.body?.text ?? '';
    return BookMetadata(
      title: doc.querySelector('title')?.text.trim() ?? '',
      author: meta('author'),
      description: meta('description'),
      language: doc.documentElement?.attributes['lang'] ?? '',
      pageCount: (text.length / BookMetadata.charsPerPage).ceil(),
    );
  }
}
