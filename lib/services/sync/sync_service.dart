import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors.dart';
import '../../data/repositories/library_repository.dart';
import 'sync_merge.dart';
import 'sync_providers.dart';
import 'sync_state.dart';

enum SyncStatus { off, idle, syncing, error }

/// Synchronisation facultative : la lecture hors ligne ne dépend jamais d'elle.
/// Elle s'exécute au démarrage, après les changements de la bibliothèque
/// (regroupés) et à la demande.
class SyncService extends ChangeNotifier {
  SyncService(this._prefs, this._state, this._library)
      : providers = [DropboxProvider(_prefs), GoogleDriveProvider(_prefs)];

  final SharedPreferences _prefs;
  final SyncState _state;
  final LibraryRepository _library;
  final List<SyncProvider> providers;

  SyncStatus status = SyncStatus.off;
  String? lastError;
  StreamSubscription<void>? _sub;
  Timer? _debounce;
  DateTime? _quietUntil;

  SyncProvider? get active {
    final id = _prefs.getString('sync.provider');
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  DateTime? get lastSync {
    final ms = _prefs.getInt('sync.last');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> start() async {
    _sub = _library.changes.listen((_) => _schedule());
    final provider = active;
    if (provider == null) return;
    if (await provider.restore()) {
      status = SyncStatus.idle;
      notifyListeners();
      unawaited(syncNow());
    } else {
      status = SyncStatus.error;
      lastError = 'Reconnexion à ${provider.label} nécessaire';
      notifyListeners();
    }
  }

  void _schedule() {
    if (status == SyncStatus.off || status == SyncStatus.syncing) return;
    if (_quietUntil != null && DateTime.now().isBefore(_quietUntil!)) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 20), () => unawaited(syncNow()));
  }

  Future<void> connect(SyncProvider provider) async {
    await provider.connect();
    final previous = active;
    if (previous != null && previous.id != provider.id) await previous.disconnect();
    await _prefs.setString('sync.provider', provider.id);
    status = SyncStatus.idle;
    notifyListeners();
    await syncNow();
  }

  Future<void> disconnect() async {
    await active?.disconnect();
    await _prefs.remove('sync.provider');
    status = SyncStatus.off;
    lastError = null;
    notifyListeners();
  }

  /// Télécharge l'état distant, fusionne, applique localement, renvoie l'état fusionné.
  Future<bool> syncNow() async {
    final provider = active;
    if (provider == null || status == SyncStatus.syncing) return false;
    status = SyncStatus.syncing;
    lastError = null;
    notifyListeners();
    try {
      final local = await _state.export();
      final raw = await provider.download();
      Map<String, dynamic> merged = local;
      if (raw != null) {
        final remote = jsonDecode(raw);
        if (remote is! Map || remote['format'] != SyncMerge.format) {
          throw const UserFacingError('Le fichier distant n\'est pas une synchronisation LIREO');
        }
        merged = SyncMerge.merge(local, Map<String, dynamic>.from(remote));
        await _state.apply(merged);
      }
      await provider.upload(jsonEncode(merged));
      await _prefs.setInt('sync.last', DateTime.now().millisecondsSinceEpoch);
      status = SyncStatus.idle;
      // Les changements appliqués ne doivent pas relancer une synchronisation.
      _quietUntil = DateTime.now().add(const Duration(seconds: 5));
      _library.notifyChanged();
      return true;
    } catch (e, st) {
      AppError.report(e, st, context: 'sync');
      status = SyncStatus.error;
      lastError = AppError.describe(e);
      return false;
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
