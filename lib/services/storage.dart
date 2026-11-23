import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Emplacements de stockage privés de l'application.
class AppStorage {
  AppStorage._(this.root);

  final Directory root;

  Directory get books => Directory(p.join(root.path, 'books'));
  Directory get covers => Directory(p.join(root.path, 'covers'));
  Directory get fonts => Directory(p.join(root.path, 'fonts'));
  Directory get incoming => Directory(p.join(root.path, 'incoming'));

  static Future<AppStorage> init({Directory? root}) async {
    final base = root ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'lireo'));
    final s = AppStorage._(base);
    for (final d in [s.books, s.covers, s.fonts, s.incoming]) {
      await d.create(recursive: true);
    }
    // Restes d'une importation interrompue.
    await for (final f in s.incoming.list()) {
      await f.delete(recursive: true).catchError((_) => f);
    }
    return s;
  }
}
