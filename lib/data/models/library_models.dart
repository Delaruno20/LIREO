import 'book.dart';

class BookCollection {
  const BookCollection({
    this.id,
    required this.name,
    this.description = '',
    this.isPrivate = false,
    required this.createdAt,
    this.bookCount = 0,
    this.coverPaths = const [],
  });

  final int? id;
  final String name;
  final String description;

  /// Les collections privées sont masquées tant que l'app n'est pas déverrouillée.
  final bool isPrivate;
  final DateTime createdAt;

  /// Champs calculés à la lecture (non persistés).
  final int bookCount;
  final List<String> coverPaths;

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'is_private': isPrivate ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory BookCollection.fromRow(Map<String, Object?> r, {List<String> covers = const []}) => BookCollection(
        id: r['id'] as int,
        name: r['name'] as String,
        description: r['description'] as String? ?? '',
        isPrivate: (r['is_private'] as int? ?? 0) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        bookCount: r['book_count'] as int? ?? 0,
        coverPaths: covers,
      );
}

enum AnnotationKind { bookmark, highlight, note }

/// Couleurs de surlignage proposées (ARGB).
const highlightColors = <int>[
  0xFFF6D365, // jaune miel
  0xFF9BD5A5, // vert sauge
  0xFF8FC1F0, // bleu ciel
  0xFFF3A0B5, // rose
  0xFFC8A2E8, // lavande
];

class Annotation {
  const Annotation({
    this.id,
    required this.bookId,
    required this.kind,
    required this.start,
    BookLocation? end,
    this.text = '',
    this.note = '',
    this.color = 0xFFF6D365,
    required this.createdAt,
    this.chapterTitle = '',
    this.progress = 0,
  }) : end = end ?? start;

  final int? id;
  final int bookId;
  final AnnotationKind kind;
  final BookLocation start;
  final BookLocation end;

  /// Extrait de texte concerné.
  final String text;
  final String note;
  final int color;
  final DateTime createdAt;
  final String chapterTitle;
  final double progress;

  Annotation copyWith({String? note, int? color, AnnotationKind? kind}) => Annotation(
        id: id,
        bookId: bookId,
        kind: kind ?? this.kind,
        start: start,
        end: end,
        text: text,
        note: note ?? this.note,
        color: color ?? this.color,
        createdAt: createdAt,
        chapterTitle: chapterTitle,
        progress: progress,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'book_id': bookId,
        'kind': kind.name,
        'start_chapter': start.chapter,
        'start_offset': start.offset,
        'end_chapter': end.chapter,
        'end_offset': end.offset,
        'text': text,
        'note': note,
        'color': color,
        'created_at': createdAt.millisecondsSinceEpoch,
        'chapter_title': chapterTitle,
        'progress': progress,
      };

  factory Annotation.fromRow(Map<String, Object?> r) => Annotation(
        id: r['id'] as int,
        bookId: r['book_id'] as int,
        kind: AnnotationKind.values.byName(r['kind'] as String),
        start: BookLocation(chapter: r['start_chapter'] as int, offset: r['start_offset'] as int),
        end: BookLocation(chapter: r['end_chapter'] as int, offset: r['end_offset'] as int),
        text: r['text'] as String? ?? '',
        note: r['note'] as String? ?? '',
        color: r['color'] as int? ?? highlightColors.first,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        chapterTitle: r['chapter_title'] as String? ?? '',
        progress: (r['progress'] as num?)?.toDouble() ?? 0,
      );
}

/// Une session de lecture continue, base des statistiques.
class ReadingSession {
  const ReadingSession({
    this.id,
    required this.bookId,
    required this.startedAt,
    required this.durationMs,
    required this.pagesRead,
    required this.startProgress,
    required this.endProgress,
  });

  final int? id;
  final int bookId;
  final DateTime startedAt;
  final int durationMs;
  final int pagesRead;
  final double startProgress;
  final double endProgress;

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'book_id': bookId,
        'started_at': startedAt.millisecondsSinceEpoch,
        'day': dayKey(startedAt),
        'duration_ms': durationMs,
        'pages_read': pagesRead,
        'start_progress': startProgress,
        'end_progress': endProgress,
      };

  factory ReadingSession.fromRow(Map<String, Object?> r) => ReadingSession(
        id: r['id'] as int,
        bookId: r['book_id'] as int,
        startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
        durationMs: r['duration_ms'] as int,
        pagesRead: r['pages_read'] as int,
        startProgress: (r['start_progress'] as num).toDouble(),
        endProgress: (r['end_progress'] as num).toDouble(),
      );

  /// Clé de jour local AAAAMMJJ, utilisée pour agréger les statistiques.
  static int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
}
