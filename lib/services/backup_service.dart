import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/settings/app_settings.dart';
import '../features/reader/model/reader_prefs.dart';

/// Sauvegarde/restauration de toutes les données de lecture (hors fichiers
/// des livres) dans un JSON portable. Les livres sont identifiés par leur
/// empreinte SHA-1 : la restauration fonctionne sur un autre appareil dès
/// que les mêmes fichiers y sont importés.
class BackupService {
  BackupService(this._db, this._settings);

  final Database _db;
  final AppSettings _settings;

  static const format = 'lireo-backup';
  static const version = 1;

  Future<String> export() async {
    final books = await _db.query('books');
    final hashById = {for (final b in books) b['id'] as int: b['file_hash'] as String};
    final collections = await _db.query('collections');
    final links = await _db.query('collection_books');
    final annotations = await _db.query('annotations');
    final sessions = await _db.query('reading_sessions');
    return const JsonEncoder.withIndent(' ').convert({
      'format': format,
      'version': version,
      'exportedAt': DateTime.now().toIso8601String(),
      'readerPrefs': _settings.readerPrefs.toJson(),
      'profiles': [for (final p in _settings.profiles) p.toJson()],
      'books': [
        for (final b in books)
          {
            'hash': b['file_hash'],
            'title': b['title'],
            'author': b['author'],
            'publisher': b['publisher'],
            'description': b['description'],
            'categories': b['categories'],
            'progress': b['progress'],
            'locator': b['locator'],
            'favorite': b['favorite'],
            'rating': b['rating'],
            'personal_note': b['personal_note'],
            'total_reading_ms': b['total_reading_ms'],
            'last_opened_at': b['last_opened_at'],
            'finished_at': b['finished_at'],
            'reader_prefs': b['reader_prefs'],
          },
      ],
      'collections': [
        for (final c in collections)
          {
            'name': c['name'],
            'description': c['description'],
            'is_private': c['is_private'],
            'created_at': c['created_at'],
            'books': [for (final l in links) if (l['collection_id'] == c['id']) hashById[l['book_id']]],
          },
      ],
      'annotations': [
        for (final a in annotations) {...a, 'book': hashById[a['book_id']]}..remove('id')..remove('book_id'),
      ],
      'sessions': [
        for (final s in sessions) {...s, 'book': hashById[s['book_id']]}..remove('id')..remove('book_id'),
      ],
    });
  }

  /// Restaure une sauvegarde. Retourne le nombre de livres retrouvés.
  Future<int> restore(String json) async {
    final data = jsonDecode(json);
    if (data is! Map || data['format'] != format) throw const FormatException('Ce fichier n\'est pas une sauvegarde LIREO.');
    final rows = await _db.query('books', columns: ['id', 'file_hash']);
    final idByHash = {for (final r in rows) r['file_hash'] as String: r['id'] as int};
    var matched = 0;

    await _db.transaction((txn) async {
      for (final b in (data['books'] as List).cast<Map>()) {
        final id = idByHash[b['hash']];
        if (id == null) continue;
        matched++;
        await txn.update(
          'books',
          {
            for (final k in [
              'title', 'author', 'publisher', 'description', 'categories', 'progress', 'locator', 'favorite', 'rating',
              'personal_note', 'total_reading_ms', 'last_opened_at', 'finished_at', 'reader_prefs',
            ])
              k: b[k],
            'title_sort': (b['title'] as String? ?? '').toLowerCase(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      for (final c in (data['collections'] as List? ?? const []).cast<Map>()) {
        final existing = await txn.query('collections', where: 'name = ?', whereArgs: [c['name']]);
        final cid = existing.isNotEmpty
            ? existing.first['id'] as int
            : await txn.insert('collections', {
                'name': c['name'],
                'description': c['description'] ?? '',
                'is_private': c['is_private'] ?? 0,
                'created_at': c['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
              });
        for (final h in (c['books'] as List).cast<String?>()) {
          final bid = idByHash[h];
          if (bid == null) continue;
          await txn.insert('collection_books', {'collection_id': cid, 'book_id': bid, 'added_at': DateTime.now().millisecondsSinceEpoch},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      for (final a in (data['annotations'] as List? ?? const []).cast<Map>()) {
        final bid = idByHash[a['book']];
        if (bid == null) continue;
        final dup = await txn.query('annotations',
            where: 'book_id = ? AND kind = ? AND start_chapter = ? AND start_offset = ? AND end_offset = ?',
            whereArgs: [bid, a['kind'], a['start_chapter'], a['start_offset'], a['end_offset']]);
        if (dup.isNotEmpty) continue;
        await txn.insert('annotations', {...Map<String, Object?>.from(a)..remove('book'), 'book_id': bid});
      }

      for (final s in (data['sessions'] as List? ?? const []).cast<Map>()) {
        final bid = idByHash[s['book']];
        if (bid == null) continue;
        final dup = await txn.query('reading_sessions', where: 'book_id = ? AND started_at = ?', whereArgs: [bid, s['started_at']]);
        if (dup.isNotEmpty) continue;
        await txn.insert('reading_sessions', {...Map<String, Object?>.from(s)..remove('book'), 'book_id': bid});
      }
    });

    if (data['readerPrefs'] is Map) {
      await _settings.setReaderPrefs(ReaderPrefs.fromJson(Map<String, dynamic>.from(data['readerPrefs'] as Map)));
    }
    if (data['profiles'] is List) {
      await _settings.saveProfiles([
        for (final p in (data['profiles'] as List).cast<Map>()) ReadingProfile.fromJson(Map<String, dynamic>.from(p)),
      ]);
    }
    return matched;
  }
}
