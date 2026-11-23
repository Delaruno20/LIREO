import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../model/reader_prefs.dart';
import 'page_curl.dart';

enum _Phase { idle, dragging, animating }

/// Affiche la page courante et anime le passage aux pages voisines
/// (curl, glissement, fondu ou sans animation), au doigt ou par commande.
class PageTurner extends StatefulWidget {
  const PageTurner({
    super.key,
    required this.animation,
    required this.speed,
    required this.curlShadow,
    required this.background,
    required this.pictureAt,
    required this.onCommit,
    required this.overlay,
    this.onTapUp,
    this.onLongPressStart,
    this.onLongPressMove,
    this.onLongPressEnd,
    this.onVerticalDrag,
    this.onPinch,
    this.onPinchEnd,
  });

  final PageAnimation animation;
  final double speed;
  final double curlShadow;
  final Color background;

  /// Image de la page à [delta] de la page courante (0 = courante), ou null
  /// si elle n'existe pas ou n'est pas encore prête.
  final ui.Picture? Function(int delta) pictureAt;

  /// Valide le changement de page. Retourne false si impossible.
  final Future<bool> Function(int delta) onCommit;
  final Widget overlay;
  final void Function(TapUpDetails details, Size size)? onTapUp;
  final void Function(Offset position)? onLongPressStart;
  final void Function(Offset position)? onLongPressMove;
  final VoidCallback? onLongPressEnd;

  /// Glissement vertical (fraction de la hauteur, négatif vers le haut).
  final void Function(double delta)? onVerticalDrag;
  final void Function(double scale)? onPinch;
  final VoidCallback? onPinchEnd;

  @override
  State<PageTurner> createState() => PageTurnerState();
}

class PageTurnerState extends State<PageTurner> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this)..addListener(() => setState(() {}));
  _Phase _phase = _Phase.idle;
  int _dir = 0;
  Size _size = Size.zero;

  // Suivi du geste.
  Offset _start = Offset.zero;
  Offset _last = Offset.zero;
  Axis? _axis;
  bool _pinching = false;

  // Curl : point tiré et coin d'origine ; slide : décalage horizontal.
  Offset _corner = Offset.zero;
  Offset _drag = Offset.zero;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  bool _tapArc = false;

  PageAnimation get _mode => widget.animation == PageAnimation.scroll ? PageAnimation.slide : widget.animation;

  Duration _duration(double fraction) {
    final base = switch (_mode) {
      PageAnimation.curl => 520,
      PageAnimation.slide => 320,
      PageAnimation.fade => 260,
      _ => 0,
    };
    return Duration(milliseconds: (base * fraction.clamp(0.25, 1.0) / widget.speed.clamp(0.4, 3.0)).round());
  }

  bool get busy => _phase != _Phase.idle;

  /// Tourne la page par programme (zones de tap, touches, TTS).
  Future<void> turn(int delta) async {
    if (busy) return;
    if (widget.pictureAt(delta) == null || _mode == PageAnimation.none || !MotionScope.enabledOf(context)) {
      await widget.onCommit(delta);
      return;
    }
    _dir = delta;
    _corner = Offset(_size.width, _size.height);
    if (_mode == PageAnimation.curl) {
      final flat = delta > 0 ? _corner : Offset(-_size.width, _size.height);
      final turned = delta > 0 ? Offset(-_size.width, _size.height) : _corner;
      _from = flat;
      _to = turned;
      _tapArc = true;
    } else {
      _from = Offset.zero;
      _to = Offset(-delta * _size.width, 0);
    }
    _drag = _from;
    await _run(complete: true, fraction: 1);
  }

  Future<void> _run({required bool complete, required double fraction}) async {
    _phase = _Phase.animating;
    _anim.duration = _duration(fraction);
    final curve = _mode == PageAnimation.curl ? Curves.easeInOutCubic : Curves.easeOutCubic;
    _anim.value = 0;
    await _anim.animateTo(1, curve: curve);
    if (!mounted) return;
    if (complete) {
      final ok = await widget.onCommit(_dir);
      if (!ok) {
        _reset();
        return;
      }
    }
    _reset();
  }

  void _reset() {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _dir = 0;
      _tapArc = false;
      _anim.value = 0;
    });
  }

  // ------------------------------------------------------------- gestes

  void _onScaleStart(ScaleStartDetails d) {
    if (busy) return;
    _pinching = d.pointerCount > 1;
    _start = d.localFocalPoint;
    _last = _start;
    _axis = null;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_pinching || d.pointerCount > 1) {
      _pinching = true;
      widget.onPinch?.call(d.scale);
      return;
    }
    if (_phase == _Phase.animating) return;
    final pos = d.localFocalPoint;
    final total = pos - _start;
    if (_axis == null) {
      if (total.distance < 10) return;
      _axis = total.dx.abs() > total.dy.abs() ? Axis.horizontal : Axis.vertical;
      if (_axis == Axis.horizontal) {
        final dir = total.dx < 0 ? 1 : -1;
        if (widget.pictureAt(dir) == null) {
          _axis = Axis.vertical; // rien de ce côté : on ignore le geste
          return;
        }
        _dir = dir;
        _phase = _Phase.dragging;
        _corner = Offset(_size.width, _start.dy < _size.height / 2 ? 0 : _size.height);
      }
    }
    if (_axis == Axis.vertical) {
      widget.onVerticalDrag?.call((pos.dy - _last.dy) / math.max(1, _size.height));
      _last = pos;
      return;
    }
    _last = pos;
    if (_mode == PageAnimation.none || _mode == PageAnimation.fade) return;
    setState(() => _drag = _dragPoint(pos));
  }

  Offset _dragPoint(Offset finger) {
    final dx = finger.dx - _start.dx;
    if (_mode == PageAnimation.curl) {
      final baseX = _dir > 0 ? _size.width : -_size.width;
      var p = Offset(baseX + dx * 2, _corner.dy + (finger.dy - _start.dy) * 0.6);
      // Empêche le coin de « décoller » la page du dos.
      final spine = Offset(0, _corner.dy);
      final v = p - spine;
      if (v.distance > _size.width) p = spine + v / v.distance * _size.width;
      return Offset(math.min(p.dx, _size.width), p.dy);
    }
    return Offset(_dir > 0 ? dx.clamp(-_size.width, 0) : dx.clamp(0, _size.width), 0);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_pinching) {
      _pinching = false;
      widget.onPinchEnd?.call();
      return;
    }
    if (_phase != _Phase.dragging) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    if (_mode == PageAnimation.none || _mode == PageAnimation.fade) {
      turnAfterGesture();
      return;
    }
    final double progress;
    if (_mode == PageAnimation.curl) {
      progress = _dir > 0 ? (_size.width - _drag.dx) / (2 * _size.width) : (_drag.dx + _size.width) / (2 * _size.width);
    } else {
      progress = _drag.dx.abs() / _size.width;
    }
    final flick = _dir > 0 ? vx < -350 : vx > 350;
    final back = _dir > 0 ? vx > 350 : vx < -350;
    // Au-delà de la moitié, la page tourne toujours ; sinon la vitesse décide.
    final complete = progress > 0.5 || (!back && (flick || progress > 0.33));
    _from = _drag;
    if (_mode == PageAnimation.curl) {
      final turned = Offset(-_size.width, _corner.dy);
      final flat = _corner;
      _to = complete == (_dir > 0) ? turned : flat;
    } else {
      _to = complete ? Offset(-_dir * _size.width, 0) : Offset.zero;
    }
    _run(complete: complete, fraction: complete ? 1 - progress : progress);
  }

  void turnAfterGesture() {
    final dir = _dir;
    _phase = _Phase.idle;
    _dir = 0;
    turn(dir);
  }

  // ------------------------------------------------------------- rendu

  Offset get _point {
    if (_phase != _Phase.animating) return _drag;
    final t = _anim.value;
    var p = Offset.lerp(_from, _to, t)!;
    if (_tapArc && _mode == PageAnimation.curl) {
      p = p.translate(0, -math.sin(math.pi * t) * _size.height * 0.12);
    }
    return p;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _size = constraints.biggest;
      final current = widget.pictureAt(0);
      Widget content;
      if (current == null) {
        content = ColoredBox(color: widget.background, child: const Center(child: CircularProgressIndicator()));
      } else if (_phase == _Phase.idle || _dir == 0) {
        content = Stack(
          fit: StackFit.expand,
          children: [CustomPaint(painter: _PicturePainter(current)), widget.overlay],
        );
      } else {
        content = _transition(current);
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => widget.onTapUp?.call(d, _size),
        onLongPressStart: widget.onLongPressStart == null ? null : (d) => widget.onLongPressStart!(d.localPosition),
        onLongPressMoveUpdate: widget.onLongPressMove == null ? null : (d) => widget.onLongPressMove!(d.localPosition),
        onLongPressEnd: widget.onLongPressEnd == null ? null : (_) => widget.onLongPressEnd!(),
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: RepaintBoundary(child: content),
      );
    });
  }

  Widget _transition(ui.Picture current) {
    final neighbour = widget.pictureAt(_dir);
    switch (_mode) {
      case PageAnimation.curl:
        // Avant : la page courante se soulève. Arrière : la précédente se repose.
        final top = _dir > 0 ? current : (neighbour ?? current);
        final under = _dir > 0 ? neighbour : current;
        return CustomPaint(
          size: _size,
          painter: PageCurlPainter(
            top: top,
            under: under,
            corner: _corner == Offset.zero ? Offset(_size.width, _size.height) : _corner,
            drag: _point,
            background: widget.background,
            shadowIntensity: widget.curlShadow,
          ),
        );
      case PageAnimation.fade:
        final t = _phase == _Phase.animating ? _anim.value : 0.0;
        return Stack(fit: StackFit.expand, children: [
          CustomPaint(painter: _PicturePainter(current)),
          if (neighbour != null) Opacity(opacity: t, child: CustomPaint(painter: _PicturePainter(neighbour))),
        ]);
      default:
        final dx = _point.dx;
        return ClipRect(
          child: Stack(fit: StackFit.expand, children: [
            if (neighbour != null)
              Transform.translate(
                offset: Offset(dx + _dir * _size.width, 0),
                child: CustomPaint(painter: _PicturePainter(neighbour)),
              ),
            Transform.translate(
              offset: Offset(dx, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18)]),
                child: CustomPaint(painter: _PicturePainter(current)),
              ),
            ),
          ]),
        );
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }
}

class _PicturePainter extends CustomPainter {
  _PicturePainter(this.picture);
  final ui.Picture picture;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPicture(picture);

  @override
  bool shouldRepaint(_PicturePainter old) => old.picture != picture;
}
