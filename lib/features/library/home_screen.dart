import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/design/palette.dart';
import '../../core/design/seasonal.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/book_cover.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/seasonal_banner.dart';
import '../../core/widgets/shelf.dart';
import '../../data/models/book.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/settings/app_settings.dart';
import '../../services/app_lock.dart';
import '../book/book_actions.dart';
import '../collections/collections_screen.dart';
import '../import/import_actions.dart';
import '../splash/splash_screen.dart';
import 'library_controller.dart';
import 'library_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (c) => HomeController(c.read<LibraryRepository>(), c.read<AppSettings>(), c.read<AppLock>()),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Bonne nuit';
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<HomeController>();
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final scale = context.select<AppSettings, double>((s) => s.coverScale);
    final season = context.select<AppSettings, SeasonalEvent?>((s) => s.activeSeason);
    final width = MediaQuery.sizeOf(context).width;
    final coverW = (width < 600 ? 98.0 : 118.0) * scale;
    void open(Book b, String tag) => Routes.bookDetail(context, b, heroTag: tag);
    void actions(Book b) => BookActions.show(context, b);

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.sm, 0),
            child: Row(
              children: [
                LireoMark(size: 38, color: p.primary),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(season == null ? 'Lireo' : 'Lireo ${season.emoji}', style: t.headlineMedium),
                      Text('${_greeting()} — plongez dans vos histoires', style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Ajouter des livres',
                  style: IconButton.styleFrom(backgroundColor: p.primary, foregroundColor: p.onPrimary),
                  onPressed: () => ImportActions.showImportMenu(context),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
      if (season != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
            child: FadeSlideIn(child: SeasonalBanner(event: season)),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.md),
          child: Hero(
            tag: 'search-bar',
            child: Material(
              color: Colors.transparent,
              child: Pressable(
                scale: 0.99,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
                semanticLabel: 'Rechercher dans la bibliothèque',
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: const BorderRadius.all(Radii.md),
                    border: Border.all(color: p.divider),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: p.textMuted),
                      const SizedBox(width: Space.md),
                      Text('Titre, auteur, catégorie…', style: t.bodyMedium?.copyWith(color: p.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];

    if (c.loading) {
      slivers.add(const SliverFillRemaining(child: Center(child: CircularProgressIndicator())));
    } else if (c.totalBooks == 0) {
      slivers.add(SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.local_library_outlined,
          title: 'Votre bibliothèque vous attend',
          message: 'Ajoutez vos livres numériques : ils seront rangés ici, couvertures comprises.',
          action: FilledButton.icon(
            onPressed: () => ImportActions.showImportMenu(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ajouter des livres'),
          ),
        ),
      ));
    } else {
      if (c.categories.isNotEmpty) {
        slivers.add(SliverToBoxAdapter(
          child: FilterChipsRow(
            labels: ['Tout', ...c.categories.take(12)],
            selected: c.category == null ? 0 : c.categories.indexOf(c.category!) + 1,
            onSelected: (i) => c.setCategory(i == 0 ? null : c.categories[i - 1]),
          ),
        ));
      }
      if (c.continueReading.isNotEmpty && c.category == null) {
        slivers.add(const SliverToBoxAdapter(child: SectionHeader(title: 'Continuer la lecture')));
        slivers.add(SliverToBoxAdapter(child: _ContinueCard(book: c.continueReading.first)));
        if (c.continueReading.length > 1) {
          slivers.add(SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: Space.lg),
              child: ShelfRow(
                books: c.continueReading.skip(1).toList(),
                onOpen: (b, _) => Routes.reader(context, b),
                onLongPress: actions,
                coverWidth: coverW * 0.78,
                heroPrefix: 'continue',
              ),
            ),
          ));
        }
      }
      void section(String title, List<Book> books, String hero, {String? subtitle, VoidCallback? more}) {
        if (books.isEmpty) return;
        slivers.add(SliverToBoxAdapter(
          child: SectionHeader(title: title, subtitle: subtitle, actionLabel: more == null ? null : 'Voir tout', onAction: more),
        ));
        slivers.add(SliverToBoxAdapter(
          child: ShelfRow(books: books, onOpen: open, onLongPress: actions, coverWidth: coverW, heroPrefix: hero),
        ));
      }

      void openLibrary({bool favorites = false}) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LibraryScreen(initialCategory: c.category, favoritesOnly: favorites),
          ));
      section('Ma bibliothèque', c.library, 'lib', subtitle: '${c.totalBooks} livre${c.totalBooks > 1 ? 's' : ''}', more: openLibrary);
      if (c.category == null) {
        section(
          'Recommandés',
          c.recommended,
          'rec',
          subtitle: c.recommendedFromHistory ? 'D\'après vos lectures' : 'À commencer dans votre bibliothèque',
        );
      }
      section('Récemment ajoutés', c.recentlyAdded, 'recent');
      section('Favoris', c.favorites, 'fav', more: () => openLibrary(favorites: true));
      if (c.collections.isNotEmpty && c.category == null) {
        slivers.add(const SliverToBoxAdapter(child: SectionHeader(title: 'Collections')));
        slivers.add(SliverToBoxAdapter(
          child: SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              itemCount: c.collections.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.md),
              itemBuilder: (context, i) => SizedBox(width: 150, child: CollectionCard(collection: c.collections[i])),
            ),
          ),
        ));
      }
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 120)));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: c.reload,
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: slivers),
      ),
    );
  }
}

/// Carte « Continuer la lecture » mise en avant.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Pressable(
        scale: 0.98,
        onTap: () => Routes.reader(context, book),
        onLongPress: () => BookActions.show(context, book),
        semanticLabel: 'Reprendre ${book.title}',
        child: Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.all(Radii.lg),
            border: Border.all(color: p.divider),
            boxShadow: [BoxShadow(color: p.shadow.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10))],
          ),
          child: Row(
            children: [
              BookCover(book: book, width: 84, heroTag: 'continue-main-${book.id}', elevation: 1.4),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title, style: t.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(book.displayAuthor, style: t.bodyMedium?.copyWith(color: p.textMuted), maxLines: 1),
                    const SizedBox(height: Space.md),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(value: book.progress, minHeight: 5),
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Text('${(book.progress * 100).round()} %', style: t.labelMedium),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    Row(
                      children: [
                        Icon(Icons.play_arrow_rounded, color: p.primary, size: 20),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text('Reprendre la lecture',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelLarge?.copyWith(color: p.primary)),
                        ),
                      ],
                    ),
                    if (book.lastOpenedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Lu ${formatRelative(book.lastOpenedAt!)}', style: t.bodySmall),
                      ),
                    Row(
                      children: [
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
