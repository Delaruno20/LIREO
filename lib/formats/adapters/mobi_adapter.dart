import 'dart:convert';
import 'dart:typed_data';

import '../document/flow_document.dart';
import '../document/html_converter.dart';
import '../metadata/book_metadata.dart';
import 'text_adapters.dart';

class MobiException implements Exception {
  const MobiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lecteur Mobipocket (MOBI, PRC) et Kindle KF8 (AZW3).
///
/// Prend en charge les livres non chiffrés compressés en PalmDOC ou non
/// compressés. Les livres protégés par DRM et la compression HUFF/CDIC
/// sont refusés explicitement plutôt que mal affichés.
class MobiFile {
  MobiFile._(this._data, this._records, this.metadata, this._html, this._firstImage);

  final Uint8List _data;
  final List<int> _records;
  final BookMetadata metadata;
  final String _html;
  final int _firstImage;

  String get html => _html;

  static int _u16(Uint8List d, int o) => (d[o] << 8) | d[o + 1];
  static int _u32(Uint8List d, int o) => (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];

  Uint8List record(int i) {
    final start = _records[i];
    final end = i + 1 < _records.length ? _records[i + 1] : _data.length;
    return Uint8List.sublistView(_data, start, end);
  }

  Uint8List? imageRecord(int index) {
    final i = _firstImage + index;
    if (i < 0 || i >= _records.length) return null;
    final r = record(i);
    // Ignore les enregistrements non image (FLIS, FCIS, SRCS, BOUNDARY…).
    if (r.length < 4) return null;
    final isJpeg = r[0] == 0xFF && r[1] == 0xD8;
    final isPng = r[0] == 0x89 && r[1] == 0x50;
    final isGif = r[0] == 0x47 && r[1] == 0x49;
    return isJpeg || isPng || isGif ? r : null;
  }

  static MobiFile parse(Uint8List data, {bool loadText = true}) {
    if (data.length < 78) throw const MobiException('Fichier MOBI tronqué.');
    final type = ascii.decode(data.sublist(60, 68), allowInvalid: true);
    if (type != 'BOOKMOBI' && type != 'TEXtREAd') throw const MobiException('Ce fichier n\'est pas un livre Mobipocket.');
    final count = _u16(data, 76);
    final records = [for (var i = 0; i < count; i++) _u32(data, 78 + i * 8)];

    var base = records[0];
    var r0 = Uint8List.sublistView(data, base, records.length > 1 ? records[1] : data.length);
    if (r0.length < 16) throw const MobiException('En-tête MOBI invalide.');

    var meta = _readHeader(r0);
    // KF8 (AZW3 ou MOBI hybride) : on préfère la section KF8 si elle existe.
    var recordOffset = 0;
    final kf8 = meta.exth[121];
    if (kf8 != null && kf8.length >= 4) {
      final boundary = _u32(kf8, 0);
      if (boundary > 0 && boundary < records.length && boundary != 0xFFFFFFFF) {
        base = records[boundary];
        r0 = Uint8List.sublistView(data, base, boundary + 1 < records.length ? records[boundary + 1] : data.length);
        final kfMeta = _readHeader(r0);
        if (kfMeta.isMobi) {
          meta = kfMeta.withExthFallback(meta);
          recordOffset = boundary;
        }
      }
    }

    if (meta.encryption != 0) throw const MobiException('Ce livre est protégé par DRM et ne peut pas être ouvert.');
    if (meta.compression == 17480) {
      throw const MobiException('Compression HUFF/CDIC pas encore prise en charge pour ce livre.');
    }
    if (meta.compression != 1 && meta.compression != 2) {
      throw MobiException('Compression MOBI inconnue (${meta.compression}).');
    }

    String exthString(int key) {
      final v = meta.exth[key];
      return v == null ? '' : utf8.decode(v, allowMalformed: true).trim();
    }

    final firstImage = meta.firstImageIndex == 0xFFFFFFFF ? records.length : meta.firstImageIndex + recordOffset;

    final file = MobiFile._(data, records, const BookMetadata(), '', firstImage);
    Uint8List? cover;
    final coverOffset = meta.exth[201];
    if (coverOffset != null && coverOffset.length >= 4) cover = file.imageRecord(_u32(coverOffset, 0));
    final thumb = meta.exth[202];
    if (cover == null && thumb != null && thumb.length >= 4) cover = file.imageRecord(_u32(thumb, 0));

    var html = '';
    if (loadText) {
      final out = BytesBuilder(copy: false);
      for (var i = 1; i <= meta.textRecords && recordOffset + i < records.length; i++) {
        var rec = file.record(recordOffset + i);
        final trailing = _trailingSize(rec, meta.extraFlags);
        rec = Uint8List.sublistView(rec, 0, (rec.length - trailing).clamp(0, rec.length));
        out.add(meta.compression == 2 ? palmDocDecompress(rec) : rec);
      }
      final bytes = out.takeBytes();
      final textBytes = bytes.length > meta.textLength && meta.textLength > 0 ? bytes.sublist(0, meta.textLength) : bytes;
      html = meta.encoding == 65001 ? utf8.decode(textBytes, allowMalformed: true) : latin1.decode(textBytes);
    }

    final title = exthString(503).isNotEmpty ? exthString(503) : meta.fullName;
    final subjects = meta.exthAll(105).map((b) => utf8.decode(b, allowMalformed: true).trim()).where((s) => s.isNotEmpty).toList();
    return MobiFile._(
      data,
      records,
      BookMetadata(
        title: title,
        author: meta.exthAll(100).map((b) => utf8.decode(b, allowMalformed: true).trim()).join(', '),
        publisher: exthString(101),
        description: exthString(103).replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
        language: exthString(524),
        categories: subjects.take(3).toList(),
        coverBytes: cover,
        pageCount: (meta.textLength / BookMetadata.charsPerPage).ceil(),
      ),
      html,
      firstImage,
    );
  }

  static _MobiHeader _readHeader(Uint8List r0) {
    final compression = _u16(r0, 0);
    final textLength = _u32(r0, 4);
    final textRecords = _u16(r0, 8);
    final encryption = _u16(r0, 12);
    final isMobi = r0.length > 20 && ascii.decode(r0.sublist(16, 20), allowInvalid: true) == 'MOBI';
    if (!isMobi) {
      return _MobiHeader(
        compression: compression,
        textLength: textLength,
        textRecords: textRecords,
        encryption: encryption,
        isMobi: false,
      );
    }
    final headerLength = _u32(r0, 20);
    final encoding = _u32(r0, 28);
    final fullNameOffset = _u32(r0, 84);
    final fullNameLength = _u32(r0, 88);
    final firstImage = r0.length > 112 ? _u32(r0, 108) : 0xFFFFFFFF;
    final exthFlags = r0.length > 132 ? _u32(r0, 128) : 0;
    final extraFlags = headerLength >= 0xE4 && r0.length > 244 ? _u16(r0, 242) : 0;
    var fullName = '';
    if (fullNameOffset + fullNameLength <= r0.length) {
      fullName = utf8.decode(r0.sublist(fullNameOffset, fullNameOffset + fullNameLength), allowMalformed: true);
    }
    final exth = <int, List<Uint8List>>{};
    final exthStart = 16 + headerLength;
    if (exthFlags & 0x40 != 0 && exthStart + 12 <= r0.length && ascii.decode(r0.sublist(exthStart, exthStart + 4), allowInvalid: true) == 'EXTH') {
      final n = _u32(r0, exthStart + 8);
      var pos = exthStart + 12;
      for (var i = 0; i < n && pos + 8 <= r0.length; i++) {
        final t = _u32(r0, pos), len = _u32(r0, pos + 4);
        if (len < 8 || pos + len > r0.length) break;
        (exth[t] ??= []).add(Uint8List.sublistView(r0, pos + 8, pos + len));
        pos += len;
      }
    }
    return _MobiHeader(
      compression: compression,
      textLength: textLength,
      textRecords: textRecords,
      encryption: encryption,
      isMobi: true,
      encoding: encoding,
      firstImageIndex: firstImage,
      extraFlags: extraFlags,
      fullName: fullName,
      exthLists: exth,
    );
  }

  static int _trailingSize(Uint8List data, int flags) {
    int entry(int size) {
      var bitpos = 0, result = 0;
      while (size > 0) {
        final v = data[size - 1];
        result |= (v & 0x7F) << bitpos;
        bitpos += 7;
        size--;
        if (v & 0x80 != 0 || bitpos >= 28) break;
      }
      return result;
    }

    var num = 0;
    var f = flags >> 1;
    while (f != 0) {
      if (f & 1 != 0) num += entry(data.length - num);
      f >>= 1;
    }
    if (flags & 1 != 0 && data.length - num - 1 >= 0) num += (data[data.length - num - 1] & 0x3) + 1;
    return num;
  }

  /// Décompression LZ77 PalmDOC.
  static Uint8List palmDocDecompress(Uint8List input) {
    final out = <int>[];
    var i = 0;
    while (i < input.length) {
      final c = input[i++];
      if (c >= 1 && c <= 8) {
        for (var k = 0; k < c && i < input.length; k++) {
          out.add(input[i++]);
        }
      } else if (c < 0x80) {
        out.add(c);
      } else if (c >= 0xC0) {
        out
          ..add(0x20)
          ..add(c ^ 0x80);
      } else if (i < input.length) {
        final pair = (c << 8) | input[i++];
        final distance = (pair >> 3) & 0x7FF;
        final length = (pair & 7) + 3;
        if (distance == 0 || distance > out.length) continue;
        for (var k = 0; k < length; k++) {
          out.add(out[out.length - distance]);
        }
      }
    }
    return Uint8List.fromList(out);
  }
}

class _MobiHeader {
  const _MobiHeader({
    required this.compression,
    required this.textLength,
    required this.textRecords,
    required this.encryption,
    required this.isMobi,
    this.encoding = 1252,
    this.firstImageIndex = 0xFFFFFFFF,
    this.extraFlags = 0,
    this.fullName = '',
    this.exthLists = const {},
  });

  final int compression, textLength, textRecords, encryption, encoding, firstImageIndex, extraFlags;
  final bool isMobi;
  final String fullName;
  final Map<int, List<Uint8List>> exthLists;

  Map<int, Uint8List> get exth => {for (final e in exthLists.entries) e.key: e.value.first};
  List<Uint8List> exthAll(int key) => exthLists[key] ?? const [];

  _MobiHeader withExthFallback(_MobiHeader other) => _MobiHeader(
        compression: compression,
        textLength: textLength,
        textRecords: textRecords,
        encryption: encryption,
        isMobi: isMobi,
        encoding: encoding,
        firstImageIndex: firstImageIndex == 0xFFFFFFFF ? other.firstImageIndex : firstImageIndex,
        extraFlags: extraFlags,
        fullName: fullName.isEmpty ? other.fullName : fullName,
        exthLists: {...other.exthLists, ...exthLists},
      );
}

abstract final class MobiAdapter {
  static BookMetadata metadata(Uint8List bytes) => MobiFile.parse(bytes, loadText: false).metadata;

  static ReflowableBook open(Uint8List bytes, String fallbackTitle) {
    final mobi = MobiFile.parse(bytes);
    final resources = <String, Uint8List>{};
    String resolve(String src) {
      // KF8 : kindle:embed:XXXX (base 32), MOBI6 : recindex numérique.
      final kindle = RegExp(r'kindle:embed:([0-9A-Va-v]{4})').firstMatch(src);
      final index = kindle != null ? int.parse(kindle.group(1)!, radix: 32) : int.tryParse(src);
      if (index == null) return src;
      final key = 'img:$index';
      final data = mobi.imageRecord(index - 1);
      if (data != null) resources[key] = data;
      return key;
    }

    // MOBI6 référence les images par l'attribut recindex.
    final html = mobi.html
        .replaceAllMapped(RegExp(r'<img([^>]*?)recindex="?(\d+)"?', caseSensitive: false), (m) => '<img src="${m[2]}"${m[1]}')
        .replaceAll(RegExp(r'<mbp:pagebreak\s*/?>', caseSensitive: false), '<hr/>');
    final blocks = HtmlFlowConverter.parse(html, resolveImage: resolve);
    return MemoryReflowableBook(
      chapters: splitIntoChapters(blocks, fallbackTitle: mobi.metadata.title.isEmpty ? fallbackTitle : mobi.metadata.title),
      resources: resources,
    );
  }
}
