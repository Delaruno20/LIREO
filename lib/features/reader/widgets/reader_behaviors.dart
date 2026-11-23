import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../../core/design/tokens.dart';
import '../model/reader_prefs.dart';

/// Comportements partagés par tous les lecteurs : barres auto-masquées,
/// luminosité au glissement, touches physiques, minuteur de lecture.
mixin ReaderBehaviors<T extends StatefulWidget> on State<T> {
  bool chromeVisible = false;
  Timer? _chromeTimer;
  double? _brightness;
  String? hudText;
  Timer? _hudTimer;
  Timer? sleepTimer;
  DateTime? sleepAt;

  static const chromeDuration = Duration(seconds: 5);

  void showChrome([bool show = true]) {
    _chromeTimer?.cancel();
    setState(() => chromeVisible = show);
    if (show) _chromeTimer = Timer(chromeDuration, () => mounted ? setState(() => chromeVisible = false) : null);
  }

  void keepChrome() {
    if (!chromeVisible) return;
    _chromeTimer?.cancel();
    _chromeTimer = Timer(chromeDuration, () => mounted ? setState(() => chromeVisible = false) : null);
  }

  void toggleChrome() => showChrome(!chromeVisible);

  void showHud(String text) {
    _hudTimer?.cancel();
    setState(() => hudText = text);
    _hudTimer = Timer(const Duration(milliseconds: 900), () => mounted ? setState(() => hudText = null) : null);
  }

  /// Glissement vertical : delta en fraction de hauteur (négatif = vers le haut).
  Future<void> adjustBrightness(double delta) async {
    try {
      _brightness ??= await ScreenBrightness.instance.application;
      _brightness = (_brightness! - delta * 1.2).clamp(0.02, 1.0);
      await ScreenBrightness.instance.setApplicationScreenBrightness(_brightness!);
      showHud('Luminosité ${(_brightness! * 100).round()} %');
    } catch (_) {
      showHud('Luminosité non réglable ici');
    }
  }

  Future<void> resetBrightness() async {
    if (_brightness == null) return;
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
  }

  /// Touches : flèches, Page suiv./préc., espace, volume, boutons média.
  KeyEventResult handleKey(KeyEvent event, ReaderPrefs prefs, void Function(int delta) turn) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final volume = {LogicalKeyboardKey.audioVolumeDown: 1, LogicalKeyboardKey.audioVolumeUp: -1};
    if (volume.containsKey(k)) {
      if (!prefs.volumeKeys) return KeyEventResult.ignored;
      turn(volume[k]!);
      return KeyEventResult.handled;
    }
    final next = {
      LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.pageDown, LogicalKeyboardKey.space,
      LogicalKeyboardKey.mediaTrackNext, LogicalKeyboardKey.mediaFastForward,
    };
    final previous = {
      LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.mediaTrackPrevious, LogicalKeyboardKey.mediaRewind,
    };
    if (next.contains(k)) {
      turn(1);
      return KeyEventResult.handled;
    }
    if (previous.contains(k)) {
      turn(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Minuteur : arrête la lecture (TTS, défilement) au bout de [minutes].
  Future<void> chooseSleepTimer(VoidCallback onElapsed) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Align(alignment: Alignment.centerLeft, child: Text('Minuteur de lecture', style: Theme.of(ctx).textTheme.headlineSmall)),
            ),
            for (final m in [10, 20, 30, 45, 60, 90])
              ListTile(title: Text('$m minutes'), onTap: () => Navigator.pop(ctx, m)),
            if (sleepTimer != null)
              ListTile(leading: const Icon(Icons.timer_off_outlined), title: const Text('Désactiver le minuteur'), onTap: () => Navigator.pop(ctx, 0)),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    sleepTimer?.cancel();
    if (choice == 0) {
      setState(() {
        sleepTimer = null;
        sleepAt = null;
      });
      return;
    }
    setState(() => sleepAt = DateTime.now().add(Duration(minutes: choice)));
    sleepTimer = Timer(Duration(minutes: choice), () {
      if (!mounted) return;
      setState(() {
        sleepTimer = null;
        sleepAt = null;
      });
      onElapsed();
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Minuteur écoulé'),
          content: Text('Vous avez lu $choice minutes. Il est peut-être temps de faire une pause.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('D\'accord'))],
        ),
      );
    });
  }

  Widget buildHud(Color background, Color foreground) {
    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: hudText == null ? 0 : 1,
          duration: const Duration(milliseconds: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: foreground.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(20)),
            child: Text(hudText ?? '', style: TextStyle(fontFamily: Fonts.ui, color: background, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  void disposeBehaviors() {
    _chromeTimer?.cancel();
    _hudTimer?.cancel();
    sleepTimer?.cancel();
    resetBrightness();
  }
}
