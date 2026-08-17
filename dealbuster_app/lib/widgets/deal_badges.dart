import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/svg_icons.dart';

/// A "lowest price in 30 days" badge — set apart from the plain coupon/
/// savings text with a slow-spinning gradient ring, since it's a rarer,
/// more notable signal than an ordinary discount. Shared by the deal card
/// grid and the product detail screen's price row.
class LowestPriceBadge extends StatefulWidget {
  const LowestPriceBadge({super.key, this.fontSize = 11});

  final double fontSize;

  @override
  State<LowestPriceBadge> createState() => _LowestPriceBadgeState();
}

class _LowestPriceBadgeState extends State<LowestPriceBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, _) {
        final gradient = SweepGradient(
          transform: GradientRotation(_spin.value * 2 * math.pi),
          colors: [
            AppColors.gold,
            AppColors.brand,
            AppColors.gold,
            AppColors.gold.withValues(alpha: 0),
            AppColors.gold.withValues(alpha: 0),
            AppColors.gold,
          ],
          stops: const [0.0, 0.18, 0.35, 0.42, 0.92, 1.0],
        );

        return CustomPaint(
          painter: _GradientBorderPainter(
            gradient: gradient,
            strokeWidth: 1.3,
            borderRadius: 6.0,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 5.5 + 1.3,
              vertical: 1.7 + 1.3,
            ),
            child: Text(
              'Lowest Price',
              style: TextStyle(
                color: AppColors.brandDark,
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GradientBorderPainter extends CustomPainter {
  _GradientBorderPainter({
    required this.gradient,
    required this.strokeWidth,
    required this.borderRadius,
  });

  final Gradient gradient;
  final double strokeWidth;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..shader = gradient.createShader(rect);

    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientBorderPainter oldDelegate) =>
      oldDelegate.gradient != gradient ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.borderRadius != borderRadius;
}

/// The tag-icon-and-fill "X% Coupon" pill — shared by the deal card grid
/// and the product detail screen's price row.
class CouponBadge extends StatelessWidget {
  const CouponBadge({super.key, required this.percent, this.fontSize = 11});

  final String percent;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgIcon(SvgIcons.tag, size: fontSize - 1, color: AppColors.success),
          const SizedBox(width: 4),
          Text(
            '$percent Coupon',
            style: TextStyle(
              color: AppColors.success,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
