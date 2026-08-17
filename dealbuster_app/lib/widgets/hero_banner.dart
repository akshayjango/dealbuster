import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------- timing
class _Cues {
  static const intro = 0.0;
  static const bagIn = 0.35;
  static const products = 1.95;
  static const bagOut = 4.35;
  static const total = 6.0; // 6.0 seconds loop for the bag animation only
}

typedef _Ease = double Function(double);

double _easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();
double _easeInCubic(double t) => t * t * t;
double _easeOutBack(double t) {
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
}

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

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

class _Product {
  const _Product(this.asset, this.dx, this.dy, this.size, this.delay, this.rot);
  final String asset;
  final double dx, dy, size, delay, rot;
}

// Positions are on the 686 x 352 reference canvas, relative to the bag anchor.
const _products = <_Product>[
  _Product('assets/icons/sunscreen.svg', -89, -38, 56, 0.00, -12),
  _Product('assets/icons/headphones.svg', -43, -80, 58, 0.18, -8),
  _Product('assets/icons/clock.svg', 26, -60, 40, 0.36, 14),
  _Product('assets/icons/player.svg', 81, -54, 68, 0.54, 6),
];

class HeroBanner extends StatefulWidget {
  const HeroBanner({super.key, required this.liveDealCount});

  final int liveDealCount;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000), // 6 seconds loop
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.md,
        14,
        AppSpace.md,
        AppSpace.md,
      ),
      height: 176,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bg0, _bg1, _bg2],
        ),
        boxShadow: [
          BoxShadow(
            color: _bg2.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          if (w <= 0) return const SizedBox();
          final s = w / 686.0; // reference canvas -> real px
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _Frame(
              t: _c.value * _Cues.total,
              s: s,
              w: w,
              h: 176.0,
              liveDealCount: widget.liveDealCount,
            ),
          );
        }),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.t,
    required this.s,
    required this.w,
    required this.h,
    required this.liveDealCount,
  });

  final double t, s, w, h;
  final int liveDealCount;

  @override
  Widget build(BuildContext context) {
    // ---- badge idle motion --------------------------------------------
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

    final bagAnchor = Offset(375 + 311 / 2, h / s / 2); // right stage centre

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // ---------------------------------------------------------- left column
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 250,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LiveBadge(count: liveDealCount, ping: ping),
                const SizedBox(height: 12),
                Text(
                  'Deals that\ndon\'t wait.',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const Spacer(),
                Text(
                  'Fresh price drops tracked\naround the clock.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12.0,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
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
      ],
    );
  }

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
    const box = 139.0;
    const hinge = 34.0;
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

// --------------------------------------------------------------- live badge
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.count, required this.ping});
  final int count;
  final double ping;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6CFFB0).withOpacity(0.75 + 0.25 * ping),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6CFFB0),
                  blurRadius: 4 + 3 * ping,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count deals live now',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- handle art
const _bagHandleBack = '''
<svg viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg"><path fill="#d1d1d6" fill-rule="evenodd" clip-rule="evenodd" d="m319.109 183.808v-99.554c0-15.342-6.282-29.296-16.403-39.416-10.121-10.121-24.074-16.403-39.416-16.403s-29.295 6.282-39.416 16.403c-10.121 10.12-16.403 24.074-16.403 39.416h-.031l.001 99.555h-15.938l-.001-99.555h-.031c0-19.759 8.077-37.716 21.09-50.729s30.97-21.09 50.729-21.09 37.716 8.078 50.729 21.09c13.013 13.013 21.09 30.97 21.09 50.729v99.555h-16z"/></svg>
''';

const _bagHandleFront = '''
<svg viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg"><path fill="#eceff1" fill-rule="evenodd" clip-rule="evenodd" d="m280.175 183.374c0 4.418-3.582 8-8 8s-8-3.582-8-8v-99.555c0-15.342-6.282-29.296-16.403-39.416-10.121-10.121-24.074-16.403-39.416-16.403s-29.295 6.282-39.416 16.403-16.403 24.074-16.403 39.416h-.031l.001 99.555c0 4.401-3.568 7.969-7.969 7.969s-7.969-3.568-7.969-7.969l-.001-99.555h-.031c0-19.759 8.077-37.716 21.09-50.729 13.014-13.013 30.97-21.09 50.729-21.09s37.716 8.077 50.729 21.09 21.09 30.97 21.09 50.729z"/></svg>
''';
