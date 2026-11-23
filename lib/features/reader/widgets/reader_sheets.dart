import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../data/models/book.dart';
import '../../../formats/document/flow_document.dart';
import '../model/reader_prefs.dart';

/// Table des matières. Retourne l'entrée choisie.
Future<TocEntry?> showTocSheet(BuildContext context, {required List<TocEntry> toc, required int currentChapter}) {
  return showModalBottomSheet<TocEntry>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final p = LireoPalette.of(ctx);
      final t = Theme.of(ctx).textTheme;
      // Entrée active = dernière entrée du chapitre courant ou d'avant.
      var active = -1;
      for (var i = 0; i < toc.length; i++) {
        if (toc[i].chapter <= currentChapter) active = i;
      }
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
              child: Row(children: [Text('Table des matières', style: t.headlineSmall)]),
            ),
            Expanded(
              child: toc.isEmpty
                  ? Center(child: Text('Ce livre ne contient pas de table des matières.', style: t.bodyMedium))
                  : ListView.builder(
                      controller: scroll,
                      itemCount: toc.length,
                      itemBuilder: (ctx, i) {
                        final e = toc[i];
                        final isActive = i == active;
                        return ListTile(
                          contentPadding: EdgeInsets.only(left: Space.gutter + e.level * 18.0, right: Space.gutter),
                          title: Text(
                            e.title.isEmpty ? 'Section ${e.chapter + 1}' : e.title,
                            style: (e.level == 0 ? t.titleSmall : t.bodyMedium)?.copyWith(
                              color: isActive ? p.primary : null,
                              fontWeight: isActive ? FontWeight.w700 : null,
                            ),
                          ),
                          leading: isActive ? Icon(Icons.play_arrow_rounded, color: p.primary, size: 18) : null,
                          minLeadingWidth: 0,
                          onTap: () => Navigator.pop(ctx, e),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class SearchHit {
  const SearchHit(this.chapter, this.offset, this.length, this.snippet, this.matchStart, this.chapterTitle);
  final int chapter;
  final int offset;
  final int length;
  final String snippet;
  final int matchStart;
  final String chapterTitle;

  BookLocation get locator => BookLocation(chapter: chapter, offset: offset);
}

/// Recherche plein texte dans un livre reflowable (chapitre par chapitre,
/// sans bloquer l'interface).
class BookSearchSheet extends StatefulWidget {
  const BookSearchSheet({super.key, required this.book, this.initialQuery = ''});

  final ReflowableBook book;
  final String initialQuery;

  @override
  State<BookSearchSheet> createState() => _BookSearchSheetState();
}

class _BookSearchSheetState extends State<BookSearchSheet> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  final _hits = <SearchHit>[];
  int _generation = 0;
  bool _searching = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) _search(widget.initialQuery);
  }

  static String _fold(String s) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyoaAAAAAACEEEEIIIINOOOOOUUUUY';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 && i < to.length ? to[i] : ch);
    }
    return b.toString().toLowerCase();
  }

  Future<void> _search(String query) async {
    final gen = ++_generation;
    final q = _fold(query.trim());
    setState(() {
      _hits.clear();
      _searching = q.length >= 2;
      _progress = 0;
    });
    if (q.length < 2) return;
    for (var c = 0; c < widget.book.chapterCount; c++) {
      final chapter = await widget.book.loadChapter(c);
      if (gen != _generation || !mounted) return;
      // Le repliage préserve la longueur (1 caractère → 1 caractère), donc les offsets.
      final folded = _fold(chapter.text);
      var from = 0;
      final found = <SearchHit>[];
      while (true) {
        final i = folded.indexOf(q, from);
        if (i < 0 || _hits.length + found.length >= 500) break;
        final s = (i - 40).clamp(0, chapter.text.length);
        final e = (i + q.length + 60).clamp(0, chapter.text.length);
        final snippet = chapter.text.substring(s, e).replaceAll('\n', ' ');
        found.add(SearchHit(c, i, q.length, snippet, i - s, chapter.title));
        from = i + q.length;
      }
      setState(() {
        _hits.addAll(found);
        _progress = (c + 1) / widget.book.chapterCount;
      });
      await Future<void>.delayed(Duration.zero);
    }
    if (gen == _generation && mounted) setState(() => _searching = false);
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: TextField(
              controller: _controller,
              autofocus: widget.initialQuery.isEmpty,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Rechercher dans le livre',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: () => _search(_controller.text)),
              ),
            ),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
              child: LinearProgressIndicator(value: _progress),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _hits.isEmpty ? (_searching || _controller.text.isEmpty ? '' : 'Aucun résultat') : '${_hits.length} résultat${_hits.length > 1 ? 's' : ''}',
                style: t.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: scroll,
              itemCount: _hits.length,
              separatorBuilder: (_, _) => const Divider(indent: Space.gutter, endIndent: Space.gutter),
              itemBuilder: (ctx, i) {
                final h = _hits[i];
                return ListTile(
                  title: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: h.snippet.substring(0, h.matchStart)),
                      TextSpan(
                        text: h.snippet.substring(h.matchStart, (h.matchStart + h.length).clamp(0, h.snippet.length)),
                        style: TextStyle(backgroundColor: p.accent.withValues(alpha: 0.4), fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: h.snippet.substring((h.matchStart + h.length).clamp(0, h.snippet.length))),
                    ]),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium,
                  ),
                  subtitle: h.chapterTitle.isEmpty ? null : Text(h.chapterTitle, maxLines: 1),
                  onTap: () => Navigator.pop(ctx, h),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Note ou définition affichée par-dessus la page, sans la quitter.
/// Suit les couleurs et la police de la page (jour, nuit, sépia…).
/// Retourne true si le lecteur veut aller à la note dans le livre.
Future<bool?> showNoteSheet(BuildContext context, List<List<InlineRun>> paragraphs, ReaderPrefs prefs) {
  final scheme = ColorScheme.fromSeed(
    seedColor: LireoPalette.of(context).primary,
    brightness: prefs.isDarkSurface ? Brightness.dark : Brightness.light,
  ).copyWith(surface: prefs.background, onSurface: prefs.textColor);
  final theme = Theme.of(context).copyWith(
    colorScheme: scheme,
    iconTheme: IconThemeData(color: prefs.textColor),
    textTheme: Theme.of(context).textTheme.apply(bodyColor: prefs.textColor, displayColor: prefs.textColor),
  );
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: prefs.background,
    builder: (ctx) => Theme(data: theme, child: Builder(builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      final accent = scheme.primary;
      final base = TextStyle(
        fontFamily: prefs.fontFamily,
        fontSize: (prefs.fontSize * 0.9).clamp(14.0, 22.0),
        height: 1.45,
        color: prefs.textColor,
      );
      TextSpan span(InlineRun r) {
        final raised = r.has(InlineStyle.superscript) || r.has(InlineStyle.subscript) || r.has(InlineStyle.small);
        return TextSpan(
          text: r.text,
          style: TextStyle(
            fontWeight: r.has(InlineStyle.bold) ? FontWeight.w700 : null,
            fontStyle: r.has(InlineStyle.italic) ? FontStyle.italic : null,
            fontSize: raised ? base.fontSize! * 0.75 : null,
            fontFamily: r.has(InlineStyle.code) ? 'monospace' : null,
            color: r.href != null ? accent : null,
          ),
        );
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.sm, 0),
                child: Row(children: [
                  Icon(Icons.sticky_note_2_outlined, color: accent, size: 20),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text('Note', style: t.titleMedium)),
                  IconButton(
                    tooltip: 'Fermer',
                    color: prefs.textColor.withValues(alpha: 0.7),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final runs in paragraphs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.sm),
                            child: Text.rich(TextSpan(style: base, children: [for (final r in runs) span(r)])),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.md),
                child: Row(children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: accent),
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Voir dans le livre'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: scheme.onPrimary),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Fermer'),
                  ),
                ]),
              ),
            ],
          ),
        ),
      );
    })),
  );
}
