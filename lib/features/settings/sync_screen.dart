import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/errors.dart';
import '../../core/widgets/common.dart';
import '../../services/sync/sync_providers.dart';
import '../../services/sync/sync_service.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  Future<void> _connect(BuildContext context, SyncProvider provider) async {
    if (!provider.configured) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${provider.label} n\'est pas configuré'),
          content: Text(provider.setupHint),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Compris'))],
        ),
      );
      return;
    }
    await AppError.guard(() => context.read<SyncService>().connect(provider), context: 'sync.connect');
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final active = sync.active;
    final statusText = switch (sync.status) {
      SyncStatus.off => 'Désactivée — tout reste sur cet appareil',
      SyncStatus.syncing => 'Synchronisation en cours…',
      SyncStatus.error => sync.lastError ?? 'Erreur de synchronisation',
      SyncStatus.idle => sync.lastSync == null ? 'Connecté' : 'Dernière synchronisation : ${formatRelative(sync.lastSync!)}',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
      body: ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: [
          Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(color: p.surface, borderRadius: const BorderRadius.all(Radii.lg), border: Border.all(color: p.divider)),
            child: Row(children: [
              Icon(
                switch (sync.status) {
                  SyncStatus.off => Icons.cloud_off_outlined,
                  SyncStatus.syncing => Icons.cloud_sync_outlined,
                  SyncStatus.error => Icons.error_outline_rounded,
                  SyncStatus.idle => Icons.cloud_done_outlined,
                },
                color: sync.status == SyncStatus.error ? Theme.of(context).colorScheme.error : p.primary,
                size: 32,
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(active == null ? 'Aucun service' : '${active.label}${active.account != null ? ' · ${active.account}' : ''}',
                      style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text(statusText, style: t.bodySmall),
                ]),
              ),
              if (sync.status == SyncStatus.syncing) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
          const SizedBox(height: Space.lg),
          if (active != null) ...[
            FilledButton.icon(
              onPressed: sync.status == SyncStatus.syncing ? null : () => sync.syncNow(),
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Synchroniser maintenant'),
            ),
            const SizedBox(height: Space.sm),
            OutlinedButton(onPressed: sync.disconnect, child: Text('Déconnecter ${active.label}')),
            const SizedBox(height: Space.xl),
          ],
          Text('Services', style: t.titleLarge),
          const SizedBox(height: Space.sm),
          for (final provider in sync.providers)
            Card(
              margin: const EdgeInsets.only(bottom: Space.md),
              child: ListTile(
                leading: Icon(provider.id == 'dropbox' ? Icons.inbox_outlined : Icons.add_to_drive_outlined, color: p.primary),
                title: Text(provider.label),
                subtitle: Text(provider.configured ? (active?.id == provider.id ? 'Connecté' : 'Disponible') : 'Non configuré dans cette version'),
                trailing: active?.id == provider.id ? Icon(Icons.check_circle_rounded, color: p.primary) : const Icon(Icons.chevron_right_rounded),
                onTap: active?.id == provider.id ? null : () => _connect(context, provider),
              ),
            ),
          const SizedBox(height: Space.lg),
          Text('Ce qui est synchronisé', style: t.titleSmall),
          const SizedBox(height: Space.sm),
          Text(
            'Progression et position de lecture, marque-pages, surlignages et notes, collections, favoris et notes '
            'personnelles, statistiques et réglages de lecture. Les fichiers des livres ne sont pas envoyés : un livre '
            'est reconnu sur chaque appareil par son empreinte une fois importé.\n\n'
            'Les données sont stockées dans un dossier réservé à LIREO (dossier d\'application Dropbox, espace caché '
            'Google Drive). La lecture fonctionne toujours hors ligne ; la synchronisation reprend à la connexion suivante.',
            style: t.bodyMedium?.copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }
}
