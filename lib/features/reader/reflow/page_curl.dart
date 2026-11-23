import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Rendu d'une page en cours de retournement.
///
/// Modèle : le coin [corner] de la page est tiré jusqu'au point [drag].
/// La ligne de pliure est la médiatrice du segment coin→point. La partie de
/// la page au-delà de la pliure est retournée (réflexion) et montre le verso.
class PageCurlPainter extends CustomPainter {
  PageCurlPainter({
    required this.top,
    required this.under,
    required this.corner,
    required this.drag,
    required this.background,
    this.shadowIntensity = 0.6,
  });

  /// Page qui se retourne.
  final ui.Picture top;

  /// Page révélée en dessous.
  final ui.Picture? under;
  final Offset corner;
  final Offset drag;
  final Color background;
  final double shadowIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    final page = Offset.zero & size;
    canvas.clipRect(page);
    final toCorner = corner - drag;
    final dist = toCorner.distance;

    if (under != null) {
      canvas.drawPicture(under!);
    } else {
      canvas.drawRect(page, Paint()..color = background);
    }
    if (dist < 0.5) {
      canvas.drawPicture(top);
      return;
    }

    final n = toCorner / dist; // normale de la pliure, vers le coin
    final m = (corner + drag) / 2; // point sur la pliure
    double side(Offset p) => (p.dx - m.dx) * n.dx + (p.dy - m.dy) * n.dy;

    final rect = [page.topLeft, page.topRight, page.bottomRight, page.bottomLeft];
    final kept = _clip(rect, side, keepPositive: false);
    final folded = _clip(rect, side, keepPositive: true);
    if (kept.isEmpty) {
      return; // page entièrement retournée
    }

    final keptPath = Path()..addPolygon(kept, true);
    final strength = shadowIntensity.clamp(0.0, 1.0);
    final foldDir = Offset(-n.dy, n.dx);
    final reach = math.min(dist * 0.5, size.width * 0.25);

    // 1. Ombre portée sur la page révélée, le long de la pliure.
    if (under != null && folded.isNotEmpty) {
      final shadowWidth = 8 + reach * 0.5;
      canvas.save();
      canvas.clipPath(Path()..addPolygon(folded, true));
      canvas.drawRect(
        page,
        Paint()
          ..shader = ui.Gradient.linear(
            m,
            m + n * shadowWidth,
            [Colors.black.withValues(alpha: 0.45 * strength), Colors.black.withValues(alpha: 0)],
          ),
      );
      canvas.restore();
    }

    // 2. Partie restée à plat de la page courante.
    canvas.save();
    canvas.clipPath(keptPath);
    canvas.drawPicture(top);
    canvas.restore();

    if (folded.isEmpty) return;

    // 3. Verso : réflexion de la partie repliée par rapport à la pliure.
    final reflected = [for (final p in folded) p - n * (2 * side(p))];
    final flapPath = Path()..addPolygon(reflected, true);

    // Ombre du rabat sur la page.
    canvas.drawPath(
      flapPath.shift(n * -3),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28 * strength)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 6 * strength),
    );

    canvas.save();
    canvas.clipPath(flapPath);
    // Fond du verso, légèrement plus sombre que le recto.
    final back = Color.lerp(background, background.computeLuminance() > 0.4 ? const Color(0xFF8A7F70) : Colors.white, 0.12)!;
    canvas.drawRect(page, Paint()..color = back);
    // Texte du recto vu par transparence (en miroir).
    final k = 2 * (m.dx * n.dx + m.dy * n.dy);
    final matrix = Float64List.fromList([
      1 - 2 * n.dx * n.dx, -2 * n.dx * n.dy, 0, 0, //
      -2 * n.dx * n.dy, 1 - 2 * n.dy * n.dy, 0, 0, //
      0, 0, 1, 0, //
      k * n.dx, k * n.dy, 0, 1,
    ]);
    canvas.saveLayer(page, Paint()..color = Colors.white.withValues(alpha: 0.13));
    canvas.transform(matrix);
    canvas.drawPicture(top);
    canvas.restore();
    // Modelé : la pliure est plus claire, le bord plus ombré.
    final far = reflected.fold<Offset>(m, (a, p) => side(p) < side(a) ? p : a);
    canvas.drawRect(
      page,
      Paint()
        ..shader = ui.Gradient.linear(
          m,
          m + n * side(far),
          [
            Colors.white.withValues(alpha: 0.18 * strength),
            Colors.black.withValues(alpha: 0.02),
            Colors.black.withValues(alpha: 0.16 * strength),
          ],
          [0, 0.35, 1],
        ),
    );
    canvas.restore();

    // Fine arête lumineuse sur la pliure.
    canvas.drawLine(
      m - foldDir * size.longestSide * 2,
      m + foldDir * size.longestSide * 2,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08 * strength)
        ..strokeWidth = 1,
    );
  }

  /// Sutherland–Hodgman : intersection d'un polygone et d'un demi-plan.
  static List<Offset> _clip(List<Offset> poly, double Function(Offset) side, {required bool keepPositive}) {
    bool inside(Offset p) => keepPositive ? side(p) > 0 : side(p) <= 0;
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final ia = inside(a), ib = inside(b);
      if (ia) out.add(a);
      if (ia != ib) {
        final sa = side(a), sb = side(b);
        final t = sa / (sa - sb);
        out.add(Offset.lerp(a, b, t)!);
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(PageCurlPainter old) =>
      old.drag != drag || old.top != top || old.under != under || old.corner != corner || old.background != background;
}
