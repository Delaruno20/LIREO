import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../design/seasonal.dart';
import '../design/tokens.dart';

/// Bannière d'accueil du thème événementiel : titre, message et décor
/// dessiné en code (aucune image embarquée).
class SeasonalBanner extends StatelessWidget {
  const SeasonalBanner({super.key, required this.event});

  final SeasonalEvent event;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${event.title}. ${event.message}',
      excludeSemantics: true,
      child: Container(
        height: 150,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radii.lg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: event.bannerGradient,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: SeasonalDecorPainter(event))),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, 110, Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    style: TextStyle(
                      fontFamily: Fonts.display,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      fontSize: 30,
                      height: 1.05,
                      color: event.bannerTitle,
                      shadows: [Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    '${event.message} ${event.emoji}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: Fonts.ui, fontSize: 13, height: 1.3, color: event.bannerText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Décor propre à chaque événement, placé surtout à droite de la bannière
/// pour laisser le texte lisible.
class SeasonalDecorPainter extends CustomPainter {
  SeasonalDecorPainter(this.event);

  final SeasonalEvent event;

  @override
  void paint(Canvas canvas, Size size) {
    switch (event) {
      case SeasonalEvent.newYear:
        _fireworks(canvas, size);
      case SeasonalEvent.christmas:
        _christmas(canvas, size);
      case SeasonalEvent.easter:
        _easter(canvas, size);
      case SeasonalEvent.fetMusique:
        _music(canvas, size);
      case SeasonalEvent.cameroonYouth:
        _cameroon(canvas, size);
    }
  }

  // Positions pseudo-aléatoires mais stables d'un rendu à l'autre.
  static final _rng = math.Random(7);
  static final _points = List.generate(40, (_) => Offset(_rng.nextDouble(), _rng.nextDouble()));

  void _sparkles(Canvas canvas, Size size, Color color, {int count = 26, double maxR = 1.8}) {
    final paint = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final o = _points[i];
      canvas.drawCircle(Offset(o.dx * size.width, o.dy * size.height), 0.6 + maxR * ((i * 37 % 10) / 10), paint);
    }
  }

  void _burst(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * r * 0.3, c + dir * r, paint);
      canvas.drawCircle(c + dir * (r + 4), 1.4, paint);
    }
  }

  void _fireworks(Canvas canvas, Size size) {
    _sparkles(canvas, size, const Color(0x66F3D38A));
    final w = size.width;
    _burst(canvas, Offset(w - 60, 46), 34, const Color(0xFFF3D38A));
    _burst(canvas, Offset(w - 96, 22), 12, const Color(0xCCE2B55C));
    _burst(canvas, Offset(w - 24, 118), 16, const Color(0x99FFF1C8));
    // Livre ouvert doré au pied des feux d'artifice.
    final book = Paint()..color = const Color(0xFFE2B55C);
    final base = Offset(w - 70, size.height - 14);
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - 34, base.dy)
        ..quadraticBezierTo(base.dx - 17, base.dy - 12, base.dx, base.dy - 4)
        ..quadraticBezierTo(base.dx + 17, base.dy - 12, base.dx + 34, base.dy)
        ..lineTo(base.dx, base.dy + 4)
        ..close(),
      book,
    );
  }

  void _snowflake(Canvas canvas, Offset c, double r, Paint paint) {
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      final tip = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawLine(c, tip, paint);
    }
  }

  void _christmas(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final snow = Paint()..color = const Color(0xCCFFFFFF);
    for (var i = 0; i < 30; i++) {
      final o = _points[i];
      canvas.drawCircle(Offset(o.dx * w, o.dy * h), 0.8 + (i % 3) * 0.7, snow);
    }
    final flake = Paint()
      ..color = const Color(0xAAFFFFFF)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    _snowflake(canvas, Offset(w - 30, 28), 9, flake);
    _snowflake(canvas, Offset(w * 0.55, 20), 6, flake);
    // Sapin
    final tree = Paint()..color = const Color(0xFF1F5A35);
    final tx = w - 70;
    for (var i = 0; i < 3; i++) {
      final top = 34.0 + i * 22;
      final half = 18.0 + i * 9;
      canvas.drawPath(
        Path()
          ..moveTo(tx, top)
          ..lineTo(tx - half, top + 34)
          ..lineTo(tx + half, top + 34)
          ..close(),
        tree,
      );
    }
    _star(canvas, Offset(tx, 30), 8, const Color(0xFFF0C87A));
    final ball = Paint()..color = const Color(0xFFD02A38);
    for (final o in const [Offset(-10, 62), Offset(12, 82), Offset(-18, 102), Offset(20, 108), Offset(2, 96)]) {
      canvas.drawCircle(Offset(tx, 0) + o, 3, ball);
    }
    // Colline enneigée
    canvas.drawPath(
      Path()
        ..moveTo(0, h)
        ..lineTo(0, h - 10)
        ..quadraticBezierTo(w * 0.5, h - 30, w, h - 12)
        ..lineTo(w, h)
        ..close(),
      Paint()..color = const Color(0xE6F4F1EA),
    );
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  void _flower(Canvas canvas, Offset c, double r, Color petal) {
    final paint = Paint()..color = petal;
    for (var i = 0; i < 5; i++) {
      final a = i * 2 * math.pi / 5;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * 0.6, r * 0.5, paint);
    }
    canvas.drawCircle(c, r * 0.32, Paint()..color = const Color(0xFFF2C14E));
  }

  void _egg(Canvas canvas, Offset c, double r, Color color, Color stripe) {
    final rect = Rect.fromCenter(center: c, width: r * 1.5, height: r * 2);
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    canvas.drawOval(rect, Paint()..color = color);
    final s = Paint()..color = stripe;
    canvas.drawRect(Rect.fromLTWH(rect.left, c.dy - r * 0.35, rect.width, r * 0.22), s);
    canvas.drawRect(Rect.fromLTWH(rect.left, c.dy + r * 0.25, rect.width, r * 0.18), s);
    canvas.restore();
  }

  void _easter(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Herbe
    canvas.drawPath(
      Path()
        ..moveTo(0, h)
        ..lineTo(0, h - 12)
        ..quadraticBezierTo(w * 0.5, h - 26, w, h - 14)
        ..lineTo(w, h)
        ..close(),
      Paint()..color = const Color(0xFFB9D98A),
    );
    _egg(canvas, Offset(w - 82, h - 32), 18, const Color(0xFFB98BE0), const Color(0xFFFFE08A));
    _egg(canvas, Offset(w - 46, h - 28), 15, const Color(0xFFFF9EB8), const Color(0xFF9ED8F0));
    _egg(canvas, Offset(w - 114, h - 24), 12, const Color(0xFF9ED8F0), const Color(0xFFFFFFFF));
    _flower(canvas, Offset(w - 30, 30), 14, const Color(0xFFFFB7CF));
    _flower(canvas, Offset(w - 78, 22), 10, const Color(0xFFE3C6F5));
    _flower(canvas, Offset(w - 120, 52), 8, const Color(0xFFFFD1E1));
    _flower(canvas, Offset(w * 0.5, 14), 6, const Color(0xFFFFD1E1));
  }

  void _note(Canvas canvas, Offset c, double r, Color color, {bool double = false}) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = r * 0.28
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(Rect.fromCenter(center: c, width: r * 1.4, height: r), paint);
    final stemTop = c + Offset(r * 0.62, -r * 3);
    canvas.drawLine(c + Offset(r * 0.62, 0), stemTop, paint);
    if (double) {
      final c2 = c + Offset(r * 2.4, -r * 0.5);
      canvas.drawOval(Rect.fromCenter(center: c2, width: r * 1.4, height: r), paint);
      canvas.drawLine(c2 + Offset(r * 0.62, 0), stemTop + Offset(r * 2.4, -r * 0.5), paint);
      canvas.drawLine(stemTop, stemTop + Offset(r * 2.4, -r * 0.5), paint..strokeWidth = r * 0.5);
    } else {
      canvas.drawLine(stemTop, stemTop + Offset(r * 0.8, r * 0.9), paint);
    }
  }

  void _music(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    _sparkles(canvas, size, const Color(0x55FFD08A), count: 22);
    // Faisceaux de scène
    final beam = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color(0x55FFB067), Color(0x00FFB067)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    for (final x in [w - 40, w - 110]) {
      canvas.drawPath(
        Path()
          ..moveTo(x - 6, h)
          ..lineTo(x - 40, 0)
          ..lineTo(x + 40, 0)
          ..lineTo(x + 6, h)
          ..close(),
        beam,
      );
    }
    _note(canvas, Offset(w - 90, 70), 12, const Color(0xFFFFD08A), double: true);
    _note(canvas, Offset(w - 34, 50), 9, const Color(0xFFFFB067));
    _note(canvas, Offset(w - 60, 122), 8, const Color(0xCCE06AAE));
    _note(canvas, Offset(w * 0.6, 30), 6, const Color(0x99FFD08A));
  }

  void _cameroon(Canvas canvas, Size size) {
    final w = size.width;
    // Guirlande de fanions aux couleurs du drapeau
    const colors = [Color(0xFF007A5E), Color(0xFFCE1126), Color(0xFFFCD116)];
    final rope = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..moveTo(0, 6)..quadraticBezierTo(w / 2, 22, w, 6), rope);
    for (var i = 0; i < 14; i++) {
      final x = (i + 0.5) * w / 14;
      final t = x / w;
      final y = 6 + 16 * 4 * t * (1 - t) / 2 + 2;
      canvas.drawPath(
        Path()
          ..moveTo(x - 7, y)
          ..lineTo(x + 7, y)
          ..lineTo(x, y + 14)
          ..close(),
        Paint()..color = colors[i % 3],
      );
    }
    // Drapeau camerounais
    final flag = Rect.fromLTWH(w - 104, 40, 78, 52);
    final third = flag.width / 3;
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(flag.left + i * third, flag.top, third + 0.5, flag.height), Paint()..color = colors[i]);
    }
    _star(canvas, flag.center, 9, const Color(0xFFFCD116));
    canvas.drawLine(
      flag.topLeft,
      flag.bottomLeft + const Offset(0, 46),
      Paint()
        ..color = const Color(0xFF5A3A1A)
        ..strokeWidth = 3,
    );
    _star(canvas, Offset(w - 20, 120), 6, const Color(0xCCFCD116));
    _star(canvas, Offset(w - 130, 118), 5, const Color(0x99FCD116));
  }

  @override
  bool shouldRepaint(SeasonalDecorPainter old) => old.event != event;
}
