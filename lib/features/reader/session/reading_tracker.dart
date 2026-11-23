import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../data/models/book.dart';
import '../../../data/models/library_models.dart';
import '../../../data/repositories/library_repository.dart';
import '../../../data/repositories/stats_repository.dart';

/// Mesure le temps de lecture réel et sauvegarde la progression.
///
/// - Le chronomètre se met en pause après [idleAfter] sans interaction
///   ou quand l'application passe en arrière-plan.
/// - Chaque segment actif est enregistré comme une session.
/// - La position est sauvegardée en continu (résistance aux fermetures brutales).
class ReadingTracker with WidgetsBindingObserver {
  ReadingTracker({
    required this.bookId,
    required this.library,
    required this.stats,
    required double startProgress,
    this.breakReminder = Duration.zero,
    this.onBreakReminder,
  }) : _progress = startProgress {
    WidgetsBinding.instance.addObserver(this);
    _resume();
  }

  final int bookId;
  final LibraryRepository library;
  final StatsRepository stats;
  final Duration breakReminder;
  final void Function(Duration readFor)? onBreakReminder;

  static const idleAfter = Duration(minutes: 3);

  DateTime? _segmentStart;
  double _segmentStartProgress = 0;
  int _pages = 0;
  double _progress;
  BookLocation? _pendingLocator;
  BookLocation? _lastLocator;
  Timer? _idle;
  Timer? _save;
  Duration _continuous = Duration.zero;
  DateTime? _lastReminder;
  bool _closed = false;

  bool get isActive => _segmentStart != null;

  void _resume() {
    if (_closed || _segmentStart != null) return;
    _segmentStart = DateTime.now();
    _segmentStartProgress = _progress;
    _pages = 0;
    _armIdle();
  }

  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(idleAfter, () => _pause(idle: true));
  }

  /// À appeler à chaque interaction (tap, page, défilement, TTS).
  void activity() {
    if (_segmentStart == null) {
      _resume();
    } else {
      _armIdle();
    }
    _checkBreak();
  }

  void pageTurned(int delta) {
    if (delta > 0) _pages += delta;
    activity();
  }

  void _checkBreak() {
    if (breakReminder == Duration.zero || _segmentStart == null) return;
    final now = DateTime.now();
    final total = _continuous + now.difference(_segmentStart!);
    if (total >= breakReminder && (_lastReminder == null || now.difference(_lastReminder!) >= breakReminder)) {
      _lastReminder = now;
      onBreakReminder?.call(total);
    }
  }

  /// Sauvegarde différée de la position (au plus toutes les 600 ms).
  void updatePosition(BookLocation locator, double progress) {
    _progress = progress;
    _pendingLocator = locator;
    _lastLocator = locator;
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 600), _flushPosition);
  }

  Future<void> _flushPosition() async {
    final l = _pendingLocator;
    if (l == null) return;
    _pendingLocator = null;
    await library.saveProgress(bookId, l, _progress);
  }

  Future<void> _pause({bool idle = false}) async {
    _idle?.cancel();
    final start = _segmentStart;
    if (start == null) return;
    _segmentStart = null;
    final duration = DateTime.now().difference(start);
    // La dernière période d'inactivité ne compte pas comme lecture.
    final effective = idle && duration > idleAfter ? duration - idleAfter : duration;
    _continuous += effective;
    await stats.recordSession(ReadingSession(
      bookId: bookId,
      startedAt: start,
      durationMs: effective.inMilliseconds,
      pagesRead: _pages,
      startProgress: _segmentStartProgress,
      endProgress: _progress,
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _flushPosition();
      _pause();
    } else if (state == AppLifecycleState.resumed) {
      _continuous = Duration.zero;
      _resume();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _save?.cancel();
    _pendingLocator = null;
    await _pause();
    final last = _lastLocator;
    if (last != null) await library.saveProgress(bookId, last, _progress, notify: true);
  }
}
