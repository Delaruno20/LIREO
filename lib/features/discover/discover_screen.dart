import 'dart:async';
import 'dart:math';

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
import '../../services/app_lock.dart';
import '../book/book_actions.dart';

/// Découvrir : redécouvrir sa propre bibliothèque (tout est calculé
/// localement, sans connexion ni données externes).
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<Book>? _books;
  Book? _surprise;
  final _random = Random();
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
    var books = await repo.books();
    if (!mounted) return;
    if (context.read<AppSettings>().hidePrivateCollections && !context.read<AppLock>().privateUnlocked) {
      final hidden = await repo.privateBookIds();
      books = books.where((b) => !hidden.contains(b.id)).toList();
    }
    if (!mounted) return;
    setState(() {
      _books = books;
      if (_surprise == null || !books.any((b) => b.id == _surprise!.id)) _pickSurprise();
    });
  }

  void _pickSurprise() {
    final pool = (_books ?? const <Book>[]).where((b) => !b.isFinished && b.id != _surprise?.id).toList();
    _surprise = pool.isEmpty ? null : pool[_random.nextInt(pool.length)];
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    final p = LireoPalette.of(context);
    final slivers = <Widget>[
      SliverAppBar.large(title: const Text('Découvrir'), backgroundColor: p.background),
    ];
    if (books == null) {
      slivers.add(const SliverFillRemaining(child: Center(child: CircularProgressIndicator())));
    } else if (books.isEmpty) {
      slivers.add(const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.explore_outlined,
          title: 'Rien à découvrir pour l\'instant',
          message: 'Ajoutez des livres : cet espace vous aidera à choisir votre prochaine lecture.',
        ),
      ));
    } else {
      void open(Book b, String tag) => Routes.bookDetail(context, b, heroTag: tag);
      void shelf(String title, String subtitle, List<Book> list, String hero) {
        if (list.isEmpty) return;
        slivers
          ..add(SliverToBoxAdapter(child: SectionHeader(title: title, subtitle: subtitle)))
          ..add(SliverToBoxAdapter(
            child: ShelfRow(books: list, onOpen: open, onLongPress: (b) => BookActions.show(context, b), coverWidth: 92, heroPrefix: hero),
          ));
      }

      if (_surprise != null) {
        slivers.add(SliverToBoxAdapter(
          child: _SurpriseCard(
            book: _surprise!,
            onShuffle: () => setState(_pickSurprise),
          ),
        ));
      }
      final unread = books.where((b) => b.lastOpenedAt == null).toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      shelf('À commencer', 'Jamais ouverts', unread.take(15).toList(), 'disc-unread');

      final cutoff = DateTime.now().subtract(const Duration(days: 21));
      final dormant = books.where((b) => b.lastOpenedAt != null && !b.isFinished && b.lastOpenedAt!.isBefore(cutoff)).toList()
        ..sort((a, b) => b.progress.compareTo(a.progress));
      shelf('À redécouvrir', 'Commencés, puis mis de côté', dormant.take(15).toList(), 'disc-dormant');

      final quick = books.where((b) => !b.isFinished && b.pageCount > 0 && b.pageCount * (1 - b.progress) <= 120).toList()
        ..sort((a, b) => (a.pageCount * (1 - a.progress)).compareTo(b.pageCount * (1 - b.progress)));
      shelf('Lectures courtes', 'Moins de 120 pages restantes', quick.take(15).toList(), 'disc-short');

      final byAuthor = <String, List<Book>>{};
      for (final b in books.where((b) => b.author.isNotEmpty)) {
        (byAuthor[b.author] ??= []).add(b);
      }
      final topAuthors = byAuthor.entries.where((e) => e.value.length > 1).toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
      for (final e in topAuthors.take(4)) {
        shelf(e.key, '${e.value.length} livres dans votre bibliothèque', e.value, 'disc-author-${e.key.hashCode}');
      }

      final finished = books.where((b) => b.isFinished).toList()
        ..sort((a, b) => (b.finishedAt ?? b.lastOpenedAt ?? b.addedAt).compareTo(a.finishedAt ?? a.lastOpenedAt ?? a.addedAt));
      shelf('Terminés', 'Votre palmarès', finished.take(15).toList(), 'disc-finished');
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 120)));
    return Scaffold(body: CustomScrollView(slivers: slivers));
  }
}

class _SurpriseCard extends StatelessWidget {
  const _SurpriseCard({required this.book, required this.onShuffle});

  final Book book;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radii.lg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.surface, Color.lerp(p.surface, p.accent, 0.18)!],
          ),
          border: Border.all(color: p.divider),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: Motion.scaled(context, Motion.medium),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: child),
              ),
              child: Pressable(
                key: ValueKey(book.id),
                onTap: () => Routes.bookDetail(context, book, heroTag: 'surprise-${book.id}'),
                child: BookCover(book: book, width: 92, heroTag: 'surprise-${book.id}', elevation: 1.5),
              ),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LIVRE SURPRISE', style: t.labelSmall?.copyWith(color: p.primary, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(book.title, style: t.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(book.displayAuthor, style: t.bodyMedium?.copyWith(color: p.textMuted), maxLines: 1),
                  const SizedBox(height: Space.md),
                  Wrap(
                    spacing: Space.sm,
                    children: [
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                        onPressed: () => Routes.reader(context, book),
                        child: Text(book.isStarted ? 'Reprendre' : 'Commencer'),
                      ),
                      IconButton(tooltip: 'Un autre', onPressed: onShuffle, icon: const Icon(Icons.shuffle_rounded)),
                    ],
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
