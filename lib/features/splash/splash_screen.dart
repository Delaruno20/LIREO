import 'package:material_ui/material_ui.dart';

import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';

/// Écran affiché pendant l'ouverture de la base et le chargement des services.
class SplashApp extends StatelessWidget {
  const SplashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, home: SplashScreen());
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const p = LireoPalette.warmLibrary;
    return Scaffold(
      backgroundColor: p.background,
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Motion.curve,
          builder: (context, v, child) => Opacity(
            opacity: v,
            child: Transform.scale(scale: 0.94 + 0.06 * v, child: child),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LireoMark(size: 72, color: Color(0xFFA0683A)),
              SizedBox(height: 18),
              Text(
                'Lireo',
                style: TextStyle(fontFamily: Fonts.display, fontSize: 38, fontWeight: FontWeight.w600, color: Color(0xFF2E1F14)),
              ),
              SizedBox(height: 6),
              Text(
                'Plongez dans vos histoires',
                style: TextStyle(fontFamily: Fonts.ui, fontSize: 14, color: Color(0xFF7D6A58), letterSpacing: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logo LIREO : un livre ouvert stylisé, dessiné en vectoriel.
class LireoMark extends StatelessWidget {
  const LireoMark({super.key, this.size = 32, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? LireoPalette.of(context).primary;
    return CustomPaint(size: Size(size, size * 0.78), painter: _MarkPainter(c));
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final fill = Paint()..color = color;
    final light = Paint()..color = color.withValues(alpha: 0.55);
    final line = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;

    // Pages gauche et droite, légèrement incurvées.
    final left = Path()
      ..moveTo(w * 0.5, h * 0.2)
      ..quadraticBezierTo(w * 0.3, h * 0.04, w * 0.04, h * 0.1)
      ..lineTo(w * 0.04, h * 0.86)
      ..quadraticBezierTo(w * 0.3, h * 0.8, w * 0.5, h * 0.96)
      ..close();
    final right = Path()
      ..moveTo(w * 0.5, h * 0.2)
      ..quadraticBezierTo(w * 0.7, h * 0.04, w * 0.96, h * 0.1)
      ..lineTo(w * 0.96, h * 0.86)
      ..quadraticBezierTo(w * 0.7, h * 0.8, w * 0.5, h * 0.96)
      ..close();
    canvas.drawPath(left, light);
    canvas.drawPath(right, fill);
    // Lignes de texte sur la page gauche.
    for (var i = 0; i < 3; i++) {
      final y = h * (0.34 + i * 0.16);
      canvas.drawLine(Offset(w * 0.14, y), Offset(w * 0.38, y + h * 0.02), line);
    }
    // Signet doré.
    final ribbon = Path()
      ..moveTo(w * 0.7, h * 0.12)
      ..lineTo(w * 0.8, h * 0.1)
      ..lineTo(w * 0.8, h * 0.46)
      ..lineTo(w * 0.75, h * 0.4)
      ..lineTo(w * 0.7, h * 0.46)
      ..close();
    canvas.drawPath(ribbon, Paint()..color = const Color(0xFFE9C987));
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}
