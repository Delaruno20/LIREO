import 'package:material_ui/material_ui.dart';

/// Espacements, rayons et durées partagés par tout le design system.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Marge latérale des écrans.
  static const gutter = 20.0;
}

abstract final class Radii {
  static const sm = Radius.circular(8);
  static const md = Radius.circular(14);
  static const lg = Radius.circular(22);
  static const pill = Radius.circular(999);

  /// Couverture de livre : dos légèrement arrondi, coin droit plus marqué.
  static const cover = BorderRadius.only(
    topLeft: Radius.circular(3),
    bottomLeft: Radius.circular(3),
    topRight: Radius.circular(8),
    bottomRight: Radius.circular(8),
  );
}

/// Durées d'animation. Toutes passent par [Motion.of] pour respecter
/// le réglage « animations désactivées ».
abstract final class Motion {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 450);
  static const curve = Curves.easeOutCubic;
  static const emphasized = Cubic(0.2, 0.0, 0, 1.0);

  static Duration scaled(BuildContext context, Duration d) {
    final enabled = MotionScope.enabledOf(context);
    return enabled ? d : Duration.zero;
  }
}

/// Propage le réglage global d'animations (et le réglage système
/// « réduire les animations ») dans l'arbre de widgets.
class MotionScope extends InheritedWidget {
  const MotionScope({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool enabledOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MotionScope>();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return (scope?.enabled ?? true) && !reduce;
  }

  @override
  bool updateShouldNotify(MotionScope oldWidget) => enabled != oldWidget.enabled;
}

abstract final class Fonts {
  static const ui = 'Inter';
  static const display = 'Lora';

  /// Polices de lecture embarquées (fonctionnent hors ligne).
  static const reading = <String, String>{
    'Literata': 'Literata',
    'Lora': 'Lora',
    'Merriweather': 'Merriweather',
    'Atkinson': 'Atkinson Hyperlegible',
    'Inter': 'Inter (sans-serif)',
  };
}
