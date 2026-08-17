// DealsBanner — looping deals banner, ported from the HTML design.
//
// Box: fixed height 176, width fills the parent (design reference 343 x 176).
// Everything inside is authored on a 686 x 352 reference canvas and scaled by
// (width / 686), so the art keeps its proportions at any phone width.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ---------------------------------------------------------------- timing
class _Cues {
  static const intro = 0.0;
  static const bagIn = 0.35;
  static const products = 1.95;
  static const bagOut = 4.35;
  static const calendar = 6.05;
  static const ticks = 6.95;
  static const reset = 10.35;
  static const total = 11.15;
}

typedef _Ease = double Function(double);

double _easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();
double _easeInCubic(double t) => t * t * t;
double _easeOutQuad(double t) => 1 - (1 - t) * (1 - t);
double _easeOutBack(double t) {
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
}

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Value that moves from [from] to [to] between [start] and [start] + [dur].
double _anim(double t, double from, double to, double start, double dur, _Ease ease) {
  if (t <= start) return from;
  if (t >= start + dur) return to;
  return from + (to - from) * ease((t - start) / dur);
}

double _enter(double t, double from, double to, double start, [double dur = 0.7]) =>
    _anim(t, from, to, start, dur, _easeOutCubic);
double _pop(double t, double from, double to, double start, [double dur = 0.6]) =>
    _anim(t, from, to, start, dur, _easeOutBack);
double _exit(double t, double from, double to, double start, [double dur = 0.5]) =>
    _anim(t, from, to, start, dur, _easeInCubic);

// ---------------------------------------------------------------- palette
const _bg0 = Color(0xFF2B0F3F);
const _bg1 = Color(0xFF7A1E37);
const _bg2 = Color(0xFFC0341C);
const _accent = Color(0xFF4BE0A2);

class _Product {
  const _Product(this.asset, this.dx, this.dy, this.size, this.delay, this.rot);
  final String asset;
  final double dx, dy, size, delay, rot;
}

// Positions are on the 686 x 352 reference canvas, relative to the bag anchor.
const _products = <_Product>[
  _Product('assets/icons/sunscreen.svg', -89, -43, 56, 0.00, -12),
  _Product('assets/icons/headphones.svg', -43, -92, 58, 0.18, -8),
  _Product('assets/icons/clock.svg', 26, -66, 40, 0.36, 14),
  _Product('assets/icons/player.svg', 81, -60, 68, 0.54, 6),
];

class DealsBanner extends StatefulWidget {
  const DealsBanner({
    super.key,
    this.height = 176,
    this.badge = '1440 deals live now',
    this.headline = "Deals that don't wait.",
    this.headlineB = 'Lowest\nDeal Prices',
    this.subA = 'Fresh price drops tracked around the clock.',
    this.subB = 'Updated Daily',
    this.borderRadius = 24,
  });

  final double height;
  final String badge, headline, headlineB, subA, subB;
  final double borderRadius;

  @override
  State<DealsBanner> createState() => _DealsBannerState();
}

class _DealsBannerState extends State<DealsBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 11150), // _Cues.total
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final s = w / 686.0; // reference canvas -> real px
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: SizedBox(
          width: w,
          height: widget.height,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _Frame(
              t: _c.value * _Cues.total,
              s: s,
              w: w,
              h: widget.height,
              cfg: widget,
            ),
          ),
        ),
      );
    });
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.t, required this.s, required this.w, required this.h, required this.cfg});
  final double t, s, w, h;
  final DealsBanner cfg;

  @override
  Widget build(BuildContext context) {
    // ---- copy swap (A = scene 1, B = scene 2) --------------------------
    const swapIn = _Cues.calendar - 0.15;
    const swapBack = _Cues.reset - 0.5;

    List<double> phase(double outDelay, double inDelay) {
      final out = _anim(t, 1, 0, swapIn + outDelay, 0.32, _easeInCubic);
      final back = _anim(t, 0, 1, swapBack + 0.34 + outDelay, 0.5, _easeOutCubic);
      final a = _clamp(out + back, 0, 1);
      final inn = _anim(t, 0, 1, swapIn + 0.26 + inDelay, 0.44, _easeOutCubic);
      final outB = _anim(t, 1, 0, swapBack, 0.34, _easeInCubic);
      return [a, _clamp(inn * outB, 0, 1)];
    }

    final hs = phase(0, 0);
    final gs = phase(0, 0.12);
    final s1 = hs[0], s2 = hs[1], g1 = gs[0], g2 = gs[1];

    // ---- badge idle motion --------------------------------------------
    final sweepP = (t % 3.6) / 3.6;
    final sweepX = -40 + sweepP * 180;
    final sweepO = sweepP < 0.45 ? math.sin(sweepP / 0.45 * math.pi) : 0.0;
    final ping = 0.5 - 0.5 * math.cos(t * 2.4);

    // ---- bag ----------------------------------------------------------
    final bagX = _pop(t, 332, 0, _Cues.bagIn, 1.0);
    final bagS = _pop(t, 0.86, 1, _Cues.bagIn + 0.15, 0.8);
    final bagOutS = _exit(t, 1, 0.2, _Cues.bagOut + 0.95, 0.55);
    final bagOutO = _clamp(_exit(t, 1, 0, _Cues.bagOut + 1.05, 0.45), 0, 1);
    final bagBob = math.sin((t - _Cues.bagIn) * 2.1) * 3;
    final flipOpen = _pop(t, 0, 168, _Cues.products - 0.55, 0.6);
    final flipShut = _clamp(_anim(t, 0, 1, _Cues.bagOut + 0.6, 0.45, _easeOutCubic), 0, 1);
    final flip = flipOpen * (1 - flipShut);

    // ---- calendar -----------------------------------------------------
    final calS = _pop(t, 0.4, 1, _Cues.calendar, 0.85);
    final calO = _clamp(_enter(t, 0, 1, _Cues.calendar, 0.4), 0, 1);
    final calOutS = _exit(t, 1, 0.25, swapBack, 0.42);
    final calOutO = _clamp(_exit(t, 1, 0, swapBack + 0.05, 0.34), 0, 1);
    final calFloat = math.sin((t - _Cues.calendar) * 1.7) * 2.7;

    final bagAnchor = Offset(375 + 311 / 2, h / s / 2); // right stage centre

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // background
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_bg0, _bg1, _bg2],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),

        // ---------------------------------------------------------- left column
        Positioned(
          left: 45 * s,
          top: 72 * s,
          width: 343 * s,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: Offset(0, -31 * s),
                child: _Badge(
                  s: s,
                  text: cfg.badge,
                  sweepX: sweepX,
                  sweepO: sweepO.toDouble(),
                  ping: ping,
                ),
              ),
              SizedBox(
                height: 92 * s,
                child: Stack(
                  children: [
                    _ScaleFade(
                      v: s1,
                      from: 0.84,
                      child: Text(cfg.headline, style: _h1(s)),
                    ),
                    _ScaleFade(
                      v: s2,
                      from: 0.84,
                      child: Text(cfg.headlineB, style: _h1(s)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 21 * s),
              SizedBox(
                height: 35 * s,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 8 * s,
                      child: _ScaleFade(
                        v: g1,
                        from: 0.86,
                        child: Text(
                          cfg.subA,
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.80),
                            fontSize: 16 * s,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.16 * s,
                          ),
                        ),
                      ),
                    ),
                    _ScaleFade(
                      v: g2,
                      from: 0.86,
                      child: _GlowTag(s: s, t: t, text: cfg.subB),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ---------------------------------------------------------- bag + products
        Positioned.fill(
          child: Opacity(
            opacity: bagOutO,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < _products.length; i++)
                  _productLayer(i, s, bagAnchor + Offset(bagX, bagBob), bagOutS),
                _bagLayer(s, bagS, flip, bagAnchor + Offset(bagX, bagBob), bagOutS),
              ],
            ),
          ),
        ),

        // ---------------------------------------------------------- calendar
        Positioned(
          left: (375 + 72) * s,
          top: (h / s / 2 - 80 + 21 + calFloat) * s,
          width: 166 * s,
          height: 161 * s,
          child: Opacity(
            opacity: calO * calOutO,
            child: Transform.scale(
              scale: calS * calOutS * 0.88,
              child: _Calendar(s: s, t: t),
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _h1(double s) => TextStyle(
        color: Colors.white,
        fontSize: 44 * s,
        height: 1.03,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.5 * s,
      );

  // one product: pops out of the bag, then drops back in
  Widget _productLayer(int i, double s, Offset anchor, double outS) {
    final p = _products[i];
    final st = _Cues.products + p.delay;
    final px = _pop(t, 0, p.dx, st, 0.7);
    final py = _pop(t, 25, p.dy, st, 0.7);
    final ps = _pop(t, 0, 1, st, 0.7);
    final po = _clamp(_enter(t, 0, 1, st, 0.25), 0, 1);
    final rt = _Cues.bagOut + 0.06 + (3 - i) * 0.12;
    final back = _clamp(_anim(t, 0, 1, rt, 0.5, _easeInCubic), 0, 1);
    final wob = math.sin((t - st) * 2.3 + i) * 2 * (1 - back);

    final fx = px * (1 - back);
    final fy = py + (28 - py) * back;
    final fs = _clamp(ps * (1 - 0.55 * back), 0, 2) * outS;
    final fo = _clamp(po * (1 - back), 0, 1);

    return Positioned(
      left: (anchor.dx + fx * outS - p.size / 2) * s,
      top: (anchor.dy + (fy + wob) * outS - p.size / 2) * s,
      width: p.size * s,
      height: p.size * s,
      child: Opacity(
        opacity: fo,
        child: Transform.rotate(
          angle: p.rot * ps * (1 - back) * math.pi / 180,
          child: Transform.scale(
            scale: fs,
            child: SvgPicture.asset(p.asset, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  // bag: back handle (behind body) / body / front handle (folds forward)
  Widget _bagLayer(double s, double bagS, double flip, Offset anchor, double outS) {
    const box = 139.0; // 260 on the web canvas
    const hinge = 34.0; // 64 on the web canvas
    final size = box * s;
    final scale = bagS * 1.3 * outS;

    Matrix4 hingeFlip() => Matrix4.identity()
      ..setEntry(3, 2, 1 / (330 * s))
      ..rotateX(flip * math.pi / 180);

    return Positioned(
      left: (anchor.dx - box / 2) * s,
      top: (anchor.dy - box / 2 + 25) * s,
      width: size,
      height: size,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scale(scale)
          ..setEntry(3, 2, 1 / (588 * s))
          ..rotateY(-13 * math.pi / 180)
          ..rotateX(6 * math.pi / 180)
          ..rotateZ(-1 * math.pi / 180),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // soft ground shadow
              Positioned(
                left: 6 * s,
                top: 130 * s,
                width: 126 * s,
                height: 20 * s,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.elliptical(63 * s, 10 * s)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.42),
                        blurRadius: 14 * s,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
              // back handle, clipped away as it rotates behind the body
              Positioned.fill(
                child: ClipRect(
                  clipper: _TopInset(math.min(flip * 2.5, 64) / 260 * size),
                  child: Transform(
                    alignment: Alignment(0, (hinge / box) * 2 - 1),
                    transform: hingeFlip(),
                    child: SvgPicture.string(_bagHandleBack, fit: BoxFit.contain),
                  ),
                ),
              ),
              // body (artwork below the rim)
              Positioned.fill(
                child: ClipRect(
                  clipper: _TopInset(hinge * s),
                  child: SvgPicture.asset('assets/icons/shopping-bag.svg', fit: BoxFit.contain),
                ),
              ),
              // front handle: folds forward, nothing drawn above the rim once open
              Positioned.fill(
                child: ClipRect(
                  clipper: _TopInset(math.min(flip / 55, 1) * hinge * s),
                  child: Transform(
                    alignment: Alignment(0, (hinge / box) * 2 - 1),
                    transform: hingeFlip(),
                    child: ClipRect(
                      clipper: _BottomInset((1 - math.min(flip / 22, 1)) * 92 / 139 * size),
                      child: SvgPicture.string(_bagHandleFront, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- helpers
class _ScaleFade extends StatelessWidget {
  const _ScaleFade({required this.v, required this.from, required this.child});
  final double v, from;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: _clamp(v, 0, 1),
        child: Transform.scale(
          scale: from + (1 - from) * _clamp(v, 0, 1),
          alignment: Alignment.centerLeft,
          child: child,
        ),
      );
}

class _TopInset extends CustomClipper<Rect> {
  _TopInset(this.top);
  final double top;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);
  @override
  bool shouldReclip(_TopInset old) => old.top != top;
}

class _BottomInset extends CustomClipper<Rect> {
  _BottomInset(this.bottom);
  final double bottom;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width, size.height - bottom);
  @override
  bool shouldReclip(_BottomInset old) => old.bottom != bottom;
}

// --------------------------------------------------------------- badge
class _Badge extends StatelessWidget {
  const _Badge({required this.s, required this.text, required this.sweepX, required this.sweepO, required this.ping});
  final double s, sweepX, sweepO, ping;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: Colors.white.withOpacity(0.10),
          border: Border.all(color: Colors.white.withOpacity(0.28), width: 1),
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12 * s, 7 * s, 14 * s, 7 * s),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7.5 * s,
                    height: 7.5 * s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _accent.withOpacity(0.75 + 0.25 * ping),
                      boxShadow: [
                        BoxShadow(color: _accent, blurRadius: (4 + 3 * ping) * s),
                      ],
                    ),
                  ),
                  SizedBox(width: 7.5 * s),
                  Text(
                    text,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14 * s,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.14 * s,
                    ),
                  ),
                ],
              ),
            ),
            // travelling light sweep
            Positioned.fill(
              child: IgnorePointer(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.45,
                  child: FractionalTranslation(
                    translation: Offset(sweepX / 45, 0),
                    child: Opacity(
                      opacity: sweepO,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withOpacity(0),
                              Colors.white.withOpacity(0.30),
                              Colors.white.withOpacity(0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- glowing tag
class _GlowTag extends StatelessWidget {
  const _GlowTag({required this.s, required this.t, required this.text});
  final double s, t;
  final String text;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GlowBorderPainter(angle: (t * 150) % 360 * math.pi / 180, s: s),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 7.5 * s),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16 * s,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.32 * s,
          ),
        ),
      ),
    );
  }
}

class _GlowBorderPainter extends CustomPainter {
  _GlowBorderPainter({required this.angle, required this.s});
  final double angle, s;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(1 * s), Radius.circular(9 * s));
    final shader = SweepGradient(
      transform: GradientRotation(angle),
      colors: [
        Colors.white.withOpacity(0.10),
        Colors.white.withOpacity(0.10),
        _accent,
        Colors.white,
        _accent,
        Colors.white.withOpacity(0.10),
      ],
      stops: const [0.0, 0.69, 0.85, 0.955, 0.978, 1.0],
    ).createShader(rect);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * s
        ..shader = shader
        ..maskFilter = MaskFilter.blur(BlurStyle.outer, 3 * s),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * s
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_GlowBorderPainter old) => old.angle != angle;
}

// --------------------------------------------------------------- calendar
class _Calendar extends StatelessWidget {
  const _Calendar({required this.s, required this.t});
  final double s, t;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 1 / (640 * s))
        ..rotateY(-15 * math.pi / 180)
        ..rotateX(7 * math.pi / 180)
        ..rotateZ(-1.5 * math.pi / 180),
      child: CustomPaint(
        painter: _CalendarPainter(t: t),
      ),
    );
  }
}

class _CalendarPainter extends CustomPainter {
  _CalendarPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 166.0; // painter units -> px
    double u(double v) => v * k;

    // depth slabs
    for (final slab in [
      [12.0, 5.0, const Color(0xFF8E8797)],
      [6.0, 2.5, const Color(0xFFC9C3D0)],
    ]) {
      final dx = slab[0] as double, dy = slab[1] as double;
      final r = RRect.fromLTRBR(u(3 + dx), u(9 + dy), u(163 + dx), u(158 + dy), Radius.circular(u(17)));
      canvas.drawRRect(r, Paint()..color = slab[2] as Color);
    }

    // rings
    final ringPaint = Paint()..color = const Color(0xFFCFCAD6);
    for (final x in [47.0, 110.0]) {
      canvas.drawRRect(
        RRect.fromLTRBR(u(x), u(1), u(x + 8.5), u(24), Radius.circular(u(4.2))),
        ringPaint,
      );
    }

    // face
    final face = RRect.fromLTRBR(u(3), u(9), u(163), u(158), Radius.circular(u(17)));
    canvas.drawRRect(
      face,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF3F1F5), Color(0xFFDEDAE3)],
          stops: [0.0, 0.7, 1.0],
        ).createShader(Rect.fromLTRB(u(3), u(9), u(163), u(158))),
    );

    // header
    canvas.save();
    canvas.clipRRect(face);
    canvas.drawRect(
      Rect.fromLTRB(u(3), u(9), u(163), u(41)),
      Paint()..color = _bg2,
    );
    canvas.drawRect(
      Rect.fromLTRB(u(3), u(41), u(163), u(42.6)),
      Paint()..color = Colors.black.withOpacity(0.10),
    );
    canvas.restore();

    // date cells + ticks
    const cols = 3, rows = 2;
    final gap = u(8.5);
    final gridL = u(14), gridT = u(44), gridR = u(152), gridB = u(148);
    final cw = (gridR - gridL - gap * (cols - 1)) / cols;
    final ch = (gridB - gridT - gap * (rows - 1)) / rows;

    for (int i = 0; i < cols * rows; i++) {
      final st = _Cues.ticks + 0.2 + i * 0.34;
      final draw = _clamp(_anim(t, 0, 1, st, 0.36, _easeOutCubic), 0, 1);
      final cellS = _clamp(_pop(t, 0.85, 1, st, 0.45), 0.85, 1.06);

      final cx = gridL + (i % cols) * (cw + gap);
      final cy = gridT + (i ~/ cols) * (ch + gap);
      final cell = Rect.fromLTWH(cx, cy, cw, ch);
      final scaled = Rect.fromCenter(
        center: cell.center,
        width: cell.width * cellS,
        height: cell.height * cellS,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(scaled, Radius.circular(u(8.5))),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: draw > 0.02
                ? [_accent.withOpacity(0.18), _accent.withOpacity(0.08)]
                : [Colors.black.withOpacity(0.07), Colors.black.withOpacity(0.03)],
          ).createShader(scaled),
      );

      if (draw <= 0) continue;
      _paintTick(canvas, scaled.deflate(u(6)), draw);
    }
  }

  void _paintTick(Canvas canvas, Rect box, double progress) {
    final badge = _clamp(progress * 2.2, 0, 1);
    final r = math.min(box.width, box.height) / 2 * (0.6 + badge * 0.4);
    final c = box.center;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.saveLayer(
      Rect.fromCircle(center: Offset.zero, radius: r * 2),
      Paint()..color = Colors.white.withOpacity(badge),
    );

    // contact shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(0, r * 0.97), width: r * 1.5, height: r * 0.38),
      Paint()..color = const Color(0xFF0A8256).withOpacity(0.18),
    );

    // badge
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3FD79A), Color(0xFF12B074), Color(0xFF0A8256)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    canvas.drawCircle(
      Offset.zero,
      r * 0.94,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.075
        ..color = Colors.white.withOpacity(0.28),
    );

    // check, drawn on
    final p = Path()
      ..moveTo(-r * 0.45, r * 0.04)
      ..lineTo(-r * 0.14, r * 0.35)
      ..lineTo(r * 0.46, -r * 0.34);
    final metric = p.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.21
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CalendarPainter old) => old.t != t;
}

// --------------------------------------------------------------- handle art
// The two handles, lifted out of shopping-bag.svg so they can hinge apart.
const _bagHandleBack = '''
<svg viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg"><path fill="#d1d1d6" fill-rule="evenodd" clip-rule="evenodd" d="m319.109 183.808v-99.554c0-15.342-6.282-29.296-16.403-39.416-10.121-10.121-24.074-16.403-39.416-16.403s-29.295 6.282-39.416 16.403c-10.121 10.12-16.403 24.074-16.403 39.416h-.031l.001 99.555h-15.938l-.001-99.555h-.031c0-19.759 8.077-37.716 21.09-50.729s30.97-21.09 50.729-21.09 37.716 8.078 50.729 21.09c13.013 13.013 21.09 30.97 21.09 50.729v99.555h-16z"/></svg>
''';

const _bagHandleFront = '''
<svg viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg"><path fill="#eceff1" fill-rule="evenodd" clip-rule="evenodd" d="m280.175 183.374c0 4.418-3.582 8-8 8s-8-3.582-8-8v-99.555c0-15.342-6.282-29.296-16.403-39.416-10.121-10.121-24.074-16.403-39.416-16.403s-29.295 6.282-39.416 16.403-16.403 24.074-16.403 39.416h-.031l.001 99.555c0 4.401-3.568 7.969-7.969 7.969s-7.969-3.568-7.969-7.969l-.001-99.555h-.031c0-19.759 8.077-37.716 21.09-50.729 13.014-13.013 30.97-21.09 50.729-21.09s37.716 8.077 50.729 21.09 21.09 30.97 21.09 50.729z"/></svg>
''';
