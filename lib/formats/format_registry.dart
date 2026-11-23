import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'adapters/docx_adapter.dart';
import 'adapters/epub_adapter.dart';
import 'adapters/fb2_adapter.dart';
import 'adapters/image_book.dart';
import 'adapters/mobi_adapter.dart';
import 'adapters/text_adapters.dart';
import 'document/flow_document.dart';
import 'metadata/book_metadata.dart';

/// Famille de moteur de rendu utilisée pour un format.
enum EngineKind { reflowable, pdf, images }

class BookFormat {
  const BookFormat(this.id, this.label, this.engine, this.extensions);

  final String id;
  final String label;
  final EngineKind engine;
  final List<String> extensions;
}

/// Registre des formats réellement pris en charge.
///
/// Un format n'apparaît ici que s'il dispose d'un vrai adaptateur. Pour en
/// ajouter un : écrire l'adaptateur puis l'enregistrer dans [formats],
/// [extractMetadata] et [openReflowable]/[openImages].
abstract final class FormatRegistry {
  static const formats = <BookFormat>[
    BookFormat('epub', 'EPUB', EngineKind.reflowable, ['epub']),
    BookFormat('pdf', 'PDF', EngineKind.pdf, ['pdf']),
    BookFormat('mobi', 'MOBI', EngineKind.reflowable, ['mobi', 'prc']),
    BookFormat('azw3', 'AZW3', EngineKind.reflowable, ['azw3', 'azw']),
    BookFormat('fb2', 'FB2', EngineKind.reflowable, ['fb2']),
    BookFormat('docx', 'DOCX', EngineKind.reflowable, ['docx']),
    BookFormat('odt', 'ODT', EngineKind.reflowable, ['odt']),
    BookFormat('txt', 'TXT', EngineKind.reflowable, ['txt', 'text']),
    BookFormat('md', 'Markdown', EngineKind.reflowable, ['md', 'markdown']),
    BookFormat('html', 'HTML', EngineKind.reflowable, ['html', 'htm', 'xhtml']),
    BookFormat('cbz', 'CBZ', EngineKind.images, ['cbz']),
    BookFormat('image', 'Image', EngineKind.images, ['webp', 'jpg', 'jpeg', 'png']),
  ];

  static final Set<String> extensions = {for (final f in formats) ...f.extensions};

  static BookFormat? forPath(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    for (final f in formats) {
      if (f.extensions.contains(ext)) return f;
    }
    return null;
  }

  static BookFormat byId(String id) => formats.firstWhere((f) => f.id == id, orElse: () => formats.first);

  static bool isSupported(String path) => forPath(path) != null;

  /// Extrait les métadonnées. Le parsing pur Dart tourne dans un isolate
  /// pour ne jamais bloquer l'interface.
  static Future<BookMetadata> extractMetadata(String path, BookFormat format) async {
    if (format.engine == EngineKind.pdf) return _pdfMetadata(path);
    final id = format.id;
    return Isolate.run(() => _extractSync(path, id));
  }

  static Future<BookMetadata> _extractSync(String path, String formatId) async {
    switch (formatId) {
      case 'epub':
        final pkg = await EpubPackage.openFile(path);
        try {
          var chars = 0;
          for (final s in pkg.spine) {
            chars += pkg.sizeOf(s);
          }
          // ~45 % du poids XHTML est du balisage : estimation du nombre de pages.
          return pkg.metadata.copyWith(pageCount: (chars * 0.55 / BookMetadata.charsPerPage).ceil());
        } finally {
          await pkg.close();
        }
      case 'cbz':
        final book = await CbzBook.open(path);
        try {
          return BookMetadata(pageCount: book.pageCount, coverBytes: await book.page(0));
        } finally {
          await book.close();
        }
      case 'image':
        return BookMetadata(pageCount: 1, coverBytes: await File(path).readAsBytes());
    }
    final bytes = await File(path).readAsBytes();
    return switch (formatId) {
      'mobi' || 'azw3' => MobiAdapter.metadata(bytes),
      'fb2' => Fb2Adapter.metadata(bytes),
      'docx' || 'odt' => OfficeAdapter.metadata(bytes, formatId),
      'md' => MarkdownAdapter.metadata(bytes),
      'html' => HtmlAdapter.metadata(bytes),
      _ => TxtAdapter.metadata(bytes),
    };
  }

  static Future<BookMetadata> _pdfMetadata(String path) async {
    final doc = await PdfDocument.openFile(path);
    try {
      Uint8List? cover;
      if (doc.pages.isNotEmpty) {
        final page = doc.pages.first;
        const width = 600.0;
        final height = width * page.height / page.width;
        final image = await page.render(
          fullWidth: width,
          fullHeight: height,
          width: width.round(),
          height: height.round(),
          backgroundColor: 0xFFFFFFFF,
        );
        if (image != null) {
          cover = await _bgraToPng(image.pixels, image.width, image.height);
          image.dispose();
        }
      }
      return BookMetadata(pageCount: doc.pages.length, coverBytes: cover);
    } finally {
      await doc.dispose();
    }
  }

  static Future<Uint8List?> _bgraToPng(Uint8List pixels, int w, int h) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: w, height: h, pixelFormat: ui.PixelFormat.bgra8888);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return data?.buffer.asUint8List();
  }

  /// Ouvre un livre reflowable. Les formats chargés entièrement en mémoire
  /// sont analysés dans un isolate.
  static Future<ReflowableBook> openReflowable(String path, String formatId, String title) async {
    if (formatId == 'epub') return EpubBook.open(path);
    return Isolate.run(() async {
      final bytes = await File(path).readAsBytes();
      return switch (formatId) {
        'mobi' || 'azw3' => MobiAdapter.open(bytes, title),
        'fb2' => Fb2Adapter.open(bytes, title),
        'docx' || 'odt' => OfficeAdapter.open(bytes, formatId, title),
        'md' => MarkdownAdapter.open(bytes, title),
        'html' => HtmlAdapter.open(bytes, title),
        _ => TxtAdapter.open(bytes, title),
      };
    });
  }

  static Future<ImageBook> openImages(String path, String formatId) async =>
      formatId == 'cbz' ? CbzBook.open(path) : SingleImageBook(path);
}
