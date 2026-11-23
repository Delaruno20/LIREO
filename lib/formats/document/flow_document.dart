import 'dart:typed_data';

/// Modèle de document « reflowable » commun à tous les formats texte
/// (EPUB, TXT, HTML, Markdown, FB2, DOCX…).
///
/// Chaque adaptateur de format produit des [FlowChapter] ; le moteur de mise
/// en page ne connaît que ce modèle. Ajouter un format = écrire un adaptateur.

enum BlockKind { paragraph, heading, quote, preformatted, listItem, centered }

/// Styles en ligne, combinables par bits.
abstract final class InlineStyle {
  static const bold = 1;
  static const italic = 2;
  static const underline = 4;
  static const superscript = 8;
  static const subscript = 16;
  static const code = 32;
  static const small = 64;
  static const strike = 128;
}

class InlineRun {
  const InlineRun(this.text, {this.style = 0, this.href});
  final String text;
  final int style;
  final String? href;

  bool has(int flag) => style & flag != 0;
}

sealed class FlowBlock {
  FlowBlock();

  /// Offset du premier caractère du bloc dans le texte du chapitre.
  int start = 0;

  /// Nombre de caractères occupés dans le texte du chapitre.
  int get length;

  /// Texte brut de ce bloc (utilisé pour la recherche, la TTS, les extraits).
  String get plainText;
}

class TextBlock extends FlowBlock {
  TextBlock(this.runs, {this.kind = BlockKind.paragraph, this.level = 0, this.anchors = const []});

  final List<InlineRun> runs;
  final BlockKind kind;

  /// Niveau de titre (1..6) ou profondeur de liste.
  final int level;

  /// Identifiants d'ancres (`id=""`) situés dans ce bloc, avec leur offset local.
  final List<(String, int)> anchors;

  late final String _text = runs.map((r) => r.text).join();

  @override
  String get plainText => _text;

  @override
  int get length => _text.length;
}

class ImageBlock extends FlowBlock {
  ImageBlock(this.source, {this.alt = ''});

  /// Clé de ressource résolue par [ReflowableBook.loadResource].
  final String source;
  final String alt;

  @override
  int get length => 1;

  @override
  String get plainText => '￼';
}

class RuleBlock extends FlowBlock {
  @override
  int get length => 1;

  @override
  String get plainText => '\n';
}

class FlowChapter {
  FlowChapter({required this.index, required this.title, required List<FlowBlock> blocks})
      : blocks = _normalize(blocks) {
    var offset = 0;
    final buffer = StringBuffer();
    for (final b in this.blocks) {
      b.start = offset;
      buffer.write(b.plainText);
      offset += b.length;
      // Séparateur virtuel entre blocs : simplifie la recherche multi-blocs.
      buffer.write('\n');
      offset += 1;
    }
    text = buffer.toString();
    for (final b in this.blocks) {
      if (b is TextBlock) {
        for (final (id, local) in b.anchors) {
          anchors[id] = b.start + local;
        }
      }
    }
  }

  final int index;
  final String title;
  final List<FlowBlock> blocks;
  late final String text;
  final Map<String, int> anchors = {};

  int get length => text.length;

  /// Bloc contenant l'offset donné (recherche dichotomique).
  int blockIndexAt(int offset) {
    var lo = 0, hi = blocks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (blocks[mid].start <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  static List<FlowBlock> _normalize(List<FlowBlock> blocks) =>
      blocks.where((b) => b is! TextBlock || b.plainText.trim().isNotEmpty).toList();
}

class TocEntry {
  const TocEntry({required this.title, required this.chapter, this.anchor, this.level = 0});
  final String title;
  final int chapter;
  final String? anchor;
  final int level;
}

/// Livre reflowable ouvert. Les chapitres sont chargés à la demande pour
/// limiter la mémoire sur les gros livres.
abstract class ReflowableBook {
  int get chapterCount;
  List<TocEntry> get toc;

  /// Poids relatif de chaque chapitre (taille source), pour la progression globale.
  List<double> get chapterWeights;

  Future<FlowChapter> loadChapter(int index);
  Future<Uint8List?> loadResource(String key);

  /// Résout un lien interne (`chapitre.xhtml#ancre`) vers un chapitre + ancre.
  (int, String?)? resolveLink(int fromChapter, String href) => null;

  Future<void> close();
}

/// Implémentation simple quand tout le contenu est déjà en mémoire
/// (TXT, Markdown, HTML, FB2, DOCX).
class MemoryReflowableBook extends ReflowableBook {
  MemoryReflowableBook({required this.chapters, List<TocEntry>? toc, this.resources = const {}})
      : toc = toc ??
            [
              for (final c in chapters)
                if (c.title.isNotEmpty) TocEntry(title: c.title, chapter: c.index),
            ];

  final List<FlowChapter> chapters;
  final Map<String, Uint8List> resources;

  @override
  final List<TocEntry> toc;

  @override
  int get chapterCount => chapters.length;

  @override
  List<double> get chapterWeights => [for (final c in chapters) c.length.toDouble().clamp(1, double.infinity)];

  @override
  Future<FlowChapter> loadChapter(int index) async => chapters[index];

  @override
  Future<Uint8List?> loadResource(String key) async => resources[key];

  @override
  (int, String?)? resolveLink(int fromChapter, String href) {
    if (!href.startsWith('#')) return null;
    final id = href.substring(1);
    for (final c in chapters) {
      if (c.anchors.containsKey(id)) return (c.index, id);
    }
    return null;
  }

  @override
  Future<void> close() async {}
}
