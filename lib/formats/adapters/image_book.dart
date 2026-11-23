import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// Livre composé d'images (bande dessinée CBZ, image isolée).
abstract class ImageBook {
  int get pageCount;
  Future<Uint8List?> page(int index);
  Future<void> close();
}

const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};

/// Tri « naturel » : page2 avant page10.
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final ma = re.allMatches(a.toLowerCase()).toList();
  final mb = re.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < ma.length && i < mb.length; i++) {
    final x = ma[i].group(0)!, y = mb[i].group(0)!;
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return ma.length.compareTo(mb.length);
}

class CbzBook extends ImageBook {
  CbzBook._(this._input, this._files);

  final InputFileStream _input;
  final List<ArchiveFile> _files;

  static Future<CbzBook> open(String path) async {
    final input = InputFileStream(path);
    final archive = ZipDecoder().decodeStream(input);
    final files = archive.files.where((f) {
      final name = f.name.toLowerCase();
      final dot = name.lastIndexOf('.');
      return f.isFile && !name.contains('__macosx') && dot >= 0 && _imageExtensions.contains(name.substring(dot));
    }).toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));
    if (files.isEmpty) {
      await input.close();
      throw const FormatException('Aucune image trouvée dans cette archive.');
    }
    return CbzBook._(input, files);
  }

  @override
  int get pageCount => _files.length;

  @override
  Future<Uint8List?> page(int index) async => _files[index].readBytes();

  @override
  Future<void> close() => _input.close();
}

class SingleImageBook extends ImageBook {
  SingleImageBook(this.path);
  final String path;

  @override
  int get pageCount => 1;

  @override
  Future<Uint8List?> page(int index) => File(path).readAsBytes();

  @override
  Future<void> close() async {}
}
