import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/banner_item.dart';
import 'hero_banner.dart';
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
    final theme = _getStoreTheme(banner);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      constraints: const BoxConstraints(minHeight: 160),
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
                        template: banner.template,
                        accentColor: theme.accentColor,
                      ),
                    ),
                  ),

                  // Radial light effect behind product image
                  if (theme.radialLight != null)
                    Positioned(
                      right: 6,
                      bottom: 12,
                      top: 22,
                      width: MediaQuery.of(context).size.width * 0.44,
                      child: Center(
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: theme.radialLight,
                          ),
                        ),
                      ),
                    ),

                  // Right-side product image (lifted up from bottom)
                  if (banner.fullImageUrl.isNotEmpty)
                    Positioned(
                      right: 6,
                      bottom: 12,
                      top: 22,
                      width: MediaQuery.of(context).size.width * 0.44,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: CachedNetworkImage(
                          imageUrl: banner.fullImageUrl,
                          fit: BoxFit.contain,
                          fadeInDuration: const Duration(milliseconds: 150),
                          fadeOutDuration: const Duration(milliseconds: 150),
                          placeholder: (_, __) => const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
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

                  // Top-right Deal badge (ribbon coming from the card's right edge, square right corners)
                  if (banner.badgeText != null &&
                      banner.badgeText!.trim().isNotEmpty)
                    Positioned(
                      top: 12,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.only(
                          left: 9,
                          right: 11,
                          top: 3.5,
                          bottom: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: theme.badgeBgColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            bottomLeft: Radius.circular(6),
                            topRight: Radius.zero,
                            bottomRight: Radius.zero,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 5,
                              offset: const Offset(-1, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          banner.badgeText!.trim().toUpperCase(),
                          style: GoogleFonts.sora(
                            color: theme.badgeTextColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),

                  // Content layer
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Store logo pill (smaller size and 6px rounded corners)
                        Container(
                          height: 24,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _buildStoreLogo(banner.storeKey, banner.storeName),
                        ),

                        const SizedBox(height: 12),

                        // Text Lines column (centered vertically, sits higher up)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.52,
                            minHeight: 96,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: banner.lines.map((line) {
                              if (line.text.trim().isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  line.text.trim(),
                                  style: line.isBig
                                      ? GoogleFonts.sora(
                                          color: Colors.white,
                                          fontSize: 23,
                                          fontWeight: FontWeight.w800,
                                          height: 1.12,
                                          letterSpacing: -0.3,
                                          shadows: const [
                                            Shadow(
                                              color: Color(0x33000000),
                                              offset: Offset(0, 1),
                                              blurRadius: 3,
                                            ),
                                          ],
                                        )
                                      : GoogleFonts.inter(
                                          color: Colors.white.withValues(alpha: 0.95),
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.22,
                                          letterSpacing: -0.1,
                                          shadows: const [
                                            Shadow(
                                              color: Color(0x26000000),
                                              offset: Offset(0, 1),
                                              blurRadius: 2,
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
          height: 13,
          fit: BoxFit.contain,
        );
      case 'flipkart':
        return SvgPicture.string(
          StoreBannerSvgs.flipkart,
          height: 13,
          fit: BoxFit.contain,
        );
      case 'ajio':
        return SvgPicture.string(
          StoreBannerSvgs.ajio,
          height: 11,
          fit: BoxFit.contain,
        );
      case 'amazon':
        return SvgPicture.string(
          StoreBannerSvgs.amazon,
          height: 13,
          fit: BoxFit.contain,
        );
      case 'nykaa':
        return Text(
          'NYKAA',
          style: GoogleFonts.sora(
            color: const Color(0xFFBE185D),
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        );
      case 'shopsy':
        return Text(
          'shopsy',
          style: GoogleFonts.sora(
            color: const Color(0xFFEA580C),
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        );
      case 'meesho':
        return Text(
          'meesho',
          style: GoogleFonts.sora(
            color: const Color(0xFF6B21A8),
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        );
      case 'tatacliq':
        return RichText(
          text: TextSpan(
            text: 'TATA ',
            style: GoogleFonts.sora(
              color: const Color(0xFF1C1917),
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
            ),
            children: [
              TextSpan(
                text: 'CLiQ',
                style: GoogleFonts.sora(
                  color: const Color(0xFFC2410C),
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        );
      case 'dealbuster':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/icons/dealbuster_logo.svg',
              height: 14,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 4),
            Text(
              'DealBuster',
              style: GoogleFonts.sora(
                color: const Color(0xFF1E293B),
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        );
      default:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.storefront_rounded,
              size: 13,
              color: Color(0xFF1E293B),
            ),
            const SizedBox(width: 4),
            Text(
              fallbackName,
              style: GoogleFonts.sora(
                color: const Color(0xFF1E293B),
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        );
    }
  }

  _StoreTheme _getStoreTheme(BannerItem banner) {
    if (banner.colors.length >= 2) {
      final parsedColors = banner.colors
          .map((c) => parseHexColor(c))
          .whereType<Color>()
          .toList();
      if (parsedColors.length >= 2) {
        Color? badgeBg = parseHexColor(banner.badgeBg);
        Color? badgeTextColor = parseHexColor(banner.badgeTextColor);
        RadialGradient? radialLight;
        if (banner.radialColor != null && banner.radialColor!.isNotEmpty) {
          final rc = parseHexColor(banner.radialColor) ?? Colors.white;
          radialLight = RadialGradient(
            colors: [rc.withValues(alpha: 0.5), Colors.transparent],
            stops: const [0.0, 0.8],
          );
        }
        return _StoreTheme(
          gradient: LinearGradient(
            colors: parsedColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: parsedColors.first,
          accentColor: Colors.white,
          textColor: const Color(0xFF111827),
          badgeBgColor: badgeBg ?? Colors.white,
          badgeTextColor: badgeTextColor ?? const Color(0xFF111827),
          radialLight: radialLight,
        );
      }
    }

    final hTpl = getHomeBannerTemplate(banner.template);
    if (hTpl != null) {
      return _StoreTheme(
        gradient: hTpl.gradient,
        shadowColor: hTpl.gradient.colors.first,
        accentColor: Colors.white,
        textColor: const Color(0xFF111827),
        badgeBgColor: hTpl.badgeBg,
        badgeTextColor: hTpl.badgeTextColor,
        radialLight: hTpl.radialLight,
      );
    }

    switch (banner.template.toLowerCase()) {
      // Flipkart templates
      case 'flipkart':
      case 'flipkart_1':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF1E40AF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFF1D4ED8),
          accentColor: Color(0xFF60A5FA),
          textColor: Color(0xFF1E3A8A),
          badgeBgColor: Color(0xFFFF2E63),
          badgeTextColor: Colors.white,
        );
      case 'flipkart_2':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFF0284C7), Color(0xFF0369A1), Color(0xFF075985)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFF0369A1),
          accentColor: Color(0xFF38BDF8),
          textColor: Color(0xFF075985),
          badgeBgColor: Color(0xFFFF2E63),
          badgeTextColor: Colors.white,
        );
      case 'flipkart_3':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8), Color(0xFF172554)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFF1D4ED8),
          accentColor: Color(0xFF93C5FD),
          textColor: Color(0xFF172554),
          badgeBgColor: Color(0xFFFF2E63),
          badgeTextColor: Colors.white,
        );
      case 'flipkart_light':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF3B82F6), Color(0xFFFFFFFF)],
            stops: [0.0, 0.40, 0.90],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFF2563EB),
          accentColor: Color(0xFF93C5FD),
          textColor: Color(0xFF1E3A8A),
          badgeBgColor: Color(0xFF1E40AF),
          badgeTextColor: Colors.white,
        );

      // Amazon templates - Golden amber and warm, NO dark brown
      case 'amazon':
      case 'amazon_1':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFFFFB300), Color(0xFFFB8C00), Color(0xFFE65100)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFFFB8C00),
          accentColor: Color(0xFFFFF176),
          textColor: Color(0xFF7C2D12),
          badgeBgColor: Color(0xFF131921),
          badgeTextColor: Color(0xFFFF9900),
        );
      case 'amazon_2':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFFFFA000), Color(0xFFFF6D00), Color(0xFFDD2C00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFFFF6D00),
          accentColor: Color(0xFFFFE082),
          textColor: Color(0xFF7C2D12),
          badgeBgColor: Color(0xFF131921),
          badgeTextColor: Color(0xFFFF9900),
        );
      case 'amazon_3':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFFFFC107), Color(0xFFFFA000), Color(0xFFF57C00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFFFFA000),
          accentColor: Color(0xFFFFF59D),
          textColor: Color(0xFF7C2D12),
          badgeBgColor: Color(0xFF131921),
          badgeTextColor: Color(0xFFFF9900),
        );
      case 'amazon_light':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFFFF9900), Color(0xFFFFB74D), Color(0xFFFFFFFF)],
            stops: [0.0, 0.38, 0.88],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFFFF9900),
          accentColor: Color(0xFFFFE082),
          textColor: Color(0xFF7C2D12),
          badgeBgColor: Color(0xFF131921),
          badgeTextColor: Color(0xFFFF9900),
        );

      // Myntra templates
      case 'myntra':
      case 'myntra_1':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFFFF1768), Color(0xFFE11D48), Color(0xFFBE123C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFFE11D48),
          accentColor: Colors.white,
          textColor: Color(0xFF111827),
          badgeBgColor: Color(0xFF9F1239),
          badgeTextColor: Colors.white,
        );
      case 'myntra_2':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFFFB7185), Color(0xFFE11D48), Color(0xFF9F1239)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFFE11D48),
          accentColor: Colors.white,
          textColor: Color(0xFF111827),
          badgeBgColor: Color(0xFF881337),
          badgeTextColor: Colors.white,
        );
      case 'myntra_3':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFFFF2A6D), Color(0xFFD91B5C), Color(0xFF881337)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFFD91B5C),
          accentColor: Colors.white,
          textColor: Color(0xFF111827),
          badgeBgColor: Color(0xFF4C0519),
          badgeTextColor: Colors.white,
        );
      case 'myntra_light':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFFFF1768), Color(0xFFFB7185), Color(0xFFFFFFFF)],
            stops: [0.0, 0.38, 0.88],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFFE11D48),
          accentColor: Colors.white,
          textColor: Color(0xFF111827),
          badgeBgColor: Color(0xFF9F1239),
          badgeTextColor: Colors.white,
        );

      // AJIO templates
      case 'ajio':
      case 'ajio_1':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFF475569), Color(0xFF334155), Color(0xFF1E293B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFF1E293B),
          accentColor: Color(0xFF94A3B8),
          textColor: Color(0xFF1E293B),
          badgeBgColor: Color(0xFF0F172A),
          badgeTextColor: Colors.white,
        );
      case 'ajio_2':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFF3B4B5E), Color(0xFF263545), Color(0xFF141E28)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFF141E28),
          accentColor: Color(0xFF94A3B8),
          textColor: Color(0xFF141E28),
          badgeBgColor: Color(0xFF0A1017),
          badgeTextColor: Colors.white,
        );
      case 'ajio_3':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFF334155), Color(0xFF1E293B), Color(0xFF0F172A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFF0F172A),
          accentColor: Color(0xFF64748B),
          textColor: Color(0xFF0F172A),
          badgeBgColor: Color(0xFF020617),
          badgeTextColor: Colors.white,
        );
      case 'ajio_light':
        return const _StoreTheme(
          gradient: LinearGradient(
            colors: [Color(0xFF334155), Color(0xFF64748B), Color(0xFFFFFFFF)],
            stops: [0.0, 0.38, 0.88],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: Color(0xFF1E293B),
          accentColor: Color(0xFF94A3B8),
          textColor: Color(0xFF1E293B),
          badgeBgColor: Color(0xFF0F172A),
          badgeTextColor: Colors.white,
        );

      default:
        final sKey = banner.storeKey.isNotEmpty
            ? banner.storeKey
            : (banner.template.contains('_') ? banner.template.split('_')[0] : banner.template);
        if (sKey != banner.template && sKey.isNotEmpty) {
          return _getStoreTheme(BannerItem(
            id: banner.id,
            store: sKey,
            template: '${sKey}_1',
            storeName: banner.storeName,
            lines: banner.lines,
            imageUrl: banner.imageUrl,
            link: banner.link,
          ));
        }
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
    this.radialLight,
  });

  final LinearGradient gradient;
  final Color shadowColor;
  final Color accentColor;
  final Color textColor;
  final Color badgeBgColor;
  final Color badgeTextColor;
  final RadialGradient? radialLight;
}

class _BannerBackgroundPainter extends CustomPainter {
  const _BannerBackgroundPainter({
    required this.template,
    required this.accentColor,
  });

  final String template;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    switch (template.toLowerCase()) {
      // --- FLIPKART TEMPLATES ---
      case 'flipkart':
      case 'flipkart_1':
        // Soft ambient radial glow on the right, no diagonal lines
        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.14),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.78, size.height * 0.5),
              radius: size.width * 0.45,
            ),
          );
        canvas.drawCircle(
          Offset(size.width * 0.78, size.height * 0.5),
          size.width * 0.45,
          glowPaint,
        );
        break;

      case 'flipkart_2':
        // Curved subtle wave arc aura
        final arcPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 32;
        canvas.drawCircle(
          Offset(size.width * 0.9, size.height * 1.1),
          size.width * 0.55,
          arcPaint,
        );
        final arcPaint2 = Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20;
        canvas.drawCircle(
          Offset(size.width * 0.9, size.height * 1.1),
          size.width * 0.75,
          arcPaint2,
        );
        break;

      case 'flipkart_3':
        // Modern micro-dot grid on top-left
        final dotPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.1)
          ..style = PaintingStyle.fill;
        for (double x = 12; x < size.width * 0.4; x += 16) {
          for (double y = 12; y < size.height * 0.55; y += 16) {
            canvas.drawCircle(Offset(x, y), 1.4, dotPaint);
          }
        }
        break;

      // --- AMAZON TEMPLATES (Warm, radiant golden amber - NO dark brown) ---
      case 'amazon':
      case 'amazon_1':
        // Warm golden radial glow behind product area
        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFF9C4).withValues(alpha: 0.28),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.78, size.height * 0.55),
              radius: size.width * 0.42,
            ),
          );
        canvas.drawCircle(
          Offset(size.width * 0.78, size.height * 0.55),
          size.width * 0.42,
          glowPaint,
        );
        break;

      case 'amazon_2':
        // Soft concentric warm golden aura rings
        final ringPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(
          Offset(size.width * 0.8, size.height * 0.55),
          65,
          ringPaint,
        );
        canvas.drawCircle(
          Offset(size.width * 0.8, size.height * 0.55),
          95,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.07)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        break;

      case 'amazon_3':
        // Ambient sunburst corner glow & micro dots
        final dotPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.14)
          ..style = PaintingStyle.fill;
        for (double x = 10; x < size.width * 0.38; x += 15) {
          for (double y = 10; y < size.height * 0.5; y += 15) {
            canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
          }
        }
        final glowPaint3 = Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFE082).withValues(alpha: 0.22),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.82, size.height * 0.6),
              radius: 80,
            ),
          );
        canvas.drawCircle(
          Offset(size.width * 0.82, size.height * 0.6),
          80,
          glowPaint3,
        );
        break;

      // --- MYNTRA TEMPLATES ---
      case 'myntra':
      case 'myntra_1':
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

      case 'myntra_2':
        // Soft ambient pink glow
        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.2),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.78, size.height * 0.55),
              radius: size.width * 0.4,
            ),
          );
        canvas.drawCircle(
          Offset(size.width * 0.78, size.height * 0.55),
          size.width * 0.4,
          glowPaint,
        );
        break;

      case 'myntra_3':
        // Subtle diagonal wave contour
        final wavePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24;
        canvas.drawCircle(
          Offset(size.width * 0.85, size.height * 1.0),
          size.width * 0.6,
          wavePaint,
        );
        break;

      // --- AJIO TEMPLATES ---
      case 'ajio':
      case 'ajio_1':
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

      case 'ajio_2':
        // Clean radial moonlight glow
        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.12),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.78, size.height * 0.55),
              radius: 90,
            ),
          );
        canvas.drawCircle(
          Offset(size.width * 0.78, size.height * 0.55),
          90,
          glowPaint,
        );
        break;

      case 'ajio_3':
        // Subtle concentric steel rings
        final ringPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(
          Offset(size.width * 0.82, size.height * 0.5),
          70,
          ringPaint,
        );
        canvas.drawCircle(
          Offset(size.width * 0.82, size.height * 0.5),
          110,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.05)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _BannerBackgroundPainter oldDelegate) {
    return oldDelegate.template != template;
  }
}
