import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/svg_icons.dart';
import '../widgets/deal_badges.dart';

const _kSheetHeightFactor = 0.83;

/// Opens [ProductDetailScreen] as a bottom sheet, with a compact close
/// button floating over the sheet's top edge instead of a drag handle.
///
/// Built on [showGeneralDialog] rather than [showModalBottomSheet] so the
/// blurred backdrop can fade in/out on its own, independent of the sheet's
/// slide — with showModalBottomSheet, the backdrop lived inside the same
/// slide-animated content as the sheet and visibly slid down with it on
/// dismiss instead of just disappearing.
void showProductDetailSheet(BuildContext context, Product product) {
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 300),
    // We drive the fade (backdrop) and slide (sheet) ourselves from the same
    // `animation` inside pageBuilder, so skip the framework's own default
    // transition here or it'd fade the whole thing a second time.
    transitionBuilder: (context, animation, secondaryAnimation, child) => child,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final sheetHeight =
          MediaQuery.of(dialogContext).size.height * _kSheetHeightFactor;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: animation,
              child: GestureDetector(
                onTap: () => Navigator.of(dialogContext).pop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(color: Colors.black.withValues(alpha: 0.35)),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: sheetHeight,
                    child: ProductDetailScreen(product: product),
                  ),
                  Positioned(
                    bottom: sheetHeight + 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _SheetCloseButton(
                        onTap: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(11),
          child: SvgIcon(SvgIcons.close, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

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
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  // Keepa's price history opens in an in-app browser tab (Chrome Custom
  // Tabs / SFSafariViewController) rather than a full external-app switch —
  // it's a quick reference link, not a destination like Amazon/Telegram.
  Future<void> _launchInApp(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      debugPrint('Error launching in-app URL: $e');
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

    // This screen uses Inter throughout rather than the Sora display font
    // used elsewhere in the app — overriding both the theme's textTheme
    // (for Text widgets built from it) and the ambient DefaultTextStyle
    // (for the few with a raw, font-family-less TextStyle) covers every
    // label in this subtree.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
      data: Theme.of(context).copyWith(
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
      ),
      child: DefaultTextStyle.merge(
        style: GoogleFonts.inter(),
        child: Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
              Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.lg,
                AppSpace.md,
                AppSpace.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ImageBlock(product: p, discountPct: discountPct, onShare: _share),
                  const SizedBox(height: AppSpace.lg),
                  _ClampedTitle(
                    text: p.displayTitle,
                    maxLines: 3,
                    // Built directly (not via titleLarge.copyWith) — deriving
                    // from a style GoogleFonts already resolved at weight 800
                    // didn't reliably swap in the regular-weight font file,
                    // so it kept rendering bold despite fontWeight: w400.
                    style: GoogleFonts.inter(
                      color: AppColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _PriceRow(product: p),
                  (() {
                    final linkLower = p.link.toLowerCase();
                    final isFlipkart = linkLower.contains('flipkart.com') || linkLower.contains('fkrt.it') || linkLower.contains('fktr.in');
                    
                    List<String> highlightsToRender = p.highlights;
                    if (highlightsToRender.isEmpty && isFlipkart) {
                      highlightsToRender = [
                        'Handpicked deal, verified live on Flipkart at the time of posting.',
                        'Discounted price shown is off the listed MRP - check the product page for the exact current price',
                      ];
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (highlightsToRender.isNotEmpty) ...[
                          const SizedBox(height: AppSpace.lg),
                          _Card(
                            title: 'Highlights',
                            child: _Highlights(
                              highlights: highlightsToRender,
                              expanded: _highlightsExpanded,
                              onToggle: () => setState(
                                () => _highlightsExpanded = !_highlightsExpanded,
                              ),
                            ),
                          ),
                        ],
                        if (!isFlipkart && p.asin.isNotEmpty) ...[
                          const SizedBox(height: AppSpace.md),
                          _Card(
                            title: 'Price History',
                            child: _PriceHistory(product: p, onOpenKeepa: _launchInApp),
                          ),
                        ],
                      ],
                    );
                  })(),
                ],
              ),
            ),
          ),
          _BuyBar(link: p.link, onBuy: () => _launch(p.link)),
        ],
      ),
        ),
      ),
      ),
    );
  }
}

/// Clamps [text] to [maxLines] on whole-word boundaries, then drops a
/// trailing word if it's a dangling fragment — lone punctuation, a bare
/// number, "(" running into a number, or a connector (and/with/for/to/from
/// etc.) — so a 2-line-clipped title never ends mid-thought on something
/// like "...P1007," or "...Printer for".
class _ClampedTitle extends StatelessWidget {
  const _ClampedTitle({
    required this.text,
    required this.style,
    required this.maxLines,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  static const _connectors = {
    'and', 'with', 'for', 'to', 'from', 'of', 'in', 'on', 'the', 'a', 'an',
    'or', '&',
  };
  static const _trailingPunctuation = {
    '-', ',', '/', '|', '(', ';', '.', '—',
  };

  static bool _isDanglingWord(String word) {
    if (word.isEmpty) return true;
    // No letters at all — a bare number, lone punctuation, or any mix of
    // the two ("7-", "(2023", "1007,") — none of it reads as a finished
    // thought on its own.
    if (!RegExp(r'[A-Za-z]').hasMatch(word)) return true;
    final letters = word.replaceAll(RegExp(r'[^A-Za-z]'), '').toLowerCase();
    return _connectors.contains(letters);
  }

  static String _dropDanglingTail(String fitted) {
    final words = fitted.split(' ');
    while (words.isNotEmpty && _isDanglingWord(words.last)) {
      words.removeLast();
    }
    var result = words.join(' ');
    while (result.isNotEmpty &&
        _trailingPunctuation.contains(result[result.length - 1])) {
      result = result.substring(0, result.length - 1).trimRight();
    }
    return result.isEmpty ? fitted : result;
  }

  bool _fitsWithin(String candidate, double maxWidth, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: candidate, style: style),
      maxLines: maxLines,
      textDirection: direction,
    )..layout(maxWidth: maxWidth);
    return !painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_fitsWithin(text, constraints.maxWidth, direction)) {
          return Text(text, style: style);
        }

        final words = text.split(' ');
        var fitted = text;
        for (var count = words.length - 1; count > 0; count--) {
          final candidate = words.sublist(0, count).join(' ');
          if (_fitsWithin(candidate, constraints.maxWidth, direction)) {
            fitted = candidate;
            break;
          }
        }

        return Text(
          _dropDanglingTail(fitted),
          style: style,
          // Safety net for the pathological single-word-too-wide case,
          // where the fit-search above can't shrink below whole words.
          maxLines: maxLines,
          overflow: TextOverflow.clip,
        );
      },
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: cardShadow(),
              ),
            ),
          ),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: CachedNetworkImage(
                        imageUrl: product.image,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  if (discountPct > 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: SizedBox(
                        width: 48,
                        height: 47.6,
                        child: Stack(
                          children: [
                            SvgPicture.string(
                              SvgIcons.discountBadge,
                              width: 48,
                              height: 47.6,
                            ),
                            Positioned(
                              top: 10,
                              left: 10,
                              child: DefaultTextStyle.merge(
                                style: GoogleFonts.inter(),
                                child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$discountPct%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      height: 1.0,
                                    ),
                                  ),
                                  const Text(
                                    'OFF',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 14,
            right: 14,
            child: _RoundIconButton(
              onTap: onShare,
              child: const SvgIcon(SvgIcons.share, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: cardShadow(opacity: 0.5),
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            color: AppColors.ink.withValues(alpha: 0.55),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Center(
                child: child,
              ),
            ),
          ),
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
    // This row (price, MRP, savings pill) keeps the app's original
    // Sora/Inter styling rather than this screen's ambient Inter override.
    return Theme(
      data: AppTheme.light,
      child: DefaultTextStyle.merge(
        style: GoogleFonts.inter(),
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          product.price,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 22,
              ),
        ),
        const SizedBox(width: 10),
        if (product.mrp != product.price)
          Text(
            product.mrp,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 17,
                  color: AppColors.ink400,
                  decoration: TextDecoration.lineThrough,
                ),
          ),
        if (product.lowestPriceText != null &&
            product.lowestPriceText!.isNotEmpty) ...[
          const SizedBox(width: 8),
          const LowestPriceBadge(fontSize: 12.5),
        ] else if (product.couponPercent != null) ...[
          const SizedBox(width: 8),
          CouponBadge(percent: product.couponPercent!, fontSize: 12.5),
        ] else if (product.savingsAmount > 0) ...[
          const SizedBox(width: 6),
          Text(
            'You save ₹${product.savingsAmount}',
            style: const TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ],
        ),
      ),
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: cardShadow(opacity: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 12.5,
                ),
          ),
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

  // Some feeds prefix highlight bullets with an emoji (✅, 🐄, etc.) — strip
  // it so bullets read as plain text, matching the rest of the app's copy.
  static final _leadingEmoji = RegExp(
    r'^[\u{1F1E6}-\u{1F1FF}\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2190}-\u{21FF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}\s]+',
    unicode: true,
  );

  static String _clean(String text) =>
      text.replaceFirst(_leadingEmoji, '').trimLeft();

  @override
  Widget build(BuildContext context) {
    final visible = expanded ? highlights : highlights.take(2).toList();
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
                  child: Text(
                    _clean(h),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 13,
                        ),
                  ),
                ),
              ],
            ),
          ),
        if (highlights.length > 2) ...[
          const SizedBox(height: 4),
          Center(
            child: OutlinedButton(
              onPressed: onToggle,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brand,
                side: const BorderSide(color: AppColors.hairline),
                padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    expanded ? 'Show less' : 'View more',
                    style: const TextStyle(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 1),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 14,
                    color: AppColors.brand,
                  ),
                ],
              ),
            ),
          ),
        ],
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
    final isAmazon = product.asin != null && product.asin!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isAmazon
              ? 'We track this deal\'s price around the clock — see the full trend, including past highs and lows, on Keepa.'
              : 'We started tracking this deal\'s price — check back later to see how it moves.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: 13,
              ),
        ),
        if (isAmazon) ...[
          const SizedBox(height: 16),
          const _DashedDivider(),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => onOpenKeepa(
              'https://keepa.com/#!product/10-${product.asin!.toUpperCase()}',
            ),
            child: Row(
              children: [
                const SvgIcon(SvgIcons.chart, size: 16, color: AppColors.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'See full price history on Keepa',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.brand,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.brand,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A thin dashed rule used to separate the blurb from the Keepa link.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 1,
      child: CustomPaint(painter: _DashedLinePainter()),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    final paint = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => false;
}

class _BuyBar extends StatefulWidget {
  const _BuyBar({required this.link, required this.onBuy});
  final String link;
  final VoidCallback onBuy;

  @override
  State<_BuyBar> createState() => _BuyBarState();
}

class _BuyBarState extends State<_BuyBar> {
  bool _isPressed = false;

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
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onBuy,
          child: AnimatedScale(
            scale: _isPressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF00B876), // Premium emerald green
                borderRadius: BorderRadius.circular(12), // Restored original rounded corner (12)
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00B876).withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    (() {
                      final l = widget.link.toLowerCase();
                      if (l.contains('flipkart.com') || l.contains('fkrt.it') || l.contains('fktr.in')) {
                        return 'Buy on Flipkart';
                      }
                      if (l.contains('myntra.com')) {
                        return 'Buy on Myntra';
                      }
                      if (l.contains('ajio.com')) {
                        return 'Buy on Ajio';
                      }
                      return 'Buy on Amazon';
                    })(),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_outward_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
