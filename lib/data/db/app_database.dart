import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

/// Accès SQLite de LIREO. Les migrations sont versionnées : chaque nouvelle
/// version ajoute une entrée dans [_migrations] sans toucher aux précédentes.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _version = 2;

  static Future<AppDatabase> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? _defaultFactory();
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'lireo.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          for (var v = 1; v <= version; v++) {
            await _migrations[v]!(db);
          }
        },
        onUpgrade: (db, from, to) async {
          for (var v = from + 1; v <= to; v++) {
            await _migrations[v]!(db);
          }
        },
      ),
    );
    return AppDatabase._(db);
  }

  static DatabaseFactory _defaultFactory() {
    if (Platform.isLinux || Platform.isWindows) {
      ffi.sqfliteFfiInit();
      return ffi.databaseFactoryFfi;
    }
    return databaseFactory;
  }

  static final Map<int, Future<void> Function(Database)> _migrations = {
    1: (db) async {
      final batch = db.batch();
      batch.execute('''
        CREATE TABLE books (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          path TEXT NOT NULL,
          file_name TEXT NOT NULL,
          format TEXT NOT NULL,
          title TEXT NOT NULL,
          title_sort TEXT NOT NULL,
          author TEXT NOT NULL DEFAULT '',
          publisher TEXT NOT NULL DEFAULT '',
          description TEXT NOT NULL DEFAULT '',
          language TEXT NOT NULL DEFAULT '',
          categories TEXT NOT NULL DEFAULT '',
          cover_path TEXT,
          page_count INTEGER NOT NULL DEFAULT 0,
          file_size INTEGER NOT NULL DEFAULT 0,
          file_hash TEXT NOT NULL UNIQUE,
          added_at INTEGER NOT NULL,
          last_opened_at INTEGER,
          finished_at INTEGER,
          progress REAL NOT NULL DEFAULT 0,
          locator TEXT,
          favorite INTEGER NOT NULL DEFAULT 0,
          rating INTEGER NOT NULL DEFAULT 0,
          personal_note TEXT NOT NULL DEFAULT '',
          total_reading_ms INTEGER NOT NULL DEFAULT 0,
          reader_prefs TEXT
        )''');
      batch.execute('CREATE INDEX idx_books_title ON books(title_sort)');
      batch.execute('CREATE INDEX idx_books_author ON books(author)');
      batch.execute('CREATE INDEX idx_books_last_opened ON books(last_opened_at)');
      batch.execute('CREATE INDEX idx_books_added ON books(added_at)');
      batch.execute('''
        CREATE TABLE collections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          is_private INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )''');
      batch.execute('''
        CREATE TABLE collection_books (
          collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
          book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          added_at INTEGER NOT NULL,
          PRIMARY KEY (collection_id, book_id)
        )''');
      batch.execute('''
        CREATE TABLE annotations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          kind TEXT NOT NULL,
          start_chapter INTEGER NOT NULL,
          start_offset INTEGER NOT NULL,
          end_chapter INTEGER NOT NULL,
          end_offset INTEGER NOT NULL,
          text TEXT NOT NULL DEFAULT '',
          note TEXT NOT NULL DEFAULT '',
          color INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          chapter_title TEXT NOT NULL DEFAULT '',
          progress REAL NOT NULL DEFAULT 0
        )''');
      batch.execute('CREATE INDEX idx_annotations_book ON annotations(book_id, start_chapter)');
      batch.execute('''
        CREATE TABLE reading_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          started_at INTEGER NOT NULL,
          day INTEGER NOT NULL,
          duration_ms INTEGER NOT NULL,
          pages_read INTEGER NOT NULL DEFAULT 0,
          start_progress REAL NOT NULL DEFAULT 0,
          end_progress REAL NOT NULL DEFAULT 0
        )''');
      batch.execute('CREATE INDEX idx_sessions_day ON reading_sessions(day)');
      await batch.commit(noResult: true);
    },
    // v2 : synchronisation — dates de modification et traces de suppression.
    2: (db) async {
      final batch = db.batch();
      batch.execute('ALTER TABLE books ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
      batch.execute('ALTER TABLE annotations ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
      batch.execute('''
        CREATE TABLE tombstones (
          kind TEXT NOT NULL,
          key TEXT NOT NULL,
          deleted_at INTEGER NOT NULL,
          PRIMARY KEY (kind, key)
        )''');
      await batch.commit(noResult: true);
    },
  };

  Future<void> close() => db.close();
}
