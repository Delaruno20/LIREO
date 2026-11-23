import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../data/models/book.dart';
import '../../../formats/adapters/image_book.dart';
import '../model/reader_prefs.dart';
import '../session/reading_tracker.dart';
import '../widgets/reader_behaviors.dart';
import '../widgets/reader_chrome.dart';
import '../widgets/reader_settings_panel.dart';

/// Lecteur d'images (bandes dessinées CBZ, images isolées) avec zoom.
class ImageReaderView extends StatefulWidget {
  const ImageReaderView({
    super.key,
    required this.book,
    required this.images,
    required this.prefs,
    required this.tracker,
    required this.onPrefsChanged,
  });

  final Book book;
  final ImageBook images;
  final ReaderPrefs prefs;
  final ReadingTracker tracker;
  final void Function(ReaderPrefs prefs, PrefsScope scope) onPrefsChanged;

  @override
  State<ImageReaderView> createState() => _ImageReaderViewState();
}

class _ImageReaderViewState extends State<ImageReaderView> with ReaderBehaviors {
  late final PageController _pages = PageController(initialPage: widget.book.locator.chapter.clamp(0, widget.images.pageCount - 1));
  late int _index = _pages.initialPage;
  late ReaderPrefs _prefs = widget.prefs;
  final _cache = <int, Future<Uint8List?>>{};
  final _focus = FocusNode();
  bool _zoomed = false;

  int get _count => widget.images.pageCount;

  Future<Uint8List?> _page(int i) {
    // Cache borné autour de la page courante.
    _cache.removeWhere((k, _) => (k - _index).abs() > 3);
    return _cache[i] ??= widget.images.page(i);
  }

  void _onChanged(int i) {
    widget.tracker.pageTurned(i - _index);
    _index = i;
    widget.tracker.updatePosition(BookLocation(chapter: i), _count <= 1 ? 1 : i / (_count - 1));
    setState(() {});
  }

  void _turn(int delta) {
    final target = (_index + delta).clamp(0, _count - 1);
    if (target == _index) return;
    if (_prefs.animation == PageAnimation.none) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(target, duration: Motion.scaled(context, Motion.medium), curve: Motion.curve);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _focus.dispose();
    disposeBehaviors();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = _prefs.isDarkSurface ? _prefs.background : const Color(0xFF111111);
    const fg = Color(0xFFEDE7DD);
    final accent = Theme.of(context).colorScheme.primary;
    final progress = _count <= 1 ? 1.0 : _index / (_count - 1);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, e) => handleKey(e, _prefs, _turn),
      child: Material(
        color: bg,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTapUp: (d) {
                  widget.tracker.activity();
                  if (chromeVisible) return showChrome(false);
                  final x = d.localPosition.dx / MediaQuery.sizeOf(context).width;
                  if (x < 0.3) {
                    _turn(-1);
                  } else if (x > 0.7) {
                    _turn(1);
                  } else {
                    toggleChrome();
                  }
                },
                child: PageView.builder(
                  controller: _pages,
                  physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                  itemCount: _count,
                  onPageChanged: _onChanged,
                  itemBuilder: (context, i) => FutureBuilder<Uint8List?>(
                    future: _page(i),
                    builder: (context, snap) {
                      if (snap.data == null) {
                        return Center(
                          child: snap.connectionState == ConnectionState.done
                              ? const Text('Image illisible', style: TextStyle(color: fg))
                              : CircularProgressIndicator(color: accent),
                        );
                      }
                      return InteractiveViewer(
                        maxScale: 5,
                        onInteractionEnd: (_) {},
                        onInteractionUpdate: (d) {
                          final zoomed = d.scale > 1.02;
                          if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                        },
                        child: Center(
                          child: Image.memory(
                            snap.data!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                            cacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context) * 1.5).round(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ReaderChrome(
                visible: chromeVisible,
                background: bg,
                foreground: fg,
                accent: accent,
                title: widget.book.title,
                subtitle: 'Page ${_index + 1} sur $_count',
                progress: progress,
                progressLabel: '${(progress * 100).round()} %',
                positionLabel: 'Page ${_index + 1} / $_count',
                onBack: () => Navigator.of(context).maybePop(),
                onInteraction: keepChrome,
                onSeek: _count <= 1 ? null : (v) => _pages.jumpToPage((v * (_count - 1)).round()),
                topActions: const [],
                bottomActions: [
                  IconButton(
                    tooltip: 'Réglages',
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: () => ReaderSettingsPanel.show(
                      context,
                      prefs: _prefs,
                      reflowable: false,
                      onChanged: (p) {
                        setState(() => _prefs = p);
                        widget.onPrefsChanged(p, PrefsScope.book);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
