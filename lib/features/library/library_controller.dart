import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../data/models/book.dart';
import '../../data/models/library_models.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/settings/app_settings.dart';
import '../../services/app_lock.dart';

/// Données de l'écran d'accueil, recalculées à chaque changement de la base.
class HomeController extends ChangeNotifier {
  HomeController(this._repo, this._settings, this._lock) {
    _sub = _repo.changes.listen((_) => _scheduleReload());
    _lock.addListener(_scheduleReload);
    _settings.addListener(_onSettings);
    reload();
  }

  final LibraryRepository _repo;
  final AppSettings _settings;
  final AppLock _lock;
  late final StreamSubscription<void> _sub;
  Timer? _debounce;
  bool _hidePrivate = true;

  bool loading = true;
  int totalBooks = 0;
  List<String> categories = const [];
  String? category;
  List<Book> continueReading = const [];
  List<Book> library = const [];
  List<Book> recentlyAdded = const [];
  List<Book> favorites = const [];
  List<Book> recommended = const [];
  bool recommendedFromHistory = false;
  List<BookCollection> collections = const [];

  void _onSettings() {
    if (_settings.hidePrivateCollections != _hidePrivate) _scheduleReload();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), reload);
  }

  void setCategory(String? c) {
    category = c;
    reload();
  }

  Future<void> reload() async {
    _hidePrivate = _settings.hidePrivateCollections;
    final hidden = _hidePrivate && !_lock.privateUnlocked ? await _repo.privateBookIds() : <int>{};
    List<Book> visible(List<Book> l) => hidden.isEmpty ? l : l.where((b) => !hidden.contains(b.id)).toList();

    final all = visible(await _repo.books(BookQuery(category: category)));
    final everything = category == null ? all : visible(await _repo.books());
    totalBooks = everything.length;
    categories = await _repo.categories();
    if (category != null && !categories.contains(category)) category = null;

    continueReading = everything.where((b) => b.lastOpenedAt != null && !b.isFinished).take(10).toList();
    library = all.take(24).toList();
    recentlyAdded = ([...all]..sort((a, b) => b.addedAt.compareTo(a.addedAt))).take(12).toList();
    favorites = all.where((b) => b.favorite).take(12).toList();
    final (rec, fromHistory) = recommend(everything);
    recommended = rec;
    recommendedFromHistory = fromHistory;
    collections = await _repo.collections(includePrivate: !_hidePrivate || _lock.privateUnlocked);
    loading = false;
    notifyListeners();
  }

  /// Recommandations calculées localement à partir de vos lectures :
  /// livres non commencés partageant un auteur ou une catégorie avec
  /// vos lectures récentes et vos favoris.
  static (List<Book>, bool) recommend(List<Book> books) {
    final read = books.where((b) => b.lastOpenedAt != null || b.favorite).toList()
      ..sort((a, b) => (b.lastOpenedAt ?? b.addedAt).compareTo(a.lastOpenedAt ?? a.addedAt));
    final unread = books.where((b) => b.lastOpenedAt == null).toList();
    if (unread.isEmpty) return (const [], false);
    if (read.isEmpty) {
      final list = [...unread]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      return (list.take(10).toList(), false);
    }
    final authors = <String, double>{};
    final cats = <String, double>{};
    for (var i = 0; i < read.length && i < 20; i++) {
      final w = 1 / (1 + i * 0.25) * (read[i].favorite ? 1.5 : 1);
      final b = read[i];
      if (b.author.isNotEmpty) authors[b.author.toLowerCase()] = (authors[b.author.toLowerCase()] ?? 0) + w;
      for (final c in b.categories) {
        cats[c] = (cats[c] ?? 0) + w;
      }
    }
    double score(Book b) {
      var s = (authors[b.author.toLowerCase()] ?? 0) * 3;
      for (final c in b.categories) {
        s += (cats[c] ?? 0) * 2;
      }
      final days = DateTime.now().difference(b.addedAt).inDays;
      if (days < 30) s += 0.5;
      return s;
    }

    final scored = unread.map((b) => (b, score(b))).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return (scored.take(10).map((e) => e.$1).toList(), scored.first.$2 > 0.5);
  }

  @override
  void dispose() {
    _sub.cancel();
    _debounce?.cancel();
    _lock.removeListener(_scheduleReload);
    _settings.removeListener(_onSettings);
    super.dispose();
  }
}
