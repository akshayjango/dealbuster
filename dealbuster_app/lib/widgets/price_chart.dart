import 'package:flutter/material.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';

/// A minimal smoothed line chart for price-history, gradient-filled under
/// the line, with a dot on the latest point.
class PriceChart extends StatelessWidget {
  const PriceChart({super.key, required this.points});
  final List<PricePoint> points;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _PriceChartPainter(points.map((p) => p.price).toList()),
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  _PriceChartPainter(this.prices);
  final List<double> prices;

  @override
  void paint(Canvas canvas, Size size) {
    if (prices.length < 2) return;

    final lowest = prices.reduce((a, b) => a < b ? a : b);
    final highest = prices.reduce((a, b) => a > b ? a : b);
    final range = (highest - lowest).abs() < 1 ? 1.0 : highest - lowest;

    final dx = size.width / (prices.length - 1);
    Offset pointAt(int i) {
      final normalized = (prices[i] - lowest) / range;
      return Offset(dx * i, size.height - normalized * size.height * 0.86 - 6);
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < prices.length; i++) {
      final prev = pointAt(i - 1);
      final curr = pointAt(i);
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(pointAt(prices.length - 1).dx, pointAt(prices.length - 1).dy);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.brand.withValues(alpha: 0.18),
            AppColors.brand.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.brand
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    final last = pointAt(prices.length - 1);
    canvas.drawCircle(last, 4.5, Paint()..color = AppColors.brand);
    canvas.drawCircle(
      last,
      4.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _PriceChartPainter oldDelegate) =>
      oldDelegate.prices != prices;
}
