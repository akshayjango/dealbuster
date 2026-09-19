import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/banner_item.dart';
import 'store_banner_svgs.dart';

class StoreBannerCard extends StatelessWidget {
  const StoreBannerCard({
    super.key,
    required this.banner,
  });

  final BannerItem banner;

  Future<void> _openLink(BuildContext context) async {
    final link = banner.link.trim();
    if (link.isEmpty) return;

    try {
      final uri = Uri.parse(link);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: $link'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _getStoreTheme(banner.store);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openLink(context),
            splashColor: Colors.white.withValues(alpha: 0.15),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: Ink(
              decoration: BoxDecoration(
                gradient: theme.gradient,
              ),
              child: Stack(
                children: [
                  // Decorative background graphics
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BannerBackgroundPainter(
                        store: banner.store,
                        accentColor: theme.accentColor,
                      ),
                    ),
                  ),

                  // Right-side product image
                  if (banner.fullImageUrl.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 0,
                      top: 45,
                      width: MediaQuery.of(context).size.width * 0.44,
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Hero(
                          tag: 'banner_img_${banner.id}',
                          child: CachedNetworkImage(
                            imageUrl: banner.fullImageUrl,
                            fit: BoxFit.contain,
                            placeholder: (_, __) => const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),

                  // Content layer
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: Store badge + Deal badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Store logo pill
                            Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: _buildStoreLogo(banner.store, banner.storeName),
                            ),

                            // Top-right Deal badge (if provided)
                            if (banner.badgeText != null &&
                                banner.badgeText!.trim().isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4.5,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.badgeBgColor,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  banner.badgeText!.trim().toUpperCase(),
                                  style: TextStyle(
                                    color: theme.badgeTextColor,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 22),

                        // Text Lines column (takes left ~58% space)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.52,
                            minHeight: 110,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: banner.lines.map((line) {
                              if (line.text.trim().isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  line.text.trim(),
                                  style: line.isBig
                                      ? const TextStyle(
                                          color: Colors.white,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w900,
                                          height: 1.08,
                                          letterSpacing: -0.4,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black38,
                                              offset: Offset(0, 2),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        )
                                      : const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          height: 1.25,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black26,
                                              offset: Offset(0, 1),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreLogo(String store, String fallbackName) {
    switch (store.toLowerCase()) {
      case 'myntra':
        return SvgPicture.string(
          StoreBannerSvgs.myntra,
          height: 18,
          fit: BoxFit.contain,
        );
      case 'flipkart':
        return SvgPicture.string(
          StoreBannerSvgs.flipkart,
          height: 18,
          fit: BoxFit.contain,
        );
      case 'ajio':
        return SvgPicture.string(
          StoreBannerSvgs.ajio,
          height: 16,
          fit: BoxFit.contain,
        );
      case 'amazon':
        return SvgPicture.string(
          StoreBannerSvgs.amazon,
          height: 18,
          fit: BoxFit.contain,
        );
      default:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.storefront_rounded,
              size: 16,
              color: Color(0xFF1E293B),
            ),
            const SizedBox(width: 5),
            Text(
              fallbackName,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        );
    }
  }

  _StoreTheme _getStoreTheme(String store) {
    switch (store.toLowerCase()) {
      case 'myntra':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFFFF1768), Color(0xFFFA1368), Color(0xFFC2004F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFFFA1368),
          accentColor: Colors.white,
          textColor: Color(0xFF111827),
          badgeBgColor: Color(0xFFE50956),
          badgeTextColor: Colors.white,
        );
      case 'flipkart':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFF2B7CF6), Color(0xFF1A64E8), Color(0xFF0747BC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFF1A64E8),
          accentColor: Color(0xFF60A5FA),
          textColor: Color(0xFF1E3A8A),
          badgeBgColor: Color(0xFFFF2E63),
          badgeTextColor: Colors.white,
        );
      case 'ajio':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFF475569), Color(0xFF334155), Color(0xFF1E293B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFF1E293B),
          accentColor: Color(0xFF94A3B8),
          textColor: Color(0xFF1E293B),
          badgeBgColor: Color(0xFF1E293B),
          badgeTextColor: Colors.white,
        );
      case 'amazon':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFD97706), Color(0xFF78350F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFFB45309),
          accentColor: Color(0xFFFDE68A),
          textColor: Color(0xFF78350F),
          badgeBgColor: Color(0xFF131921),
          badgeTextColor: Color(0xFFFF9900),
        );
      default:
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF4F46E5), Color(0xFF3730A3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFF4F46E5),
          accentColor: Colors.white24,
          textColor: Color(0xFF111827),
          badgeBgColor: Colors.white,
          badgeTextColor: Color(0xFF111827),
        );
    }
  }
}

class _StoreTheme {
  const _StoreTheme({
    required this.gradient,
    required this.shadowColor,
    required this.accentColor,
    required this.textColor,
    required this.badgeBgColor,
    required this.badgeTextColor,
  });

  final LinearGradient gradient;
  final Color shadowColor;
  final Color accentColor;
  final Color textColor;
  final Color badgeBgColor;
  final Color badgeTextColor;
}

class _BannerBackgroundPainter extends CustomPainter {
  const _BannerBackgroundPainter({
    required this.store,
    required this.accentColor,
  });

  final String store;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    switch (store.toLowerCase()) {
      case 'myntra':
        // Halftone dot matrix pattern on top left
        final dotPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.14)
          ..style = PaintingStyle.fill;
        for (double x = 8; x < size.width * 0.38; x += 14) {
          for (double y = 8; y < size.height * 0.55; y += 14) {
            canvas.drawCircle(Offset(x, y), 1.6, dotPaint);
          }
        }
        break;

      case 'flipkart':
        // Diagonal translucent stripes
        final stripePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.08)
          ..strokeWidth = 14
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(size.width * 0.45, 0),
          Offset(size.width * 0.85, size.height),
          stripePaint,
        );
        canvas.drawLine(
          Offset(size.width * 0.65, 0),
          Offset(size.width * 1.05, size.height),
          stripePaint,
        );
        break;

      case 'ajio':
        // Subtle dot matrix in corner
        final dotPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.1)
          ..style = PaintingStyle.fill;
        for (double x = 12; x < size.width * 0.35; x += 16) {
          for (double y = 12; y < size.height * 0.6; y += 16) {
            canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
          }
        }
        break;

      case 'amazon':
        // Warm glow radial accent
        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFDE68A).withValues(alpha: 0.22),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.75, size.height * 0.7),
              radius: 90,
            ),
          );
        canvas.drawCircle(
          Offset(size.width * 0.75, size.height * 0.7),
          90,
          glowPaint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _BannerBackgroundPainter oldDelegate) {
    return oldDelegate.store != store;
  }
}
