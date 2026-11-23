import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/routes.dart';
import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/errors.dart';
import '../../core/widgets/book_cover.dart';
import '../../data/models/book.dart';
import '../../data/models/library_models.dart';
import '../../data/repositories/library_repository.dart';
import '../../services/import_service.dart';

/// Actions communes sur un ou plusieurs livres.
abstract final class BookActions {
  static Future<void> show(BuildContext context, Book book) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
              leading: Icon(icon, color: color ?? p.text),
              title: Text(label, style: TextStyle(color: color)),
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
                  child: Row(
                    children: [
                      BookCover(book: book, width: 44, elevation: 0.6),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(book.title, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                            Text(book.displayAuthor, style: t.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                item(Icons.menu_book_rounded, book.isStarted ? 'Reprendre la lecture' : 'Commencer la lecture',
                    () => Routes.reader(context, book)),
                item(Icons.info_outline_rounded, 'Fiche du livre', () => Routes.bookDetail(context, book)),
                item(book.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    book.favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                    () => context.read<LibraryRepository>().setFavorite(book.id!, !book.favorite)),
                item(Icons.playlist_add_rounded, 'Ajouter à une collection', () => addToCollection(context, [book])),
                item(Icons.ios_share_rounded, 'Partager le fichier', () => share(book)),
                item(Icons.delete_outline_rounded, 'Supprimer', () => delete(context, [book]),
                    color: Theme.of(context).colorScheme.error),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> share(Book book) => AppError.guard(
        () => SharePlus.instance.share(ShareParams(
          files: [XFile(book.path)],
          fileNameOverrides: [book.fileName],
          subject: book.title,
        )),
        context: 'share',
      );

  static Future<bool> delete(BuildContext context, List<Book> books) async {
    final many = books.length > 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(many ? 'Supprimer ${books.length} livres ?' : 'Supprimer ce livre ?'),
        content: Text(
          many
              ? 'Les fichiers, progressions, annotations et statistiques associés seront supprimés de LIREO.'
              : '« ${books.first.title} » sera retiré de LIREO, avec sa progression et ses annotations.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    await AppError.guard(() => context.read<ImportService>().deleteBooks(books), context: 'delete');
    AppError.toast(many ? '${books.length} livres supprimés' : 'Livre supprimé');
    return true;
  }

  /// Choix (ou création) d'une collection pour une sélection de livres.
  static Future<void> addToCollection(BuildContext context, List<Book> books) async {
    final repo = context.read<LibraryRepository>();
    final collections = await repo.collections();
    if (!context.mounted) return;
    final chosen = await showModalBottomSheet<BookCollection>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: Text('Ajouter à une collection', style: Theme.of(ctx).textTheme.headlineSmall),
              ),
              const SizedBox(height: Space.sm),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: const Text('Nouvelle collection…'),
                onTap: () async {
                  final created = await createCollectionDialog(ctx);
                  if (created != null && ctx.mounted) Navigator.pop(ctx, created);
                },
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in collections)
                      ListTile(
                        leading: Icon(c.isPrivate ? Icons.lock_outline_rounded : Icons.collections_bookmark_outlined),
                        title: Text(c.name),
                        subtitle: Text('${c.bookCount} livre${c.bookCount > 1 ? 's' : ''}'),
                        onTap: () => Navigator.pop(ctx, c),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    await repo.addToCollection(chosen.id!, [for (final b in books) b.id!]);
    AppError.toast('Ajouté à « ${chosen.name} »');
  }

  static Future<BookCollection?> createCollectionDialog(BuildContext context, {BookCollection? editing}) async {
    final name = TextEditingController(text: editing?.name);
    final description = TextEditingController(text: editing?.description);
    var isPrivate = editing?.isPrivate ?? false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(editing == null ? 'Nouvelle collection' : 'Modifier la collection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(hintText: 'Nom')),
              const SizedBox(height: Space.md),
              TextField(controller: description, decoration: const InputDecoration(hintText: 'Description (facultatif)')),
              const SizedBox(height: Space.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isPrivate,
                onChanged: (v) => setState(() => isPrivate = v),
                title: const Text('Collection privée'),
                subtitle: const Text('Masquée tant que LIREO n\'est pas déverrouillé par PIN'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (result != true || name.text.trim().isEmpty || !context.mounted) return null;
    final repo = context.read<LibraryRepository>();
    if (editing != null) {
      final updated = BookCollection(
        id: editing.id,
        name: name.text.trim(),
        description: description.text.trim(),
        isPrivate: isPrivate,
        createdAt: editing.createdAt,
      );
      await repo.updateCollection(updated);
      return updated;
    }
    return repo.createCollection(name.text.trim(), description: description.text.trim(), isPrivate: isPrivate);
  }
}
