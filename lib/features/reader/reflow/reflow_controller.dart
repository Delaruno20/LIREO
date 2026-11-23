import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../../core/errors.dart';
import '../../../data/models/book.dart';
import '../../../formats/document/flow_document.dart';
import 'page_layout.dart';

/// Adresse d'une page : chapitre + index de page dans le chapitre.
typedef PageRef = ({int chapter, int page});

/// État de lecture d'un livre reflowable : chargement des chapitres,
/// pagination à la demande, navigation et progression.
///
/// Seuls quelques chapitres paginés sont gardés en mémoire (LRU).
class ReflowController extends ChangeNotifier {
  ReflowController(this.book, {this.linkColor});

  final ReflowableBook book;
  final Color? linkColor;

  LayoutSpec? _spec;
  final _layouts = <int, ChapterLayout>{};
  final _pending = <int, Future<ChapterLayout>>{};
  static const _maxCached = 4;

  int chapter = 0;
  int page = 0;
  bool ready = false;
  Object? error;

  /// Position conservée lors des changements de mise en page.
  BookLocation _anchor = BookLocation.start;

  late final List<double> _cumulative = () {
    final w = book.chapterWeights;
    final total = w.fold<double>(0, (a, b) => a + b);
    var acc = 0.0;
    return [
      for (final x in w)
        () {
          final v = acc / total;
          acc += x;
          return v;
        }(),
      1.0,
    ];
  }();

  LayoutSpec? get spec => _spec;
  ChapterLayout? layoutOf(int c) => _layouts[c];
  ChapterLayout? get current => _layouts[chapter];
  PageLayout? get currentPage {
    final l = current;
    if (l == null || l.pages.isEmpty) return null;
    return l.pages[page.clamp(0, l.pages.length - 1)];
  }

  BookLocation get locator {
    final p = currentPage;
    return p == null ? _anchor : BookLocation(chapter: chapter, offset: p.start);
  }

  double progressAt(int c, int offset) {
    if (c >= book.chapterCount) return 1;
    final layout = _layouts[c];
    final len = layout?.chapter.length ?? 1;
    final within = len <= 1 ? 0.0 : (offset / len).clamp(0.0, 1.0);
    return _cumulative[c] + (_cumulative[c + 1] - _cumulative[c]) * within;
  }

  double get progress {
    final p = currentPage;
    if (p == null) return progressAt(_anchor.chapter, _anchor.offset);
    final isLast = chapter == book.chapterCount - 1 && page >= (current?.pages.length ?? 1) - 1;
    return isLast ? 1.0 : progressAt(chapter, p.start);
  }

  String get chapterTitle {
    final title = current?.chapter.title ?? '';
    if (title.isNotEmpty) return title;
    for (final t in book.toc.reversed) {
      if (t.chapter <= chapter) return t.title;
    }
    return '';
  }

  /// Ouvre le livre à une position.
  Future<void> open(BookLocation at) async {
    _anchor = BookLocation(chapter: at.chapter.clamp(0, book.chapterCount - 1), offset: at.offset);
    if (_spec != null) await _goToAnchor();
  }

  /// Applique une nouvelle mise en page (taille, typographie) en conservant la position.
  Future<void> setSpec(LayoutSpec spec) async {
    if (spec == _spec) return;
    if (ready) _anchor = locator;
    _spec = spec;
    // Les anciennes pages restent affichables jusqu'à ce que les nouvelles soient prêtes.
    final retired = _layouts.values.toList();
    _layouts.clear();
    await _goToAnchor();
    for (final l in retired) {
      l.dispose();
    }
  }

  Future<void> _goToAnchor() async {
    try {
      final layout = await layoutFor(_anchor.chapter);
      chapter = _anchor.chapter;
      page = layout.pageFor(_anchor.offset);
      ready = true;
      error = null;
      notifyListeners();
      _preloadNeighbours();
    } catch (e, st) {
      AppError.report(e, st, context: 'layout');
      error = e;
      notifyListeners();
    }
  }

  Future<ChapterLayout> layoutFor(int c) {
    final cached = _layouts[c];
    if (cached != null) {
      _layouts
        ..remove(c)
        ..[c] = cached;
      return Future.value(cached);
    }
    final existing = _pending[c];
    if (existing != null) return existing;
    late final Future<ChapterLayout> future;
    future = _build(c).whenComplete(() {
      if (identical(_pending[c], future)) _pending.remove(c);
    });
    _pending[c] = future;
    return future;
  }

  Future<ChapterLayout> _build(int c) async {
    final spec = _spec!;
    final flow = await book.loadChapter(c);
    final layout = await Paginator(spec, linkColor: linkColor).layout(flow, _loadImage);
    if (spec != _spec) {
      layout.dispose();
      _pending.remove(c);
      return layoutFor(c);
    }
    _layouts[c] = layout;
    while (_layouts.length > _maxCached) {
      final victim = _layouts.keys.firstWhere((k) => (k - chapter).abs() > 1, orElse: () => -1);
      if (victim < 0) break;
      _layouts.remove(victim)!.dispose();
    }
    return layout;
  }

  Future<ui.Image?> _loadImage(String key, int maxWidth) async {
    try {
      final bytes = await book.loadResource(key);
      if (bytes == null || bytes.isEmpty) return null;
      final probe = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(probe);
      final targetWidth = descriptor.width > maxWidth ? maxWidth : null;
      final codec = await descriptor.instantiateCodec(targetWidth: targetWidth);
      final frame = await codec.getNextFrame();
      codec.dispose();
      descriptor.dispose();
      probe.dispose();
      return frame.image;
    } catch (_) {
      return null; // image corrompue ou format non décodable : ignorée
    }
  }

  void _preloadNeighbours() {
    if (chapter + 1 < book.chapterCount) unawaited(layoutFor(chapter + 1).catchError((_) => current!));
    if (chapter > 0) unawaited(layoutFor(chapter - 1).catchError((_) => current!));
  }

  /// Page voisine si elle est déjà paginée (sinon null, et préchargement).
  PageRef? neighbour(int delta, {PageRef? from}) {
    var c = from?.chapter ?? chapter;
    var p = (from?.page ?? page) + delta;
    var layout = _layouts[c];
    if (layout == null) return null;
    while (p >= layout!.pages.length) {
      p -= layout.pages.length;
      c++;
      if (c >= book.chapterCount) return null;
      layout = _layouts[c];
      if (layout == null) {
        unawaited(layoutFor(c).then((_) => notifyListeners(), onError: (_) {}));
        return null;
      }
    }
    while (p < 0) {
      c--;
      if (c < 0) return null;
      layout = _layouts[c];
      if (layout == null) {
        unawaited(layoutFor(c).then((_) => notifyListeners(), onError: (_) {}));
        return null;
      }
      p += layout.pages.length;
    }
    return (chapter: c, page: p);
  }

  PageLayout? pageAt(PageRef? ref) {
    if (ref == null) return null;
    final l = _layouts[ref.chapter];
    if (l == null || ref.page < 0 || ref.page >= l.pages.length) return null;
    return l.pages[ref.page];
  }

  bool get canGoNext => chapter < book.chapterCount - 1 || page < (current?.pages.length ?? 1) - 1;
  bool get canGoPrevious => chapter > 0 || page > 0;

  /// Avance/recule de [delta] pages. Retourne false en début/fin de livre.
  Future<bool> turn(int delta) async {
    var ref = neighbour(delta);
    if (ref == null) {
      final targetChapter = delta > 0 ? chapter + 1 : chapter - 1;
      if (targetChapter < 0 || targetChapter >= book.chapterCount) {
        if (delta > 0 && page < (current?.pages.length ?? 1) - 1) {
          page = current!.pages.length - 1;
          notifyListeners();
          return true;
        }
        return false;
      }
      final l = await layoutFor(targetChapter);
      ref = (chapter: targetChapter, page: delta > 0 ? 0 : l.pages.length - 1);
    }
    final changedChapter = ref.chapter != chapter;
    chapter = ref.chapter;
    page = ref.page;
    notifyListeners();
    if (changedChapter) _preloadNeighbours();
    return true;
  }

  Future<void> goTo(BookLocation at) async {
    _anchor = at;
    await _goToAnchor();
  }

  Future<void> goToChapter(int c, {String? anchor}) async {
    final layout = await layoutFor(c);
    final offset = anchor == null ? 0 : (layout.chapter.anchors[anchor] ?? 0);
    await goTo(BookLocation(chapter: c, offset: offset));
  }

  /// Saut à une progression globale (0..1), via les poids des chapitres.
  Future<void> goToProgress(double value) async {
    var c = 0;
    while (c < book.chapterCount - 1 && _cumulative[c + 1] <= value) {
      c++;
    }
    final span = _cumulative[c + 1] - _cumulative[c];
    final within = span <= 0 ? 0.0 : ((value - _cumulative[c]) / span).clamp(0.0, 1.0);
    final layout = await layoutFor(c);
    await goTo(BookLocation(chapter: c, offset: (layout.chapter.length * within).round()));
  }

  void _clear() {
    for (final l in _layouts.values) {
      l.dispose();
    }
    _layouts.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }
}
