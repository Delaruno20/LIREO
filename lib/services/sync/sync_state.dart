import 'package:sqflite/sqflite.dart';

import '../../data/repositories/annotation_repository.dart';
import '../../data/settings/app_settings.dart';
import '../../features/reader/model/reader_prefs.dart';
import 'sync_merge.dart';

/// Passerelle entre la base locale et l'état de synchronisation (JSON).
///
/// Les livres sont identifiés par leur empreinte SHA-1 : un livre absent de
/// cet appareil est conservé dans l'état partagé sans être touché ici.
class SyncState {
  SyncState(this._db, this._settings);

  final Database _db;
  final AppSettings _settings;

  Future<Map<String, dynamic>> export() async {
    final books = await _db.query('books');
    final hashById = {for (final b in books) b['id'] as int: b['file_hash'] as String};
    final state = SyncMerge.empty();

    final out = state['books'] as Map<String, dynamic>;
    for (final b in books) {
      out[b['file_hash'] as String] = {
        for (final f in [...SyncMerge.readingFields, ...SyncMerge.metaFields]) f: b[f],
        'updated_at': b['updated_at'],
      };
    }

    final annotations = state['annotations'] as Map<String, dynamic>;
    for (final a in await _db.query('annotations')) {
      final hash = hashById[a['book_id']];
      if (hash == null) continue;
      annotations[AnnotationRepository.annotationKey(hash, a)] = {...a, 'book': hash}
        ..remove('id')
        ..remove('book_id');
    }

    final sessions = state['sessions'] as Map<String, dynamic>;
    for (final s in await _db.query('reading_sessions')) {
      final hash = hashById[s['book_id']];
      if (hash == null) continue;
      sessions['$hash|${s['started_at']}'] = {...s, 'book': hash}
        ..remove('id')
        ..remove('book_id');
    }

    final collections = state['collections'] as Map<String, dynamic>;
    final links = await _db.query('collection_books');
    for (final c in await _db.query('collections')) {
      collections[c['name'] as String] = {
        'description': c['description'],
        'is_private': c['is_private'],
        'created_at': c['created_at'],
        'updated_at': c['created_at'],
        'members': {
          for (final l in links)
            if (l['collection_id'] == c['id'] && hashById[l['book_id']] != null) hashById[l['book_id']]!: l['added_at'],
        },
      };
    }

    final tombstones = state['tombstones'] as Map<String, dynamic>;
    for (final t in await _db.query('tombstones')) {
      tombstones['${t['kind']}|${t['key']}'] = t['deleted_at'];
    }

    state['settings'] = {
      'updated_at': _settings.syncedSettingsUpdatedAt,
      'readerPrefs': _settings.readerPrefs.toJson(),
      'profiles': [for (final p in _settings.profiles) p.toJson()],
    };
    return state;
  }

  /// Applique un état fusionné à la base locale.
  Future<void> apply(Map<String, dynamic> state) async {
    final rows = await _db.query('books', columns: ['id', 'file_hash']);
    final idByHash = {for (final r in rows) r['file_hash'] as String: r['id'] as int};
    Map<String, dynamic> section(String key) => Map<String, dynamic>.from((state[key] as Map?) ?? const {});

    await _db.transaction((txn) async {
      // Livres présents sur cet appareil.
      for (final entry in section('books').entries) {
        final id = idByHash[entry.key];
        if (id == null) continue;
        final b = Map<String, dynamic>.from(entry.value as Map);
        await txn.update(
          'books',
          {
            for (final f in [...SyncMerge.readingFields, ...SyncMerge.metaFields]) f: b[f],
            'title_sort': (b['title'] as String? ?? '').toLowerCase(),
            'updated_at': b['updated_at'] ?? 0,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      // Annotations : l'état fusionné fait foi pour les livres locaux.
      final wanted = section('annotations');
      final local = await txn.query('annotations');
      final hashById = {for (final e in idByHash.entries) e.value: e.key};
      final localKeys = <String, int>{};
      for (final a in local) {
        final hash = hashById[a['book_id']];
        if (hash == null) continue;
        localKeys[AnnotationRepository.annotationKey(hash, a)] = a['id'] as int;
      }
      for (final e in localKeys.entries) {
        if (!wanted.containsKey(e.key)) await txn.delete('annotations', where: 'id = ?', whereArgs: [e.value]);
      }
      for (final e in wanted.entries) {
        final a = Map<String, Object?>.from(e.value as Map);
        final bookId = idByHash[a.remove('book')];
        if (bookId == null) continue;
        final row = {...a, 'book_id': bookId};
        final existing = localKeys[e.key];
        if (existing == null) {
          await txn.insert('annotations', row);
        } else {
          await txn.update('annotations', row, where: 'id = ?', whereArgs: [existing]);
        }
      }

      // Sessions manquantes, puis temps de lecture recalculé.
      for (final s in section('sessions').values) {
        final m = Map<String, Object?>.from(s as Map);
        final bookId = idByHash[m.remove('book')];
        if (bookId == null) continue;
        final dup = await txn.query('reading_sessions', where: 'book_id = ? AND started_at = ?', whereArgs: [bookId, m['started_at']]);
        if (dup.isEmpty) await txn.insert('reading_sessions', {...m, 'book_id': bookId});
      }
      await txn.rawUpdate(
        'UPDATE books SET total_reading_ms = (SELECT COALESCE(SUM(duration_ms), 0) FROM reading_sessions s WHERE s.book_id = books.id)',
      );

      // Collections
      final wantedCollections = section('collections');
      for (final c in await txn.query('collections')) {
        if (!wantedCollections.containsKey(c['name'])) await txn.delete('collections', where: 'id = ?', whereArgs: [c['id']]);
      }
      for (final e in wantedCollections.entries) {
        final c = Map<String, dynamic>.from(e.value as Map);
        final existing = await txn.query('collections', where: 'name = ?', whereArgs: [e.key]);
        final id = existing.isNotEmpty
            ? existing.first['id'] as int
            : await txn.insert('collections', {
                'name': e.key,
                'description': c['description'] ?? '',
                'is_private': c['is_private'] ?? 0,
                'created_at': c['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
              });
        if (existing.isNotEmpty) {
          await txn.update('collections', {'description': c['description'] ?? '', 'is_private': c['is_private'] ?? 0},
              where: 'id = ?', whereArgs: [id]);
        }
        final members = Map<String, dynamic>.from((c['members'] as Map?) ?? const {});
        await txn.delete('collection_books', where: 'collection_id = ?', whereArgs: [id]);
        for (final m in members.entries) {
          final bookId = idByHash[m.key];
          if (bookId == null) continue;
          await txn.insert('collection_books', {'collection_id': id, 'book_id': bookId, 'added_at': m.value},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      for (final t in section('tombstones').entries) {
        final sep = t.key.indexOf('|');
        await txn.insert(
          'tombstones',
          {'kind': t.key.substring(0, sep), 'key': t.key.substring(sep + 1), 'deleted_at': t.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    final settings = state['settings'] as Map?;
    if (settings != null && ((settings['updated_at'] as num?)?.toInt() ?? 0) > _settings.syncedSettingsUpdatedAt) {
      await _settings.applySyncedSettings(
        ReaderPrefs.fromJson(Map<String, dynamic>.from(settings['readerPrefs'] as Map)),
        [for (final p in (settings['profiles'] as List? ?? const [])) ReadingProfile.fromJson(Map<String, dynamic>.from(p as Map))],
        (settings['updated_at'] as num).toInt(),
      );
    }
  }
}
