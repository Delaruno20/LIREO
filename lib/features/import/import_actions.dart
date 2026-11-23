import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/errors.dart';
import '../../formats/format_registry.dart';
import '../../services/import_service.dart';
import 'file_manager_screen.dart';

abstract final class ImportActions {
  /// Ouvre le sélecteur de fichiers natif (sélection multiple).
  static Future<void> pickFiles(BuildContext context) async {
    final List<PlatformFile> files;
    try {
      // FileType.any : Android ne connaît pas le type MIME de FB2, AZW3…
      // Le filtrage est fait par le registre de formats.
      files = await FilePicker.pickFiles(dialogTitle: 'Importer des livres');
    } catch (e, st) {
      AppError.report(e, st, context: 'picker');
      AppError.toast('Impossible d\'ouvrir le sélecteur de fichiers');
      return;
    }
    if (files.isEmpty || !context.mounted) return;
    final sources = [
      for (final f in files)
        ImportSource(name: f.name, path: f.path, open: f.path == null ? f.readAsByteStream : null),
    ];
    await run(context, sources);
  }

  static Future<void> openFileManager(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FileManagerScreen()));

  /// Lance l'import et affiche la progression dans une feuille.
  static Future<void> run(BuildContext context, List<ImportSource> sources) async {
    final importer = context.read<ImportService>();
    final future = importer.enqueue(sources);
    showModalBottomSheet<void>(context: context, builder: (_) => const ImportProgressSheet());
    final items = await future;
    final ok = items.where((i) => i.status == ImportStatus.done).length;
    final dup = items.where((i) => i.status == ImportStatus.duplicate).length;
    final failed = items.where((i) => i.status == ImportStatus.failed).length;
    final parts = [
      if (ok > 0) '$ok livre${ok > 1 ? 's' : ''} ajouté${ok > 1 ? 's' : ''}',
      if (dup > 0) '$dup déjà présent${dup > 1 ? 's' : ''}',
      if (failed > 0) '$failed échec${failed > 1 ? 's' : ''}',
    ];
    if (parts.isNotEmpty) AppError.toast(parts.join(' · '));
  }

  /// Menu d'import : sélecteur natif ou gestionnaire de fichiers intégré.
  static Future<void> showImportMenu(BuildContext context) {
    final p = LireoPalette.of(context);
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: Text('Ajouter des livres', style: Theme.of(ctx).textTheme.headlineSmall),
              ),
              const SizedBox(height: Space.md),
              ListTile(
                leading: Icon(Icons.file_open_outlined, color: p.primary),
                title: const Text('Choisir des fichiers'),
                subtitle: const Text('Sélecteur de fichiers du système'),
                onTap: () {
                  Navigator.pop(ctx);
                  pickFiles(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.folder_open_rounded, color: p.primary),
                title: const Text('Parcourir l\'appareil'),
                subtitle: const Text('Gestionnaire de fichiers intégré, import de dossiers entiers'),
                onTap: () {
                  Navigator.pop(ctx);
                  openFileManager(context);
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
                child: Text(
                  'Formats : ${FormatRegistry.formats.map((f) => f.label).join(', ')}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ImportProgressSheet extends StatelessWidget {
  const ImportProgressSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final importer = context.watch<ImportService>();
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final items = importer.items.reversed.toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      importer.isRunning ? 'Importation… (${importer.completed}/${importer.items.length})' : 'Importation terminée',
                      style: t.titleLarge,
                    ),
                  ),
                  if (!importer.isRunning)
                    TextButton(
                      onPressed: () {
                        importer.clearFinished();
                        Navigator.pop(context);
                      },
                      child: const Text('Fermer'),
                    ),
                ],
              ),
            ),
            if (importer.isRunning)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
                child: LinearProgressIndicator(
                  value: importer.items.isEmpty ? null : importer.completed / importer.items.length,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final (icon, color) = switch (item.status) {
                    ImportStatus.queued => (Icons.schedule_rounded, p.textMuted),
                    ImportStatus.running => (Icons.downloading_rounded, p.primary),
                    ImportStatus.done => (Icons.check_circle_rounded, const Color(0xFF5E8C5A)),
                    ImportStatus.duplicate => (Icons.content_copy_rounded, p.accent),
                    ImportStatus.failed => (Icons.error_outline_rounded, Theme.of(context).colorScheme.error),
                  };
                  return ListTile(
                    dense: true,
                    leading: item.status == ImportStatus.running
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(icon, color: color),
                    title: Text(item.book?.title ?? item.source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: item.message != null ? Text(item.message!, maxLines: 2) : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
