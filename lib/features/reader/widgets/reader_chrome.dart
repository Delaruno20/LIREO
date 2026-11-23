import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';

/// Barres de commande du lecteur (haut et bas), superposées au texte.
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({
    super.key,
    required this.visible,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.progressLabel,
    required this.positionLabel,
    required this.onBack,
    required this.topActions,
    required this.bottomActions,
    this.onSeek,
    this.onPreviousSection,
    this.onNextSection,
    this.onInteraction,
  });

  final bool visible;
  final Color background;
  final Color foreground;
  final Color accent;
  final String title;
  final String subtitle;
  final double progress;
  final String progressLabel;
  final String positionLabel;
  final VoidCallback onBack;
  final List<Widget> topActions;
  final List<Widget> bottomActions;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onPreviousSection;
  final VoidCallback? onNextSection;
  final VoidCallback? onInteraction;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.scaled(context, Motion.medium);
    final surface = Color.lerp(background, foreground, 0.04)!;
    final iconTheme = IconThemeData(color: foreground.withValues(alpha: 0.85));
    final textStyle = TextStyle(fontFamily: Fonts.ui, color: foreground);
    final decoration = BoxDecoration(
      color: surface,
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16)],
    );

    return IgnorePointer(
      ignoring: !visible,
      child: Listener(
        onPointerDown: (_) => onInteraction?.call(),
        behavior: HitTestBehavior.translucent,
        child: IconTheme(
          data: iconTheme,
          child: DefaultTextStyle(
            style: textStyle,
            child: Column(
              children: [
                AnimatedSlide(
                  offset: visible ? Offset.zero : const Offset(0, -1),
                  duration: duration,
                  curve: Motion.curve,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: duration,
                    child: Container(
                      decoration: decoration,
                      child: SafeArea(
                        bottom: false,
                        child: SizedBox(
                          height: 56,
                          child: Row(
                            children: [
                              IconButton(tooltip: 'Retour', icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: textStyle.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
                                    if (subtitle.isNotEmpty)
                                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: textStyle.copyWith(fontSize: 12, color: foreground.withValues(alpha: 0.6))),
                                  ],
                                ),
                              ),
                              ...topActions,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedSlide(
                  offset: visible ? Offset.zero : const Offset(0, 1),
                  duration: duration,
                  curve: Motion.curve,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: duration,
                    child: Container(
                      decoration: decoration,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    Text(positionLabel, style: textStyle.copyWith(fontSize: 12, color: foreground.withValues(alpha: 0.65))),
                                    const Spacer(),
                                    Text(progressLabel, style: textStyle.copyWith(fontSize: 12, color: foreground.withValues(alpha: 0.65))),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  if (onPreviousSection != null)
                                    IconButton(tooltip: 'Section précédente', icon: const Icon(Icons.skip_previous_rounded), onPressed: onPreviousSection),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor: accent,
                                        thumbColor: accent,
                                        inactiveTrackColor: foreground.withValues(alpha: 0.15),
                                      ),
                                      child: _SeekSlider(value: progress, onSeek: onSeek),
                                    ),
                                  ),
                                  if (onNextSection != null)
                                    IconButton(tooltip: 'Section suivante', icon: const Icon(Icons.skip_next_rounded), onPressed: onNextSection),
                                ],
                              ),
                              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: bottomActions),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Curseur de progression : la valeur suit le doigt, le saut a lieu au relâchement.
class _SeekSlider extends StatefulWidget {
  const _SeekSlider({required this.value, required this.onSeek});
  final double value;
  final ValueChanged<double>? onSeek;

  @override
  State<_SeekSlider> createState() => _SeekSliderState();
}

class _SeekSliderState extends State<_SeekSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final v = (_dragging ?? widget.value).clamp(0.0, 1.0);
    return Slider(
      value: v,
      label: '${(v * 100).round()} %',
      divisions: widget.onSeek == null ? null : 1000,
      onChanged: widget.onSeek == null ? null : (x) => setState(() => _dragging = x),
      onChangeEnd: widget.onSeek == null
          ? null
          : (x) {
              setState(() => _dragging = null);
              widget.onSeek!(x);
            },
    );
  }
}
