import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/book_cover.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/shelf.dart';
import '../../data/models/book.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/settings/app_settings.dart';
import '../../formats/format_registry.dart';
import '../../services/app_lock.dart';
import '../book/book_actions.dart';
import '../import/import_actions.dart';

/// Bibliothèque complète : étagères, grille ou liste ; tri, filtres,
/// sélection multiple. Les cellules sont construites à la demande
/// (listes virtualisées) pour tenir des milliers de livres.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.initialCategory, this.favoritesOnly = false, this.collectionId, this.title});

  final String? initialCategory;
  final bool favoritesOnly;
  final int? collectionId;
  final String? title;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryRepository _repo = context.read<LibraryRepository>();
  late String? _category = widget.initialCategory;
  late bool _favorites = widget.favoritesOnly;
  String? _format;
  String? _status;
  BookSort _sort = BookSort.lastRead;
  List<Book> _books = const [];
  List<String> _categories = const [];
  List<String> _formats = const [];
  bool _loading = true;
  Set<int>? _selection;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _repo.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = context.read<AppSettings>();
    final lock = context.read<AppLock>();
    var books = widget.collectionId != null
        ? await _repo.booksInCollection(widget.collectionId!)
        : await _repo.books(BookQuery(
            category: _category,
            format: _format,
            favoritesOnly: _favorites,
            status: _status,
            sort: _sort,
          ));
    if (widget.collectionId == null && settings.hidePrivateCollections && !lock.privateUnlocked) {
      final hidden = await _repo.privateBookIds();
      books = books.where((b) => !hidden.contains(b.id)).toList();
    }
    final cats = await _repo.categories();
    final formats = await _repo.formats();
    if (!mounted) return;
    setState(() {
      _books = books;
      _categories = cats;
      _formats = formats;
      _loading = false;
      _selection?.removeWhere((id) => !books.any((b) => b.id == id));
    });
  }

  void _toggleSelect(Book b) {
    setState(() {
      _selection ??= {};
      if (!_selection!.remove(b.id)) _selection!.add(b.id!);
      if (_selection!.isEmpty) _selection = null;
    });
  }

  void _onTap(Book b, String heroTag) {
    if (_selection != null) return _toggleSelect(b);
    Routes.bookDetail(context, b, heroTag: heroTag);
  }

  List<Book> get _selectedBooks => _books.where((b) => _selection?.contains(b.id) ?? false).toList();

  Future<void> _showSort() async {
    final chosen = await showModalBottomSheet<BookSort>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in BookSort.values)
              ListTile(
                title: Text(s.label),
                trailing: s == _sort ? Icon(Icons.check_rounded, color: LireoPalette.of(ctx).primary) : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      _sort = chosen;
      _load();
    }
  }

  Future<void> _showFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void update(VoidCallback f) {
          setSheet(f);
          _load();
        }

        Widget group(String title, List<(String?, String)> options, String? value, ValueChanged<String?> onChanged) => Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: Space.sm),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      for (final (v, label) in options)
                        ChoiceChip(label: Text(label), selected: v == value, onSelected: (_) => update(() => onChanged(v))),
                    ],
                  ),
                ],
              ),
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: Text('Filtrer', style: Theme.of(ctx).textTheme.headlineSmall),
                ),
                group('Statut', const [(null, 'Tous'), ('unread', 'Non commencés'), ('reading', 'En cours'), ('finished', 'Terminés')],
                    _status, (v) => _status = v),
                group('Format', [(null, 'Tous'), for (final f in _formats) (f, FormatRegistry.byId(f).label)], _format,
                    (v) => _format = v),
                if (_categories.isNotEmpty)
                  group('Catégorie', [(null, 'Toutes'), for (final c in _categories) (c, c)], _category, (v) => _category = v),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.gutter, 0),
                  child: SwitchListTile(
                    value: _favorites,
                    onChanged: (v) => update(() => _favorites = v),
                    title: const Text('Favoris uniquement'),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final selecting = _selection != null;
    final filtersActive = _format != null || _status != null || _category != null || _favorites;

    Widget content;
    if (_loading) {
      content = const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
    } else if (_books.isEmpty) {
      content = SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: filtersActive ? Icons.filter_alt_off_outlined : Icons.menu_book_outlined,
          title: filtersActive ? 'Aucun livre ne correspond' : 'Aucun livre ici',
          message: filtersActive ? 'Modifiez ou retirez les filtres.' : 'Ajoutez des livres pour remplir vos étagères.',
          action: filtersActive
              ? OutlinedButton(
                  onPressed: () {
                    _format = _status = _category = null;
                    _favorites = false;
                    _load();
                  },
                  child: const Text('Retirer les filtres'),
                )
              : null,
        ),
      );
    } else {
      content = switch (settings.libraryLayout) {
        LibraryLayout.shelves => _shelves(settings.coverScale),
        LibraryLayout.grid => _grid(settings.coverScale),
        LibraryLayout.list => _list(),
      };
    }

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selection = null);
      },
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: selecting
                  ? Text('${_selection!.length} sélectionné${_selection!.length > 1 ? 's' : ''}')
                  : Text(widget.title ?? (_favorites ? 'Favoris' : 'Ma bibliothèque')),
              leading: selecting
                  ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _selection = null))
                  : null,
              actions: selecting
                  ? [
                      IconButton(
                        tooltip: 'Tout sélectionner',
                        icon: const Icon(Icons.select_all_rounded),
                        onPressed: () => setState(() => _selection = {for (final b in _books) b.id!}),
                      ),
                    ]
                  : [
                      IconButton(tooltip: 'Trier', icon: const Icon(Icons.sort_rounded), onPressed: _showSort),
                      if (widget.collectionId == null)
                        IconButton(
                          tooltip: 'Filtrer',
                          icon: Badge(isLabelVisible: filtersActive, smallSize: 8, child: const Icon(Icons.tune_rounded)),
                          onPressed: _showFilters,
                        ),
                      PopupMenuButton<String>(
                        tooltip: 'Affichage',
                        icon: Icon(switch (settings.libraryLayout) {
                          LibraryLayout.shelves => Icons.shelves,
                          LibraryLayout.grid => Icons.grid_view_rounded,
                          LibraryLayout.list => Icons.view_list_rounded,
                        }),
                        onSelected: (v) {
                          if (v == 'select') {
                            setState(() => _selection = {});
                          } else {
                            settings.setLibraryLayout(LibraryLayout.values.byName(v));
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'shelves', child: Text('Étagères')),
                          const PopupMenuItem(value: 'grid', child: Text('Grille')),
                          const PopupMenuItem(value: 'list', child: Text('Liste')),
                          const PopupMenuDivider(),
                          const PopupMenuItem(value: 'select', child: Text('Sélectionner…')),
                        ],
                      ),
                    ],
            ),
            if (!selecting && settings.libraryLayout != LibraryLayout.list && _books.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
                  child: Row(
                    children: [
                      Text('${_books.length} livre${_books.length > 1 ? 's' : ''} · ${_sort.label.toLowerCase()}', style: t.bodySmall),
                      const Spacer(),
                      Icon(Icons.photo_size_select_small_rounded, size: 16, color: p.textMuted),
                      SizedBox(
                        width: 130,
                        child: Slider(
                          value: settings.coverScale,
                          min: 0.7,
                          max: 1.4,
                          onChanged: settings.setCoverScale,
                          semanticFormatterCallback: (v) => 'Taille des couvertures ${(v * 100).round()} %',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            content,
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
        floatingActionButton: selecting
            ? null
            : FloatingActionButton(
                backgroundColor: p.primary,
                foregroundColor: p.onPrimary,
                tooltip: 'Ajouter des livres',
                onPressed: () => ImportActions.showImportMenu(context),
                child: const Icon(Icons.add_rounded),
              ),
        bottomNavigationBar: selecting && _selection!.isNotEmpty ? _selectionBar() : null,
      ),
    );
  }

  Widget _selectionBar() {
    final books = _selectedBooks;
    final allFav = books.every((b) => b.favorite);
    return SafeArea(
      minimum: const EdgeInsets.all(12),
      child: Glass(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: allFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
              icon: Icon(allFav ? Icons.favorite_rounded : Icons.favorite_border_rounded),
              onPressed: () async {
                for (final b in books) {
                  await _repo.setFavorite(b.id!, !allFav);
                }
              },
            ),
            IconButton(
              tooltip: 'Ajouter à une collection',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: () => BookActions.addToCollection(context, books),
            ),
            if (widget.collectionId != null)
              IconButton(
                tooltip: 'Retirer de la collection',
                icon: const Icon(Icons.playlist_remove_rounded),
                onPressed: () async {
                  await _repo.removeFromCollection(widget.collectionId!, [for (final b in books) b.id!]);
                  setState(() => _selection = null);
                },
              ),
            IconButton(
              tooltip: 'Supprimer',
              icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
              onPressed: () async {
                if (await BookActions.delete(context, books)) setState(() => _selection = null);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _shelves(double scale) {
    return SliverLayoutBuilder(builder: (context, constraints) {
      final coverW = 96.0 * scale;
      const gap = Space.lg;
      final perRow = ((constraints.crossAxisExtent - Space.gutter * 2 + gap) / (coverW + gap)).floor().clamp(2, 12);
      final rows = (_books.length / perRow).ceil();
      return SliverList.builder(
        itemCount: rows,
        itemBuilder: (context, r) {
          final rowBooks = _books.skip(r * perRow).take(perRow).toList();
          return Padding(
            padding: const EdgeInsets.only(top: Space.lg),
            child: SizedBox(
              height: coverW * BookCover.aspect + 24,
              child: Stack(
                children: [
                  const Positioned(left: 0, right: 0, bottom: 0, child: ShelfPlank()),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 15),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final b in rowBooks)
                          Padding(
                            padding: const EdgeInsets.only(right: gap),
                            child: BookTile(
                              book: b,
                              width: coverW,
                              showText: false,
                              heroPrefix: 'libshelf',
                              selected: _selection?.contains(b.id),
                              onTap: () => _onTap(b, 'libshelf-${b.id}'),
                              onLongPress: () => _selection == null ? BookActions.show(context, b) : _toggleSelect(b),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Widget _grid(double scale) {
    final coverW = 104.0 * scale;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: coverW + Space.lg,
          mainAxisSpacing: Space.lg,
          crossAxisSpacing: Space.md,
          childAspectRatio: coverW / (coverW * BookCover.aspect + 62),
        ),
        itemCount: _books.length,
        itemBuilder: (context, i) {
          final b = _books[i];
          return LayoutBuilder(
            builder: (context, c) => BookTile(
              book: b,
              width: c.maxWidth,
              heroPrefix: 'libgrid',
              selected: _selection?.contains(b.id),
              onTap: () => _onTap(b, 'libgrid-${b.id}'),
              onLongPress: () => _selection == null ? BookActions.show(context, b) : _toggleSelect(b),
            ),
          );
        },
      ),
    );
  }

  Widget _list() {
    final t = Theme.of(context).textTheme;
    final p = LireoPalette.of(context);
    return SliverList.builder(
      itemCount: _books.length,
      itemBuilder: (context, i) {
        final b = _books[i];
        final selected = _selection?.contains(b.id);
        return ListTile(
          leading: BookCover(book: b, width: 38, heroTag: 'liblist-${b.id}', elevation: 0.5),
          title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
          subtitle: Text(
            '${b.displayAuthor} · ${FormatRegistry.byId(b.format).label}${b.progress > 0 ? ' · ${(b.progress * 100).round()} %' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: selected != null
              ? Checkbox(value: selected, onChanged: (_) => _toggleSelect(b))
              : (b.favorite ? Icon(Icons.favorite_rounded, color: p.accent, size: 18) : null),
          onTap: () => _onTap(b, 'liblist-${b.id}'),
          onLongPress: () => _selection == null ? BookActions.show(context, b) : _toggleSelect(b),
        );
      },
    );
  }
}
