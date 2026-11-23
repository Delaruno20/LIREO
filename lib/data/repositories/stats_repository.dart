import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../models/library_models.dart';

class DayStat {
  const DayStat(this.day, this.durationMs, this.pages);
  final DateTime day;
  final int durationMs;
  final int pages;
}

class StatsSummary {
  const StatsSummary({
    required this.todayMs,
    required this.weekMs,
    required this.monthMs,
    required this.totalMs,
    required this.finishedBooks,
    required this.pagesRead,
    required this.pagesPerHour,
    required this.currentStreak,
    required this.bestStreak,
    required this.last7Days,
    required this.last30Days,
  });

  final int todayMs;
  final int weekMs;
  final int monthMs;
  final int totalMs;
  final int finishedBooks;
  final int pagesRead;
  final double pagesPerHour;
  final int currentStreak;
  final int bestStreak;
  final List<DayStat> last7Days;
  final List<DayStat> last30Days;
}

class StatsRepository {
  StatsRepository(this._db);

  final Database _db;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  /// Les sessions trop courtes (feuilletage) ne comptent pas.
  static const minSessionMs = 10 * 1000;

  Future<void> recordSession(ReadingSession s) async {
    if (s.durationMs < minSessionMs) return;
    await _db.transaction((txn) async {
      await txn.insert('reading_sessions', s.toRow());
      await txn.rawUpdate(
        'UPDATE books SET total_reading_ms = total_reading_ms + ? WHERE id = ?',
        [s.durationMs, s.bookId],
      );
    });
    _changes.add(null);
  }

  Future<StatsSummary> summary({DateTime? now}) async {
    final today = _dateOnly(now ?? DateTime.now());
    final rows = await _db.rawQuery(
      'SELECT day, SUM(duration_ms) AS ms, SUM(pages_read) AS pages FROM reading_sessions GROUP BY day ORDER BY day',
    );
    final byDay = <int, (int, int)>{
      for (final r in rows) r['day'] as int: ((r['ms'] as num).toInt(), (r['pages'] as num? ?? 0).toInt()),
    };

    int sumSince(DateTime from) {
      final fromKey = ReadingSession.dayKey(from);
      return byDay.entries.where((e) => e.key >= fromKey).fold(0, (a, e) => a + e.value.$1);
    }

    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(today.year, today.month);
    final totalMs = byDay.values.fold(0, (a, v) => a + v.$1);
    final totalPages = byDay.values.fold(0, (a, v) => a + v.$2);

    List<DayStat> lastDays(int n) => [
          for (var i = n - 1; i >= 0; i--)
            () {
              final d = DateTime(today.year, today.month, today.day - i);
              final v = byDay[ReadingSession.dayKey(d)];
              return DayStat(d, v?.$1 ?? 0, v?.$2 ?? 0);
            }(),
        ];

    // Série : jours consécutifs avec lecture, en tolérant qu'aujourd'hui
    // ne soit pas encore lu.
    var streak = 0;
    var cursor = today;
    if (!byDay.containsKey(ReadingSession.dayKey(cursor))) {
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    while (byDay.containsKey(ReadingSession.dayKey(cursor))) {
      streak++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }

    var best = 0, run = 0;
    DateTime? prev;
    for (final key in byDay.keys.toList()..sort()) {
      final d = DateTime(key ~/ 10000, (key ~/ 100) % 100, key % 100);
      run = (prev != null && d.difference(prev).inHours.abs() <= 25) ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }

    final finished = Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM books WHERE finished_at IS NOT NULL OR progress >= 0.995'),
        ) ??
        0;

    return StatsSummary(
      todayMs: sumSince(today),
      weekMs: sumSince(weekStart),
      monthMs: sumSince(monthStart),
      totalMs: totalMs,
      finishedBooks: finished,
      pagesRead: totalPages,
      pagesPerHour: totalMs < 60000 ? 0 : totalPages / (totalMs / 3600000),
      currentStreak: streak,
      bestStreak: best,
      last7Days: lastDays(7),
      last30Days: lastDays(30),
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void dispose() => _changes.close();
}
