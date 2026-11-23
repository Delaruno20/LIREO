import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../models/library_models.dart';

class AnnotationRepository {
  AnnotationRepository(this._db);

  final Database _db;
  final _changes = StreamController<int>.broadcast();

  /// Émet l'id du livre dont les annotations ont changé.
  Stream<int> get changes => _changes.stream;

  Future<List<Annotation>> forBook(int bookId, {AnnotationKind? kind}) async {
    final rows = await _db.query(
      'annotations',
      where: kind == null ? 'book_id = ?' : 'book_id = ? AND kind = ?',
      whereArgs: kind == null ? [bookId] : [bookId, kind.name],
      orderBy: 'start_chapter, start_offset',
    );
    return rows.map(Annotation.fromRow).toList();
  }

  Future<Annotation> add(Annotation a) async {
    final id = await _db.insert('annotations', {...a.toRow(), 'updated_at': DateTime.now().millisecondsSinceEpoch});
    _changes.add(a.bookId);
    return Annotation.fromRow({...a.toRow(), 'id': id});
  }

  Future<void> update(Annotation a) async {
    await _db.update('annotations', {...a.toRow(), 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [a.id]);
    _changes.add(a.bookId);
  }

  Future<void> delete(Annotation a) async {
    final hash = (await _db.query('books', columns: ['file_hash'], where: 'id = ?', whereArgs: [a.bookId])).firstOrNull?['file_hash'];
    if (hash != null) {
      await _db.insert(
        'tombstones',
        {'kind': 'annotation', 'key': annotationKey(hash as String, a.toRow()), 'deleted_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await _db.delete('annotations', where: 'id = ?', whereArgs: [a.id]);
    _changes.add(a.bookId);
  }

  /// Identité d'une annotation indépendante de l'appareil.
  static String annotationKey(String bookHash, Map<String, Object?> row) =>
      '$bookHash|${row['kind']}|${row['start_chapter']}:${row['start_offset']}-${row['end_chapter']}:${row['end_offset']}';

  Future<int> totalCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery("SELECT COUNT(*) FROM annotations WHERE kind != 'bookmark'")) ?? 0;

  /// Exporte les annotations d'un livre au format Markdown.
  static String toMarkdown(String title, String author, List<Annotation> items) {
    final b = StringBuffer('# $title\n');
    if (author.isNotEmpty) b.writeln('_${author}_\n');
    String? lastChapter;
    for (final a in items.where((a) => a.kind != AnnotationKind.bookmark)) {
      if (a.chapterTitle.isNotEmpty && a.chapterTitle != lastChapter) {
        b.writeln('\n## ${a.chapterTitle}\n');
        lastChapter = a.chapterTitle;
      }
      if (a.text.isNotEmpty) b.writeln('> ${a.text.replaceAll('\n', '\n> ')}\n');
      if (a.note.isNotEmpty) b.writeln('${a.note}\n');
    }
    return b.toString();
  }

  void dispose() => _changes.close();
}
