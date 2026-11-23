import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/settings/app_settings.dart';
import '../design/palette.dart';
import '../design/tokens.dart';

/// Retour haptique respectant le réglage utilisateur.
void haptic(BuildContext context, [HapticKind kind = HapticKind.selection]) {
  final settings = context.read<AppSettings>();
  if (!settings.hapticsEnabled) return;
  switch (kind) {
    case HapticKind.selection:
      HapticFeedback.selectionClick();
    case HapticKind.light:
      HapticFeedback.lightImpact();
    case HapticKind.medium:
      HapticFeedback.mediumImpact();
  }
}

enum HapticKind { selection, light, medium }

/// Micro-interaction : léger enfoncement à l'appui.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.96, this.semanticLabel});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                haptic(context);
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                _set(false);
                haptic(context, HapticKind.medium);
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Motion.scaled(context, Motion.fast),
          curve: Motion.curve,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Surface en verre dépoli, utilisée avec parcimonie (barres flottantes).
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = Radii.lg, this.padding, this.blur = 18});

  final Widget child;
  final Radius radius;
  final EdgeInsetsGeometry? padding;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final saver = context.select<AppSettings, bool>((s) => s.batterySaver);
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: saver ? p.surface : p.glass,
        borderRadius: BorderRadius.all(radius),
        border: Border.all(color: p.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: p.shadow.withValues(alpha: 0.16), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: child,
    );
    if (saver) return content;
    return ClipRRect(
      borderRadius: BorderRadius.all(radius),
      child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: content),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction, this.subtitle});

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.sm, Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: t.bodySmall),
                ],
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text(actionLabel!), const SizedBox(width: 4), const Icon(Icons.arrow_forward_rounded, size: 16)],
              ),
            ),
        ],
      ),
    );
  }
}

/// Rangée de puces de filtre défilante.
class FilterChipsRow extends StatelessWidget {
  const FilterChipsRow({super.key, required this.labels, required this.selected, required this.onSelected});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (context, i) {
          final active = i == selected;
          return Pressable(
            onTap: () => onSelected(i),
            semanticLabel: labels[i],
            child: AnimatedContainer(
              duration: Motion.scaled(context, Motion.medium),
              curve: Motion.curve,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? p.primary : p.surface,
                borderRadius: const BorderRadius.all(Radii.pill),
                border: Border.all(color: active ? p.primary : p.divider),
                boxShadow: active
                    ? [BoxShadow(color: p.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))]
                    : null,
              ),
              child: Text(
                labels[i],
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: active ? p.onPrimary : p.text,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = LireoPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: p.surfaceAlt, shape: BoxShape.circle),
              child: Icon(icon, size: 38, color: p.primary),
            ),
            const SizedBox(height: Space.lg),
            Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: Space.sm),
            Text(message, style: t.bodyMedium?.copyWith(color: p.textMuted), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: Space.xl), action!],
          ],
        ),
      ),
    );
  }
}

/// Apparition progressive (fondu + léger glissement), désactivable.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (!MotionScope.enabledOf(context)) return child;
    final delay = (index.clamp(0, 8) * 40);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + delay),
      curve: Interval(delay / (360 + delay), 1, curve: Motion.curve),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
      ),
      child: child,
    );
  }
}

String formatDuration(int ms, {bool short = false}) {
  final minutes = (ms / 60000).round();
  if (minutes < 60) return short ? '$minutes min' : '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : (short ? '${h}h${m.toString().padLeft(2, '0')}' : '$h h $m min');
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} Mo';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} Go';
}

String formatDate(DateTime d) {
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String formatRelative(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'à l\'instant';
  if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
  if (diff.inDays == 1) return 'hier';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} jours';
  return formatDate(d);
}
