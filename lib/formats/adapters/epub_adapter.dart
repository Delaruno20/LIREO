import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../document/flow_document.dart';
import '../document/html_converter.dart';
import '../metadata/book_metadata.dart';

/// Lecture d'un paquet EPUB 2/3 : container.xml → OPF → spine/manifest/TOC.
class EpubPackage {
  EpubPackage._(this._archive, this._input, this._opfDir, this.metadata, this.spine, this.toc, this._manifest);

  final Archive _archive;
  final InputFileStream? _input;
  final String _opfDir;
  final BookMetadata metadata;

  /// Chemins (dans l'archive) des documents du spine, dans l'ordre de lecture.
  final List<String> spine;
  final List<TocEntry> toc;
  final Map<String, String> _manifest;

  static Future<EpubPackage> openFile(String path) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return _parse(archive, input);
    } catch (e) {
      await input.close();
      rethrow;
    }
  }

  static EpubPackage fromBytes(List<int> bytes) => _parse(ZipDecoder().decodeBytes(bytes), null);

  static String _decodeText(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

  static EpubPackage _parse(Archive archive, InputFileStream? input) {
    String read(String name) {
      final f = archive.find(name);
      if (f == null) throw FormatException('Fichier manquant dans l\'EPUB : $name');
      return _decodeText(f.readBytes() ?? Uint8List(0));
    }

    final container = XmlDocument.parse(read('META-INF/container.xml'));
    final opfPath = Uri.decodeFull(
      container.findAllElements('rootfile').first.getAttribute('full-path') ?? '',
    );
    final opfDir = p.posix.dirname(opfPath) == '.' ? '' : p.posix.dirname(opfPath);
    final opf = XmlDocument.parse(read(opfPath));

    String resolve(String base, String href) {
      final clean = Uri.decodeFull(href.split('#').first);
      return p.posix.normalize(base.isEmpty ? clean : p.posix.join(base, clean));
    }

    // Manifeste
    final manifest = <String, String>{};
    final mediaTypes = <String, String>{};
    String? navId, coverId;
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = resolve(opfDir, href);
      mediaTypes[id] = item.getAttribute('media-type') ?? '';
      final props = item.getAttribute('properties') ?? '';
      if (props.contains('nav')) navId = id;
      if (props.contains('cover-image')) coverId = id;
    }

    // Métadonnées Dublin Core
    String dc(String name) => opf.findAllElements(name, namespaceUri: '*').map((e) => e.innerText.trim()).firstWhere(
          (t) => t.isNotEmpty,
          orElse: () => '',
        );
    final authors = opf
        .findAllElements('creator', namespaceUri: '*')
        .map((e) => e.innerText.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final subjects = opf
        .findAllElements('subject', namespaceUri: '*')
        .map((e) => e.innerText.trim())
        .where((t) => t.isNotEmpty && t.length < 40)
        .toList();
    for (final meta in opf.findAllElements('meta')) {
      if (meta.getAttribute('name') == 'cover') coverId ??= meta.getAttribute('content');
    }
    if (coverId != null && !manifest.containsKey(coverId)) coverId = null;
    coverId ??= manifest.keys.firstWhere(
      (k) => k.toLowerCase().contains('cover') && (mediaTypes[k] ?? '').startsWith('image/'),
      orElse: () => '',
    );

    // Spine
    final spineEl = opf.findAllElements('spine').firstOrNull;
    final spine = <String>[];
    for (final ref in spineEl?.findElements('itemref', namespaceUri: '*') ?? const <XmlElement>[]) {
      final path = manifest[ref.getAttribute('idref')];
      if (path != null && archive.find(path) != null) spine.add(path);
    }
    if (spine.isEmpty) throw const FormatException('EPUB sans contenu lisible (spine vide).');

    // Table des matières : EPUB 3 (nav) puis EPUB 2 (NCX).
    var toc = <TocEntry>[];
    int? chapterOf(String path) {
      final i = spine.indexOf(path);
      return i < 0 ? null : i;
    }

    if (navId != null) {
      try {
        final navPath = manifest[navId]!;
        final navDir = p.posix.dirname(navPath) == '.' ? '' : p.posix.dirname(navPath);
        final navDoc = XmlDocument.parse(read(navPath));
        final tocNav = navDoc.findAllElements('nav', namespaceUri: '*').firstWhere(
              (n) => n.attributes.any((a) => a.localName == 'type' && a.value == 'toc'),
              orElse: () => navDoc.findAllElements('nav', namespaceUri: '*').first,
            );
        void walk(XmlElement ol, int level) {
          for (final li in ol.findElements('li', namespaceUri: '*')) {
            final a = li.findElements('a', namespaceUri: '*').firstOrNull ?? li.findElements('span', namespaceUri: '*').firstOrNull;
            final href = a?.getAttribute('href');
            if (a != null && href != null) {
              final ch = chapterOf(resolve(navDir, href));
              if (ch != null) {
                final frag = href.contains('#') ? href.split('#').last : null;
                toc.add(TocEntry(title: a.innerText.trim().replaceAll(RegExp(r'\s+'), ' '), chapter: ch, anchor: frag, level: level));
              }
            }
            final sub = li.findElements('ol', namespaceUri: '*').firstOrNull;
            if (sub != null) walk(sub, level + 1);
          }
        }

        final rootOl = tocNav.findElements('ol', namespaceUri: '*').firstOrNull;
        if (rootOl != null) walk(rootOl, 0);
      } catch (_) {
        toc = [];
      }
    }
    if (toc.isEmpty) {
      final ncxId = spineEl?.getAttribute('toc') ??
          mediaTypes.entries.firstWhere((e) => e.value == 'application/x-dtbncx+xml', orElse: () => const MapEntry('', '')).key;
      final ncxPath = manifest[ncxId];
      if (ncxPath != null) {
        try {
          final ncxDir = p.posix.dirname(ncxPath) == '.' ? '' : p.posix.dirname(ncxPath);
          final ncx = XmlDocument.parse(read(ncxPath));
          void walk(XmlElement parent, int level) {
            for (final np in parent.findElements('navPoint', namespaceUri: '*')) {
              final label = np.findAllElements('text', namespaceUri: '*').firstOrNull?.innerText.trim() ?? '';
              final src = np.findElements('content', namespaceUri: '*').firstOrNull?.getAttribute('src');
              if (src != null) {
                final ch = chapterOf(resolve(ncxDir, src));
                if (ch != null) {
                  toc.add(TocEntry(
                    title: label,
                    chapter: ch,
                    anchor: src.contains('#') ? src.split('#').last : null,
                    level: level,
                  ));
                }
              }
              walk(np, level + 1);
            }
          }

          final navMap = ncx.findAllElements('navMap', namespaceUri: '*').firstOrNull;
          if (navMap != null) walk(navMap, 0);
        } catch (_) {}
      }
    }

    final metadata = BookMetadata(
      title: dc('title'),
      author: authors.join(', '),
      publisher: dc('publisher'),
      description: _stripHtml(dc('description')),
      language: dc('language'),
      categories: subjects.take(4).toList(),
      coverBytes: coverId.isEmpty ? null : archive.find(manifest[coverId]!)?.readBytes(),
    );

    return EpubPackage._(archive, input, opfDir, metadata, spine, toc, manifest);
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  Uint8List? readFile(String path) => _archive.find(path)?.readBytes();

  int sizeOf(String path) => _archive.find(path)?.size ?? 0;

  String? get opfDir => _opfDir;

  bool contains(String path) => _archive.find(path) != null || _manifest.containsValue(path);

  Future<void> close() async => _input?.close();
}

class EpubBook extends ReflowableBook {
  EpubBook._(this._pkg) : chapterWeights = [for (final s in _pkg.spine) _pkg.sizeOf(s).toDouble().clamp(1, double.infinity)];

  final EpubPackage _pkg;
  final _cache = <int, FlowChapter>{};
  static const _isolateThreshold = 150 * 1024;

  static Future<EpubBook> open(String path) async => EpubBook._(await EpubPackage.openFile(path));

  @override
  final List<double> chapterWeights;

  @override
  int get chapterCount => _pkg.spine.length;

  @override
  List<TocEntry> get toc => _pkg.toc;

  @override
  Future<FlowChapter> loadChapter(int index) async {
    final cached = _cache[index];
    if (cached != null) return cached;
    final path = _pkg.spine[index];
    final dir = p.posix.dirname(path) == '.' ? '' : p.posix.dirname(path);
    final bytes = _pkg.readFile(path) ?? Uint8List(0);
    List<FlowBlock> parse() => HtmlFlowConverter.parse(
          utf8.decode(bytes, allowMalformed: true),
          resolveImage: (src) => p.posix.normalize(dir.isEmpty ? Uri.decodeFull(src) : p.posix.join(dir, Uri.decodeFull(src))),
        );
    // Un gros chapitre s'analyse en arrière-plan : sinon l'interface se fige
    // (≈ 280 ms pour 1 Mo de XHTML sur un téléphone milieu de gamme).
    final blocks = bytes.length > _isolateThreshold ? await Isolate.run(parse) : parse();
    final tocTitle = _pkg.toc.where((t) => t.chapter == index).firstOrNull?.title;
    final headingTitle = blocks.whereType<TextBlock>().where((b) => b.kind == BlockKind.heading).firstOrNull?.plainText;
    final chapter = FlowChapter(index: index, title: tocTitle ?? headingTitle ?? '', blocks: blocks);
    // Cache borné : seuls quelques chapitres restent en mémoire.
    if (_cache.length > 6) _cache.remove(_cache.keys.first);
    _cache[index] = chapter;
    return chapter;
  }

  @override
  Future<Uint8List?> loadResource(String key) async => _pkg.readFile(key);

  @override
  (int, String?)? resolveLink(int fromChapter, String href) {
    if (href.startsWith('http://') || href.startsWith('https://') || href.startsWith('mailto:')) return null;
    final from = _pkg.spine[fromChapter];
    final dir = p.posix.dirname(from) == '.' ? '' : p.posix.dirname(from);
    final parts = href.split('#');
    final target = parts.first.isEmpty ? from : p.posix.normalize(p.posix.join(dir, Uri.decodeFull(parts.first)));
    final idx = _pkg.spine.indexOf(target);
    if (idx < 0) return null;
    return (idx, parts.length > 1 ? parts[1] : null);
  }

  @override
  Future<void> close() => _pkg.close();
}
