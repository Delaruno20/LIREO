import 'package:shared_preferences/shared_preferences.dart';

import '../data/db/app_database.dart';
import '../data/repositories/annotation_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/stats_repository.dart';
import '../data/settings/app_settings.dart';
import '../services/app_lock.dart';
import '../services/font_service.dart';
import '../services/home_widget_service.dart';
import '../services/reminder_service.dart';
import '../services/import_service.dart';
import '../services/storage.dart';
import '../services/sync/sync_service.dart';
import '../services/sync/sync_state.dart';

/// Conteneur des dépendances, construit une fois au démarrage.
class AppServices {
  AppServices({
    required this.database,
    required this.storage,
    required this.settings,
    required this.library,
    required this.annotations,
    required this.stats,
    required this.importer,
    required this.lock,
    required this.fonts,
    required this.observers,
    required this.sync,
  });

  final AppDatabase database;
  final AppStorage storage;
  final AppSettings settings;
  final LibraryRepository library;
  final AnnotationRepository annotations;
  final StatsRepository stats;
  final ImportService importer;
  final AppLock lock;
  final FontService fonts;
  final LibraryObservers observers;
  final SyncService sync;

  static Future<AppServices> create() async {
    final results = await Future.wait([
      AppDatabase.open(),
      AppStorage.init(),
      SharedPreferences.getInstance(),
    ]);
    final db = results[0] as AppDatabase;
    final storage = results[1] as AppStorage;
    final prefs = results[2] as SharedPreferences;
    final settings = AppSettings(prefs);
    final library = LibraryRepository(db.db);
    final fonts = FontService(storage);
    await fonts.loadInstalled();
    return AppServices(
      database: db,
      storage: storage,
      settings: settings,
      library: library,
      annotations: AnnotationRepository(db.db),
      stats: StatsRepository(db.db),
      importer: ImportService(library, storage),
      lock: AppLock(settings),
      fonts: fonts,
      observers: LibraryObservers(library, settings, ReminderService())..start(),
      sync: SyncService(prefs, SyncState(db.db, settings), library)..start(),
    );
  }
}
