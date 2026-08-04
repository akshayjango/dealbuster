import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:ui' as ui;
import '../models/product.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _isExpanded = false;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _shareProduct() {
    final text = '${widget.product.displayTitle} - Amazing deal on Dealbuster!\n${widget.product.link}';
    Share.share(text);
  }

  String _getRelativeTime(String timeStr) {
    if (timeStr.isEmpty) return 'Updated today';
    try {
      final date = DateTime.parse(timeStr);
      final diff = DateTime.now().difference(date);
      final diffHours = diff.inHours;

      if (diffHours < 24) {
        if (diffHours < 1) {
          return 'Updated 1hr ago';
        }
        return 'Updated ${diffHours}hr ago';
      } else {
        final diffDays = diff.inDays;
        if (diffDays <= 0) {
          return 'Updated today';
        } else if (diffDays == 1) {
          return 'Updated 1 day ago';
        } else {
          return 'Updated $diffDays days ago';
        }
      }
    } catch (_) {
      return 'Updated today';
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final relativeTime = _getRelativeTime(product.addedAt);
    final cleanDisc = product.disc.replaceAll('-', '').replaceAll('%', '');

    // Capped highlights: default to 2 items unless expanded
    final displayedHighlights = (product.highlights.isEmpty)
        ? _genericHighlights
        : product.highlights;
    final visibleHighlights = _isExpanded
        ? displayedHighlights
        : displayedHighlights.take(2).toList();
    final hasMoreHighlights = displayedHighlights.length > 2;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: Stack(
        children: [
          // ── 1. Blurred Backdrop Image ──
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: product.image,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFF170733),
              ),
            ),
          ),
          // Blur layer overlay
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 35, sigmaY: 35),
              child: Container(
                color: const Color(0xFFF6F7FB).withOpacity(0.7),
              ),
            ),
          ),

          // ── 2. Scrollable Modal Sheet Content ──
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Safe Area Space for close button
                  const SizedBox(height: 52),

                  // Floating Sliding Sheet Container
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF6F7FB),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 110), // Clearance for bottom CTA
                          children: [
                            // ── Square Image Card ──
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: AspectRatio(
                                aspectRatio: 1.0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF17192B).withOpacity(0.05),
                                        blurRadius: 2,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      // Image
                                      Positioned.fill(
                                        child: Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: CachedNetworkImage(
                                            imageUrl: product.image,
                                            fit: BoxFit.contain,
                                            errorWidget: (context, url, error) => const Icon(
                                              Icons.image_not_supported_outlined,
                                              size: 48,
                                              color: Color(0xFF6E7385),
                                            ),
                                          ),
                                        ),
                                      ),

                                      // Overlaid Floating Share Button (bottom right corner)
                                      Positioned(
                                        bottom: 14,
                                        right: 14,
                                        child: SizedBox(
                                          width: 40,
                                          height: 40,
                                          child: FloatingActionButton(
                                            heroTag: 'share_fab_detail',
                                            elevation: 2,
                                            backgroundColor: Colors.white,
                                            foregroundColor: const Color(0xFF1A1D2E),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(20),
                                              side: const BorderSide(
                                                color: Color(0xFFE7E8F0),
                                                width: 1,
                                              ),
                                            ),
                                            onPressed: _shareProduct,
                                            child: const Icon(Icons.share_outlined, size: 18),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // ── Badges Row ──
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Row(
                                children: [
                                  // Discount tag
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE94444),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '-$cleanDisc% OFF',
                                      style: const TextStyle(
                                        fontFamily: 'Plus Jakarta Sans',
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Relative update time badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: const Color(0xFFE7E8F0),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF12925A),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          relativeTime,
                                          style: const TextStyle(
                                            fontFamily: 'Plus Jakarta Sans',
                                            fontWeight: FontWeight.w500,
                                            fontSize: 9.5,
                                            color: Color(0xFF1A1D2E),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── Category Tag & Title ──
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.category.toUpperCase(),
                                    style: const TextStyle(
                                      fontFamily: 'Plus Jakarta Sans',
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                      color: Color(0xFF6C47FF),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    product.displayTitle,
                                    style: const TextStyle(
                                      fontFamily: 'Plus Jakarta Sans',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      height: 1.4,
                                      color: Color(0xFF1A1D2E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Price Pill Card Row ──
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Row(
                                children: [
                                  // Current Price Pill
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6C47FF),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF6C47FF).withOpacity(0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      product.price,
                                      style: const TextStyle(
                                        fontFamily: 'Plus Jakarta Sans',
                                        fontWeight: FontWeight.w800,
                                        fontSize: 20,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Original MRP and Savings info
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (product.mrp.isNotEmpty && product.mrp != '₹0')
                                        Text(
                                          'MRP ${product.mrp}',
                                          style: const TextStyle(
                                            fontFamily: 'Plus Jakarta Sans',
                                            fontWeight: FontWeight.w600,
                                            fontSize: 11,
                                            color: Color(0xFF6E7385),
                                            decoration: TextDecoration.lineThrough,
                                          ),
                                        ),
                                      if (product.savingsAmount > 0)
                                        Text(
                                          'You save ₹${product.savingsAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                                          style: const TextStyle(
                                            fontFamily: 'Plus Jakarta Sans',
                                            fontWeight: FontWeight.w600,
                                            fontSize: 11,
                                            color: Color(0xFF12925A),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // ── Highlights Card ──
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 14),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Highlights',
                                    style: TextStyle(
                                      fontFamily: 'Plus Jakarta Sans',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Color(0xFF1A1D2E),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    itemCount: visibleHighlights.length,
                                    itemBuilder: (context, index) {
                                      final item = visibleHighlights[index];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Text(
                                          '•  $item',
                                          style: const TextStyle(
                                            fontFamily: 'Plus Jakarta Sans',
                                            fontWeight: FontWeight.w400,
                                            fontSize: 11,
                                            height: 1.5,
                                            color: Color(0xFF1A1D2E),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  if (hasMoreHighlights) ...[
                                    const SizedBox(height: 12),
                                    Center(
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _isExpanded = !_isExpanded;
                                          });
                                        },
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _isExpanded ? 'View less' : 'View more',
                                              style: const TextStyle(
                                                fontFamily: 'Plus Jakarta Sans',
                                                fontWeight: FontWeight.w700,
                                                fontSize: 10,
                                                color: Color(0xFF6C47FF),
                                              ),
                                            ),
                                            Icon(
                                              _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                              size: 14,
                                              color: const Color(0xFF6C47FF),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ── Price History Section ──
                            _buildPriceHistory(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 3. Sticky Bottom CTA Bar ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                top: 10,
                bottom: 10 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(
                  top: BorderSide(color: Color(0xFFE7E8F0), width: 1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF17192B).withOpacity(0.12),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD000),
                    foregroundColor: const Color(0xFF1A1D2E),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _launchUrl(product.link),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Buy on Amazon',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Transform.rotate(
                        angle: -math.pi / 4,
                        child: const Icon(Icons.arrow_forward, size: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── 4. Circular Pinned Close Button ──
          Positioned(
            left: 0,
            right: 0,
            top: 42 + MediaQuery.of(context).padding.top,
            child: Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: FloatingActionButton(
                  heroTag: 'close_fab_detail',
                  elevation: 0,
                  backgroundColor: Colors.black.withOpacity(0.75),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(Icons.keyboard_arrow_down, size: 24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Price History Widget ──
  Widget _buildPriceHistory() {
    final product = widget.product;
    final history = product.priceHistory;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Price History',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFF1A1D2E),
            ),
          ),
          const SizedBox(height: 12),

          if (history.length < 2) ...[
            const Text(
              "We just started tracking this deal's price — check back later to see how it's moved.",
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontWeight: FontWeight.w400,
                fontSize: 11,
                color: Color(0xFF6E7385),
                height: 1.5,
              ),
            ),
          ] else ...[
            // Statistics values (Lowest, Current, Highest)
            _buildStatRow(),
            const SizedBox(height: 16),

            // Brutalist custom painted line chart
            SizedBox(
              height: 160,
              child: CustomPaint(
                painter: BrutalistChartPainter(points: history),
                child: Container(),
              ),
            ),
          ],

          if (product.asin != null && product.asin!.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: Color(0xFFE7E8F0)),
            const SizedBox(height: 6),
            // Keepa redirect link
            GestureDetector(
              onTap: () {
                final keepaUrl = 'https://keepa.com/#!product/10-${product.asin!.toUpperCase()}';
                _launchUrl(keepaUrl);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // Keepa trend line drawing simulated with icons
                      Icon(
                        Icons.trending_up_outlined,
                        size: 20,
                        color: const Color(0xFF6C47FF).withOpacity(0.85),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'See Full Price History on Keepa',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: Color(0xFF1A1D2E),
                        ),
                      ),
                    ],
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF6E7385)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatRow() {
    final prices = widget.product.priceHistory.map((p) => p.price).toList();
    final lowest = prices.reduce(math.min);
    final highest = prices.reduce(math.max);
    final current = prices.last;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildStatCol('Lowest', lowest, isLowest: true),
        _buildStatCol('Current', current),
        _buildStatCol('Highest', highest, isHighest: true),
      ],
    );
  }

  Widget _buildStatCol(String label, double value, {bool isLowest = false, bool isHighest = false}) {
    Color valColor = const Color(0xFF1A1D2E);
    if (isLowest) valColor = const Color(0xFF12925A); // Green
    if (isHighest) valColor = const Color(0xFFE94444); // Red

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontWeight: FontWeight.w500,
            fontSize: 10,
            color: Color(0xFF6E7385),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '₹${value.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
          style: TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: valColor,
          ),
        ),
      ],
    );
  }

  // Static generic blurb options when highlights are placeholder
  static const List<String> _genericHighlights = [
    'Handpicked deal, verified live on Amazon at the time of posting.',
    'Discounted price shown is off the listed MRP — check the product page for the exact current price.',
    'Sold and delivered via Amazon India, so standard Amazon delivery, returns, and warranty terms apply.',
    'Review full specifications, size/variant options, and buyer ratings on Amazon before purchasing.',
    'Deal prices and stock can change anytime, so grab it while it lasts.',
    'One of our daily-curated picks across electronics, fashion, home, beauty, and health deals.'
  ];
}

// ── Brutalist Custom Chart Painter ──
class BrutalistChartPainter extends CustomPainter {
  final List<PricePoint> points;

  BrutalistChartPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final prices = points.map((pt) => pt.price).toList();
    final lowest = prices.reduce(math.min);
    final highest = prices.reduce(math.max);

    // Padding margins
    const padL = 60.0;
    const padR = 16.0;
    const padT = 20.0;
    const padB = 34.0;

    final plotW = size.width - padL - padR;
    final plotH = size.height - padT - padB;

    final yMin = lowest == highest ? lowest - 1.0 : lowest;
    final yMax = lowest == highest ? highest + 1.0 : highest;

    // Helper functions mapping data coordinate points to custom canvas vectors
    double xFor(int i) => padL + (points.length == 1 ? 0 : (plotW * i) / (points.length - 1));
    double yFor(double v) => padT + plotH - ((v - yMin) / (yMax - yMin)) * plotH;

    // 1. Draw Grid Axis Lines (brutalist style: bold, sharp corners)
    final axisPaint = Paint()
      ..color = const Color(0xFF1A1D2E)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(const Offset(padL, padT), Offset(padL, padT + plotH), axisPaint);
    canvas.drawLine(Offset(padL, padT + plotH), Offset(padL + plotW, padT + plotH), axisPaint);

    // 2. Render Text Labels (Min / Max Prices)
    final textPainterMax = TextPainter(
      text: TextSpan(
        text: '₹${yMax.toInt()}',
        style: const TextStyle(
          color: Color(0xFF1A1D2E),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    textPainterMax.paint(
      canvas,
      Offset(padL - textPainterMax.width - 8, padT - textPainterMax.height / 2),
    );

    final textPainterMin = TextPainter(
      text: TextSpan(
        text: '₹${yMin.toInt()}',
        style: const TextStyle(
          color: Color(0xFF1A1D2E),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    textPainterMin.paint(
      canvas,
      Offset(padL - textPainterMin.width - 8, padT + plotH - textPainterMin.height / 2),
    );

    // Render Date Label at start of history
    final firstDateStr = _formatDate(points.first.date);
    final textPainterDate = TextPainter(
      text: TextSpan(
        text: firstDateStr,
        style: const TextStyle(
          color: Color(0xFF6B7280),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    textPainterDate.paint(
      canvas,
      Offset(padL, size.height - textPainterDate.height - 4),
    );

    // 3. Draw Price Polyline connecting all points
    final linePaint = Paint()
      ..color = const Color(0xFF6C47FF)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.miter
      ..strokeCap = StrokeCap.square;

    final path = Path();
    path.moveTo(xFor(0), yFor(points[0].price));
    for (int i = 1; i < points.length; i++) {
      path.lineTo(xFor(i), yFor(points[i].price));
    }
    canvas.drawPath(path, linePaint);

    // 4. Draw Square Point Markers
    final markerFillPaint = Paint()..color = const Color(0xFF6C47FF);
    final markerStrokePaint = Paint()
      ..color = const Color(0xFF1A1D2E)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      final x = xFor(i);
      final y = yFor(points[i].price);
      final rect = Rect.fromCenter(center: Offset(x, y), width: 8, height: 8);
      
      canvas.drawRect(rect, markerFillPaint);
      canvas.drawRect(rect, markerStrokePaint);
    }
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]}';
  }

  @override
  bool shouldRepaint(covariant BrutalistChartPainter oldDelegate) => true;
}
