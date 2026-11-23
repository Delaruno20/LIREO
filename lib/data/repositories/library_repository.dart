import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import '../models/library_models.dart';

enum BookSort {
  lastRead('Dernière lecture'),
  added('Date d\'ajout'),
  title('Titre'),
  author('Auteur'),
  progress('Progression');

  const BookSort(this.label);
  final String label;

  String get orderBy => switch (this) {
        BookSort.lastRead => 'COALESCE(last_opened_at, 0) DESC, added_at DESC',
        BookSort.added => 'added_at DESC',
        BookSort.title => 'title_sort ASC',
        BookSort.author => 'author COLLATE NOCASE ASC, title_sort ASC',
        BookSort.progress => 'progress DESC',
      };
}

class BookQuery {
  const BookQuery({
    this.search = '',
    this.format,
    this.category,
    this.favoritesOnly = false,
    this.status,
    this.sort = BookSort.lastRead,
    this.limit,
  });

  final String search;
  final String? format;
  final String? category;
  final bool favoritesOnly;

  /// 'unread' | 'reading' | 'finished'
  final String? status;
  final BookSort sort;
  final int? limit;
}

/// Source de vérité de la bibliothèque. Toute écriture émet sur [changes]
/// pour que les écrans se rafraîchissent sans couplage direct.
class LibraryRepository {
  LibraryRepository(this._db);

  final Database _db;
  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;
  void _notify() => _changes.add(null);

  /// Signale un changement fait hors du dépôt (ex. restauration de sauvegarde).
  void notifyChanged() => _notify();

  // ---------------------------------------------------------------- Livres

  Future<List<Book>> books([BookQuery q = const BookQuery()]) async {
    final where = <String>[];
    final args = <Object?>[];
    if (q.search.trim().isNotEmpty) {
      final like = '%${q.search.trim().toLowerCase()}%';
      where.add('(title_sort LIKE ? OR LOWER(author) LIKE ? OR LOWER(publisher) LIKE ? OR LOWER(categories) LIKE ?)');
      args.addAll([like, like, like, like]);
    }
    if (q.format != null) {
      where.add('format = ?');
      args.add(q.format);
    }
    if (q.category != null) {
      where.add("('\u001f' || categories || '\u001f') LIKE ?");
      args.add('%\u001f${q.category}\u001f%');
    }
    if (q.favoritesOnly) where.add('favorite = 1');
    switch (q.status) {
      case 'unread':
        where.add('last_opened_at IS NULL AND progress < 0.001');
      case 'reading':
        where.add('last_opened_at IS NOT NULL AND finished_at IS NULL AND progress < 0.995');
      case 'finished':
        where.add('(finished_at IS NOT NULL OR progress >= 0.995)');
    }
    final rows = await _db.query(
      'books',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: q.sort.orderBy,
      limit: q.limit,
    );
    return rows.map(Book.fromRow).toList();
  }

  Future<Book?> book(int id) async {
    final rows = await _db.query('books', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Book.fromRow(rows.first);
  }

  Future<Book?> bookByHash(String hash) async {
    final rows = await _db.query('books', where: 'file_hash = ?', whereArgs: [hash]);
    return rows.isEmpty ? null : Book.fromRow(rows.first);
  }

  Future<int> count() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM books')) ?? 0;

  Future<Book> insertBook(Book book) async {
    final id = await _db.insert('books', book.toRow());
    _notify();
    return book.copyWith(id: id);
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Trace d'une suppression, pour la propager aux autres appareils.
  Future<void> tombstone(String kind, String key) => _db.insert(
        'tombstones',
        {'kind': kind, 'key': key, 'deleted_at': _now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> updateBook(Book book) async {
    await _db.update('books', {...book.toRow(), 'updated_at': _now}, where: 'id = ?', whereArgs: [book.id]);
    _notify();
  }

  /// Sauvegarde légère de la position (appelée souvent pendant la lecture).
  Future<void> saveProgress(int bookId, BookLocation locator, double progress, {bool notify = false}) async {
    await _db.update(
      'books',
      {
        'locator': locator.encode(),
        'progress': progress,
        'last_opened_at': DateTime.now().millisecondsSinceEpoch,
        if (progress >= 0.995) 'finished_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
    if (notify) _notify();
  }

  /// Réglages de lecture propres au livre (null = profil global).
  Future<void> setReaderPrefs(int bookId, String? prefs) async {
    await _db.update('books', {'reader_prefs': prefs, 'updated_at': _now}, where: 'id = ?', whereArgs: [bookId]);
  }

  Future<void> setFavorite(int bookId, bool value) async {
    await _db.update('books', {'favorite': value ? 1 : 0, 'updated_at': _now}, where: 'id = ?', whereArgs: [bookId]);
    _notify();
  }

  Future<void> deleteBooks(List<int> ids) async {
    if (ids.isEmpty) return;
    await _db.delete('books', where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
    _notify();
  }

  /// Catégories distinctes présentes dans la bibliothèque, par fréquence.
  Future<List<String>> categories() async {
    final rows = await _db.query('books', columns: ['categories']);
    final counts = <String, int>{};
    for (final r in rows) {
      for (final c in ((r['categories'] as String?) ?? '').split('\u001f')) {
        if (c.trim().isEmpty) continue;
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    final list = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return list;
  }

  Future<List<String>> formats() async {
    final rows = await _db.rawQuery('SELECT DISTINCT format FROM books ORDER BY format');
    return rows.map((r) => r['format'] as String).toList();
  }

  // ------------------------------------------------------------ Collections

  Future<List<BookCollection>> collections({bool includePrivate = true}) async {
    final rows = await _db.rawQuery('''
      SELECT c.*, COUNT(cb.book_id) AS book_count
      FROM collections c LEFT JOIN collection_books cb ON cb.collection_id = c.id
      ${includePrivate ? '' : 'WHERE c.is_private = 0'}
      GROUP BY c.id ORDER BY c.name COLLATE NOCASE''');
    final result = <BookCollection>[];
    for (final r in rows) {
      final covers = await _db.rawQuery('''
        SELECT b.cover_path FROM collection_books cb JOIN books b ON b.id = cb.book_id
        WHERE cb.collection_id = ? AND b.cover_path IS NOT NULL
        ORDER BY cb.added_at DESC LIMIT 3''', [r['id']]);
      result.add(BookCollection.fromRow(r, covers: covers.map((c) => c['cover_path'] as String).toList()));
    }
    return result;
  }

  Future<BookCollection> createCollection(String name, {String description = '', bool isPrivate = false}) async {
    final c = BookCollection(name: name, description: description, isPrivate: isPrivate, createdAt: DateTime.now());
    final id = await _db.insert('collections', c.toRow());
    _notify();
    return BookCollection(id: id, name: name, description: description, isPrivate: isPrivate, createdAt: c.createdAt);
  }

  Future<void> updateCollection(BookCollection c) async {
    final old = (await _db.query('collections', columns: ['name'], where: 'id = ?', whereArgs: [c.id])).firstOrNull?['name'];
    if (old != null && old != c.name) await tombstone('collection', old as String);
    await _db.update('collections', c.toRow(), where: 'id = ?', whereArgs: [c.id]);
    _notify();
  }

  Future<void> deleteCollection(int id) async {
    final rows = await _db.query('collections', columns: ['name'], where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) await tombstone('collection', rows.first['name'] as String);
    await _db.delete('collections', where: 'id = ?', whereArgs: [id]);
    _notify();
  }

  Future<List<Book>> booksInCollection(int collectionId) async {
    final rows = await _db.rawQuery('''
      SELECT b.* FROM books b JOIN collection_books cb ON cb.book_id = b.id
      WHERE cb.collection_id = ? ORDER BY cb.added_at DESC''', [collectionId]);
    return rows.map(Book.fromRow).toList();
  }

  Future<Set<int>> collectionIdsForBook(int bookId) async {
    final rows = await _db.query('collection_books', columns: ['collection_id'], where: 'book_id = ?', whereArgs: [bookId]);
    return rows.map((r) => r['collection_id'] as int).toSet();
  }

  Future<void> addToCollection(int collectionId, List<int> bookIds) async {
    final batch = _db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in bookIds) {
      batch.insert('collection_books', {'collection_id': collectionId, 'book_id': id, 'added_at': now},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    _notify();
  }

  Future<void> removeFromCollection(int collectionId, List<int> bookIds) async {
    final name = (await _db.query('collections', columns: ['name'], where: 'id = ?', whereArgs: [collectionId])).firstOrNull?['name'];
    final hashes = await _db.query('books',
        columns: ['file_hash'], where: 'id IN (${List.filled(bookIds.length, '?').join(',')})', whereArgs: bookIds);
    for (final h in hashes) {
      if (name != null) await tombstone('member', '$name|${h['file_hash']}');
    }
    await _db.delete(
      'collection_books',
      where: 'collection_id = ? AND book_id IN (${List.filled(bookIds.length, '?').join(',')})',
      whereArgs: [collectionId, ...bookIds],
    );
    _notify();
  }

  /// IDs des livres appartenant à au moins une collection privée.
  Future<Set<int>> privateBookIds() async {
    final rows = await _db.rawQuery('''
      SELECT DISTINCT cb.book_id FROM collection_books cb
      JOIN collections c ON c.id = cb.collection_id WHERE c.is_private = 1''');
    return rows.map((r) => r['book_id'] as int).toSet();
  }

  void dispose() => _changes.close();
}
