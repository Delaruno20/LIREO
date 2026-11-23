import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../core/errors.dart';
import '../data/models/book.dart';
import '../data/repositories/library_repository.dart';
import '../formats/format_registry.dart';
import 'storage.dart';

/// Source à importer : un chemin local ou un flux (sélecteur natif Android,
/// qui fournit souvent une URI de contenu sans chemin).
class ImportSource {
  const ImportSource({required this.name, this.path, this.open});
  final String name;
  final String? path;
  final Stream<List<int>> Function()? open;

  Stream<List<int>> read() => open != null ? open!() : File(path!).openRead();
}

enum ImportStatus { queued, running, done, duplicate, failed }

class ImportItem {
  ImportItem(this.source);
  final ImportSource source;
  ImportStatus status = ImportStatus.queued;
  String? message;
  Book? book;
}

/// File d'importation asynchrone : copie, empreinte (anti-doublons),
/// extraction des métadonnées et de la couverture, insertion en base.
class ImportService extends ChangeNotifier {
  ImportService(this._repo, this._storage);

  final LibraryRepository _repo;
  final AppStorage _storage;

  final List<ImportItem> items = [];
  bool _running = false;

  bool get isRunning => _running;
  int get pending => items.where((i) => i.status == ImportStatus.queued || i.status == ImportStatus.running).length;
  int get completed => items.where((i) => i.status != ImportStatus.queued && i.status != ImportStatus.running).length;

  void clearFinished() {
    items.removeWhere((i) => i.status != ImportStatus.queued && i.status != ImportStatus.running);
    notifyListeners();
  }

  /// Ajoute des fichiers à la file. Les formats non pris en charge sont
  /// signalés immédiatement, sans être copiés.
  Future<List<ImportItem>> enqueue(List<ImportSource> sources) {
    final added = <ImportItem>[];
    for (final s in sources) {
      final item = ImportItem(s);
      if (!FormatRegistry.isSupported(s.name)) {
        item
          ..status = ImportStatus.failed
          ..message = 'Format non pris en charge';
      }
      items.add(item);
      added.add(item);
    }
    notifyListeners();
    final done = Completer<List<ImportItem>>();
    _drain().whenComplete(() => done.complete(added));
    return done.future;
  }

  Future<void> _drain() async {
    if (_running) {
      while (_running) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      return;
    }
    _running = true;
    try {
      while (true) {
        final next = items.where((i) => i.status == ImportStatus.queued).firstOrNull;
        if (next == null) break;
        next.status = ImportStatus.running;
        notifyListeners();
        try {
          final (book, duplicate) = await importOne(next.source);
          next
            ..book = book
            ..status = duplicate ? ImportStatus.duplicate : ImportStatus.done
            ..message = duplicate ? 'Déjà dans la bibliothèque' : null;
        } catch (e, st) {
          next
            ..status = ImportStatus.failed
            ..message = AppError.describe(e);
          AppError.report(e, st, context: 'import ${next.source.name}');
        }
        notifyListeners();
      }
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Importe un fichier. Retourne le livre et `true` s'il existait déjà.
  Future<(Book, bool)> importOne(ImportSource source) async {
    final format = FormatRegistry.forPath(source.name);
    if (format == null) throw const UserFacingError('Format non pris en charge');

    // 1. Copie dans l'espace privé + empreinte SHA-1 en un seul passage.
    final tmp = File(p.join(_storage.incoming.path, '${DateTime.now().microsecondsSinceEpoch}.part'));
    final sink = tmp.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha1.startChunkedConversion(digestSink);
    var size = 0;
    try {
      await for (final chunk in source.read()) {
        sink.add(chunk);
        hasher.add(chunk);
        size += chunk.length;
      }
    } finally {
      await sink.close();
      hasher.close();
    }
    final hash = digestSink.value.toString();

    final existing = await _repo.bookByHash(hash);
    if (existing != null) {
      await tmp.delete();
      return (existing, true);
    }

    final ext = p.extension(source.name).toLowerCase();
    final dest = File(p.join(_storage.books.path, '$hash$ext'));
    await tmp.rename(dest.path);

    // 2. Métadonnées et couverture (en arrière-plan).
    try {
      final meta = await FormatRegistry.extractMetadata(dest.path, format);
      String? coverPath;
      if (meta.coverBytes != null && meta.coverBytes!.isNotEmpty) {
        coverPath = await _saveCover(hash, meta.coverBytes!);
      }
      final fallbackTitle = _titleFromFileName(source.name);
      final book = await _repo.insertBook(Book(
        path: dest.path,
        fileName: source.name,
        format: format.id,
        title: meta.title.trim().isNotEmpty ? meta.title.trim() : fallbackTitle,
        author: meta.author.trim(),
        publisher: meta.publisher.trim(),
        description: meta.description.trim(),
        language: meta.language.trim(),
        categories: meta.categories,
        coverPath: coverPath,
        pageCount: meta.pageCount,
        fileSize: size,
        fileHash: hash,
        addedAt: DateTime.now(),
      ));
      return (book, false);
    } catch (_) {
      await dest.delete().catchError((_) => dest);
      rethrow;
    }
  }

  static String _titleFromFileName(String name) {
    final base = p.basenameWithoutExtension(name).replaceAll(RegExp(r'[_\.]+'), ' ').trim();
    return base.isEmpty ? name : base;
  }

  /// Réduit la couverture (largeur max 520 px) pour un affichage rapide
  /// et une faible empreinte mémoire dans les grandes bibliothèques.
  Future<String?> _saveCover(String hash, Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final probe = await codec.getNextFrame();
      final w = probe.image.width;
      probe.image.dispose();
      codec.dispose();
      var data = bytes;
      var ext = _sniffExtension(bytes);
      if (w > 520 || ext == null) {
        final resized = await ui.instantiateImageCodec(bytes, targetWidth: w > 520 ? 520 : null);
        final frame = await resized.getNextFrame();
        final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        frame.image.dispose();
        resized.dispose();
        if (png == null) return null;
        data = png.buffer.asUint8List();
        ext = 'png';
      }
      final file = File(p.join(_storage.covers.path, '$hash.$ext'));
      await file.writeAsBytes(data, flush: true);
      return file.path;
    } catch (e, st) {
      AppError.report(e, st, context: 'cover');
      return null;
    }
  }

  static String? _sniffExtension(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'jpg';
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
    return null;
  }

  /// Remplace la couverture d'un livre par une image choisie par l'utilisateur.
  Future<String?> replaceCover(Book book, Uint8List bytes) async {
    if (book.coverPath != null) {
      imageCache.evict(FileImage(File(book.coverPath!)));
      await File(book.coverPath!).delete().catchError((_) => File(book.coverPath!));
    }
    return _saveCover('${book.fileHash}-${DateTime.now().millisecondsSinceEpoch}', bytes);
  }

  /// Supprime les livres et leurs fichiers privés (copie + couverture).
  Future<void> deleteBooks(List<Book> books) async {
    await _repo.deleteBooks([for (final b in books) b.id!]);
    for (final b in books) {
      await File(b.path).delete().catchError((_) => File(b.path));
      if (b.coverPath != null) await File(b.coverPath!).delete().catchError((_) => File(b.coverPath!));
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
