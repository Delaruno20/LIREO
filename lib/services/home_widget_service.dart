import 'dart:async';
import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../core/errors.dart';
import '../data/models/book.dart';
import '../data/repositories/library_repository.dart';
import '../data/settings/app_settings.dart';
import 'reminder_service.dart';

/// Tient à jour ce qui vit hors de l'application : widget d'écran
/// d'accueil et texte du rappel quotidien (qui cite le livre en cours).
class LibraryObservers {
  LibraryObservers(this._library, this._settings, this.reminders);

  final LibraryRepository _library;
  final AppSettings _settings;
  final ReminderService reminders;
  StreamSubscription<void>? _sub;
  Timer? _debounce;

  static const androidWidget = 'app.lireo.lireo.LireoBookWidget';

  void start() {
    _sub = _library.changes.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 1), refresh);
    });
    _settings.addListener(_onSettings);
    refresh();
  }

  bool _lastReminder = false;
  int _lastMinutes = -1;

  void _onSettings() {
    if (_settings.reminderEnabled != _lastReminder || _settings.reminderMinutes != _lastMinutes) refresh();
  }

  /// Livre mis en avant : dernier livre ouvert et non terminé, hors collections privées masquées.
  Future<Book?> currentBook() async {
    final reading = await _library.books(const BookQuery(status: 'reading', limit: 5));
    if (reading.isEmpty) return null;
    if (!_settings.hidePrivateCollections) return reading.first;
    final hidden = await _library.privateBookIds();
    for (final b in reading) {
      if (!hidden.contains(b.id)) return b;
    }
    return null;
  }

  Future<void> refresh() async {
    try {
      final book = await currentBook();
      await _updateWidget(book);
      _lastReminder = _settings.reminderEnabled;
      _lastMinutes = _settings.reminderMinutes;
      if (_settings.reminderEnabled) {
        await reminders.schedule(_settings.reminderTime, current: book);
      } else {
        await reminders.cancel();
      }
    } catch (e, st) {
      AppError.report(e, st, context: 'observers');
    }
  }

  Future<void> _updateWidget(Book? book) async {
    if (!Platform.isAndroid) return;
    await HomeWidget.saveWidgetData<int>('book_id', book?.id ?? -1);
    await HomeWidget.saveWidgetData<String>('book_title', book?.title ?? '');
    await HomeWidget.saveWidgetData<String>('book_author', book?.displayAuthor ?? '');
    await HomeWidget.saveWidgetData<int>('book_progress', ((book?.progress ?? 0) * 100).round());
    await HomeWidget.saveWidgetData<String>('book_cover', book?.coverPath ?? '');
    await HomeWidget.updateWidget(qualifiedAndroidName: androidWidget);
  }

  /// Identifiant du livre demandé par un tap sur le widget (`lireo://resume?id=…`).
  static int? bookIdFrom(Uri? uri) {
    if (uri == null || uri.host != 'resume') return null;
    return int.tryParse(uri.queryParameters['id'] ?? '');
  }

  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _settings.removeListener(_onSettings);
  }
}
