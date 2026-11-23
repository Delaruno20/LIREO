import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/book_cover.dart';
import '../../core/widgets/common.dart';
import '../../data/models/book.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/stats_repository.dart';
import '../../data/settings/app_settings.dart';

/// Tableau de bord de lecture, calculé hors ligne à partir des sessions.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StatsSummary? _summary;
  List<Book> _reading = const [];
  final _subs = <StreamSubscription<void>>[];

  @override
  void initState() {
    super.initState();
    _subs
      ..add(context.read<StatsRepository>().changes.listen((_) => _load()))
      ..add(context.read<LibraryRepository>().changes.listen((_) => _load()));
    _load();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final summary = await context.read<StatsRepository>().summary();
    if (!mounted) return;
    final reading = await context.read<LibraryRepository>().books(const BookQuery(status: 'reading', limit: 8));
    if (mounted) {
      setState(() {
        _summary = summary;
        _reading = reading;
      });
    }
  }

  Future<void> _editGoal() async {
    final settings = context.read<AppSettings>();
    var value = settings.dailyGoalMinutes.toDouble();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Objectif quotidien'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.round()} minutes par jour', style: Theme.of(ctx).textTheme.titleLarge),
              Slider(value: value, min: 5, max: 180, divisions: 35, onChanged: (v) => setState(() => value = v)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok == true) await settings.setDailyGoal(value.round());
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final p = LireoPalette.of(context);
    final goal = context.watch<AppSettings>().dailyGoalMinutes;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(title: const Text('Statistiques'), backgroundColor: p.background),
            if (s == null)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                sliver: SliverList.list(children: [
                  _TodayCard(summary: s, goalMinutes: goal, onEditGoal: _editGoal),
                  const SizedBox(height: Space.lg),
                  _Card(
                    title: '7 derniers jours',
                    trailing: formatDuration(s.last7Days.fold(0, (a, d) => a + d.durationMs)),
                    child: SizedBox(height: 180, child: _WeekBars(days: s.last7Days, goalMinutes: goal)),
                  ),
                  const SizedBox(height: Space.lg),
                  _Card(
                    title: '30 derniers jours',
                    trailing: '${s.last30Days.where((d) => d.durationMs > 0).length} jours de lecture',
                    child: _Heatmap(days: s.last30Days),
                  ),
                  const SizedBox(height: Space.lg),
                  GridView.count(
                    crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: Space.md,
                    crossAxisSpacing: Space.md,
                    childAspectRatio: 1.55,
                    children: [
                      _Tile(Icons.date_range_rounded, formatDuration(s.weekMs, short: true), 'cette semaine'),
                      _Tile(Icons.calendar_month_rounded, formatDuration(s.monthMs, short: true), 'ce mois-ci'),
                      _Tile(Icons.hourglass_bottom_rounded, formatDuration(s.totalMs, short: true), 'au total'),
                      _Tile(Icons.emoji_events_outlined, '${s.finishedBooks}', s.finishedBooks > 1 ? 'livres terminés' : 'livre terminé'),
                      _Tile(Icons.auto_stories_outlined, '${s.pagesRead}', 'pages tournées'),
                      _Tile(Icons.speed_rounded, s.pagesPerHour == 0 ? '—' : s.pagesPerHour.round().toString(), 'pages / heure'),
                      _Tile(Icons.local_fire_department_outlined, '${s.bestStreak}', 'meilleure série (jours)'),
                    ],
                  ),
                  if (_reading.isNotEmpty) ...[
                    const SizedBox(height: Space.xl),
                    Text('En cours', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: Space.sm),
                    for (final b in _reading)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: BookCover(book: b, width: 36, elevation: 0.5),
                        title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(value: b.progress, minHeight: 5),
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                            Text('${(b.progress * 100).round()} %'),
                          ]),
                        ),
                        onTap: () => Routes.reader(context, b),
                      ),
                  ],
                  if (s.totalMs == 0) ...[
                    const SizedBox(height: Space.lg),
                    Text(
                      'Les statistiques se remplissent automatiquement pendant vos lectures (les sessions de moins de 10 secondes sont ignorées).',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 130),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});
  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.all(Radii.lg),
        border: Border.all(color: p.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: t.titleMedium)),
            if (trailing != null) Text(trailing!, style: t.bodySmall),
          ]),
          const SizedBox(height: Space.lg),
          child,
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.summary, required this.goalMinutes, required this.onEditGoal});
  final StatsSummary summary;
  final int goalMinutes;
  final VoidCallback onEditGoal;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final minutes = summary.todayMs / 60000;
    final ratio = (minutes / goalMinutes).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radii.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.surface, Color.lerp(p.surface, p.accent, 0.16)!],
        ),
        border: Border.all(color: p.divider),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            height: 104,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: Motion.scaled(context, Motion.slow),
              curve: Motion.curve,
              builder: (_, v, _) => CustomPaint(
                painter: _RingPainter(v, p.primary, p.divider),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${minutes.round()}', style: t.headlineMedium?.copyWith(fontFamily: Fonts.ui, fontWeight: FontWeight.w700)),
                    Text('/ $goalMinutes min', style: t.bodySmall),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aujourd\'hui', style: t.titleLarge),
                const SizedBox(height: 4),
                Text(
                  ratio >= 1 ? 'Objectif atteint, bravo !' : 'Encore ${(goalMinutes - minutes).ceil()} min pour votre objectif',
                  style: t.bodyMedium?.copyWith(color: p.textMuted),
                ),
                const SizedBox(height: Space.md),
                Row(children: [
                  Icon(Icons.local_fire_department_rounded, color: p.accent, size: 20),
                  const SizedBox(width: 4),
                  Text('${summary.currentStreak} jour${summary.currentStreak > 1 ? 's' : ''} d\'affilée', style: t.labelLarge),
                ]),
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                  onPressed: onEditGoal,
                  child: const Text('Modifier l\'objectif'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track);
  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(6);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, stroke..color = track);
    if (value > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, stroke..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}

/// Histogramme des 7 derniers jours (une série : teinte unique, barres
/// fines arrondies, ligne d'objectif). Toucher une barre affiche sa valeur.
class _WeekBars extends StatefulWidget {
  const _WeekBars({required this.days, required this.goalMinutes});
  final List<DayStat> days;
  final int goalMinutes;

  @override
  State<_WeekBars> createState() => _WeekBarsState();
}

class _WeekBarsState extends State<_WeekBars> {
  int? _selected;

  static const _dayNames = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final mins = [for (final d in widget.days) d.durationMs / 60000];
    final max = math.max(widget.goalMinutes * 1.2, mins.fold<double>(0, math.max));
    return Semantics(
      label: 'Minutes de lecture par jour : ${[for (var i = 0; i < 7; i++) '${_dayNames[widget.days[i].day.weekday - 1]} ${mins[i].round()}'].join(', ')}',
      child: LayoutBuilder(builder: (context, c) {
        final slot = c.maxWidth / 7;
        return GestureDetector(
          onTapDown: (d) => setState(() => _selected = (d.localPosition.dx / slot).floor().clamp(0, 6)),
          child: Stack(children: [
            CustomPaint(
              size: c.biggest,
              painter: _BarsPainter(
                values: mins,
                max: max,
                goal: widget.goalMinutes.toDouble(),
                bar: p.primary,
                muted: p.primary.withValues(alpha: 0.35),
                grid: p.divider,
                selected: _selected,
                labels: [for (final d in widget.days) _dayNames[d.day.weekday - 1]],
                labelStyle: t.labelSmall!,
              ),
            ),
            if (_selected != null)
              Positioned(
                left: (slot * _selected! + slot / 2 - 40).clamp(0, c.maxWidth - 80),
                top: 0,
                child: Container(
                  width: 80,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(color: p.text, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${mins[_selected!].round()} min',
                    textAlign: TextAlign.center,
                    style: t.labelMedium?.copyWith(color: p.background),
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.max,
    required this.goal,
    required this.bar,
    required this.muted,
    required this.grid,
    required this.selected,
    required this.labels,
    required this.labelStyle,
  });

  final List<double> values;
  final double max;
  final double goal;
  final Color bar;
  final Color muted;
  final Color grid;
  final int? selected;
  final List<String> labels;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 20.0, topPad = 28.0;
    final chartH = size.height - labelH - topPad;
    final base = topPad + chartH;
    final slot = size.width / values.length;
    final barW = math.min(22.0, slot * 0.42);
    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = grid);
    // Ligne d'objectif (pointillés discrets).
    final gy = base - chartH * (goal / max);
    final dash = Paint()
      ..color = grid
      ..strokeWidth = 1.2;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, gy), Offset(x + 4, gy), dash);
    }
    for (var i = 0; i < values.length; i++) {
      final cx = slot * i + slot / 2;
      final h = values[i] <= 0 ? 0.0 : math.max(3.0, chartH * (values[i] / max));
      if (h > 0) {
        final r = Rect.fromLTWH(cx - barW / 2, base - h, barW, h);
        canvas.drawRRect(
          RRect.fromRectAndCorners(r, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
          Paint()..color = (selected == null || selected == i) ? bar : muted,
        );
      }
      final tp = TextPainter(text: TextSpan(text: labels[i], style: labelStyle), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, base + 5));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.values != values || old.selected != selected || old.bar != bar;
}

/// Carte de chaleur des 30 derniers jours (teinte unique, clair → foncé).
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.days});
  final List<DayStat> days;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    final max = days.fold<int>(0, (a, d) => math.max(a, d.durationMs));
    Color colorFor(int ms) {
      if (ms <= 0) return p.surfaceAlt;
      final v = max == 0 ? 0.0 : ms / max;
      final step = v < 0.25 ? 0.3 : (v < 0.5 ? 0.5 : (v < 0.75 ? 0.75 : 1.0));
      return Color.lerp(p.surfaceAlt, p.primary, step)!;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, c) {
          const cols = 10;
          const gap = 6.0;
          final cell = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final d in days)
                Tooltip(
                  message: '${formatDate(d.day)} : ${formatDuration(d.durationMs)}',
                  triggerMode: TooltipTriggerMode.tap,
                  child: Container(
                    width: cell,
                    height: math.min(cell, 28),
                    decoration: BoxDecoration(color: colorFor(d.durationMs), borderRadius: BorderRadius.circular(5)),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: Space.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Moins', style: t.labelSmall),
            for (final s in [0.0, 0.3, 0.5, 0.75, 1.0])
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(color: Color.lerp(p.surfaceAlt, p.primary, s), borderRadius: BorderRadius.circular(3)),
              ),
            Text('Plus', style: t.labelSmall),
          ],
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.all(Radii.md),
        border: Border.all(color: p.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: p.primary, size: 20),
          Text(value, style: t.headlineSmall?.copyWith(fontFamily: Fonts.ui, fontWeight: FontWeight.w700)),
          Text(label, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
