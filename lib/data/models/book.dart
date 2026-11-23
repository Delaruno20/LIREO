import 'dart:convert';

/// Position de lecture indépendante de la mise en page.
///
/// - Formats reflowables : [chapter] + [offset] (caractère dans le chapitre),
///   ce qui reste valable quand la police ou les marges changent.
/// - Formats paginés (PDF, BD) : [chapter] = numéro de page (base 0), [offset] = 0.
class BookLocation {
  const BookLocation({required this.chapter, this.offset = 0});

  final int chapter;
  final int offset;

  static const start = BookLocation(chapter: 0);

  Map<String, Object?> toJson() => {'c': chapter, 'o': offset};
  String encode() => jsonEncode(toJson());

  static BookLocation decode(String? raw) {
    if (raw == null || raw.isEmpty) return start;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return BookLocation(chapter: (m['c'] as num?)?.toInt() ?? 0, offset: (m['o'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return start;
    }
  }

  int compareTo(BookLocation other) =>
      chapter != other.chapter ? chapter.compareTo(other.chapter) : offset.compareTo(other.offset);

  @override
  bool operator ==(Object other) => other is BookLocation && other.chapter == chapter && other.offset == offset;

  @override
  int get hashCode => Object.hash(chapter, offset);
}

class Book {
  const Book({
    this.id,
    required this.path,
    required this.fileName,
    required this.format,
    required this.title,
    this.author = '',
    this.publisher = '',
    this.description = '',
    this.language = '',
    this.categories = const [],
    this.coverPath,
    this.pageCount = 0,
    this.fileSize = 0,
    required this.fileHash,
    required this.addedAt,
    this.lastOpenedAt,
    this.finishedAt,
    this.progress = 0,
    this.locator = BookLocation.start,
    this.favorite = false,
    this.rating = 0,
    this.personalNote = '',
    this.totalReadingMs = 0,
    this.readerPrefs,
  });

  final int? id;
  final String path;
  final String fileName;
  final String format;
  final String title;
  final String author;
  final String publisher;
  final String description;
  final String language;
  final List<String> categories;
  final String? coverPath;
  final int pageCount;
  final int fileSize;
  final String fileHash;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;
  final DateTime? finishedAt;

  /// Progression globale 0..1.
  final double progress;
  final BookLocation locator;
  final bool favorite;
  final int rating;
  final String personalNote;
  final int totalReadingMs;

  /// Réglages de lecture propres à ce livre (JSON), null = profil global.
  final String? readerPrefs;

  bool get isStarted => progress > 0.001 || lastOpenedAt != null;
  bool get isFinished => finishedAt != null || progress >= 0.995;
  String get displayAuthor => author.isEmpty ? 'Auteur inconnu' : author;

  Book copyWith({
    int? id,
    String? title,
    String? author,
    String? publisher,
    String? description,
    String? language,
    List<String>? categories,
    String? coverPath,
    int? pageCount,
    DateTime? lastOpenedAt,
    DateTime? finishedAt,
    bool clearFinished = false,
    double? progress,
    BookLocation? locator,
    bool? favorite,
    int? rating,
    String? personalNote,
    int? totalReadingMs,
    String? readerPrefs,
    bool clearReaderPrefs = false,
  }) =>
      Book(
        id: id ?? this.id,
        path: path,
        fileName: fileName,
        format: format,
        title: title ?? this.title,
        author: author ?? this.author,
        publisher: publisher ?? this.publisher,
        description: description ?? this.description,
        language: language ?? this.language,
        categories: categories ?? this.categories,
        coverPath: coverPath ?? this.coverPath,
        pageCount: pageCount ?? this.pageCount,
        fileSize: fileSize,
        fileHash: fileHash,
        addedAt: addedAt,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        finishedAt: clearFinished ? null : (finishedAt ?? this.finishedAt),
        progress: progress ?? this.progress,
        locator: locator ?? this.locator,
        favorite: favorite ?? this.favorite,
        rating: rating ?? this.rating,
        personalNote: personalNote ?? this.personalNote,
        totalReadingMs: totalReadingMs ?? this.totalReadingMs,
        readerPrefs: clearReaderPrefs ? null : (readerPrefs ?? this.readerPrefs),
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'path': path,
        'file_name': fileName,
        'format': format,
        'title': title,
        'title_sort': title.toLowerCase(),
        'author': author,
        'publisher': publisher,
        'description': description,
        'language': language,
        'categories': categories.join('\u001f'),
        'cover_path': coverPath,
        'page_count': pageCount,
        'file_size': fileSize,
        'file_hash': fileHash,
        'added_at': addedAt.millisecondsSinceEpoch,
        'last_opened_at': lastOpenedAt?.millisecondsSinceEpoch,
        'finished_at': finishedAt?.millisecondsSinceEpoch,
        'progress': progress,
        'locator': locator.encode(),
        'favorite': favorite ? 1 : 0,
        'rating': rating,
        'personal_note': personalNote,
        'total_reading_ms': totalReadingMs,
        'reader_prefs': readerPrefs,
      };

  static DateTime? _date(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

  factory Book.fromRow(Map<String, Object?> r) => Book(
        id: r['id'] as int,
        path: r['path'] as String,
        fileName: r['file_name'] as String,
        format: r['format'] as String,
        title: r['title'] as String,
        author: r['author'] as String? ?? '',
        publisher: r['publisher'] as String? ?? '',
        description: r['description'] as String? ?? '',
        language: r['language'] as String? ?? '',
        categories: ((r['categories'] as String?) ?? '').split('\u001f').where((e) => e.isNotEmpty).toList(),
        coverPath: r['cover_path'] as String?,
        pageCount: r['page_count'] as int? ?? 0,
        fileSize: r['file_size'] as int? ?? 0,
        fileHash: r['file_hash'] as String,
        addedAt: _date(r['added_at'])!,
        lastOpenedAt: _date(r['last_opened_at']),
        finishedAt: _date(r['finished_at']),
        progress: (r['progress'] as num?)?.toDouble() ?? 0,
        locator: BookLocation.decode(r['locator'] as String?),
        favorite: (r['favorite'] as int? ?? 0) == 1,
        rating: r['rating'] as int? ?? 0,
        personalNote: r['personal_note'] as String? ?? '',
        totalReadingMs: r['total_reading_ms'] as int? ?? 0,
        readerPrefs: r['reader_prefs'] as String?,
      );
}
