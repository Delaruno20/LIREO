import 'dart:typed_data';

/// Métadonnées extraites d'un fichier à l'importation.
class BookMetadata {
  const BookMetadata({
    this.title = '',
    this.author = '',
    this.publisher = '',
    this.description = '',
    this.language = '',
    this.categories = const [],
    this.coverBytes,
    this.pageCount = 0,
  });

  final String title;
  final String author;
  final String publisher;
  final String description;
  final String language;
  final List<String> categories;
  final Uint8List? coverBytes;

  /// Nombre de pages réel (PDF, BD) ou estimé (texte : ~1 500 caractères/page).
  final int pageCount;

  BookMetadata copyWith({String? title, int? pageCount, Uint8List? coverBytes}) => BookMetadata(
        title: title ?? this.title,
        author: author,
        publisher: publisher,
        description: description,
        language: language,
        categories: categories,
        coverBytes: coverBytes ?? this.coverBytes,
        pageCount: pageCount ?? this.pageCount,
      );

  static const charsPerPage = 1500;
}
