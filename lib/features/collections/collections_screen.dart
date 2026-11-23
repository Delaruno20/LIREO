import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/errors.dart';
import '../../core/widgets/common.dart';
import '../../data/models/library_models.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/settings/app_settings.dart';
import '../../services/app_lock.dart';
import '../book/book_actions.dart';
import '../library/library_screen.dart';
import '../security/unlock_dialog.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  List<BookCollection>? _collections;
  StreamSubscription<void>? _sub;
  late final AppLock _lock = context.read<AppLock>();

  @override
  void initState() {
    super.initState();
    _sub = context.read<LibraryRepository>().changes.listen((_) => _load());
    _lock.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _lock.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final list = await context.read<LibraryRepository>().collections();
    if (mounted) setState(() => _collections = list);
  }

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final list = _collections;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Collections'),
            backgroundColor: p.background,
            actions: [
              IconButton(
                tooltip: 'Nouvelle collection',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => BookActions.createCollectionDialog(context),
              ),
            ],
          ),
          if (list == null)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.collections_bookmark_outlined,
                title: 'Aucune collection',
                message: 'Regroupez vos livres par thème, saga ou envie. Une collection peut être privée.',
                action: FilledButton.icon(
                  onPressed: () => BookActions.createCollectionDialog(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Créer une collection'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: Space.lg,
                  crossAxisSpacing: Space.lg,
                  childAspectRatio: 0.78,
                ),
                itemCount: list.length,
                itemBuilder: (context, i) => FadeSlideIn(index: i, child: CollectionCard(collection: list[i])),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

/// Carte de collection : couvertures en éventail.
class CollectionCard extends StatelessWidget {
  const CollectionCard({super.key, required this.collection});

  final BookCollection collection;

  Future<void> _open(BuildContext context) async {
    final lock = context.read<AppLock>();
    if (collection.isPrivate && !lock.privateUnlocked) {
      final ok = await showUnlockDialog(context);
      if (!ok || !context.mounted) return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LibraryScreen(collectionId: collection.id, title: collection.name),
    ));
  }

  Future<void> _menu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Modifier'), onTap: () => Navigator.pop(ctx, 'edit')),
            ListTile(leading: const Icon(Icons.ios_share_rounded), title: const Text('Partager la liste'), onTap: () => Navigator.pop(ctx, 'share')),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error),
              title: Text('Supprimer la collection', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              subtitle: const Text('Les livres restent dans la bibliothèque'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    final repo = context.read<LibraryRepository>();
    switch (action) {
      case 'edit':
        await BookActions.createCollectionDialog(context, editing: collection);
      case 'share':
        final books = await repo.booksInCollection(collection.id!);
        final text = StringBuffer('📚 ${collection.name}\n');
        if (collection.description.isNotEmpty) text.writeln(collection.description);
        text.writeln();
        for (final b in books) {
          text.writeln('• ${b.title}${b.author.isNotEmpty ? ' — ${b.author}' : ''}');
        }
        await AppError.guard(() => SharePlus.instance.share(ShareParams(text: text.toString(), subject: collection.name)));
      case 'delete':
        await repo.deleteCollection(collection.id!);
        AppError.toast('Collection supprimée');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final locked = collection.isPrivate &&
        !context.select<AppLock, bool>((l) => l.privateUnlocked) &&
        context.select<AppSettings, bool>((s) => s.hidePrivateCollections);
    final covers = locked ? const <String>[] : collection.coverPaths;
    return Pressable(
      onTap: () => _open(context),
      onLongPress: () => _menu(context),
      semanticLabel: 'Collection ${collection.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: const BorderRadius.all(Radii.md),
              ),
              child: LayoutBuilder(builder: (context, c) {
                final w = c.maxHeight * 0.62 / 1.5 * 1.0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (covers.isEmpty)
                      Icon(locked ? Icons.lock_rounded : Icons.collections_bookmark_outlined, size: 36, color: p.textMuted),
                    for (var i = covers.length - 1; i >= 0; i--)
                      Transform.translate(
                        offset: Offset((i - (covers.length - 1) / 2) * w * 0.42, 0),
                        child: Transform.rotate(
                          angle: (i - (covers.length - 1) / 2) * 0.09,
                          child: Container(
                            width: w,
                            height: w * 1.5,
                            decoration: BoxDecoration(
                              borderRadius: Radii.cover,
                              boxShadow: [BoxShadow(color: p.shadow, blurRadius: 10, offset: const Offset(2, 5))],
                              image: DecorationImage(
                                image: ResizeImage(FileImage(File(covers[i])), width: (w * 2.5).round()),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              if (collection.isPrivate) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.lock_outline_rounded, size: 14, color: p.textMuted)),
              Expanded(child: Text(collection.name, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          Text(locked ? 'Privée' : '${collection.bookCount} livre${collection.bookCount > 1 ? 's' : ''}', style: t.bodySmall),
        ],
      ),
    );
  }
}
