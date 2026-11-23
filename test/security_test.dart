import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lireo/app/services.dart';
import 'package:lireo/core/design/app_theme.dart';
import 'package:lireo/data/db/app_database.dart';
import 'package:lireo/data/repositories/annotation_repository.dart';
import 'package:lireo/data/repositories/library_repository.dart';
import 'package:lireo/data/repositories/stats_repository.dart';
import 'package:lireo/data/settings/app_settings.dart';
import 'package:lireo/features/settings/settings_screen.dart';
import 'package:lireo/services/app_lock.dart';
import 'package:lireo/services/font_service.dart';
import 'package:lireo/services/home_widget_service.dart';
import 'package:lireo/services/import_service.dart';
import 'package:lireo/services/reminder_service.dart';
import 'package:lireo/services/storage.dart';
import 'package:lireo/services/sync/sync_service.dart';
import 'package:lireo/services/sync/sync_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('temporisation du PIN', () {
    late AppSettings settings;
    late AppLock lock;
    var now = DateTime(2026, 11, 19, 12);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = AppSettings(await SharedPreferences.getInstance());
      await settings.setPin('2468');
      now = DateTime(2026, 11, 19, 12);
      lock = AppLock(settings, clock: () => now, observeLifecycle: false);
    });

    test('paliers', () {
      expect(AppLock.lockoutFor(4), Duration.zero);
      expect(AppLock.lockoutFor(5), const Duration(seconds: 30));
      expect(AppLock.lockoutFor(6), const Duration(seconds: 60));
      expect(AppLock.lockoutFor(50), const Duration(minutes: 15));
    });

    test('5 codes faux bloquent, même le bon code, puis le délai expire', () {
      for (var i = 0; i < 4; i++) {
        expect(lock.checkPin('0000'), PinCheck.wrong);
      }
      expect(lock.lockoutRemaining, Duration.zero);
      expect(lock.checkPin('0000'), PinCheck.wrong);
      expect(lock.lockoutRemaining, const Duration(seconds: 30));
      expect(lock.checkPin('2468'), PinCheck.lockedOut);
      expect(settings.pinFailures, 5, reason: 'une saisie bloquée ne compte pas');

      now = now.add(const Duration(seconds: 31));
      expect(lock.checkPin('1111'), PinCheck.wrong);
      expect(lock.lockoutRemaining, const Duration(seconds: 60), reason: 'le délai double');
      now = now.add(const Duration(seconds: 61));
      expect(lock.unlockWithPin('2468'), PinCheck.ok);
      expect(settings.pinFailures, 0);
      expect(lock.lockoutRemaining, Duration.zero);
    });

    test('le compteur survit à un redémarrage', () async {
      for (var i = 0; i < 5; i++) {
        lock.checkPin('9999');
      }
      final restarted = AppLock(AppSettings(await SharedPreferences.getInstance()), clock: () => now, observeLifecycle: false);
      expect(restarted.checkPin('2468'), PinCheck.lockedOut);
    });

    test('validation automatique seulement à la longueur du PIN', () {
      expect(lock.isFullLength('246'), isFalse);
      expect(lock.isFullLength('2468'), isTrue);
    });
  });

  group('paramètres protégés', () {
    late AppServices services;

    Future<void> pumpSettings(WidgetTester tester) async {
      await tester.runAsync(() async {
        sqfliteFfiInit();
        SharedPreferences.setMockInitialValues({'onboardingDone': true});
        final prefs = await SharedPreferences.getInstance();
        final db = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
        final storage = await AppStorage.init(root: Directory.systemTemp.createTempSync('lireo_sec'));
        final settings = AppSettings(prefs);
        await settings.setPin('2468');
        final library = LibraryRepository(db.db);
        services = AppServices(
          database: db,
          storage: storage,
          settings: settings,
          library: library,
          annotations: AnnotationRepository(db.db),
          stats: StatsRepository(db.db),
          importer: ImportService(library, storage),
          lock: AppLock(settings, observeLifecycle: false),
          fonts: FontService(storage),
          observers: LibraryObservers(library, settings, ReminderService()),
          sync: SyncService(prefs, SyncState(db.db, settings), library),
        );
      });
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider.value(value: services),
          ChangeNotifierProvider.value(value: services.settings),
          ChangeNotifierProvider.value(value: services.lock),
          ChangeNotifierProvider.value(value: services.fonts),
          ChangeNotifierProvider.value(value: services.sync),
        ],
        child: MaterialApp(theme: buildTheme(services.settings.palette), home: const SettingsScreen()),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> type(WidgetTester tester, String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.text(d).last);
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('supprimer le PIN exige le code actuel', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Supprimer le code PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmez votre identité'), findsOneWidget);

      await type(tester, '1111');
      expect(find.textContaining('Code incorrect'), findsOneWidget);
      expect(services.settings.hasPin, isTrue);

      await type(tester, '2468');
      expect(find.text('Confirmez votre identité'), findsNothing);
      expect(services.settings.hasPin, isFalse);
    });

    testWidgets('annuler laisse le PIN et le masquage intacts', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Masquer les collections privées'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmez votre identité'), findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(services.settings.hidePrivateCollections, isTrue);

      await tester.tap(find.text('Modifier le code PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmez votre identité'), findsOneWidget, reason: 'pas de nouveau code sans l\'ancien');
      await type(tester, '2468');
      expect(find.text('Nouveau code PIN'), findsOneWidget);
    });

    testWidgets('temporisation affichée après 5 codes faux', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Supprimer le code PIN'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await type(tester, '0000');
      }
      expect(find.textContaining('Réessayez dans'), findsOneWidget);
      await type(tester, '2468');
      expect(services.settings.hasPin, isTrue, reason: 'le bon code est refusé pendant l\'attente');
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
    });
  });
}
