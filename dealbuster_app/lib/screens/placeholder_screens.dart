import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'feed_screen.dart';

class StoresPlaceholderScreen extends StatelessWidget {
  const StoresPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTabScaffold(
      title: 'Stores',
      icon: Icons.storefront_rounded,
      headline: 'Store Deals & Coupons',
      description:
          'Browse handpicked deals and offers organized by your favorite online stores like Amazon, Flipkart, Myntra, and more.',
    );
  }
}

class OffersPlaceholderScreen extends StatelessWidget {
  const OffersPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTabScaffold(
      title: 'Offers',
      icon: Icons.confirmation_number_rounded,
      headline: 'Exclusive Offers & Steals',
      description:
          'Discover lightning deals, bank discounts, special coupon vouchers, and limited-time mega price drops.',
    );
  }
}

class FeedPlaceholderScreen extends StatelessWidget {
  const FeedPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeedScreen();
  }
}

class _PlaceholderTabScaffold extends StatelessWidget {
  const _PlaceholderTabScaffold({
    required this.title,
    required this.icon,
    required this.headline,
    required this.description,
  });

  final String title;
  final IconData icon;
  final String headline;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.6),
          child: Container(
            color: AppColors.cardStroke,
            height: 0.6,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.cardStroke, width: 0.6),
              boxShadow: cardShadow(),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      color: AppColors.brand,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.ink700,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: const Text(
                    'Coming Soon',
                    style: TextStyle(
                      color: AppColors.brand,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
