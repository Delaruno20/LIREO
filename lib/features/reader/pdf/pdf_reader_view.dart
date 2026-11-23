import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../../core/design/tokens.dart';
import '../../../data/models/book.dart';
import '../../../data/models/library_models.dart';
import '../../../data/repositories/annotation_repository.dart';
import '../model/reader_prefs.dart';
import '../session/reading_tracker.dart';
import '../widgets/annotations_screen.dart';
import '../widgets/reader_behaviors.dart';
import '../widgets/reader_chrome.dart';
import '../widgets/reader_settings_panel.dart';
import '../widgets/reader_sheets.dart';
import '../../../formats/document/flow_document.dart' show TocEntry;

/// Lecteur PDF (rendu PDFium via pdfrx) : pagination ou défilement,
/// double page, zoom, recherche, sommaire, marque-pages, modes nuit/sépia.
class PdfReaderView extends StatefulWidget {
  const PdfReaderView({
    super.key,
    required this.book,
    required this.prefs,
    required this.scope,
    required this.tracker,
    required this.onPrefsChanged,
    required this.onOpenDetails,
  });

  final Book book;
  final ReaderPrefs prefs;
  final PrefsScope scope;
  final ReadingTracker tracker;
  final void Function(ReaderPrefs prefs, PrefsScope scope) onPrefsChanged;
  final VoidCallback onOpenDetails;

  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();
}

class _PdfReaderViewState extends State<PdfReaderView> with ReaderBehaviors {
  final _controller = PdfViewerController();
  late final _searcher = PdfTextSearcher(_controller)..addListener(_onSearch);
  late ReaderPrefs _prefs = widget.prefs;
  late PrefsScope _scope = widget.scope;
  final _focus = FocusNode();
  int _page = 1;
  int _pageCount = 0;
  List<PdfOutlineNode> _outline = const [];
  List<Annotation> _bookmarks = const [];
  bool _searchOpen = false;
  final _searchField = TextEditingController();

  bool get _paged => _prefs.animation != PageAnimation.scroll;

  bool _double(Size size) =>
      _prefs.doublePage == DoublePageMode.always ||
      (_prefs.doublePage == DoublePageMode.auto && size.width > size.height && size.width >= 720);

  @override
  void initState() {
    super.initState();
    _page = widget.book.locator.chapter + 1;
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final list = await context.read<AnnotationRepository>().forBook(widget.book.id!, kind: AnnotationKind.bookmark);
    if (mounted) setState(() => _bookmarks = list);
  }

  void _onSearch() => mounted ? setState(() {}) : null;

  void _onPageChanged(int? page) {
    if (page == null) return;
    final delta = page - _page;
    _page = page;
    widget.tracker.pageTurned(delta);
    final progress = _pageCount <= 1 ? 1.0 : (page - 1) / (_pageCount - 1);
    widget.tracker.updatePosition(BookLocation(chapter: page - 1), progress);
    setState(() {});
  }

  void _turn(int delta) {
    if (_pageCount == 0) return;
    final target = (_page + delta).clamp(1, _pageCount);
    _controller.goToPage(pageNumber: target, duration: Motion.scaled(context, Motion.medium));
  }

  ColorFilter? get _filter {
    if (_prefs.isDarkSurface) {
      // Inversion des luminances, teinte conservée approximativement.
      return const ColorFilter.matrix([
        -0.9, 0, 0, 0, 235, //
        0, -0.9, 0, 0, 230,
        0, 0, -0.9, 0, 222,
        0, 0, 0, 1, 0,
      ]);
    }
    final s = _prefs.surface.id;
    if (s == 'sepia' || s == 'cream') {
      return const ColorFilter.matrix([
        0.95, 0, 0, 0, 0, //
        0, 0.9, 0, 0, 0,
        0, 0, 0.76, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    }
    return null;
  }

  bool _onGeneralTap(BuildContext context, PdfViewerController controller, PdfViewerGeneralTapHandlerDetails details) {
    widget.tracker.activity();
    if (chromeVisible) {
      showChrome(false);
      return true;
    }
    final width = MediaQuery.sizeOf(context).width;
    final x = details.localPosition.dx / width;
    final action = x < 0.3 ? _prefs.leftTap : (x > 0.7 ? _prefs.rightTap : _prefs.centerTap);
    switch (action) {
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
    return true;
  }

  Future<void> _toggleBookmark() async {
    final repo = context.read<AnnotationRepository>();
    final existing = _bookmarks.where((b) => b.start.chapter == _page - 1).toList();
    if (existing.isNotEmpty) {
      for (final b in existing) {
        await repo.delete(b);
      }
      showHud('Marque-page retiré');
    } else {
      await repo.add(Annotation(
        bookId: widget.book.id!,
        kind: AnnotationKind.bookmark,
        start: BookLocation(chapter: _page - 1),
        text: 'Page $_page',
        createdAt: DateTime.now(),
        progress: _pageCount <= 1 ? 1 : (_page - 1) / (_pageCount - 1),
      ));
      showHud('Marque-page ajouté');
    }
    await _loadBookmarks();
  }

  Future<void> _openToc() async {
    final entries = <TocEntry>[];
    void walk(List<PdfOutlineNode> nodes, int level) {
      for (final n in nodes) {
        if (n.dest != null) entries.add(TocEntry(title: n.title, chapter: n.dest!.pageNumber - 1, level: level));
        walk(n.children, level + 1);
      }
    }

    walk(_outline, 0);
    final entry = await showTocSheet(context, toc: entries, currentChapter: _page - 1);
    if (entry != null) await _controller.goToPage(pageNumber: entry.chapter + 1);
  }

  Future<void> _openAnnotations() async {
    final loc = await Navigator.of(context).push<BookLocation>(
      MaterialPageRoute(builder: (_) => AnnotationsScreen(book: widget.book, fromReader: true)),
    );
    await _loadBookmarks();
    if (loc != null) await _controller.goToPage(pageNumber: loc.chapter + 1);
  }

  void _applyPrefs(ReaderPrefs p) {
    setState(() => _prefs = p);
    widget.onPrefsChanged(p, _scope);
  }

  @override
  void dispose() {
    _searcher
      ..removeListener(_onSearch)
      ..dispose();
    _focus.dispose();
    _searchField.dispose();
    disposeBehaviors();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fg = _prefs.textColor;
    final bg = _prefs.background;
    final accent = Theme.of(context).colorScheme.primary;
    final size = MediaQuery.sizeOf(context);
    final facing = _double(size);
    final layout = facing
        ? const FacingPagesLayout(fitMode: PdfFitMode.fit, coverPage: true)
        : SequentialPagesLayout(
            scrollDirection: _paged ? Axis.horizontal : Axis.vertical,
            fitMode: _paged ? PdfFitMode.fit : PdfFitMode.fill,
          );
    final bookmarked = _bookmarks.any((b) => b.start.chapter == _page - 1);
    final progress = _pageCount <= 1 ? 0.0 : (_page - 1) / (_pageCount - 1);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, e) => handleKey(e, _prefs, _turn),
      child: Material(
        color: bg,
        child: Stack(
          children: [
            Positioned.fill(
              child: PdfViewer.file(
                widget.book.path,
                controller: _controller,
                initialPageNumber: _page,
                params: PdfViewerParams(
                  backgroundColor: bg,
                  layoutStrategy: layout,
                  paging: _paged ? PdfPaging(duration: Motion.scaled(context, Motion.medium)) : null,
                  pageImageColorFilter: _filter,
                  pageDropShadow: BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 2)),
                  onGeneralTap: _onGeneralTap,
                  onPageChanged: _onPageChanged,
                  pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
                  matchTextColor: accent.withValues(alpha: 0.3),
                  activeMatchTextColor: accent.withValues(alpha: 0.6),
                  onViewerReady: (document, controller) async {
                    final outline = await document.loadOutline();
                    if (!mounted) return;
                    setState(() {
                      _pageCount = document.pages.length;
                      _outline = outline;
                    });
                  },
                  errorBannerBuilder: (context, error, stack, ref) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Text('Ce PDF ne peut pas être ouvert.\n$error', textAlign: TextAlign.center, style: TextStyle(color: fg)),
                    ),
                  ),
                ),
              ),
            ),
            if (_searchOpen) _searchBar(fg, bg),
            Positioned.fill(
              child: ReaderChrome(
                visible: chromeVisible && !_searchOpen,
                background: bg,
                foreground: fg,
                accent: accent,
                title: widget.book.title,
                subtitle: _pageCount == 0 ? '' : 'Page $_page sur $_pageCount',
                progress: progress,
                progressLabel: '${(progress * 100).round()} %',
                positionLabel: _pageCount == 0 ? '' : 'Page $_page / $_pageCount',
                onBack: () => Navigator.of(context).maybePop(),
                onInteraction: keepChrome,
                onSeek: _pageCount == 0 ? null : (v) => _controller.goToPage(pageNumber: (1 + v * (_pageCount - 1)).round()),
                topActions: [
                  IconButton(
                    tooltip: 'Rechercher',
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () => setState(() {
                      _searchOpen = true;
                      showChrome(false);
                    }),
                  ),
                  IconButton(
                    tooltip: bookmarked ? 'Retirer le marque-page' : 'Ajouter un marque-page',
                    icon: Icon(bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: bookmarked ? accent : null),
                    onPressed: _toggleBookmark,
                  ),
                  PopupMenuButton<String>(
                    iconColor: fg,
                    onSelected: (v) => switch (v) {
                      'timer' => chooseSleepTimer(() {}),
                      'details' => widget.onOpenDetails(),
                      _ => null,
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'timer', child: ListTile(leading: Icon(Icons.timer_outlined), title: Text('Minuteur de lecture'))),
                      PopupMenuItem(value: 'details', child: ListTile(leading: Icon(Icons.info_outline_rounded), title: Text('Fiche du livre'))),
                    ],
                  ),
                ],
                bottomActions: [
                  IconButton(tooltip: 'Sommaire', icon: const Icon(Icons.format_list_bulleted_rounded), onPressed: _openToc),
                  IconButton(tooltip: 'Marque-pages', icon: const Icon(Icons.bookmarks_outlined), onPressed: _openAnnotations),
                  IconButton(
                    tooltip: _paged ? 'Défilement continu' : 'Page par page',
                    icon: Icon(_paged ? Icons.view_day_outlined : Icons.auto_stories_outlined),
                    onPressed: () => _applyPrefs(_prefs.copyWith(animation: _paged ? PageAnimation.scroll : PageAnimation.slide)),
                  ),
                  IconButton(
                    tooltip: 'Apparence',
                    icon: const Icon(Icons.palette_outlined),
                    onPressed: () {
                      showChrome(false);
                      ReaderSettingsPanel.show(
                        context,
                        prefs: _prefs,
                        onChanged: _applyPrefs,
                        reflowable: false,
                        scope: _scope,
                        onScopeChanged: (s) {
                          _scope = s;
                          widget.onPrefsChanged(_prefs, s);
                        },
                        format: widget.book.format,
                      );
                    },
                  ),
                ],
              ),
            ),
            Positioned.fill(child: buildHud(bg, fg)),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(Color fg, Color bg) {
    final count = _searcher.matches.length;
    final index = _searcher.currentIndex;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Color.lerp(bg, fg, 0.05),
        elevation: 4,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close_rounded, color: fg),
                  onPressed: () {
                    _searcher.resetTextSearch();
                    setState(() => _searchOpen = false);
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _searchField,
                    autofocus: true,
                    style: TextStyle(color: fg),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(hintText: 'Rechercher dans le PDF'),
                    onSubmitted: (q) {
                      if (q.trim().length >= 2) _searcher.startTextSearch(q.trim());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _searcher.isSearching ? '…' : (count == 0 ? '0' : '${(index ?? 0) + 1}/$count'),
                  style: TextStyle(color: fg, fontFamily: Fonts.ui),
                ),
                IconButton(icon: Icon(Icons.keyboard_arrow_up_rounded, color: fg), onPressed: count == 0 ? null : _searcher.goToPrevMatch),
                IconButton(icon: Icon(Icons.keyboard_arrow_down_rounded, color: fg), onPressed: count == 0 ? null : _searcher.goToNextMatch),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
