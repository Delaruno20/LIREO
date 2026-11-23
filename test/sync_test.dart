import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lireo/data/db/app_database.dart';
import 'package:lireo/data/models/book.dart';
import 'package:lireo/data/models/library_models.dart';
import 'package:lireo/data/repositories/annotation_repository.dart';
import 'package:lireo/data/repositories/library_repository.dart';
import 'package:lireo/data/repositories/stats_repository.dart';
import 'package:lireo/data/settings/app_settings.dart';
import 'package:lireo/features/reader/model/reader_prefs.dart';
import 'package:lireo/services/sync/sync_merge.dart';
import 'package:lireo/services/sync/sync_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Un « appareil » : sa base, ses dépôts, ses réglages.
class _Device {
  _Device(this.db, this.settings)
      : library = LibraryRepository(db.db),
        annotations = AnnotationRepository(db.db),
        stats = StatsRepository(db.db),
        state = SyncState(db.db, settings);

  final AppDatabase db;
  final AppSettings settings;
  final LibraryRepository library;
  final AnnotationRepository annotations;
  final StatsRepository stats;
  final SyncState state;

  /// Synchronisation complète contre un « nuage » en mémoire.
  Future<void> sync(Map<String, Map<String, dynamic>?> cloud) async {
    final local = await state.export();
    final remote = cloud['file'];
    final merged = remote == null ? local : SyncMerge.merge(local, remote);
    await state.apply(merged);
    cloud['file'] = merged;
  }

  static Future<_Device> create() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    return _Device(
      await AppDatabase.open(
        path: '${Directory.systemTemp.createTempSync('lireo_sync').path}/device.db',
        factory: databaseFactoryFfiNoIsolate,
      ),
      AppSettings(prefs),
    );
  }

  Future<Book> addBook(String hash, String title) => library.insertBook(Book(
        path: '/tmp/$hash',
        fileName: '$title.epub',
        format: 'epub',
        title: title,
        fileHash: hash,
        addedAt: DateTime(2026, 1, 1),
      ));
}

void main() {
  sqfliteFfiInit();

  group('SyncMerge (pur)', () {
    test('la lecture la plus récente gagne pour la progression', () {
      final a = SyncMerge.empty()..['books'] = {'h': {'progress': 0.2, 'last_opened_at': 100, 'favorite': 1, 'updated_at': 50}};
      final b = SyncMerge.empty()..['books'] = {'h': {'progress': 0.6, 'last_opened_at': 200, 'favorite': 0, 'updated_at': 10}};
      final m = SyncMerge.merge(a, b)['books']['h'] as Map;
      expect(m['progress'], 0.6);
      expect(m['favorite'], 1); // métadonnée la plus récente (a)
      expect(SyncMerge.merge(b, a)['books'], SyncMerge.merge(a, b)['books']);
    });

    test('une suppression tracée l\'emporte sur une annotation plus ancienne', () {
      final ann = {'updated_at': 100, 'created_at': 100, 'text': 'x'};
      final a = SyncMerge.empty()
        ..['annotations'] = {'k': ann}
        ..['tombstones'] = {};
      final b = SyncMerge.empty()..['tombstones'] = {'annotation|k': 150};
      expect((SyncMerge.merge(a, b)['annotations'] as Map), isEmpty);
      // Recréée après la suppression : conservée.
      final c = SyncMerge.empty()..['annotations'] = {'k': {...ann, 'updated_at': 200}};
      expect((SyncMerge.merge(c, b)['annotations'] as Map), contains('k'));
    });

    test('fusionner un état avec lui-même ne change rien', () {
      final a = SyncMerge.empty()
        ..['books'] = {'h': {'progress': 0.3, 'last_opened_at': 1, 'updated_at': 1}}
        ..['sessions'] = {'h|1': {'duration_ms': 1000}};
      final m = SyncMerge.merge(a, a);
      expect((m['books'] as Map)['h']['progress'], 0.3);
      expect(SyncMerge.merge(m, a)['books'], m['books']);
      expect(m['sessions'], a['sessions']);
    });
  });

  test('deux appareils convergent : progression, annotations, collections, sessions, réglages', () async {
    final phone = await _Device.create();
    final tablet = await _Device.create();
    final cloud = <String, Map<String, dynamic>?>{'file': null};

    final p1 = await phone.addBook('h1', 'Dune');
    final t1 = await tablet.addBook('h1', 'Dune');
    await phone.addBook('h2', 'Seulement sur le téléphone');

    // Téléphone : lecture, annotation, collection, session.
    await phone.library.saveProgress(p1.id!, const BookLocation(chapter: 3, offset: 120), 0.4);
    await phone.annotations.add(Annotation(
      bookId: p1.id!,
      kind: AnnotationKind.note,
      start: const BookLocation(chapter: 1, offset: 10),
      end: const BookLocation(chapter: 1, offset: 30),
      text: 'La peur tue l\'esprit',
      note: 'Litanie',
      createdAt: DateTime(2026, 2, 1),
    ));
    final c = await phone.library.createCollection('SF');
    await phone.library.addToCollection(c.id!, [p1.id!]);
    await phone.stats.recordSession(ReadingSession(
      bookId: p1.id!,
      startedAt: DateTime(2026, 2, 1, 20),
      durationMs: 20 * 60000,
      pagesRead: 12,
      startProgress: 0,
      endProgress: 0.4,
    ));
    await phone.settings.setReaderPrefs(const ReaderPrefs(fontFamily: 'Lora', fontSize: 22));

    await phone.sync(cloud);
    await tablet.sync(cloud);

    final tb = (await tablet.library.book(t1.id!))!;
    expect(tb.progress, 0.4);
    expect(tb.locator, const BookLocation(chapter: 3, offset: 120));
    expect(tb.totalReadingMs, 20 * 60000);
    final tAnn = await tablet.annotations.forBook(t1.id!);
    expect(tAnn.single.note, 'Litanie');
    expect((await tablet.library.booksInCollection((await tablet.library.collections()).single.id!)).single.title, 'Dune');
    expect(tablet.settings.readerPrefs.fontFamily, 'Lora');
    // Le livre absent de la tablette reste dans l'état partagé.
    expect((cloud['file']!['books'] as Map).containsKey('h2'), isTrue);

    // Tablette : supprime l'annotation et lit plus loin ; le téléphone suit.
    await tablet.annotations.delete(tAnn.single);
    await tablet.library.saveProgress(t1.id!, const BookLocation(chapter: 5), 0.7);
    await tablet.sync(cloud);
    await phone.sync(cloud);
    expect(await phone.annotations.forBook(p1.id!), isEmpty);
    expect((await phone.library.book(p1.id!))!.progress, 0.7);

    // Une nouvelle synchronisation ne duplique rien.
    await phone.sync(cloud);
    await tablet.sync(cloud);
    expect((await tablet.stats.summary()).pagesRead, 12);

    await phone.db.close();
    await tablet.db.close();
  });
}
