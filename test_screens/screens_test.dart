// ignore_for_file: invalid_use_of_visible_for_testing_member
// Captures d'écran des écrans réels (vraies polices, vraie base SQLite,
// vrais EPUB importés). Usage :
//   flutter test test_screens/screens_test.dart --update-goldens
// Les PNG sont écrits dans test_screens/goldens/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lireo/app/app.dart';
import 'package:lireo/app/routes.dart';
import 'package:lireo/app/services.dart';
import 'package:lireo/core/design/palette.dart';
import 'package:lireo/core/design/seasonal.dart';
import 'package:lireo/data/db/app_database.dart';
import 'package:lireo/data/models/book.dart';
import 'package:lireo/data/models/library_models.dart';
import 'package:lireo/data/repositories/annotation_repository.dart';
import 'package:lireo/data/repositories/library_repository.dart';
import 'package:lireo/data/repositories/stats_repository.dart';
import 'package:lireo/data/settings/app_settings.dart';
import 'package:lireo/services/app_lock.dart';
import 'package:lireo/services/font_service.dart';
import 'package:lireo/services/home_widget_service.dart';
import 'package:lireo/services/reminder_service.dart';
import 'package:lireo/services/import_service.dart';
import 'package:lireo/services/storage.dart';
import 'package:lireo/services/sync/sync_service.dart';
import 'package:lireo/services/sync/sync_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test/test_utils.dart';

Future<void> _loadFonts() async {
  final families = <String, List<String>>{};
  for (final f in Directory('assets/fonts').listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    final family = switch (name.split('-').first) {
      'inter' => 'Inter',
      'lora' => 'Lora',
      'literata' => 'Literata',
      'merriweather' => 'Merriweather',
      _ => 'Atkinson',
    };
    (families[family] ??= []).add(f.path);
  }
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final path in e.value) {
      loader.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    }
    await loader.load();
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/development/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(
        File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

/// Couverture peinte (dégradé + titre) pour exercer l'extraction des couvertures.
Future<Uint8List> _paintCover(String title, Color a, Color b) async {
  const size = Size(400, 600);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, size.height), [a, b]));
  canvas.drawCircle(const Offset(200, 330), 110, Paint()..color = Colors.white.withValues(alpha: 0.12));
  canvas.drawCircle(const Offset(200, 330), 70, Paint()..color = const Color(0xFFE9C987).withValues(alpha: 0.5));
  final tp = TextPainter(
    text: TextSpan(text: title, style: const TextStyle(fontFamily: 'Lora', fontSize: 46, color: Color(0xFFF6E7C8), fontWeight: FontWeight.w600)),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 340);
  tp.paint(canvas, Offset((size.width - tp.width) / 2, 60));
  final image = await recorder.endRecording().toImage(400, 600);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

const _prose = '''
<p>Le vent s'était levé avant l'aube, et avec lui l'odeur salée des marées d'automne. Élise poussa la porte de l'atelier, où les horloges attendaient en silence que quelqu'un les remonte.</p>
<p>Chaque mécanisme avait son caractère. La grande comtoise du fond grognait au moindre courant d'air ; la petite pendule de voyage, au contraire, battait avec une obstination joyeuse, comme si le temps ne pouvait rien contre elle.</p>
<p>Elle alluma la lampe, déroula son étui d'outils et choisit la plus fine des pinces. Le cadran qu'on lui avait confié la veille portait une inscription presque effacée : <em>« À celle qui écoute les heures »</em>.</p>
<p>Dehors, les mouettes tournaient au-dessus du port. Les pêcheurs rentraient, les filets lourds, et quelqu'un chantait sur le quai une chanson qu'Élise n'avait plus entendue depuis l'enfance.</p>
<p>Elle ouvrit le boîtier. À l'intérieur, au lieu des rouages attendus, reposait une minuscule carte marine, pliée avec un soin extrême, et marquée d'une croix à l'encre bleue.</p>
<p>Le cœur battant, elle la déplia sur l'établi. Les contours de la côte lui étaient familiers, mais l'île dessinée au large n'existait sur aucune des cartes qu'elle connaissait.</p>
<p>« Une île qui n'existe pas », murmura-t-elle. Et pourtant, la main qui l'avait tracée ne tremblait pas.</p>
<p>Elle passa la matinée à comparer les relevés, les échelles, les profondeurs. À midi, elle avait la certitude que la carte était exacte — et que quelqu'un, quelque part, voulait qu'elle la trouve.</p>
''';

void main() {
  testWidgets('captures des écrans principaux', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    late AppServices services;
    late Book featured;
    await tester.runAsync(() async {
      await _loadFonts();
      sqfliteFfiInit();
      SharedPreferences.setMockInitialValues({'onboardingDone': true});
      final db = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
      final storage = await AppStorage.init(root: Directory.systemTemp.createTempSync('lireo_shots'));
      final settings = AppSettings(await SharedPreferences.getInstance(), clock: () => DateTime(2026, 11, 19));
      final library = LibraryRepository(db.db);
      services = AppServices(
        database: db,
        storage: storage,
        settings: settings,
        library: library,
        annotations: AnnotationRepository(db.db),
        stats: StatsRepository(db.db),
        importer: ImportService(library, storage),
        lock: AppLock(settings),
        fonts: FontService(storage),
        observers: LibraryObservers(library, settings, ReminderService()),
        sync: SyncService(await SharedPreferences.getInstance(), SyncState(db.db, settings), library),
      );

      final books = [
        ('L\'Horloger des marées', 'Élise Marchal', ['Aventure'], (const Color(0xFF233A52), const Color(0xFF0E1A26))),
        ('Les Jardins de Vellmar', 'Ana Duroc', ['Fantastique'], (const Color(0xFF2F4A3A), const Color(0xFF13241A))),
        ('Atlas des vents', 'Paul Ressac', ['Roman'], (const Color(0xFF8A5A2B), const Color(0xFF3B2410))),
        ('Nuit sur Carthéa', 'Ana Duroc', ['Fantastique'], null),
        ('Le Phare d\'Ysel', 'Marin Lebrun', ['Aventure'], (const Color(0xFF6B2D2D), const Color(0xFF2A0F0F))),
        ('Chroniques de la lanterne', 'Iris Volant', ['Roman'], null),
      ];
      final dir = Directory.systemTemp.createTempSync('lireo_src');
      for (final (title, author, cats, colors) in books) {
        final cover = colors == null ? null : await _paintCover(title, colors.$1, colors.$2);
        final file = File('${dir.path}/${title.hashCode}.epub')
          ..writeAsBytesSync(buildEpub(
            title: title,
            author: author,
            subjects: cats,
            cover: cover,
            chapters: [
              ('Chapitre I', _prose * 2),
              ('Chapitre II', _prose * 2),
              ('Chapitre III', _prose),
            ],
          ));
        await services.importer.importOne(ImportSource(name: '$title.epub', path: file.path));
      }
      final all = await library.books();
      featured = all.firstWhere((b) => b.title.startsWith('L\'Horloger'));
      await library.saveProgress(featured.id!, const BookLocation(chapter: 0), 0.18);
      final second = all.firstWhere((b) => b.title.startsWith('Atlas'));
      await library.saveProgress(second.id!, const BookLocation(chapter: 1), 0.52);
      await library.setFavorite(all.firstWhere((b) => b.title.startsWith('Les Jardins')).id!, true);
      final c = await library.createCollection('Aventures marines');
      await library.addToCollection(c.id!, [featured.id!, all.firstWhere((b) => b.title.startsWith('Le Phare')).id!]);
      final now = DateTime.now();
      for (var d = 0; d < 9; d++) {
        if (d == 4) continue;
        await services.stats.recordSession(ReadingSession(
          bookId: featured.id!,
          startedAt: now.subtract(Duration(days: d, hours: 1)),
          durationMs: (12 + (d * 7) % 25) * 60000,
          pagesRead: 8 + d,
          startProgress: 0,
          endProgress: 0.1,
        ));
      }
      featured = (await library.book(featured.id!))!;
      await services.annotations.add(Annotation(
        bookId: featured.id!,
        kind: AnnotationKind.highlight,
        start: const BookLocation(chapter: 0, offset: 210),
        end: const BookLocation(chapter: 0, offset: 300),
        text: 'surligné',
        color: highlightColors.first,
        createdAt: now,
      ));
    });

    Future<void> settle([int frames = 20]) async {
      for (var i = 0; i < frames; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      await settle();
      await expectLater(find.byType(LireoRoot), matchesGoldenFile('goldens/$name.png'));
    }

    Future<void> back() async {
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle();
    }

    await tester.pumpWidget(LireoRoot(services: services));
    await shot('01_accueil');

    await tester.tap(find.text('Voir tout').first);
    await shot('02_bibliotheque_etageres');
    services.settings.setLibraryLayout(LibraryLayout.grid);
    await shot('03_bibliotheque_grille');
    services.settings.setLibraryLayout(LibraryLayout.shelves);
    await back();
    await settle();

    Routes.bookDetail(tester.element(find.byType(Scaffold).first), featured);
    await shot('04_fiche_livre');

    Routes.reader(tester.element(find.byType(Scaffold).first), featured);
    await settle(40);
    await shot('05_lecteur');
    await tester.tapAt(const Offset(195, 420));
    await shot('06_lecteur_commandes');
    await tester.tapAt(const Offset(195, 420));
    await settle();

    // Page curl à mi-course.
    final gesture = await tester.startGesture(const Offset(370, 700));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(-18, -6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await shot('07_page_curl');
    await gesture.up();
    await settle();

    await back();
    await settle();
    await back();
    await settle();

    await tester.tap(find.text('Statistiques'));
    await shot('08_statistiques');
    await tester.tap(find.text('Collections'));
    await shot('09_collections');
    await tester.tap(find.text('Découvrir'));
    await shot('10_decouvrir');
    await tester.tap(find.text('Paramètres'));
    await shot('11_parametres');

    await services.settings.setTheme(ThemePreset.oledMidnight);
    await tester.tap(find.text('Accueil'));
    await shot('12_accueil_oled');

    for (final (i, e) in SeasonalEvent.values.indexed) {
      await services.settings.forceSeason(e);
      await shot('${13 + i}_evenement_${e.name}');
    }
  });
}
