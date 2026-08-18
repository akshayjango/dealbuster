import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/svg_icons.dart';
import 'deal_badges.dart';

/// The deal card used across the home grid and search results.
/// Tapping anywhere opens the detail sheet; the Amazon CTA itself lives
/// there, keeping the grid a browsing surface rather than a tap-trap.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onNetworkError,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onNetworkError;

  @override
  Widget build(BuildContext context) {
    final discountPct = int.tryParse(
          product.disc.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: cardShadow(opacity: 0.7),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(10),
                      child: CachedNetworkImage(
                        imageUrl: product.image,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const _ImageSkeleton(),
                        errorWidget: (context, url, error) {
                          final errStr = error.toString().toLowerCase();
                          if (errStr.contains('socketexception') ||
                              errStr.contains('failed host lookup') ||
                              errStr.contains('network') ||
                              errStr.contains('connection')) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              onNetworkError?.call();
                            });
                          }
                          return const Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.ink400,
                          );
                        },
                      ),
                    ),
                  ),
                  if (discountPct > 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: SizedBox(
                        width: 36,
                        height: 35.6,
                        child: Stack(
                          children: [
                            SvgPicture.string(
                              SvgIcons.discountBadge,
                              width: 36,
                              height: 35.6,
                            ),
                            Positioned(
                              top: 7,
                              left: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$discountPct%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      height: 1.0,
                                    ),
                                  ),
                                  const Text(
                                    'OFF',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fixed to exactly 2 lines' height regardless of how many
                  // lines the title actually takes, so the price row below
                  // lands in the same spot for both 1- and 2-line titles.
                  SizedBox(
                    height: 11 * 1.4 * 2,
                    child: Text(
                      product.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        product.price,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (product.mrp != product.price) ...[
                        const SizedBox(width: 6),
                        Text(
                          product.mrp,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                decoration: TextDecoration.lineThrough,
                              ),
                        ),
                      ],
                    ],
                  ),
                  if (product.lowestPriceText != null &&
                      product.lowestPriceText!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    const LowestPriceBadge(),
                  ] else if (product.couponPercent != null) ...[
                    const SizedBox(height: 3),
                    CouponBadge(percent: product.couponPercent!),
                  ] else if (product.savingsAmount > 0) ...[
                    const SizedBox(height: 7),
                    Text(
                      'You save ₹${product.savingsAmount}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageSkeleton extends StatelessWidget {
  const _ImageSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.hairline,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
}
