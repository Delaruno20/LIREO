/// Fusion de deux états de synchronisation (local et distant).
///
/// Fonction pure, sans effet de bord : l'ordre des arguments n'influence pas
/// le résultat, et fusionner un état avec lui-même le laisse inchangé.
///
/// Règles :
/// - Progression d'un livre : celle de la lecture la plus récente (`last_opened_at`).
/// - Métadonnées, favori, note : la modification la plus récente (`updated_at`).
/// - Annotations, sessions, membres de collection : union, moins ce qui a été
///   supprimé (trace `tombstones`) après sa dernière modification.
/// - Réglages : la version la plus récente.
abstract final class SyncMerge {
  static const format = 'lireo-sync';
  static const version = 1;

  static const readingFields = ['progress', 'locator', 'last_opened_at', 'finished_at'];
  static const metaFields = [
    'title', 'author', 'publisher', 'description', 'categories', 'favorite', 'rating', 'personal_note', 'reader_prefs',
  ];

  static Map<String, dynamic> empty() => {
        'format': format,
        'version': version,
        'books': <String, dynamic>{},
        'annotations': <String, dynamic>{},
        'sessions': <String, dynamic>{},
        'collections': <String, dynamic>{},
        'tombstones': <String, dynamic>{},
        'settings': null,
      };

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  static Map<String, dynamic> _map(Map<String, dynamic> s, String key) =>
      Map<String, dynamic>.from((s[key] as Map?) ?? const {});

  static Map<String, dynamic> merge(Map<String, dynamic> a, Map<String, dynamic> b) {
    // Traces de suppression : union, date la plus récente.
    final tombstones = _map(a, 'tombstones');
    _map(b, 'tombstones').forEach((k, v) {
      if (_int(v) > _int(tombstones[k])) tombstones[k] = v;
    });
    bool deletedAfter(String kind, String key, int stamp) =>
        tombstones.containsKey('$kind|$key') && _int(tombstones['$kind|$key']) >= stamp;

    // Livres
    final books = <String, dynamic>{};
    final ba = _map(a, 'books'), bb = _map(b, 'books');
    for (final hash in {...ba.keys, ...bb.keys}) {
      final x = ba[hash] as Map?, y = bb[hash] as Map?;
      if (x == null || y == null) {
        books[hash] = Map<String, dynamic>.from((x ?? y)!);
        continue;
      }
      final reading = _int(x['last_opened_at']) >= _int(y['last_opened_at']) ? x : y;
      final meta = _int(x['updated_at']) >= _int(y['updated_at']) ? x : y;
      books[hash] = {
        for (final f in readingFields) f: reading[f],
        for (final f in metaFields) f: meta[f],
        'updated_at': meta['updated_at'],
      };
    }

    // Annotations
    final annotations = <String, dynamic>{};
    final aa = _map(a, 'annotations'), ab = _map(b, 'annotations');
    for (final key in {...aa.keys, ...ab.keys}) {
      final x = aa[key] as Map?, y = ab[key] as Map?;
      final pick = x == null ? y! : (y == null ? x : (_int(x['updated_at']) >= _int(y['updated_at']) ? x : y));
      final stamp = _int(pick['updated_at']) > 0 ? _int(pick['updated_at']) : _int(pick['created_at']);
      if (deletedAfter('annotation', key, stamp)) continue;
      annotations[key] = Map<String, dynamic>.from(pick);
    }

    // Sessions de lecture : union simple (elles ne sont jamais modifiées).
    final sessions = {..._map(a, 'sessions'), ..._map(b, 'sessions')};

    // Collections
    final collections = <String, dynamic>{};
    final ca = _map(a, 'collections'), cb = _map(b, 'collections');
    for (final name in {...ca.keys, ...cb.keys}) {
      final x = ca[name] as Map?, y = cb[name] as Map?;
      final meta = x == null ? y! : (y == null ? x : (_int(x['updated_at']) >= _int(y['updated_at']) ? x : y));
      final members = <String, dynamic>{};
      for (final src in [x, y]) {
        final m = Map<String, dynamic>.from((src?['members'] as Map?) ?? const {});
        m.forEach((hash, added) {
          if (_int(added) > _int(members[hash])) members[hash] = added;
        });
      }
      members.removeWhere((hash, added) => deletedAfter('member', '$name|$hash', _int(added)));
      final stamp = [_int(meta['updated_at']), _int(meta['created_at']), ...members.values.map(_int)].reduce((p, q) => p > q ? p : q);
      if (deletedAfter('collection', name, stamp)) continue;
      collections[name] = {...Map<String, dynamic>.from(meta), 'members': members};
    }

    // Réglages
    final sa = a['settings'] as Map?, sb = b['settings'] as Map?;
    final settings = sa == null ? sb : (sb == null ? sa : (_int(sa['updated_at']) >= _int(sb['updated_at']) ? sa : sb));

    return {
      'format': format,
      'version': version,
      'books': books,
      'annotations': annotations,
      'sessions': sessions,
      'collections': collections,
      'tombstones': tombstones,
      'settings': settings,
    };
  }
}
