import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design/tokens.dart';
import '../../../core/errors.dart';
import '../../../data/models/book.dart';
import '../../../data/models/library_models.dart';
import '../../../data/repositories/annotation_repository.dart';
import '../../../data/settings/app_settings.dart';
import '../../../formats/document/flow_document.dart';
import '../../../formats/document/note_excerpt.dart';
import '../model/reader_prefs.dart';
import '../session/reading_tracker.dart';
import '../tts/tts_controller.dart';
import '../widgets/annotations_screen.dart';
import '../widgets/reader_behaviors.dart';
import '../widgets/reader_chrome.dart';
import '../widgets/reader_settings_panel.dart';
import '../widgets/reader_sheets.dart';
import 'page_layout.dart';
import 'page_painter.dart';
import 'page_turner.dart';
import 'reflow_controller.dart';

/// Lecteur des formats reflowables (EPUB, MOBI, FB2, DOCX, TXT, HTML, MD).
class ReflowReaderView extends StatefulWidget {
  const ReflowReaderView({
    super.key,
    required this.book,
    required this.document,
    required this.prefs,
    required this.scope,
    required this.tracker,
    required this.onPrefsChanged,
    required this.onOpenDetails,
  });

  final Book book;
  final ReflowableBook document;
  final ReaderPrefs prefs;
  final PrefsScope scope;
  final ReadingTracker tracker;
  final void Function(ReaderPrefs prefs, PrefsScope scope) onPrefsChanged;
  final VoidCallback onOpenDetails;

  @override
  State<ReflowReaderView> createState() => _ReflowReaderViewState();
}

class _Selection {
  _Selection(this.chapter, this.anchor, this.start, this.end);
  final int chapter;
  final int anchor;
  int start;
  int end;
}

class _ReflowReaderViewState extends State<ReflowReaderView> with ReaderBehaviors, TickerProviderStateMixin {
  late final ReflowController _controller;
  late TtsController _tts;
  final _turnerKey = GlobalKey<PageTurnerState>();
  final _focus = FocusNode();
  late ReaderPrefs _prefs = widget.prefs;
  late PrefsScope _scope = widget.scope;

  List<Annotation> _annotations = const [];
  final _pictures = <String, ui.Picture>{};
  int _decorVersion = 0;

  _Selection? _selection;
  bool _selecting = false;
  (int, int, int)? _searchHit; // chapitre, début, fin
  Timer? _searchTimer;
  double? _pinchSize;
  bool _doublePage = false;
  Size _viewport = Size.zero;
  BookLocation? _lastSaved;

  // Mode défilement.
  final _scroll = ScrollController();
  final _scrollRefs = <PageRef>[];
  bool _appending = false;
  Ticker? _autoScroll;
  Duration _lastTick = Duration.zero;

  bool get _scrollMode => _prefs.animation == PageAnimation.scroll;

  @override
  void initState() {
    super.initState();
    _controller = ReflowController(widget.document, linkColor: null)..addListener(_onPosition);
    _controller.open(widget.book.locator);
    _tts = TtsController(
      settings: context.read<AppSettings>(),
      loadChapter: widget.document.loadChapter,
      chapterCount: widget.document.chapterCount,
      language: widget.book.language,
    )..addListener(_onTts);
    _loadAnnotations();
  }

  @override
  void didUpdateWidget(ReflowReaderView old) {
    super.didUpdateWidget(old);
    if (old.prefs != widget.prefs) _prefs = widget.prefs;
  }

  Future<void> _loadAnnotations() async {
    final list = await context.read<AnnotationRepository>().forBook(widget.book.id!);
    if (!mounted) return;
    setState(() {
      _annotations = list;
      _invalidatePictures();
    });
  }

  void _invalidatePictures() {
    for (final p in _pictures.values) {
      p.dispose();
    }
    _pictures.clear();
    _decorVersion++;
  }

  void _onPosition() {
    if (!_controller.ready) return setState(() {});
    final loc = _controller.locator;
    if (loc != _lastSaved) {
      _lastSaved = loc;
      widget.tracker.updatePosition(loc, _controller.progress);
    }
    _trimPictures();
    setState(() {});
  }

  void _trimPictures() {
    if (_pictures.length < 14) return;
    final keep = <String>{};
    for (var d = -2; d <= 3; d++) {
      final ref = d == 0 ? (chapter: _controller.chapter, page: _controller.page) : _controller.neighbour(d);
      if (ref != null) keep.add('${ref.chapter}:${ref.page}');
    }
    _pictures.removeWhere((k, v) {
      final base = k.split('@').first;
      if (keep.contains(base) || keep.any((x) => k.startsWith('spread:$x'))) return false;
      v.dispose();
      return true;
    });
  }

  // ------------------------------------------------------------- rendu

  LayoutSpec _specFor(Size size) {
    _doublePage = !_scrollMode &&
        (_prefs.doublePage == DoublePageMode.always ||
            (_prefs.doublePage == DoublePageMode.auto && size.width > size.height && size.width >= 720));
    final pageSize = _doublePage ? Size(size.width / 2, size.height) : size;
    return LayoutSpec(
      pageSize: _scrollMode ? Size(size.width, size.height * 2) : pageSize,
      prefs: _prefs,
      textScaler: TextScaler.noScaling,
      footerHeight: _prefs.showProgressFooter && !_scrollMode ? PagePainter.footerHeight : 0,
      continuous: _scrollMode,
    );
  }

  PageDecor _decorFor(PageLayout page) {
    final layout = _controller.layoutOf(page.chapter);
    final total = layout?.pages.length ?? 1;
    final bookmarked = _annotations.any((a) => a.kind == AnnotationKind.bookmark && a.start.chapter == page.chapter && page.contains(a.start.offset));
    final title = layout?.chapter.title.isNotEmpty == true ? layout!.chapter.title : widget.book.title;
    return PageDecor(
      highlights: [for (final a in _annotations) if (a.kind != AnnotationKind.bookmark) a],
      bookmarked: bookmarked,
      footerLeft: title,
      footerRight: '${page.index + 1} / $total  ·  ${(_controller.progressAt(page.chapter, page.start) * 100).round()} %',
      accent: Theme.of(context).colorScheme.primary,
    );
  }

  ui.Picture? _pictureFor(PageRef? ref, Size pageSize) {
    final page = _controller.pageAt(ref);
    if (page == null) return null;
    final key = '${ref!.chapter}:${ref.page}@$_decorVersion';
    return _pictures[key] ??= PagePainter.record(page, pageSize, _prefs, _decorFor(page));
  }

  PageRef? _ref(int delta) {
    if (delta == 0) return (chapter: _controller.chapter, page: _controller.page);
    return _controller.neighbour(_doublePage ? delta * 2 : delta);
  }

  ui.Picture? _pictureAt(int delta) {
    final size = _viewport;
    if (!_doublePage) return _pictureFor(_ref(delta), size);
    final left = _ref(delta);
    if (left == null) return null;
    final right = _controller.neighbour(1, from: left);
    final key = 'spread:${left.chapter}:${left.page}@$_decorVersion';
    final cached = _pictures[key];
    if (cached != null) return cached;
    final half = Size(size.width / 2, size.height);
    final l = _pictureFor(left, half);
    if (l == null) return null;
    final r = right == null ? null : _pictureFor(right, half);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Offset.zero & size, Paint()..color = _prefs.background);
    canvas.drawPicture(l);
    if (r != null) {
      canvas.save();
      canvas.translate(half.width, 0);
      canvas.drawPicture(r);
      canvas.restore();
    }
    // Ombre de reliure au centre.
    final gutter = Rect.fromLTWH(half.width - 18, 0, 36, size.height);
    canvas.drawRect(
      gutter,
      Paint()
        ..shader = ui.Gradient.linear(gutter.centerLeft, gutter.centerRight, [
          Colors.black.withValues(alpha: 0),
          Colors.black.withValues(alpha: _prefs.isDarkSurface ? 0.35 : 0.12),
          Colors.black.withValues(alpha: 0),
        ]),
    );
    return _pictures[key] = recorder.endRecording();
  }

  /// Pages visibles avec leur décalage horizontal (1 ou 2 en mode double).
  List<(PageLayout, double)> get _visiblePages {
    final first = _controller.currentPage;
    if (first == null) return const [];
    final out = [(first, 0.0)];
    if (_doublePage) {
      final second = _controller.pageAt(_controller.neighbour(1));
      if (second != null) out.add((second, _viewport.width / 2));
    }
    return out;
  }

  (PageLayout, Offset)? _hit(Offset pos) {
    for (final (page, dx) in _visiblePages.reversed) {
      if (pos.dx >= dx) return (page, pos - Offset(dx, 0));
    }
    return null;
  }

  // ------------------------------------------------------------- navigation

  Future<bool> _commit(int delta) async {
    final ok = await _controller.turn(_doublePage ? delta * 2 : delta);
    if (ok) {
      widget.tracker.pageTurned(delta);
      haptic();
    } else if (delta > 0 && !_controller.canGoNext) {
      showHud('Fin du livre');
    }
    return ok;
  }

  void haptic() {
    if (context.read<AppSettings>().hapticsEnabled) HapticFeedback.selectionClick();
  }

  void _turn(int delta) {
    _clearSelection();
    if (_scrollMode) {
      final h = _viewport.height * 0.85;
      _scroll.animateTo((_scroll.offset + delta * h).clamp(0, _scroll.position.maxScrollExtent),
          duration: Motion.scaled(context, Motion.medium), curve: Motion.curve);
      return;
    }
    _turnerKey.currentState?.turn(delta);
  }

  Future<void> _goTo(BookLocation l) async {
    _clearSelection();
    await _controller.goTo(l);
    if (_scrollMode) _resetScroll();
  }

  void _runAction(ReaderAction a) {
    switch (a) {
      case ReaderAction.previousPage:
        _turn(-1);
      case ReaderAction.nextPage:
        _turn(1);
      case ReaderAction.toggleControls:
        toggleChrome();
      case ReaderAction.bookmark:
        _toggleBookmark();
      case ReaderAction.none:
        break;
    }
  }

  void _onTap(TapUpDetails d, Size size) {
    widget.tracker.activity();
    if (_selection != null) return _clearSelection();
    if (chromeVisible) return showChrome(false);
    final hit = _hit(d.localPosition);
    if (hit != null) {
      final (page, local) = hit;
      final href = page.linkAt(local);
      if (href != null) {
        _openLink(page.chapter, href);
        return;
      }
      final offset = page.offsetAt(local);
      if (offset != null) {
        final h = _annotations.where((a) =>
            a.kind != AnnotationKind.bookmark && a.start.chapter == page.chapter && offset >= a.start.offset && offset < a.end.offset);
        if (h.isNotEmpty && page.rectsFor(h.first.start.offset, h.first.end.offset).any((r) => r.inflate(2).contains(local))) {
          _editAnnotation(h.first);
          return;
        }
      }
    }
    final x = d.localPosition.dx / size.width;
    _runAction(x < 0.3 ? _prefs.leftTap : (x > 0.7 ? _prefs.rightTap : _prefs.centerTap));
  }

  Future<void> _openLink(int chapter, String href) async {
    final target = widget.document.resolveLink(chapter, href);
    if (target != null) {
      final (c, anchor) = target;
      // Note ou définition : affichée par-dessus la page courante.
      if (anchor != null) {
        List<List<InlineRun>>? note;
        try {
          note = noteExcerpt(await widget.document.loadChapter(c), anchor);
        } catch (_) {}
        if (note != null) {
          if (!mounted) return;
          final go = await showNoteSheet(context, note, _prefs);
          if (go != true) return;
        }
      }
      await _controller.goToChapter(c, anchor: anchor);
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto')) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ouvrir le lien ?'),
        content: Text(href),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ouvrir')),
        ],
      ),
    );
    if (ok == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ------------------------------------------------------------- sélection

  static bool _isWordChar(int c) {
    final ch = String.fromCharCode(c);
    return RegExp(r"[\p{L}\p{N}'’-]", unicode: true).hasMatch(ch);
  }

  (int, int) _wordAt(String text, int offset) {
    var s = math.min(math.max(offset, 0), math.max(0, text.length - 1));
    var e = s;
    while (s > 0 && _isWordChar(text.codeUnitAt(s - 1))) {
      s--;
    }
    while (e < text.length && _isWordChar(text.codeUnitAt(e))) {
      e++;
    }
    if (e == s) e = math.min(text.length, s + 1);
    return (s, e);
  }

  void _onLongPressStart(Offset pos) {
    final hit = _hit(pos);
    if (hit == null) return;
    final (page, local) = hit;
    final offset = page.offsetAt(local);
    final layout = _controller.layoutOf(page.chapter);
    if (offset == null || layout == null) return;
    final (s, e) = _wordAt(layout.chapter.text, offset);
    HapticFeedback.mediumImpact();
    setState(() {
      _selection = _Selection(page.chapter, s, s, e);
      _selecting = true;
    });
  }

  void _onLongPressMove(Offset pos) {
    final sel = _selection;
    final hit = _hit(pos);
    if (sel == null || hit == null) return;
    final (page, local) = hit;
    if (page.chapter != sel.chapter) return;
    final offset = page.offsetAt(local);
    final layout = _controller.layoutOf(page.chapter);
    if (offset == null || layout == null) return;
    final (ws, we) = _wordAt(layout.chapter.text, offset);
    setState(() {
      if (offset < sel.anchor) {
        sel.start = ws;
        sel.end = _wordAt(layout.chapter.text, sel.anchor).$2;
      } else {
        sel.start = _wordAt(layout.chapter.text, sel.anchor).$1;
        sel.end = we;
      }
    });
  }

  void _onLongPressEnd() => setState(() => _selecting = false);

  void _clearSelection() {
    if (_selection != null) setState(() => _selection = null);
  }

  String get _selectedText {
    final s = _selection;
    final layout = s == null ? null : _controller.layoutOf(s.chapter);
    if (s == null || layout == null) return '';
    return layout.chapter.text.substring(s.start, math.min(s.end, layout.chapter.text.length)).trim();
  }

  Future<void> _addHighlight(int color, {String note = ''}) async {
    final s = _selection;
    if (s == null) return;
    final text = _selectedText;
    final a = await context.read<AnnotationRepository>().add(Annotation(
          bookId: widget.book.id!,
          kind: note.isEmpty ? AnnotationKind.highlight : AnnotationKind.note,
          start: BookLocation(chapter: s.chapter, offset: s.start),
          end: BookLocation(chapter: s.chapter, offset: s.end),
          text: text,
          note: note,
          color: color,
          createdAt: DateTime.now(),
          chapterTitle: _controller.layoutOf(s.chapter)?.chapter.title ?? '',
          progress: _controller.progressAt(s.chapter, s.start),
        ));
    setState(() {
      _annotations = [..._annotations, a];
      _selection = null;
      _invalidatePictures();
    });
  }

  Future<String?> _askNote({String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          minLines: 2,
          decoration: const InputDecoration(hintText: 'Votre réflexion sur ce passage'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
  }

  Future<void> _editAnnotation(Annotation a) async {
    final repo = context.read<AnnotationRepository>();
    final action = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Text(a.text, maxLines: 4, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
            ),
            const SizedBox(height: Space.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Row(children: [
                for (final c in highlightColors)
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, c),
                    child: Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: c == a.color ? Theme.of(ctx).colorScheme.onSurface : Colors.transparent, width: 2),
                      ),
                    ),
                  ),
              ]),
            ),
            ListTile(leading: const Icon(Icons.edit_note_rounded), title: Text(a.note.isEmpty ? 'Ajouter une note' : 'Modifier la note'), onTap: () => Navigator.pop(ctx, 'note')),
            ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('Copier'), onTap: () => Navigator.pop(ctx, 'copy')),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error),
              title: Text('Supprimer', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    Annotation? updated;
    switch (action) {
      case int color:
        updated = a.copyWith(color: color);
      case 'note':
        final note = await _askNote(initial: a.note);
        if (note != null) updated = a.copyWith(note: note, kind: note.isEmpty ? AnnotationKind.highlight : AnnotationKind.note);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: a.text));
        AppError.toast('Passage copié');
      case 'delete':
        await repo.delete(a);
        setState(() {
          _annotations = _annotations.where((x) => x.id != a.id).toList();
          _invalidatePictures();
        });
    }
    if (updated != null) {
      await repo.update(updated);
      setState(() {
        _annotations = [for (final x in _annotations) x.id == updated!.id ? updated : x];
        _invalidatePictures();
      });
    }
  }

  Future<void> _toggleBookmark() async {
    final page = _controller.currentPage;
    if (page == null) return;
    final repo = context.read<AnnotationRepository>();
    final existing = _annotations
        .where((a) => a.kind == AnnotationKind.bookmark && a.start.chapter == page.chapter && page.contains(a.start.offset))
        .toList();
    if (existing.isNotEmpty) {
      for (final a in existing) {
        await repo.delete(a);
      }
      _annotations = _annotations.where((a) => !existing.contains(a)).toList();
      showHud('Marque-page retiré');
    } else {
      final layout = _controller.current!;
      final excerpt = layout.chapter.text.substring(page.start, math.min(page.end, page.start + 140)).replaceAll('\n', ' ').trim();
      final a = await repo.add(Annotation(
        bookId: widget.book.id!,
        kind: AnnotationKind.bookmark,
        start: BookLocation(chapter: page.chapter, offset: page.start),
        text: excerpt,
        createdAt: DateTime.now(),
        chapterTitle: _controller.chapterTitle,
        progress: _controller.progress,
      ));
      _annotations = [..._annotations, a];
      showHud('Marque-page ajouté');
    }
    HapticFeedback.lightImpact();
    setState(_invalidatePictures);
  }

  // ------------------------------------------------------------- TTS

  void _onTts() {
    if (!mounted) return;
    final s = _tts.sentence;
    if (_tts.active && s != null && !_scrollMode) {
      final page = _controller.currentPage;
      if (page != null && (_tts.chapter != page.chapter || s.$1 >= page.end || s.$1 < page.start)) {
        final next = _controller.pageAt(_controller.neighbour(1));
        if (next != null && next.chapter == _tts.chapter && next.contains(s.$1)) {
          _turnerKey.currentState?.turn(1);
        } else {
          _controller.goTo(BookLocation(chapter: _tts.chapter, offset: s.$1));
        }
      }
    }
    widget.tracker.activity();
    setState(() {});
  }

  Future<void> _startTts([int? fromOffset]) async {
    final page = _controller.currentPage;
    if (page == null) return;
    await _tts.start(page.chapter, fromOffset ?? page.start);
    showChrome(false);
  }

  // ------------------------------------------------------------- défilement continu

  void _resetScroll() {
    _scrollRefs
      ..clear()
      ..addAll([for (var i = 0; i < (_controller.current?.pages.length ?? 0); i++) (chapter: _controller.chapter, page: i)]);
    final idx = _controller.page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      var offset = 0.0;
      for (var i = 0; i < idx && i < _scrollRefs.length; i++) {
        offset += _extent(i);
      }
      _scroll.jumpTo(offset);
    });
    setState(() {});
  }

  double _extent(int i) {
    final page = _controller.pageAt(_scrollRefs[i]);
    if (page == null) return 0;
    final first = i == 0 || _scrollRefs[i - 1].chapter != _scrollRefs[i].chapter;
    return page.usedHeight + (first ? _prefs.marginV * 2 + 40 : 0);
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (_scrollRefs.isEmpty) return false;
    widget.tracker.activity();
    // Page en haut de l'écran → position de lecture.
    var acc = 0.0;
    for (var i = 0; i < _scrollRefs.length; i++) {
      final e = _extent(i);
      if (acc + e > n.metrics.pixels + 1) {
        final ref = _scrollRefs[i];
        if (ref.chapter != _controller.chapter || ref.page != _controller.page) {
          _controller
            ..chapter = ref.chapter
            ..page = ref.page;
          _onPosition();
        }
        break;
      }
      acc += e;
    }
    if (n.metrics.extentAfter < _viewport.height * 1.5) _appendNextChapter();
    return false;
  }

  Future<void> _appendNextChapter() async {
    if (_appending || _scrollRefs.isEmpty) return;
    final next = _scrollRefs.last.chapter + 1;
    if (next >= widget.document.chapterCount) return;
    _appending = true;
    try {
      final layout = await _controller.layoutFor(next);
      if (!mounted) return;
      setState(() => _scrollRefs.addAll([for (var i = 0; i < layout.pages.length; i++) (chapter: next, page: i)]));
    } finally {
      _appending = false;
    }
  }

  void _toggleAutoScroll() {
    if (_autoScroll != null) {
      _autoScroll!.dispose();
      setState(() => _autoScroll = null);
      return;
    }
    _lastTick = Duration.zero;
    _autoScroll = createTicker((elapsed) {
      final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
      _lastTick = elapsed;
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      final target = math.min(max, _scroll.offset + _prefs.autoScrollSpeed * dt);
      _scroll.jumpTo(target);
    })
      ..start();
    showChrome(false);
    setState(() {});
  }

  // ------------------------------------------------------------- réglages

  void _applyPrefs(ReaderPrefs p) {
    final modeChanged = (p.animation == PageAnimation.scroll) != _scrollMode;
    setState(() {
      _prefs = p;
      _invalidatePictures();
    });
    widget.onPrefsChanged(p, _scope);
    if (modeChanged) {
      _autoScroll?.dispose();
      _autoScroll = null;
    }
  }

  Future<void> _openSettings() async {
    showChrome(false);
    await ReaderSettingsPanel.show(
      context,
      prefs: _prefs,
      onChanged: _applyPrefs,
      scope: _scope,
      onScopeChanged: (s) {
        _scope = s;
        widget.onPrefsChanged(_prefs, s);
      },
      format: widget.book.format,
    );
  }

  Future<void> _openToc() async {
    final toc = widget.document.toc.isNotEmpty
        ? widget.document.toc
        : [for (var i = 0; i < widget.document.chapterCount; i++) TocEntry(title: 'Section ${i + 1}', chapter: i)];
    final entry = await showTocSheet(context, toc: toc, currentChapter: _controller.chapter);
    if (entry == null) return;
    await _controller.goToChapter(entry.chapter, anchor: entry.anchor);
    if (_scrollMode) _resetScroll();
    showChrome(false);
  }

  Future<void> _openSearch([String query = '']) async {
    final hit = await showModalBottomSheet<SearchHit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BookSearchSheet(book: widget.document, initialQuery: query),
    );
    if (hit == null) return;
    await _goTo(hit.locator);
    _searchTimer?.cancel();
    setState(() => _searchHit = (hit.chapter, hit.offset, hit.offset + hit.length));
    _searchTimer = Timer(const Duration(seconds: 5), () => mounted ? setState(() => _searchHit = null) : null);
    showChrome(false);
  }

  Future<void> _openAnnotations() async {
    final loc = await Navigator.of(context).push<BookLocation>(
      MaterialPageRoute(builder: (_) => AnnotationsScreen(book: widget.book, fromReader: true)),
    );
    await _loadAnnotations();
    if (loc != null) await _goTo(loc);
    showChrome(false);
  }

  @override
  void dispose() {
    _controller.removeListener(_onPosition);
    _controller.dispose();
    _tts.removeListener(_onTts);
    _tts.dispose();
    _autoScroll?.dispose();
    _scroll.dispose();
    _searchTimer?.cancel();
    _focus.dispose();
    _invalidatePictures();
    disposeBehaviors();
    super.dispose();
  }

  // ------------------------------------------------------------- build

  List<OverlayRange> _rangesFor(PageLayout page) {
    final accent = Theme.of(context).colorScheme.primary;
    final out = <OverlayRange>[];
    final s = _selection;
    if (s != null && s.chapter == page.chapter) out.add(OverlayRange(s.start, s.end, accent.withValues(alpha: 0.28)));
    final h = _searchHit;
    if (h != null && h.$1 == page.chapter) out.add(OverlayRange(h.$2, h.$3, accent.withValues(alpha: 0.4)));
    if (_tts.active && _tts.chapter == page.chapter) {
      final sentence = _tts.sentence;
      if (sentence != null) out.add(OverlayRange(sentence.$1, sentence.$2, accent.withValues(alpha: 0.1)));
      final word = _tts.word;
      if (word != null) out.add(OverlayRange(word.$1, word.$2, accent, underline: true));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final fg = _prefs.textColor;
    final bg = _prefs.background;
    final accent = Theme.of(context).colorScheme.primary;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, e) => handleKey(e, _prefs, _turn),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _prefs.isDarkSurface ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Material(
          color: bg,
          child: LayoutBuilder(builder: (context, constraints) {
            final size = constraints.biggest;
            final spec = _specFor(size);
            if (spec != _controller.spec || size != _viewport) {
              _viewport = size;
              _invalidatePictures();
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await _controller.setSpec(spec);
                if (!mounted) return;
                // Les pages enregistrées pendant le recalcul utilisaient l'ancienne mise en page.
                setState(_invalidatePictures);
                if (_scrollMode) _resetScroll();
              });
            }
            Widget reading;
            if (_controller.error != null) {
              reading = Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Text('Impossible d\'afficher ce chapitre.\n${AppError.describe(_controller.error!)}',
                      textAlign: TextAlign.center, style: TextStyle(color: fg)),
                ),
              );
            } else if (!_controller.ready) {
              reading = Center(child: CircularProgressIndicator(color: accent));
            } else if (_scrollMode) {
              reading = _buildScroll(size);
            } else {
              reading = PageTurner(
                key: _turnerKey,
                animation: _doublePage && _prefs.animation == PageAnimation.curl ? PageAnimation.slide : _prefs.animation,
                speed: _prefs.animationSpeed,
                curlShadow: _prefs.curlShadow,
                background: bg,
                pictureAt: _pictureAt,
                onCommit: _commit,
                overlay: CustomPaint(painter: _OverlayPainter([for (final (p, dx) in _visiblePages) (p, dx, _rangesFor(p))])),
                onTapUp: _onTap,
                onLongPressStart: _onLongPressStart,
                onLongPressMove: _onLongPressMove,
                onLongPressEnd: _onLongPressEnd,
                onVerticalDrag: _prefs.brightnessSwipe ? adjustBrightness : null,
                onPinch: (scale) {
                  _pinchSize = (_prefs.fontSize * scale).clamp(12.0, 40.0).roundToDouble();
                  showHud('Taille ${_pinchSize!.round()}');
                },
                onPinchEnd: () {
                  if (_pinchSize != null && _pinchSize != _prefs.fontSize) _applyPrefs(_prefs.copyWith(fontSize: _pinchSize));
                  _pinchSize = null;
                },
              );
            }
            return Stack(
              children: [
                Positioned.fill(child: reading),
                if (_selection != null && !_selecting) _selectionToolbar(size),
                if (_tts.active) _ttsBar(fg, bg, accent),
                Positioned.fill(child: _chrome(fg, bg, accent)),
                Positioned.fill(child: buildHud(bg, fg)),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildScroll(Size size) {
    if (_scrollRefs.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _resetScroll() : null);
      return const SizedBox();
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        if (_autoScroll != null) return _toggleAutoScroll();
        toggleChrome();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ListView.builder(
          controller: _scroll,
          itemCount: _scrollRefs.length,
          itemExtentBuilder: (i, _) => i < _scrollRefs.length ? _extent(i) : null,
          itemBuilder: (context, i) {
            final ref = _scrollRefs[i];
            final page = _controller.pageAt(ref);
            if (page == null) return const SizedBox();
            final first = i == 0 || _scrollRefs[i - 1].chapter != ref.chapter;
            final key = 'scroll:${ref.chapter}:${ref.page}@$_decorVersion';
            final picture = _pictures[key] ??= PagePainter.record(page, Size(size.width, page.usedHeight), _prefs, PageDecor(
                  highlights: [for (final a in _annotations) if (a.kind != AnnotationKind.bookmark) a],
                ));
            return Padding(
              padding: EdgeInsets.only(top: first ? _prefs.marginV + 40 : 0, bottom: first ? _prefs.marginV : 0),
              child: CustomPaint(
                size: Size(size.width, page.usedHeight),
                painter: _ScrollPagePainter(picture, page, _rangesFor(page)),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _chrome(Color fg, Color bg, Color accent) {
    final page = _controller.currentPage;
    final total = _controller.current?.pages.length ?? 0;
    final bookmarked = page != null &&
        _annotations.any((a) => a.kind == AnnotationKind.bookmark && a.start.chapter == page.chapter && page.contains(a.start.offset));
    return ReaderChrome(
      visible: chromeVisible,
      background: bg,
      foreground: fg,
      accent: accent,
      title: widget.book.title,
      subtitle: _controller.chapterTitle,
      progress: _controller.progress,
      progressLabel: '${(_controller.progress * 100).toStringAsFixed(1)} % lu',
      positionLabel: page == null ? '' : 'Page ${page.index + 1} / $total du chapitre',
      onBack: () => Navigator.of(context).maybePop(),
      onInteraction: keepChrome,
      onSeek: (v) async {
        await _controller.goToProgress(v);
        if (_scrollMode) _resetScroll();
      },
      onPreviousSection: _controller.chapter > 0 ? () => _goTo(BookLocation(chapter: _controller.chapter - 1)) : null,
      onNextSection: _controller.chapter < widget.document.chapterCount - 1 ? () => _goTo(BookLocation(chapter: _controller.chapter + 1)) : null,
      topActions: [
        IconButton(tooltip: 'Rechercher', icon: const Icon(Icons.search_rounded), onPressed: () => _openSearch()),
        IconButton(
          tooltip: bookmarked ? 'Retirer le marque-page' : 'Ajouter un marque-page',
          icon: Icon(bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: bookmarked ? accent : null),
          onPressed: _toggleBookmark,
        ),
        PopupMenuButton<String>(
          tooltip: 'Plus',
          iconColor: fg,
          onSelected: (v) => switch (v) {
            'tts' => _startTts(),
            'auto' => _toggleAutoScroll(),
            'timer' => chooseSleepTimer(() {
                _tts.stop();
                if (_autoScroll != null) _toggleAutoScroll();
              }),
            'focus' => _applyPrefs(_prefs.copyWith(showProgressFooter: !_prefs.showProgressFooter)),
            'details' => widget.onOpenDetails(),
            _ => null,
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'tts', child: ListTile(leading: Icon(Icons.record_voice_over_outlined), title: Text('Lecture à voix haute'))),
            if (_scrollMode)
              PopupMenuItem(
                value: 'auto',
                child: ListTile(
                  leading: const Icon(Icons.slow_motion_video_rounded),
                  title: Text(_autoScroll == null ? 'Défilement automatique' : 'Arrêter le défilement'),
                ),
              ),
            PopupMenuItem(
              value: 'timer',
              child: ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(sleepAt == null ? 'Minuteur de lecture' : 'Minuteur (fin ${TimeOfDay.fromDateTime(sleepAt!).format(context)})'),
              ),
            ),
            PopupMenuItem(
              value: 'focus',
              child: ListTile(
                leading: const Icon(Icons.center_focus_strong_outlined),
                title: Text(_prefs.showProgressFooter ? 'Mode sans distraction' : 'Afficher la progression'),
              ),
            ),
            const PopupMenuItem(value: 'details', child: ListTile(leading: Icon(Icons.info_outline_rounded), title: Text('Fiche du livre'))),
          ],
        ),
      ],
      bottomActions: [
        IconButton(tooltip: 'Table des matières', icon: const Icon(Icons.format_list_bulleted_rounded), onPressed: _openToc),
        IconButton(tooltip: 'Annotations', icon: const Icon(Icons.bookmarks_outlined), onPressed: _openAnnotations),
        IconButton(
          tooltip: _prefs.isDarkSurface ? 'Mode jour' : 'Mode nuit',
          icon: Icon(_prefs.isDarkSurface ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          onPressed: () => _applyPrefs(_prefs.copyWith(surfaceId: _prefs.isDarkSurface ? 'paper' : 'night', clearCustomColors: true)),
        ),
        IconButton(tooltip: 'Réglages de lecture', icon: const Icon(Icons.text_fields_rounded), onPressed: _openSettings),
      ],
    );
  }

  Widget _selectionToolbar(Size size) {
    final s = _selection!;
    final rects = [for (final (p, dx) in _visiblePages) if (p.chapter == s.chapter) ...p.rectsFor(s.start, s.end).map((r) => r.shift(Offset(dx, 0)))];
    final top = rects.isEmpty ? size.height / 2 : rects.first.top;
    final placeBelow = top < 170;
    final y = placeBelow ? (rects.isEmpty ? 120.0 : rects.last.bottom + 12) : top - 112;
    final p = Theme.of(context).colorScheme;
    final text = _selectedText;
    final singleWord = !text.contains(RegExp(r'\s'));
    Widget action(IconData icon, String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 10.5, fontFamily: Fonts.ui)),
            ]),
          ),
        );
    return Positioned(
      left: 10,
      right: 10,
      top: y.clamp(60.0, size.height - 130),
      child: Center(
        child: Material(
          elevation: 8,
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final c in highlightColors)
                    GestureDetector(
                      onTap: () => _addHighlight(c),
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
                      ),
                    ),
                ]),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    action(Icons.edit_note_rounded, 'Note', () async {
                      final note = await _askNote();
                      if (note != null && note.isNotEmpty) await _addHighlight(highlightColors.first, note: note);
                    }),
                    action(Icons.copy_rounded, 'Copier', () {
                      Clipboard.setData(ClipboardData(text: text));
                      _clearSelection();
                      AppError.toast('Passage copié');
                    }),
                    action(Icons.ios_share_rounded, 'Partager', () {
                      SharePlus.instance.share(ShareParams(text: '« $text »\n— ${widget.book.title}${widget.book.author.isNotEmpty ? ', ${widget.book.author}' : ''}'));
                      _clearSelection();
                    }),
                    if (singleWord)
                      action(Icons.menu_book_rounded, 'Définir', () {
                        launchUrl(Uri.https('fr.wiktionary.org', '/wiki/${text.toLowerCase()}'), mode: LaunchMode.externalApplication);
                        _clearSelection();
                      }),
                    action(Icons.translate_rounded, 'Traduire', () {
                      launchUrl(Uri.https('translate.google.com', '/', {'sl': 'auto', 'tl': 'fr', 'text': text, 'op': 'translate'}),
                          mode: LaunchMode.externalApplication);
                      _clearSelection();
                    }),
                    action(Icons.search_rounded, 'Chercher', () {
                      _clearSelection();
                      _openSearch(text.length > 60 ? text.substring(0, 60) : text);
                    }),
                    action(Icons.record_voice_over_outlined, 'Lire', () {
                      final start = s.start;
                      _clearSelection();
                      _startTts(start);
                    }),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ttsBar(Color fg, Color bg, Color accent) {
    final settings = context.read<AppSettings>();
    return Positioned(
      left: 12,
      right: 12,
      bottom: chromeVisible ? 150 : 16,
      child: SafeArea(
        child: Material(
          elevation: 6,
          color: Color.lerp(bg, fg, 0.06),
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: IconTheme(
              data: IconThemeData(color: fg),
              child: Row(
                children: [
                  IconButton(tooltip: 'Paragraphe précédent', icon: const Icon(Icons.fast_rewind_rounded), onPressed: () => _tts.skipParagraph(-1)),
                  IconButton(
                    tooltip: _tts.playing ? 'Pause' : 'Lecture',
                    icon: Icon(_tts.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: accent, size: 34),
                    onPressed: _tts.playing ? _tts.pause : _tts.resume,
                  ),
                  IconButton(tooltip: 'Paragraphe suivant', icon: const Icon(Icons.fast_forward_rounded), onPressed: () => _tts.skipParagraph(1)),
                  Expanded(
                    child: PopupMenuButton<double>(
                      tooltip: 'Vitesse',
                      onSelected: (r) => _tts.updateSettings(rate: r),
                      itemBuilder: (_) => [for (final r in [0.3, 0.4, 0.5, 0.6, 0.75, 0.9]) PopupMenuItem(value: r, child: Text('×${(r / 0.5).toStringAsFixed(1)}'))],
                      child: Center(child: Text('Vitesse ×${(settings.ttsRate / 0.5).toStringAsFixed(1)}', style: TextStyle(color: fg, fontFamily: Fonts.ui))),
                    ),
                  ),
                  IconButton(tooltip: 'Voix et tonalité', icon: const Icon(Icons.tune_rounded), onPressed: _ttsSettings),
                  IconButton(tooltip: 'Arrêter', icon: const Icon(Icons.close_rounded), onPressed: _tts.stop),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _ttsSettings() async {
    final settings = context.read<AppSettings>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final voices = _tts.voices.where((v) {
          final lang = widget.book.language.split('-').first.toLowerCase();
          return lang.isEmpty || (v['locale'] ?? '').toLowerCase().startsWith(lang);
        }).toList();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              children: [
                Text('Synthèse vocale', style: Theme.of(ctx).textTheme.headlineSmall),
                const SizedBox(height: Space.md),
                Text('Vitesse', style: Theme.of(ctx).textTheme.titleSmall),
                Slider(value: settings.ttsRate, min: 0.2, max: 1.0, divisions: 16, onChanged: (v) {
                  setSheet(() {});
                  _tts.updateSettings(rate: v);
                }),
                Text('Tonalité', style: Theme.of(ctx).textTheme.titleSmall),
                Slider(value: settings.ttsPitch, min: 0.5, max: 2.0, divisions: 15, onChanged: (v) {
                  setSheet(() {});
                  _tts.updateSettings(pitch: v);
                }),
                Text('Voix', style: Theme.of(ctx).textTheme.titleSmall),
                if (voices.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Voix par défaut du système')),
                RadioGroup<String>(
                  groupValue: settings.ttsVoice,
                  onChanged: (id) {
                    final v = voices.firstWhere((v) => '${v['name']}|${v['locale']}' == id);
                    _tts.updateSettings(voice: v);
                    setSheet(() {});
                  },
                  child: Column(children: [
                    for (final v in voices)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: '${v['name']}|${v['locale']}',
                        title: Text(v['name'] ?? ''),
                        subtitle: Text(v['locale'] ?? ''),
                      ),
                  ]),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.pages);
  final List<(PageLayout, double, List<OverlayRange>)> pages;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (page, dx, ranges) in pages) {
      if (ranges.isEmpty) continue;
      canvas.save();
      canvas.translate(dx, 0);
      PagePainter.paintOverlay(canvas, page, ranges);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => true;
}

class _ScrollPagePainter extends CustomPainter {
  _ScrollPagePainter(this.picture, this.page, this.ranges);
  final ui.Picture picture;
  final PageLayout page;
  final List<OverlayRange> ranges;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(picture);
    if (ranges.isNotEmpty) PagePainter.paintOverlay(canvas, page, ranges);
  }

  @override
  bool shouldRepaint(_ScrollPagePainter old) => old.picture != picture || old.ranges.length != ranges.length || ranges.isNotEmpty;
}
