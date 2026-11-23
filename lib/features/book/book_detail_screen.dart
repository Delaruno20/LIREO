import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/book_cover.dart';
import '../../core/widgets/common.dart';
import '../../data/models/book.dart';
import '../../data/models/library_models.dart';
import '../../data/repositories/annotation_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../formats/format_registry.dart';
import '../reader/widgets/annotations_screen.dart';
import 'book_actions.dart';
import 'edit_book_screen.dart';

class BookDetailScreen extends StatefulWidget {
  const BookDetailScreen({super.key, required this.bookId, this.initial, this.heroTag});

  final int bookId;
  final Book? initial;
  final String? heroTag;

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late Book? _book = widget.initial;
  List<BookCollection> _collections = const [];
  int _annotationCount = 0;
  bool _expanded = false;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = context.read<LibraryRepository>().changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = context.read<LibraryRepository>();
    final book = await repo.book(widget.bookId);
    if (book == null) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final ids = await repo.collectionIdsForBook(book.id!);
    final all = await repo.collections();
    if (!mounted) return;
    final annotations = await context.read<AnnotationRepository>().forBook(book.id!);
    if (!mounted) return;
    setState(() {
      _book = book;
      _collections = all.where((c) => ids.contains(c.id)).toList();
      _annotationCount = annotations.length;
    });
  }

  Future<void> _editNote(Book book) async {
    final controller = TextEditingController(text: book.personalNote);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note personnelle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(hintText: 'Vos impressions, une citation, un rappel…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (result != null && mounted) await context.read<LibraryRepository>().updateBook(book.copyWith(personalNote: result));
  }

  Future<void> _menu(Book book, String action) async {
    final repo = context.read<LibraryRepository>();
    switch (action) {
      case 'edit':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditBookScreen(book: book)));
      case 'collection':
        await BookActions.addToCollection(context, [book]);
        _load();
      case 'reset':
        await repo.updateBook(book.copyWith(progress: 0, locator: BookLocation.start, clearFinished: true));
      case 'finished':
        await repo.updateBook(book.copyWith(progress: 1, finishedAt: DateTime.now()));
      case 'delete':
        if (await BookActions.delete(context, [book]) && mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    if (book == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final format = FormatRegistry.byId(book.format);
    final wide = MediaQuery.sizeOf(context).width > 720;
    final coverWidth = wide ? 200.0 : 170.0;

    final header = Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Halo doux derrière la couverture.
            Container(
              width: coverWidth * 1.9,
              height: coverWidth * 1.3,
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [p.accent.withValues(alpha: p.isDark ? 0.22 : 0.3), p.background.withValues(alpha: 0)]),
              ),
            ),
            BookCover(book: book, width: coverWidth, heroTag: widget.heroTag ?? 'detail-${book.id}', elevation: 2.2),
          ],
        ),
        const SizedBox(height: Space.xl),
        Text(book.title, style: t.displaySmall?.copyWith(fontSize: 27), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(book.displayAuthor, style: t.titleMedium?.copyWith(color: p.textMuted, fontWeight: FontWeight.w500)),
        const SizedBox(height: Space.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              GestureDetector(
                onTap: () => context.read<LibraryRepository>().updateBook(book.copyWith(rating: book.rating == i ? 0 : i)),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(i <= book.rating ? Icons.star_rounded : Icons.star_outline_rounded, color: p.accent, size: 24,
                      semanticLabel: 'Note $i sur 5'),
                ),
              ),
            const SizedBox(width: Space.md),
            Container(width: 1, height: 16, color: p.divider),
            const SizedBox(width: Space.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: const BorderRadius.all(Radii.pill)),
              child: Text(format.label, style: t.labelMedium?.copyWith(color: p.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ],
    );

    final stats = Container(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.all(Radii.lg),
        border: Border.all(color: p.divider),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _Stat(icon: Icons.menu_book_outlined, value: book.pageCount > 0 ? '${book.pageCount}' : '—',
                label: format.engine == EngineKind.reflowable ? 'pages (est.)' : 'pages'),
            VerticalDivider(color: p.divider, width: 1),
            _Stat(icon: Icons.schedule_rounded, value: book.totalReadingMs > 0 ? formatDuration(book.totalReadingMs, short: true) : '—', label: 'lecture'),
            VerticalDivider(color: p.divider, width: 1),
            _Stat(icon: Icons.donut_large_rounded, value: '${(book.progress * 100).round()} %', label: book.isFinished ? 'terminé' : 'lu'),
          ],
        ),
      ),
    );

    final actions = Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => Routes.reader(context, book),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(book.isStarted ? 'Reprendre la lecture' : 'Commencer la lecture'),
          ),
        ),
        const SizedBox(width: Space.md),
        _RoundButton(
          tooltip: book.favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
          icon: book.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: book.favorite ? const Color(0xFFE07A8F) : null,
          onTap: () => context.read<LibraryRepository>().setFavorite(book.id!, !book.favorite),
        ),
      ],
    );

    final info = <(String, String)>[
      if (book.publisher.isNotEmpty) ('Éditeur', book.publisher),
      if (book.language.isNotEmpty) ('Langue', book.language),
      ('Format', format.label),
      ('Taille', formatBytes(book.fileSize)),
      ('Ajouté le', formatDate(book.addedAt)),
      if (book.lastOpenedAt != null) ('Dernière lecture', formatRelative(book.lastOpenedAt!)),
      if (book.finishedAt != null) ('Terminé le', formatDate(book.finishedAt!)),
      ('Fichier', book.fileName),
    ];

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (book.description.isNotEmpty) ...[
          Text('À propos', style: t.titleLarge),
          const SizedBox(height: Space.sm),
          AnimatedSize(
            duration: Motion.scaled(context, Motion.medium),
            alignment: Alignment.topCenter,
            child: Text(book.description, style: t.bodyMedium?.copyWith(color: p.textMuted, height: 1.55),
                maxLines: _expanded ? null : 4, overflow: _expanded ? null : TextOverflow.fade),
          ),
          if (book.description.length > 220)
            TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Text(_expanded ? 'Réduire' : 'Lire la suite'),
          ),
        ],
        if (book.categories.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final c in book.categories) Chip(label: Text(c))]),
          const SizedBox(height: Space.lg),
        ],
        _Tile(
          icon: Icons.edit_note_rounded,
          title: 'Note personnelle',
          subtitle: book.personalNote.isEmpty ? 'Ajouter une note' : book.personalNote,
          onTap: () => _editNote(book),
        ),
        _Tile(
          icon: Icons.format_quote_rounded,
          title: 'Annotations et marque-pages',
          subtitle: _annotationCount == 0 ? 'Aucune pour l\'instant' : '$_annotationCount élément${_annotationCount > 1 ? 's' : ''}',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnnotationsScreen(book: book))),
        ),
        _Tile(
          icon: Icons.collections_bookmark_outlined,
          title: 'Collections',
          subtitle: _collections.isEmpty ? 'Ajouter à une collection' : _collections.map((c) => c.name).join(', '),
          onTap: () => _menu(book, 'collection'),
        ),
        const SizedBox(height: Space.lg),
        Text('Informations', style: t.titleLarge),
        const SizedBox(height: Space.sm),
        for (final (k, v) in info)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 130, child: Text(k, style: t.bodyMedium?.copyWith(color: p.textMuted))),
                Expanded(child: Text(v, style: t.bodyMedium)),
              ],
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(tooltip: 'Partager', icon: const Icon(Icons.ios_share_rounded), onPressed: () => BookActions.share(book)),
          PopupMenuButton<String>(
            onSelected: (a) => _menu(book, a),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Modifier les informations')),
              const PopupMenuItem(value: 'collection', child: Text('Ajouter à une collection')),
              if (book.progress > 0) const PopupMenuItem(value: 'reset', child: Text('Réinitialiser la progression')),
              if (!book.isFinished) const PopupMenuItem(value: 'finished', child: Text('Marquer comme terminé')),
              PopupMenuItem(value: 'delete', child: Text('Supprimer', style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Column(children: [header, const SizedBox(height: Space.xl), stats, const SizedBox(height: Space.lg), actions]),
                    ),
                  ),
                  Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(Space.xl), child: details)),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.xxl),
                children: [
                  header,
                  const SizedBox(height: Space.xl),
                  stats,
                  const SizedBox(height: Space.lg),
                  actions,
                  const SizedBox(height: Space.xl),
                  details,
                ],
              ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: p.primary, size: 22),
          const SizedBox(height: 6),
          Text(value, style: t.titleMedium),
          Text(label, style: t.bodySmall),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.tooltip, this.color});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        semanticLabel: tooltip,
        child: AnimatedContainer(
          duration: Motion.scaled(context, Motion.fast),
          width: 52,
          height: 52,
          decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface, border: Border.all(color: p.divider)),
          child: Icon(icon, color: color ?? p.text),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: const BorderRadius.all(Radii.md)),
        child: Icon(icon, color: p.primary),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
