import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../core/design/tokens.dart';
import 'storage.dart';

/// Polices de lecture : embarquées + importées par l'utilisateur (TTF/OTF).
class FontService extends ChangeNotifier {
  FontService(this._storage);

  final AppStorage _storage;
  final List<String> _custom = [];

  List<String> get customFamilies => List.unmodifiable(_custom);

  /// Toutes les familles disponibles : id → libellé.
  Map<String, String> get families => {
        ...Fonts.reading,
        for (final f in _custom) f: '$f (importée)',
      };

  Future<void> loadInstalled() async {
    if (!await _storage.fonts.exists()) return;
    await for (final f in _storage.fonts.list()) {
      if (f is File && _isFont(f.path)) {
        try {
          await _register(_familyOf(f.path), await f.readAsBytes());
        } catch (_) {
          // Fichier corrompu : ignoré, l'utilisateur peut le supprimer.
        }
      }
    }
  }

  static bool _isFont(String path) => ['.ttf', '.otf'].contains(p.extension(path).toLowerCase());
  static String _familyOf(String path) => p.basenameWithoutExtension(path).replaceAll(RegExp(r'[-_]+'), ' ').trim();

  Future<void> _register(String family, Uint8List bytes) async {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    if (!_custom.contains(family)) _custom.add(family);
  }

  /// Importe une police ; retourne le nom de famille utilisable.
  Future<String> importFont(String name, Uint8List bytes) async {
    if (!_isFont(name)) throw const FormatException('Seules les polices TTF et OTF sont acceptées.');
    final family = _familyOf(name);
    await _register(family, bytes);
    await File(p.join(_storage.fonts.path, p.basename(name))).writeAsBytes(bytes, flush: true);
    notifyListeners();
    return family;
  }

  Future<void> removeFont(String family) async {
    await for (final f in _storage.fonts.list()) {
      if (f is File && _familyOf(f.path) == family) await f.delete();
    }
    _custom.remove(family);
    notifyListeners();
  }
}
