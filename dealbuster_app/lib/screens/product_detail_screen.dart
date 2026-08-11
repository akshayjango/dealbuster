import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';
import '../widgets/price_chart.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});
  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _highlightsExpanded = false;

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _share() {
    final p = widget.product;
    Share.share('${p.displayTitle} — spotted on DealBuster!\n${p.link}');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final discountPct =
        int.tryParse(p.disc.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.hairline,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.md,
                AppSpace.md,
                100,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ImageBlock(product: p, discountPct: discountPct, onShare: _share),
                  const SizedBox(height: AppSpace.lg),
                  Text(
                    p.category[0].toUpperCase() + p.category.substring(1),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.brand,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(p.displayTitle, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  _PriceRow(product: p),
                  if (p.highlights.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.lg),
                    _Card(
                      title: 'Highlights',
                      child: _Highlights(
                        highlights: p.highlights,
                        expanded: _highlightsExpanded,
                        onToggle: () => setState(
                          () => _highlightsExpanded = !_highlightsExpanded,
                        ),
                      ),
                    ),
                  ],
                  if (p.priceHistory.length >= 2) ...[
                    const SizedBox(height: AppSpace.md),
                    _Card(
                      title: 'Price History',
                      child: _PriceHistory(product: p, onOpenKeepa: _launch),
                    ),
                  ],
                  const SizedBox(height: AppSpace.md),
                  Text(
                    'Discounted price shown is off the listed MRP — check the product page on Amazon for the exact current price.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          _BuyBar(onBuy: () => _launch(p.link)),
        ],
      ),
    );
  }
}

class _ImageBlock extends StatelessWidget {
  const _ImageBlock({
    required this.product,
    required this.discountPct,
    required this.onShare,
  });

  final Product product;
  final int discountPct;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.15,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: cardShadow(),
              ),
              padding: const EdgeInsets.all(20),
              child: CachedNetworkImage(
                imageUrl: product.image,
                fit: BoxFit.contain,
              ),
            ),
          ),
          if (discountPct > 0)
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '$discountPct% OFF',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 14,
            right: 14,
            child: _RoundIconButton(icon: Icons.ios_share_rounded, onTap: onShare),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(product.price, style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(width: 10),
        if (product.mrp != product.price)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              product.mrp,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    decoration: TextDecoration.lineThrough,
                  ),
            ),
          ),
        const Spacer(),
        if (product.savingsAmount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.successSoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                'You save ₹${product.savingsAmount}',
                style: const TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: cardShadow(opacity: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights({
    required this.highlights,
    required this.expanded,
    required this.onToggle,
  });

  final List<String> highlights;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final visible = expanded ? highlights : highlights.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final h in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 5, color: AppColors.brand),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(h, style: Theme.of(context).textTheme.bodyLarge),
                ),
              ],
            ),
          ),
        if (highlights.length > 4)
          GestureDetector(
            onTap: onToggle,
            child: Text(
              expanded ? 'Show less' : 'View more',
              style: const TextStyle(
                color: AppColors.brand,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

class _PriceHistory extends StatelessWidget {
  const _PriceHistory({required this.product, required this.onOpenKeepa});
  final Product product;
  final Future<void> Function(String) onOpenKeepa;

  @override
  Widget build(BuildContext context) {
    final prices = product.priceHistory.map((p) => p.price).toList();
    final lowest = prices.reduce((a, b) => a < b ? a : b);
    final highest = prices.reduce((a, b) => a > b ? a : b);
    final current = prices.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Stat(label: 'Lowest', value: lowest, color: AppColors.success),
            _Stat(label: 'Current', value: current, color: AppColors.ink),
            _Stat(label: 'Highest', value: highest, color: AppColors.brand),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(height: 90, child: PriceChart(points: product.priceHistory)),
        if (product.asin != null && product.asin!.isNotEmpty) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => onOpenKeepa(
              'https://keepa.com/#!product/10-${product.asin!.toUpperCase()}',
            ),
            child: Row(
              children: [
                Text(
                  'See full price history on Keepa',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.brand,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_outward_rounded, size: 14, color: AppColors.brand),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '₹${value.toStringAsFixed(0)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _BuyBar extends StatelessWidget {
  const _BuyBar({required this.onBuy});
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 12, AppSpace.md, 20),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onBuy,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Buy on Amazon'),
                SizedBox(width: 8),
                Icon(Icons.arrow_outward_rounded, size: 17),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
