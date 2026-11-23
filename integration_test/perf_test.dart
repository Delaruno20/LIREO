// Mesures de performance sur appareil réel (mode profile) :
//   flutter drive --profile -d <appareil> --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart
// Tout est généré dans le dossier temporaire de l'app ; la base est en
// mémoire et les préférences simulées : la bibliothèque de l'utilisateur
// n'est jamais touchée. Résultats : build/perf/perf_report.json.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lireo/app/app.dart';
import 'package:lireo/app/services.dart';
import 'package:lireo/data/db/app_database.dart';
import 'package:lireo/data/models/book.dart';
import 'package:lireo/data/repositories/annotation_repository.dart';
import 'package:lireo/data/repositories/library_repository.dart';
import 'package:lireo/data/repositories/stats_repository.dart';
import 'package:lireo/data/settings/app_settings.dart';
import 'package:lireo/features/library/library_screen.dart';
import 'package:lireo/features/reader/model/reader_prefs.dart';
import 'package:lireo/features/reader/reader_screen.dart';
import 'package:lireo/features/reader/reflow/page_layout.dart';
import 'package:lireo/features/reader/reflow/page_turner.dart';
import 'package:lireo/formats/adapters/epub_adapter.dart';
import 'package:lireo/services/app_lock.dart';
import 'package:lireo/services/font_service.dart';
import 'package:lireo/services/home_widget_service.dart';
import 'package:lireo/services/import_service.dart';
import 'package:lireo/services/reminder_service.dart';
import 'package:lireo/services/storage.dart';
import 'package:lireo/services/sync/sync_service.dart';
import 'package:lireo/services/sync/sync_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:archive/archive.dart';

import '../test/test_utils.dart';

const _libraryBooks = int.fromEnvironment('PERF_BOOKS', defaultValue: 300);

const _para = 'Le vent tournait sur la jetée lorsque Marin referma le carnet. Les horloges du port, '
    'toutes réglées sur la marée, sonnaient avec un léger décalage, comme une conversation '
    'qui hésite. Il compta les secondes entre deux tintements et sourit : la mer avait encore '
    'gagné trois minutes sur la ville. ';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final report = <String, dynamic>{};

  double mb(int bytes) => (bytes / (1024 * 1024) * 10).roundToDouble() / 10;
  void memory(String phase) {
    report['rss_$phase'] = mb(ProcessInfo.currentRss);
    report['imageCache_$phase'] = mb(PaintingBinding.instance.imageCache.currentSizeBytes);
    debugPrint('PERF mémoire $phase : RSS ${report['rss_$phase']} Mo, cache images ${report['imageCache_$phase']} Mo');
  }

  /// Exécute [action] en relevant les temps de chaque image.
  Future<void> frames(String name, Future<void> Function() action) async {
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);
    await action();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    SchedulerBinding.instance.removeTimingsCallback(collect);
    if (timings.isEmpty) return;
    double ms(Duration d) => d.inMicroseconds / 1000;
    List<double> sorted(Iterable<double> v) => v.toList()..sort();
    final build = sorted(timings.map((t) => ms(t.buildDuration)));
    final raster = sorted(timings.map((t) => ms(t.rasterDuration)));
    final total = sorted(timings.map((t) => ms(t.totalSpan)));
    double pct(List<double> v, double p) => v[math.min(v.length - 1, (v.length * p).floor())];
    double r(double v) => (v * 10).roundToDouble() / 10;
    // Écran 120 Hz possible : on compte les images au-delà de 16,7 ms (60 i/s).
    final janky = total.where((t) => t > 16.7).length;
    report[name] = {
      'frames': timings.length,
      'build_avg': r(build.reduce((a, b) => a + b) / build.length),
      'build_p90': r(pct(build, 0.9)),
      'raster_avg': r(raster.reduce((a, b) => a + b) / raster.length),
      'raster_p90': r(pct(raster, 0.9)),
      'total_p99': r(pct(total, 0.99)),
      'worst': r(total.last),
      'janky_pct': r(janky * 100 / timings.length),
    };
    debugPrint('PERF $name ${jsonEncode(report[name])}');
  }

  testWidgets('performances', (tester) async {
    await pdfrxFlutterInitialize();
    final tmp = Directory('${(await getTemporaryDirectory()).path}/lireo_perf');
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    final src = Directory('${tmp.path}/src')..createSync(recursive: true);

    SharedPreferences.setMockInitialValues({'onboardingDone': true});
    final prefs = await SharedPreferences.getInstance();
    final db = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactory);
    final storage = await AppStorage.init(root: Directory('${tmp.path}/app'));
    final settings = AppSettings(prefs);
    final library = LibraryRepository(db.db);
    final services = AppServices(
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
      sync: SyncService(prefs, SyncState(db.db, settings), library),
    );
    await settings.setReaderPrefs(settings.readerPrefs.copyWith(animation: PageAnimation.curl));

    // ------------------------------------------------ génération des fichiers
    var sw = Stopwatch()..start();
    final cover = await _png(600, 900, const Color(0xFF233A52));
    for (var i = 0; i < _libraryBooks; i++) {
      File('${src.path}/livre_$i.epub').writeAsBytesSync(buildEpub(
        title: 'Livre de test n° $i',
        author: 'Auteur ${i % 37}',
        subjects: ['Genre ${i % 9}'],
        cover: i % 3 == 0 ? null : cover,
        chapters: [('Chapitre I', '<p>$_para</p>' * 4)],
      ));
    }
    final illustration = await _png(1600, 2400, const Color(0xFF8A5A2B));
    final big = File('${src.path}/gros_livre.epub')
      ..writeAsBytesSync(_bigEpub(chapters: 60, parasPerChapter: 260, image: illustration, hugeChapter: 30));
    final pdf = File('${src.path}/gros.pdf')..writeAsBytesSync(_pdf(400));
    report['generation_ms'] = sw.elapsedMilliseconds;
    report['big_epub_mb'] = mb(big.lengthSync());
    report['pdf_pages'] = 400;

    // ------------------------------------------------ import en masse
    memory('debut');
    sw = Stopwatch()..start();
    for (var i = 0; i < _libraryBooks; i++) {
      await services.importer.importOne(ImportSource(name: 'livre_$i.epub', path: '${src.path}/livre_$i.epub'));
    }
    report['import_ms_per_book'] = (sw.elapsedMilliseconds / _libraryBooks).round();
    final (bigBook, _) = await services.importer.importOne(ImportSource(name: 'gros_livre.epub', path: big.path));
    final (pdfBook, _) = await services.importer.importOne(ImportSource(name: 'gros.pdf', path: pdf.path));
    debugPrint('PERF import ${report['import_ms_per_book']} ms/livre');

    await tester.pumpWidget(LireoRoot(services: services));
    await tester.pumpAndSettle();
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);

    // ------------------------------------------------ défilement de la bibliothèque
    for (final layout in [LibraryLayout.grid, LibraryLayout.shelves]) {
      await settings.setLibraryLayout(layout);
      nav.push(MaterialPageRoute<void>(builder: (_) => const LibraryScreen()));
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;
      await frames('scroll_${layout.name}', () async {
        for (var i = 0; i < 6; i++) {
          await tester.fling(scrollable, const Offset(0, -900), 2500);
          await tester.pumpAndSettle();
        }
        for (var i = 0; i < 6; i++) {
          await tester.fling(scrollable, const Offset(0, 900), 2500);
          await tester.pumpAndSettle();
        }
      });
      memory('bibliotheque_${layout.name}');
      nav.pop();
      await tester.pumpAndSettle();
    }

    // ------------------------------------------------ pagination brute
    final epub = await EpubBook.open(bigBook.path);
    final view = tester.view;
    final spec = LayoutSpec(
      pageSize: view.physicalSize / view.devicePixelRatio,
      prefs: settings.readerPrefs,
      textScaler: TextScaler.noScaling,
    );
    final perChapter = <int>[];
    var pages = 0;
    for (var c = 0; c < epub.chapterCount; c++) {
      final s = Stopwatch()..start();
      final flow = await epub.loadChapter(c);
      final layout = await Paginator(spec).layout(flow, (key, maxWidth) async => null);
      perChapter.add(s.elapsedMilliseconds);
      pages += layout.pages.length;
      layout.dispose();
    }
    await epub.close();
    perChapter.sort();
    report['pagination'] = {
      'chapters': perChapter.length,
      'pages': pages,
      'avg_ms': (perChapter.reduce((a, b) => a + b) / perChapter.length).round(),
      'p90_ms': perChapter[(perChapter.length * 0.9).floor()],
      'max_ms': perChapter.last,
    };
    debugPrint('PERF pagination ${jsonEncode(report['pagination'])}');

    // ------------------------------------------------ ouverture du gros livre
    Future<int> openBook(int id, Finder ready) async {
      final s = Stopwatch()..start();
      nav.push(MaterialPageRoute<void>(builder: (_) => ReaderScreen(bookId: id)));
      while (ready.evaluate().isEmpty || find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 8));
        if (s.elapsed > const Duration(seconds: 60)) fail('Livre non ouvert en 60 s');
      }
      return s.elapsedMilliseconds;
    }

    report['open_big_epub_ms'] = await openBook(bigBook.id!, find.byType(PageTurner));
    debugPrint('PERF ouverture EPUB ${report['open_big_epub_ms']} ms');
    await Future<void>.delayed(const Duration(seconds: 2)); // préchargement des voisins
    memory('lecteur_epub');

    // ------------------------------------------------ Page Curl
    final size = view.physicalSize / view.devicePixelRatio;
    await frames('page_curl', () async {
      for (var i = 0; i < 12; i++) {
        await tester.timedDragFrom(Offset(size.width - 20, size.height * 0.6), Offset(-size.width * 0.8, -40), const Duration(milliseconds: 380));
        await tester.pumpAndSettle();
      }
    });
    memory('apres_curl');
    nav.pop();
    await tester.pumpAndSettle();

    // Reprise dans le chapitre géant : pagination pendant l'animation d'ouverture.
    await library.saveProgress(bigBook.id!, const BookLocation(chapter: 30), 0.5);
    await frames('chapitre_geant', () async {
      report['open_huge_chapter_ms'] = await openBook(bigBook.id!, find.byType(PageTurner));
      for (var i = 0; i < 6; i++) {
        await tester.timedDragFrom(Offset(size.width - 20, size.height * 0.6), Offset(-size.width * 0.8, 0), const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
      }
    });
    nav.pop();
    await tester.pumpAndSettle();

    // ------------------------------------------------ PDF de 400 pages
    report['open_pdf_ms'] = await openBook(pdfBook.id!, find.byType(PdfViewer));
    await Future<void>.delayed(const Duration(seconds: 2));
    await frames('pdf_scroll', () async {
      for (var i = 0; i < 8; i++) {
        await tester.fling(find.byType(PdfViewer), const Offset(0, -1200), 4000);
        await tester.pump(const Duration(milliseconds: 700));
      }
    });
    memory('pdf');
    nav.pop();
    await tester.pumpAndSettle();
    memory('fin');

    binding.reportData = report;
    debugPrint('PERF RAPPORT ${jsonEncode(report)}');
    await db.close();
    tmp.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 20)));
}

Future<Uint8List> _png(int w, int h, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = color);
  for (var i = 0; i < 30; i++) {
    canvas.drawCircle(Offset(w * (i % 6) / 6, h * (i ~/ 6) / 5), w / 9, Paint()..color = Color(0x22FFFFFF + i * 0x050301));
  }
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// EPUB volumineux : beaucoup de chapitres, des illustrations pleine page et
/// un chapitre géant (~10x les autres) pour éprouver la pagination.
Uint8List _bigEpub({required int chapters, required int parasPerChapter, required Uint8List image, required int hugeChapter}) {
  final base = buildEpub(
    title: 'Le Très Gros Livre',
    author: 'Perf Test',
    chapters: [
      for (var c = 0; c < chapters; c++)
        (
          'Chapitre ${c + 1}',
          [
            for (var p = 0; p < (c == hugeChapter ? parasPerChapter * 10 : parasPerChapter); p++) ...[
              if (p % 60 == 30) '<p><img src="illus.png" alt=""/></p>',
              '<p>$_para</p>',
            ],
          ].join(),
        ),
    ],
  );
  // Ajoute l'illustration référencée au paquet.
  final archive = ZipDecoder().decodeBytes(base);
  archive.add(ArchiveFile('OEBPS/illus.png', image.length, image));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// PDF texte minimal de [pages] pages (Helvetica), sans dépendance.
Uint8List _pdf(int pages) {
  final out = BytesBuilder();
  final offsets = <int>[];
  void obj(String body) {
    offsets.add(out.length);
    out.add(latin1.encode('${offsets.length} 0 obj\n$body\nendobj\n'));
  }

  out.add(latin1.encode('%PDF-1.4\n'));
  obj('<< /Type /Catalog /Pages 2 0 R >>');
  final kids = [for (var i = 0; i < pages; i++) '${4 + i * 2} 0 R'].join(' ');
  obj('<< /Type /Pages /Kids [$kids] /Count $pages >>');
  obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  for (var i = 0; i < pages; i++) {
    final text = StringBuffer('BT /F1 11 Tf 56 780 Td 14 TL (Page ${i + 1}) Tj T*');
    for (var l = 0; l < 48; l++) {
      text.write(' (Ligne $l de la page ${i + 1} : la mer avait encore gagne trois minutes sur la ville.) Tj T*');
    }
    text.write(' ET');
    obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>');
    obj('<< /Length ${text.length} >>\nstream\n$text\nendstream');
  }
  final xref = out.length;
  final table = StringBuffer('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    table.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  table.write('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  out.add(latin1.encode(table.toString()));
  return out.toBytes();
}
