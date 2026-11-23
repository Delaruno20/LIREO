import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../formats/format_registry.dart';
import '../../services/import_service.dart';
import 'import_actions.dart';

/// Gestionnaire de fichiers intégré : parcourt les dossiers de l'appareil,
/// détecte les fichiers compatibles et importe une sélection ou un dossier entier.
class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  Directory? _dir;
  List<FileSystemEntity> _entries = const [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _permissionDenied = false;
  String? _error;

  static Directory get _root {
    if (Platform.isAndroid) return Directory('/storage/emulated/0');
    return Directory(Platform.environment['HOME'] ?? '/');
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (Platform.isAndroid) {
      // Android 11+ : accès à tous les fichiers ; versions antérieures : stockage.
      var status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) status = await Permission.storage.request();
      if (!status.isGranted) {
        setState(() {
          _permissionDenied = true;
          _loading = false;
        });
        return;
      }
    }
    await _open(_root);
  }

  Future<void> _open(Directory dir) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await dir.list(followLinks: false).where((e) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) return false;
        return e is Directory || (e is File && FormatRegistry.isSupported(e.path));
      }).toList();
      list.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (b is Directory && a is! Directory) return 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
      setState(() {
        _dir = dir;
        _entries = list;
        _selected.clear();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _dir = dir;
        _entries = const [];
        _error = 'Dossier inaccessible';
        _loading = false;
      });
    }
  }

  Future<void> _importSelected() async {
    final sources = [
      for (final path in _selected) ImportSource(name: p.basename(path), path: path),
    ];
    if (sources.isEmpty) return;
    setState(_selected.clear);
    await ImportActions.run(context, sources);
  }

  Future<void> _importFolder() async {
    final dir = _dir;
    if (dir == null) return;
    final files = <ImportSource>[];
    await for (final e in dir.list(recursive: true, followLinks: false).handleError((_) {})) {
      if (e is File && FormatRegistry.isSupported(e.path) && !p.split(e.path).any((s) => s.startsWith('.'))) {
        files.add(ImportSource(name: p.basename(e.path), path: e.path));
      }
      if (files.length >= 5000) break;
    }
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun livre compatible dans ce dossier')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importer le dossier ?'),
        content: Text('${files.length} fichier${files.length > 1 ? 's' : ''} compatible${files.length > 1 ? 's' : ''} trouvé${files.length > 1 ? 's' : ''}, sous-dossiers compris.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Importer')),
        ],
      ),
    );
    if (ok == true && mounted) await ImportActions.run(context, files);
  }

  @override
  Widget build(BuildContext context) {
    final pal = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final dir = _dir;
    final atRoot = dir == null || p.equals(dir.path, _root.path) || dir.parent.path == dir.path;

    Widget body;
    if (_permissionDenied) {
      body = EmptyState(
        icon: Icons.folder_off_outlined,
        title: 'Accès aux fichiers refusé',
        message: 'Autorisez l\'accès aux fichiers pour parcourir l\'appareil, ou utilisez le sélecteur de fichiers du système.',
        action: FilledButton(onPressed: openAppSettings, child: const Text('Ouvrir les réglages')),
      );
    } else if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null || _entries.isEmpty) {
      body = EmptyState(
        icon: Icons.folder_outlined,
        title: _error ?? 'Dossier vide',
        message: _error != null ? 'Ce dossier ne peut pas être lu.' : 'Aucun dossier ni livre compatible ici.',
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: _entries.length,
        itemBuilder: (context, i) {
          final e = _entries[i];
          final name = p.basename(e.path);
          if (e is Directory) {
            return ListTile(
              leading: Icon(Icons.folder_rounded, color: pal.accent),
              title: Text(name),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(e),
            );
          }
          final format = FormatRegistry.forPath(e.path)!;
          final selected = _selected.contains(e.path);
          return ListTile(
            leading: Container(
              width: 44,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: pal.surfaceAlt, borderRadius: const BorderRadius.all(Radii.sm)),
              child: Text(format.label.length > 5 ? format.label.substring(0, 4) : format.label,
                  style: t.labelSmall?.copyWith(color: pal.primary, fontWeight: FontWeight.w700)),
            ),
            title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: FutureBuilder<int>(
              future: (e as File).length(),
              builder: (_, s) => Text(s.hasData ? formatBytes(s.data!) : ''),
            ),
            trailing: Checkbox(
              value: selected,
              onChanged: (v) => setState(() => v == true ? _selected.add(e.path) : _selected.remove(e.path)),
            ),
            onTap: () => setState(() => selected ? _selected.remove(e.path) : _selected.add(e.path)),
          );
        },
      );
    }

    return PopScope(
      canPop: atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && dir != null) _open(dir.parent);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Parcourir'),
              if (dir != null) Text(dir.path, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
          actions: [
            if (dir != null && !_permissionDenied)
              IconButton(
                tooltip: 'Importer tout le dossier',
                icon: const Icon(Icons.drive_folder_upload_outlined),
                onPressed: _importFolder,
              ),
          ],
        ),
        body: body,
        floatingActionButton: _selected.isEmpty
            ? null
            : FloatingActionButton.extended(
                backgroundColor: pal.primary,
                foregroundColor: pal.onPrimary,
                onPressed: _importSelected,
                icon: const Icon(Icons.download_rounded),
                label: Text('Importer ${_selected.length}'),
              ),
      ),
    );
  }
}
