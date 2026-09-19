import "dart:math" as math;
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "../theme/app_theme.dart";
import "main_screen.dart";
import "notification_permission_screen.dart";

/// Duolingo-style animated splash screen featuring:
/// 1. Pop entrance of center brand logo + bottom brand text.
/// 2. Playful mascot-style squish & stretch hop animation on the logo itself.
/// 3. Bottom text smooth fadeout prior to background fill.
/// 4. Vibrant brand-orange circle-fill transition expanding from center.
/// 5. Seamless handoff to the Notification Permission (or Home) screen.
class SplashScreen extends StatefulWidget {
  final bool shouldPrompt;
  const SplashScreen({super.key, required this.shouldPrompt});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateToNext();
      }
    });

    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _navigateToNext() {
    if (_navigated || !mounted) return;
    _navigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) =>
            widget.shouldPrompt
                ? const NotificationPermissionScreen()
                : const MainScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;

          // ── Phase 1: Entrance (0.0 -> 0.28) ──
          final entranceProgress = (t / 0.28).clamp(0.0, 1.0);
          final entranceScale = Curves.easeOutBack.transform(entranceProgress);
          final entranceOpacity = (t / 0.18).clamp(0.0, 1.0);

          // ── Phase 2: Bottom Text Entrance, Hold & Smooth Fadeout ──
          double textOpacity = 0.0;
          double textSlideY = 0.0;
          if (t < 0.28) {
            // Text entrance
            final textIn = ((t - 0.08) / 0.20).clamp(0.0, 1.0);
            textOpacity = Curves.easeOutCubic.transform(textIn);
            textSlideY = (1.0 - textOpacity) * 16.0;
          } else if (t <= 0.50) {
            // Rest/hold
            textOpacity = 1.0;
            textSlideY = 0.0;
          } else if (t < 0.62) {
            // Text exits smoothly before fill starts
            final textOut = ((t - 0.50) / 0.12).clamp(0.0, 1.0);
            textOpacity = 1.0 - Curves.easeInCubic.transform(textOut);
            textSlideY = textOut * 12.0;
          } else {
            textOpacity = 0.0;
          }

          // ── Phase 3: Center-out Circular Fill (0.62 -> 0.90) ──
          final fillProgress = ((t - 0.62) / 0.28).clamp(0.0, 1.0);
          final fillEased = Curves.easeInOutCubic.transform(fillProgress);

          // Transformation of logo during fill (turns into crisp elevated white emblem on orange)
          final invertProgress = ((t - 0.68) / 0.20).clamp(0.0, 1.0);
          final invertEased = Curves.easeOutCubic.transform(invertProgress);

          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;

              return Stack(
                children: [
                  // ── Circular Fill Canvas ──
                  if (fillEased > 0)
                    CustomPaint(
                      size: Size(width, height),
                      painter: _CircleFillPainter(
                        progress: fillEased,
                        color: AppColors.brand,
                      ),
                    ),

                  // ── Center Logo Unit ──
                  Center(
                    child: Transform.scale(
                      scale: entranceScale,
                      child: Opacity(
                        opacity: entranceOpacity,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              AppColors.brand,
                              Colors.white,
                              invertEased,
                            ),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: Color.lerp(
                                  AppColors.brand.withValues(alpha: 0.38),
                                  Colors.black.withValues(alpha: 0.18),
                                  invertEased,
                                )!,
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: CustomPaint(
                              size: const Size(48, 48),
                              painter: DealBusterMarkPainter(
                                color: Color.lerp(
                                  Colors.white,
                                  AppColors.brand,
                                  invertEased,
                                )!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Bottom Brand Text ("DealBuster") ──
                  if (textOpacity > 0.01)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 54,
                      child: Transform.translate(
                        offset: Offset(0, textSlideY),
                        child: Opacity(
                          opacity: textOpacity,
                          child: Center(
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: "Deal",
                                    style: GoogleFonts.sora(
                                      fontSize: 27,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink,
                                      letterSpacing: -0.8,
                                    ),
                                  ),
                                  TextSpan(
                                    text: "Buster",
                                    style: GoogleFonts.sora(
                                      fontSize: 27,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.brand,
                                      letterSpacing: -0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Expanding circular background fill painter
class _CircleFillPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CircleFillPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius * progress, paint);
  }

  @override
  bool shouldRepaint(covariant _CircleFillPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// High-performance, vector-sharp painter for DealBuster brand "D" emblem
class DealBusterMarkPainter extends CustomPainter {
  final Color color;
  const DealBusterMarkPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final scale = size.width / 64.0;
    canvas.save();
    canvas.scale(scale, scale);

    final path = Path();
    // Outer "D" boundary
    path.moveTo(35.1199, 0);
    path.cubicTo(41.0864, 0, 46.2228, 1.06368, 50.5284, 3.19091);
    path.cubicTo(54.896, 5.25728, 58.2179, 8.2052, 60.4941, 12.0343);
    path.cubicTo(62.8314, 15.8025, 64, 20.2394, 64, 25.3446);
    path.cubicTo(64, 27.1072, 63.7846, 29.3257, 63.3537, 32);
    path.cubicTo(62.2466, 38.2603, 59.8478, 43.8214, 56.157, 48.6835);
    path.cubicTo(52.5282, 53.5462, 47.8837, 57.314, 42.2246, 59.9883);
    path.cubicTo(36.6269, 62.6626, 30.4449, 64, 23.6786, 64);
    path.lineTo(2.81689, 64);
    path.cubicTo(1.04975, 64, -0.280678, 62.4103, 0.050903, 60.6955);
    path.lineTo(11.3547, 2.26021);
    path.cubicTo(11.6084, 0.948787, 12.7692, 0, 14.1207, 0);
    path.lineTo(35.1199, 0);
    path.close();

    // Inner stylized lightning bolt cutout
    path.moveTo(29.5428, 13.4536);
    path.cubicTo(29.1087, 13.4532, 28.6854, 13.588, 28.3329, 13.8389);
    path.cubicTo(27.9804, 14.0899, 27.7171, 14.4442, 27.5801, 14.8516);
    path.lineTo(20.5693, 32.8482);
    path.cubicTo(20.4655, 33.1556, 20.4374, 33.483, 20.4867, 33.8034);
    path.cubicTo(20.5364, 34.1239, 20.6617, 34.4285, 20.8537, 34.6915);
    path.cubicTo(21.0451, 34.9544, 21.2981, 35.1682, 21.59, 35.3157);
    path.cubicTo(21.882, 35.4631, 22.2053, 35.5406, 22.5334, 35.5406);
    path.lineTo(27.3116, 35.5406);
    path.cubicTo(28.01, 35.5406, 28.4638, 36.2668, 28.1508, 36.8835);
    path.lineTo(21.9045, 49.1895);
    path.cubicTo(21.798, 49.637, 21.8496, 50.1072, 22.0505, 50.5218);
    path.cubicTo(22.2518, 50.9368, 22.5907, 51.2711, 23.0102, 51.4692);
    path.cubicTo(23.2989, 51.6101, 23.6161, 51.6839, 23.9381, 51.6848);
    path.cubicTo(24.2399, 51.6839, 24.5379, 51.6171, 24.8101, 51.4886);
    path.cubicTo(25.0828, 51.3606, 25.3236, 51.1742, 25.5146, 50.9433);
    path.lineTo(43.4504, 31.5316);
    path.cubicTo(43.702, 31.233, 43.8625, 30.8694, 43.9127, 30.4841);
    path.cubicTo(43.9629, 30.0987, 43.9005, 29.7073, 43.7339, 29.3554);
    path.cubicTo(43.5668, 29.0034, 43.3021, 28.7057, 42.9703, 28.497);
    path.cubicTo(42.6385, 28.2888, 42.2532, 28.178, 41.8599, 28.178);
    path.lineTo(37.612, 28.178);
    path.cubicTo(36.8155, 28.178, 36.3809, 27.2598, 36.8916, 26.6555);
    path.lineTo(45.6267, 16.3292);
    path.cubicTo(45.767, 16.0179, 45.8262, 15.6768, 45.799, 15.337);
    path.cubicTo(45.7717, 14.9972, 45.6586, 14.6695, 45.4709, 14.3837);
    path.cubicTo(45.2827, 14.098, 45.0255, 13.8633, 44.7223, 13.7008);
    path.cubicTo(44.4191, 13.5383, 44.0798, 13.4533, 43.7348, 13.4536);
    path.lineTo(29.5428, 13.4536);
    path.close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
