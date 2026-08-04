import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/svg_icons.dart';

class AnimatedBanner extends StatefulWidget {
  final VoidCallback onTap;

  const AnimatedBanner({super.key, required this.onTap});

  @override
  State<AnimatedBanner> createState() => _AnimatedBannerState();
}

class _AnimatedBannerState extends State<AnimatedBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 13),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Helper to retrieve animated values inside sub-intervals
  double getProgress(double startSec, double endSec) {
    final t = _controller.value * 13.0;
    if (t < startSec) return 0.0;
    if (t > endSec) return 1.0;
    return (t - startSec) / (endSec - startSec);
  }

  double easeOutBack(double p) {
    const c1 = 1.70158;
    const c3 = c1 + 1.0;
    return 1.0 + c3 * math.pow(p - 1.0, 3.0) + c1 * math.pow(p - 1.0, 2.0);
  }

  double easeOutCubic(double p) {
    return 1.0 - math.pow(1.0 - p, 3.0);
  }

  double easeInOutCubic(double p) {
    return p < 0.5
        ? 4.0 * p * p * p
        : 1.0 - math.pow(-2.0 * p + 2.0, 3.0) / 2.0;
  }

  double easeInCubic(double p) {
    return p * p * p;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = (width * 880) / 1080;

          return Container(
            width: width,
            height: height,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF4A1B96),
                  Color(0xFF2E0F63),
                  Color(0xFF170733),
                ],
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // ── Continuous Twinkling Stars Background ──
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: StarsPainter(
                          time: _controller.value * 13.0,
                          bannerWidth: width,
                        ),
                      );
                    },
                  ),
                ),

                // ── Main Scenes Render ──
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final t = _controller.value * 13.0;

                    // Hero beat: 0.0s to 6.9s
                    final showHero = t < 6.9;
                    if (showHero) {
                      return _buildHeroScene(width, height, t);
                    } else {
                      return _buildCalendarScene(width, height, t);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Hero Scene Announce (0.0s to 6.9s) ──
  Widget _buildHeroScene(double width, double height, double t) {
    // 1. Intro animations
    final panelP = easeOutCubic(getProgress(0.0, 0.96)); // Fades & slides
    final giftP = easeOutBack(getProgress(0.32, 1.79)); // Back-out fly in
    final introTextP = easeOutCubic(getProgress(0.64, 1.34)); // Fades + rises
    final outlineP = easeOutCubic(getProgress(0.77, 1.60)); // Scale + fade
    final dealP = easeOutBack(getProgress(1.02, 2.05)); // Drops + scales
    final busterP = easeOutBack(getProgress(1.34, 2.37)); // Rises + scales
    final ctaP = easeOutBack(getProgress(1.92, 2.94)); // Scale + bounce

    // 2. Glow sweeps (3.2s to 6.0s)
    final glowSweepP = getProgress(3.2, 6.0);
    final glowBoxOn = (glowSweepP > 0.04 && glowSweepP < 0.52)
        ? easeInOutCubic(
            glowSweepP < 0.12
                ? (glowSweepP - 0.04) / 0.08
                : (0.52 - glowSweepP) / 0.08,
          )
        : 0.0;
    final glowBtnOn = (glowSweepP > 0.5 && glowSweepP < 0.99)
        ? easeInOutCubic(
            glowSweepP < 0.58
                ? (glowSweepP - 0.5) / 0.08
                : (0.99 - glowSweepP) / 0.09,
          )
        : 0.0;

    final glowBoxAngle = getProgress(3.31, 4.60) * 360.0;
    final glowBtnAngle = getProgress(4.60, 5.89) * 360.0;

    // 3. Collapse/Shrink animation (6.0s to 6.9s)
    final collapseP = getProgress(6.0, 6.9);
    final heroScale = 1.0 - easeInCubic(collapseP) * 0.96;
    final heroOpacity = collapseP < 0.5 ? 1.0 : 1.0 - (collapseP - 0.5) / 0.5;

    final scaleFactor = width / 1080;

    return Transform.translate(
      offset: Offset(0, -height * 0.03 * panelP), // Micro shift
      child: Opacity(
        opacity: heroOpacity,
        child: Transform.scale(
          scale: heroScale,
          alignment: const Alignment(0.0, -0.08), // Origin 50% 46%
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Hanging panel shadow / strings / panel body
              Positioned(
                left: 300 * scaleFactor,
                top: (96 + (1.0 - panelP) * -150) * scaleFactor,
                child: Opacity(
                  opacity: panelP * 0.9,
                  child: SizedBox(
                    width: 520 * scaleFactor,
                    height: 470 * scaleFactor,
                    child: CustomPaint(
                      painter: TrapezoidPainter(scaleFactor: scaleFactor),
                    ),
                  ),
                ),
              ),

              // Introducing text label
              Positioned(
                left: 322 * scaleFactor,
                top: (196 + (1.0 - introTextP) * 16) * scaleFactor,
                child: Opacity(
                  opacity: introTextP,
                  child: SizedBox(
                    width: 664 * scaleFactor,
                    child: Center(
                      child: Text(
                        'INTRODUCING',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 34 * scaleFactor,
                          letterSpacing: 0.3 * 34 * scaleFactor,
                          color: const Color(0xFFF2ECFF),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Outline Box with Custom Glow Sweep
              Positioned(
                left: 322 * scaleFactor,
                top: 268 * scaleFactor,
                child: Opacity(
                  opacity: outlineP,
                  child: Container(
                    width: 664 * scaleFactor,
                    height: 288 * scaleFactor,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFB6F24C),
                        width: 5 * scaleFactor,
                      ),
                      borderRadius: BorderRadius.circular(20 * scaleFactor),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFB6F24C).withOpacity(0.2),
                          blurRadius: 26 * scaleFactor,
                          spreadRadius: 2 * scaleFactor,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Sweeping outline glow head
                        if (glowBoxOn > 0.01)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: GlowBorderPainter(
                                angle: glowBoxAngle,
                                opacity: glowBoxOn,
                                strokeWidth: 5 * scaleFactor,
                                borderRadius: 20 * scaleFactor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // "DEAL" Text
              Positioned(
                left: 322 * scaleFactor,
                top: (314 + (1.0 - dealP) * -54) * scaleFactor,
                child: Opacity(
                  opacity: dealP,
                  child: Transform.scale(
                    scale: 0.86 + dealP * 0.14,
                    child: SizedBox(
                      width: 664 * scaleFactor,
                      child: Center(
                        child: Text(
                          'DEAL',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            fontSize: 132 * scaleFactor,
                            height: 0.94,
                            letterSpacing: -0.015 * 132 * scaleFactor,
                            color: const Color(0xFFB6F24C),
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.35),
                                offset: Offset(0, 6 * scaleFactor),
                              ),
                              Shadow(
                                color: const Color(0xFFB6F24C).withOpacity(0.35),
                                blurRadius: 34 * scaleFactor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // "BUSTER" Text
              Positioned(
                left: 322 * scaleFactor,
                top: (446 + (1.0 - busterP) * 48) * scaleFactor,
                child: Opacity(
                  opacity: busterP,
                  child: Transform.scale(
                    scale: 0.86 + busterP * 0.14,
                    child: SizedBox(
                      width: 664 * scaleFactor,
                      child: Center(
                        child: Text(
                          'BUSTER',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            fontSize: 92 * scaleFactor,
                            letterSpacing: 0.02 * 92 * scaleFactor,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.32),
                                offset: Offset(0, 5 * scaleFactor),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Gift box illustration on the left
              Positioned(
                left: (74 + (1.0 - giftP) * -300) * scaleFactor,
                top: 286 * scaleFactor,
                child: Opacity(
                  opacity: giftP.clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: (1.0 - giftP) * -22 * math.pi / 180,
                    child: Transform.scale(
                      scale: 0.8 + giftP * 0.2,
                      child: Container(
                        width: 300 * scaleFactor,
                        height: 300 * scaleFactor,
                        decoration: BoxDecoration(
                          shadows: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.45),
                              blurRadius: 26 * scaleFactor,
                              offset: Offset(0, 18 * scaleFactor),
                            ),
                          ],
                        ),
                        child: SvgPicture.string(
                          SvgIcons.gift,
                          width: 300 * scaleFactor,
                          height: 300 * scaleFactor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // CTA check it out pill button
              Positioned(
                left: 354 * scaleFactor,
                top: 622 * scaleFactor,
                child: Opacity(
                  opacity: ctaP,
                  child: Transform.scale(
                    scale: 0.7 + ctaP * 0.3,
                    child: Container(
                      width: 372 * scaleFactor,
                      height: 104 * scaleFactor,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFB6F24C), Color(0xFF8FCF20)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 30 * scaleFactor,
                            offset: Offset(0, 12 * scaleFactor),
                          ),
                          BoxShadow(
                            color: const Color(0xFFB6F24C).withOpacity(0.12),
                            spreadRadius: 6 * scaleFactor,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Text(
                              'Check it out',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: 44 * scaleFactor,
                                color: const Color(0xFF17200A),
                              ),
                            ),
                          ),
                          // CTA Sweeping Glow
                          if (glowBtnOn > 0.01)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: GlowBorderPainter(
                                  angle: glowBtnAngle,
                                  opacity: glowBtnOn,
                                  strokeWidth: 4 * scaleFactor,
                                  borderRadius: 52 * scaleFactor,
                                ),
                              ),
                            ),
                        ],
                      ),
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

  // ── Calendar Scene beat (6.9s to 13.0s) ──
  Widget _buildCalendarScene(double width, double height, double t) {
    // 1. Calendar fly-in animation (6.9s to 7.78s)
    final inFlyP = easeOutBack(getProgress(6.9, 7.78));
    final calScale = (0.06 + inFlyP * 0.94) * 0.82; // CAL_SHRINK = 0.82

    // 2. Caption text fade/slide (7.68s to 8.25s)
    final captionP = easeOutCubic(getProgress(7.68, 8.25));

    // 3. CTA button scale (7.94s to 8.72s)
    final ctaCalP = easeOutBack(getProgress(7.94, 8.72));

    // 4. Popper explode lines (11.37s to 12.05s)
    final popperP = getProgress(11.37, 12.05);

    // 5. Calendar grid ticks landing
    // Tick index ranges: i from 0 to 5
    final List<double> ticksP = List.generate(6, (i) {
      final start = 6.9 + 5.2 * (0.5 + i * 0.055);
      final end = start + 5.2 * 0.14;
      return getProgress(start, end);
    });

    // 6. Reset collapse (12.1s to 13.0s)
    final resetP = getProgress(12.1, 13.0);
    final finalScale = 1.0 - easeInCubic(resetP) * 0.96;
    final finalOpacity = resetP < 0.5 ? 1.0 : 1.0 - (resetP - 0.5) / 0.5;

    final scaleFactor = width / 1080;

    return Opacity(
      opacity: finalOpacity,
      child: Transform.scale(
        scale: finalScale,
        alignment: const Alignment(0.0, -0.08), // Origin 50% 46%
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Calendar Group (3D perspectives simulated)
            Positioned(
              left: 264 * scaleFactor,
              top: (178 + (1.0 - inFlyP) * 400) * scaleFactor,
              child: Opacity(
                opacity: inFlyP.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: calScale,
                  child: Container(
                    width: 552 * scaleFactor,
                    height: 340 * scaleFactor,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.45),
                          blurRadius: 30 * scaleFactor,
                          offset: Offset(0, 26 * scaleFactor),
                        ),
                      ],
                    ),
                    child: CustomPaint(
                      painter: Calendar3DPainter(
                        scaleFactor: scaleFactor,
                        ticksProgress: ticksP,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Left and Right exploder burst paths (poppers)
            if (popperP > 0.01) ...[
              // Left Popper
              Positioned(
                left: 118 * scaleFactor,
                top: 268 * scaleFactor,
                child: SizedBox(
                  width: 190 * scaleFactor,
                  height: 190 * scaleFactor,
                  child: CustomPaint(
                    painter: PopperPainter(
                      progress: popperP,
                      isLeft: true,
                      scaleFactor: scaleFactor,
                    ),
                  ),
                ),
              ),
              // Right Popper (mirrored)
              Positioned(
                left: 772 * scaleFactor,
                top: 268 * scaleFactor,
                child: SizedBox(
                  width: 190 * scaleFactor,
                  height: 190 * scaleFactor,
                  child: CustomPaint(
                    painter: PopperPainter(
                      progress: popperP,
                      isLeft: false,
                      scaleFactor: scaleFactor,
                    ),
                  ),
                ),
              ),
            ],

            // Caption text "New deals updated daily"
            Positioned(
              left: 0,
              top: (578 + (1.0 - captionP) * 20) * scaleFactor,
              width: width,
              child: Opacity(
                opacity: captionP,
                child: Center(
                  child: Text(
                    'New deals updated daily',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 46 * scaleFactor,
                      color: const Color(0xFFEFE9FF),
                    ),
                  ),
                ),
              ),
            ),

            // CTA Check it out button
            Positioned(
              left: 354 * scaleFactor,
              top: 662 * scaleFactor,
              child: Opacity(
                opacity: ctaCalP,
                child: Transform.scale(
                  scale: 0.7 + ctaCalP * 0.3,
                  child: Container(
                    width: 372 * scaleFactor,
                    height: 100 * scaleFactor,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFB6F24C), Color(0xFF8FCF20)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 30 * scaleFactor,
                          offset: Offset(0, 12 * scaleFactor),
                        ),
                        BoxShadow(
                          color: const Color(0xFFB6F24C).withOpacity(0.12),
                          spreadRadius: 6 * scaleFactor,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'Check it out',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 44 * scaleFactor,
                          color: const Color(0xFF17200A),
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

// ── Background Star Particle Painter ──
class StarsPainter extends CustomPainter {
  final double time;
  final double bannerWidth;

  StarsPainter({required this.time, required this.bannerWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = bannerWidth / 1080;
    canvas.save();
    canvas.scale(scale);

    // Dynamic configuration of the 5 twinkling stars
    final stars = [
      _Star(x: 62, y: 196, size: 30, baseO: 0.85, phase: 0.0),
      _Star(x: 128, y: 620, size: 22, baseO: 0.60, phase: 0.34),
      _Star(x: 992, y: 160, size: 34, baseO: 0.90, phase: 0.62),
      _Star(x: 946, y: 700, size: 18, baseO: 0.50, phase: 0.18),
      _Star(x: 520, y: 112, size: 14, baseO: 0.40, phase: 0.80),
    ];

    final paint = Paint()..color = Colors.white;

    for (final star in stars) {
      final w = (math.sin((time * 1.15 + star.phase) * math.pi * 2) + 1.0) / 2.0;
      final k = 0.22 + w * 0.78;
      final opacity = star.baseO * k;
      final scaleSize = star.size * (0.62 + k * 0.5);

      paint.color = Colors.white.withOpacity(opacity.clamp(0.0, 1.0));

      canvas.save();
      // Center translate
      canvas.translate(star.x, star.y);
      canvas.rotate(w * 24 * math.pi / 180);

      // Star shape drawing
      final path = Path();
      final s = scaleSize;
      path.moveTo(s / 2, 0);
      path.lineTo(0.57 * s, 0.43 * s);
      path.lineTo(s, s / 2);
      path.lineTo(0.57 * s, 0.57 * s);
      path.lineTo(s / 2, s);
      path.lineTo(0.43 * s, 0.57 * s);
      path.lineTo(0, s / 2);
      path.lineTo(0.43 * s, 0.43 * s);
      path.close();

      // Shadow drawing simulating dropshadow
      final shadowPaint = Paint()
        ..color = Colors.white.withOpacity(0.35 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, (4 + k * 12) / scale);

      canvas.drawPath(path, shadowPaint);
      canvas.drawPath(path, paint);

      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StarsPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.bannerWidth != bannerWidth;
}

class _Star {
  final double x;
  final double y;
  final double size;
  final double baseO;
  final double phase;

  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.baseO,
    required this.phase,
  });
}

// ── Hanging Panel trapezoid shape custom painter ──
class TrapezoidPainter extends CustomPainter {
  final double scaleFactor;

  TrapezoidPainter({required this.scaleFactor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Strings
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.16)
      ..strokeWidth = 3 * scaleFactor
      ..strokeCap = StrokeCap.round;

    // String left (rotated -7 deg)
    canvas.drawLine(
      Offset(w * 0.15, 0),
      Offset(w * 0.22, 104 * scaleFactor),
      linePaint,
    );
    // String right (rotated +7 deg)
    canvas.drawLine(
      Offset(w * 0.85, 0),
      Offset(w * 0.78, 104 * scaleFactor),
      linePaint,
    );

    // 2. Hanging Trapezoid Panel
    final path = Path()
      ..moveTo(w * 0.12, 104 * scaleFactor)
      ..lineTo(w * 0.88, 104 * scaleFactor)
      ..lineTo(w * 0.80, h)
      ..lineTo(w * 0.20, h)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.075),
          Colors.white.withOpacity(0.01),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(path, fillPaint);

    // 3. Round Hooks
    final hookPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * scaleFactor;

    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(w * 0.15, 50 * scaleFactor),
        radius: 20 * scaleFactor,
      ),
      35 * math.pi / 180,
      270 * math.pi / 180,
      false,
      hookPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(w * 0.85, 50 * scaleFactor),
        radius: 20 * scaleFactor,
      ),
      -35 * math.pi / 180,
      -270 * math.pi / 180,
      false,
      hookPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Glow Border Sweep Painter ──
class GlowBorderPainter extends CustomPainter {
  final double angle;
  final double opacity;
  final double strokeWidth;
  final double borderRadius;

  GlowBorderPainter({
    required this.angle,
    required this.opacity,
    required this.strokeWidth,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        transform: GradientRotation(angle * math.pi / 180),
        colors: [
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.0),
          const Color(0xFFDFFF8A).withOpacity(0.2),
          const Color(0xFFDFFF8A).withOpacity(0.8 * opacity),
          Colors.white.withOpacity(opacity),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.0, 0.65, 0.78, 0.94, 0.99, 1.0],
      ).createShader(rect);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant GlowBorderPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.opacity != opacity;
}

// ── Calendar 3D Simulated Drawing ──
class Calendar3DPainter extends CustomPainter {
  final double scaleFactor;
  final List<double> ticksProgress;

  Calendar3DPainter({
    required this.scaleFactor,
    required this.ticksProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Simulate 3D rotation with shear transformations
    canvas.save();
    canvas.skew(-0.06, 0.0); // Simple Z-tilt simulation

    // 1. Left Flap (Backing fold page)
    final leftPath = Path()
      ..moveTo(0, 54 * scaleFactor)
      ..lineTo(128 * scaleFactor, 54 * scaleFactor)
      ..lineTo(128 * scaleFactor, h)
      ..lineTo(0, h)
      ..close();

    final leftPaint = Paint()..color = const Color(0xFFCBB292);
    canvas.drawPath(leftPath, leftPaint);

    final leftTopPath = Path()
      ..moveTo(0, 0)
      ..lineTo(128 * scaleFactor, 0)
      ..lineTo(128 * scaleFactor, 54 * scaleFactor)
      ..lineTo(0, 54 * scaleFactor)
      ..close();
    final leftTopPaint = Paint()..color = const Color(0xFF5E9A2C);
    canvas.drawPath(leftTopPath, leftTopPaint);

    // 2. Front Face (Main Calendar Page)
    final faceRect = Rect.fromLTWH(128 * scaleFactor, 0, w - 128 * scaleFactor, h);
    final facePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF2E2C9), Color(0xFFE2CDAC)],
      ).createShader(faceRect);

    canvas.drawRect(faceRect, facePaint);

    // Top Green Band
    final topBandRect = Rect.fromLTWH(128 * scaleFactor, 0, w - 128 * scaleFactor, 54 * scaleFactor);
    final topBandPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF7CBE3A), Color(0xFF63A128)],
      ).createShader(topBandRect);

    canvas.drawRect(topBandRect, topBandPaint);

    // 3. Spiral Rings (Hanger Loops)
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * scaleFactor
      ..color = const Color(0xFF1D3A16);

    // Left Ring
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(186 * scaleFactor, 22 * scaleFactor),
        radius: 12 * scaleFactor,
      ),
      -18 * math.pi / 180,
      270 * math.pi / 180,
      false,
      ringPaint,
    );

    // Right Ring
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset((w - 58) * scaleFactor, 22 * scaleFactor),
        radius: 12 * scaleFactor,
      ),
      18 * math.pi / 180,
      270 * math.pi / 180,
      false,
      ringPaint,
    );

    // 4. Tick grid rendering (6 cells)
    final startX = 148.0 * scaleFactor;
    final startY = 78.0 * scaleFactor;
    final cellW = 100.0 * scaleFactor;
    final cellH = 100.0 * scaleFactor;
    final gapX = 26.0 * scaleFactor;
    final gapY = 20.0 * scaleFactor;

    for (int i = 0; i < 6; i++) {
      final row = i ~/ 3;
      final col = i % 3;

      final x = startX + col * (cellW + gapX);
      final y = startY + row * (cellH + gapY);

      final progress = ticksProgress[i];
      if (progress <= 0.01) continue;

      // Elastic zoom-in effect on the checkbox
      final double scale = 0.55 + 0.45 * progress;
      final double offsetShift = (1.0 - scale) * (cellW / 2.0);

      canvas.save();
      canvas.translate(x + offsetShift, y + offsetShift);
      canvas.scale(scale);

      final boxPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7CC03C), Color(0xFF5E9A2C)],
        ).createShader(Rect.fromLTWH(0, 0, cellW, cellH));

      // Checkbox Base
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, cellW, cellH),
          Radius.circular(10 * scaleFactor),
        ),
        boxPaint,
      );

      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * scaleFactor
        ..color = Colors.white.withOpacity(0.9);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, cellW, cellH),
          Radius.circular(10 * scaleFactor),
        ),
        borderPaint,
      );

      // Checkmark drawing inside
      final checkP = (progress - 0.25) / 0.75;
      if (checkP > 0.01) {
        final checkPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8 * scaleFactor
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        final path = Path();
        // Checkmark vectors normalized to cell coordinates
        path.moveTo(cellW * 0.2, cellH * 0.5);
        path.lineTo(cellW * 0.42, cellH * 0.76);
        path.lineTo(cellW * 0.8, cellH * 0.22);

        // Animate path drawing via stroke-dash extraction (simulated using progress)
        final metric = path.computeMetrics().first;
        final extractPath = metric.extractPath(0.0, metric.length * checkP.clamp(0.0, 1.0));
        canvas.drawPath(extractPath, checkPaint);
      }

      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant Calendar3DPainter oldDelegate) => true;
}

// ── Popper Exploding Bursts Painter ──
class PopperPainter extends CustomPainter {
  final double progress;
  final bool isLeft;
  final double scaleFactor;

  PopperPainter({
    required this.progress,
    required this.isLeft,
    required this.scaleFactor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.save();
    if (!isLeft) {
      canvas.scale(-1.0, 1.0);
      canvas.translate(-w, 0);
    }

    final p = progress.clamp(0.0, 1.0);
    final popFadeOut = (p > 0.85) ? (p - 0.85) / 0.15 : 0.0;
    final opacity = (p * 4.0).clamp(0.0, 1.0) * (1.0 - popFadeOut);

    final burstPaint = Paint()
      ..color = const Color(0xFFB6F24C).withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * scaleFactor
      ..strokeCap = StrokeCap.round;

    // Curved spiral segment M14 168 C 52 66, 150 44, 146 96 C 143 138, 78 122, 112 62
    final spiralPath = Path()
      ..moveTo(14 * scaleFactor, 168 * scaleFactor)
      ..cubicTo(52 * scaleFactor, 66 * scaleFactor, 150 * scaleFactor, 44 * scaleFactor, 146 * scaleFactor, 96 * scaleFactor)
      ..cubicTo(143 * scaleFactor, 138 * scaleFactor, 78 * scaleFactor, 122 * scaleFactor, 112 * scaleFactor, 62 * scaleFactor);

    final metric = spiralPath.computeMetrics().first;
    // Drawn-on from the end (reversing)
    final drawLength = metric.length * (p < 0.8 ? p / 0.8 : 1.0);
    final startOffset = metric.length * (1.0 - drawLength / metric.length);
    final extractPath = metric.extractPath(startOffset, metric.length);

    canvas.drawPath(extractPath, burstPaint);

    // Popper short tick segment M4 128 L 44 118 (appears late at 60%)
    if (p > 0.6) {
      final tickOpacity = ((p - 0.6) * 4.0).clamp(0.0, 1.0) * (1.0 - popFadeOut);
      final tickPaint = Paint()
        ..color = const Color(0xFFB6F24C).withOpacity(tickOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 * scaleFactor
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(4 * scaleFactor, 128 * scaleFactor),
        Offset(44 * scaleFactor, 118 * scaleFactor),
        tickPaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PopperPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isLeft != isLeft;
}
