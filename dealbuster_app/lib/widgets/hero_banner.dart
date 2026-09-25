import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/home_banner_item.dart';
import '../theme/app_theme.dart';
import 'store_banner_svgs.dart';

// ---------------------------------------------------------------- timing
class _Cues {
  static const intro = 0.0;
  static const bagIn = 0.35;
  static const products = 1.95;
  static const bagOut = 4.35;
  static const total = 6.0; // 6.0 seconds loop for the bag animation only
}

typedef _Ease = double Function(double);

double _easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();
double _easeInCubic(double t) => t * t * t;
double _easeOutBack(double t) {
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
}

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

double _anim(double t, double from, double to, double start, double dur, _Ease ease) {
  if (t <= start) return from;
  if (t >= start + dur) return to;
  return from + (to - from) * ease((t - start) / dur);
}

double _enter(double t, double from, double to, double start, [double dur = 0.7]) =>
    _anim(t, from, to, start, dur, _easeOutCubic);
double _pop(double t, double from, double to, double start, [double dur = 0.6]) =>
    _anim(t, from, to, start, dur, _easeOutBack);
double _exit(double t, double from, double to, double start, [double dur = 0.5]) =>
    _anim(t, from, to, start, dur, _easeInCubic);

// ---------------------------------------------------------------- palette
const _bg0 = Color(0xFF2B0F3F);
const _bg1 = Color(0xFF7A1E37);
const _bg2 = Color(0xFFC0341C);

class _Product {
  const _Product(this.asset, this.dx, this.dy, this.size, this.delay, this.rot);
  final String asset;
  final double dx, dy, size, delay, rot;
}

// Positions are on the 686 x 352 reference canvas, relative to the bag anchor.
const _products = <_Product>[
  _Product('assets/icons/sunscreen.svg', -89, -38, 56, 0.00, -12),
  _Product('assets/icons/headphones.svg', -43, -80, 58, 0.18, -8),
  _Product('assets/icons/clock.svg', 26, -60, 40, 0.36, 14),
  _Product('assets/icons/player.svg', 81, -54, 68, 0.54, 6),
];

class HeroBanner extends StatefulWidget {
  const HeroBanner({
    super.key,
    required this.liveDealCount,
    this.showDefaultAnimatedBanner = true,
    this.customBanners = const [],
  });

  final int liveDealCount;
  final bool showDefaultAnimatedBanner;
  final List<HomeBannerItem> customBanners;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final PageController _pageController;
  Timer? _timer;
  int _virtualPage = 0;

  int get _totalCount =>
      (widget.showDefaultAnimatedBanner ? 1 : 0) + widget.customBanners.length;

  int _getInitialVirtualPage(int count) {
    if (count <= 1) return 0;
    return count * 1000;
  }

  @override
  void initState() {
    super.initState();
    final count = _totalCount;
    _virtualPage = _getInitialVirtualPage(count);
    _pageController = PageController(initialPage: _virtualPage);
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000), // 6 seconds loop
    )..repeat();
    _startAutoSlide();
  }

  @override
  void didUpdateWidget(covariant HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCount = (oldWidget.showDefaultAnimatedBanner ? 1 : 0) +
        oldWidget.customBanners.length;
    final newCount = _totalCount;
    if (oldCount != newCount) {
      _virtualPage = _getInitialVirtualPage(newCount);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_virtualPage);
      }
      _startAutoSlide();
    }
  }

  void _startAutoSlide() {
    _timer?.cancel();
    if (_totalCount <= 1) return;
    // Increased duration to 6500ms so users have comfortable time to read each banner
    _timer = Timer.periodic(const Duration(milliseconds: 6500), (_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    _c.dispose();
    super.dispose();
  }

  Widget _buildDefaultAnimatedBanner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bg0, _bg1, _bg2],
        ),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        if (w <= 0) return const SizedBox();
        final s = w / 686.0; // reference canvas -> real px
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) => _Frame(
            t: _c.value * _Cues.total,
            s: s,
            w: w,
            h: 176.0,
            liveDealCount: widget.liveDealCount,
          ),
        );
      }),
    );
  }

  Widget _buildCustomBanner(HomeBannerItem banner) {
    return _CustomBannerCard(banner: banner);
  }

  Widget _buildBannerAt(int index) {
    if (widget.showDefaultAnimatedBanner) {
      if (index == 0) return _buildDefaultAnimatedBanner();
      return _buildCustomBanner(widget.customBanners[index - 1]);
    }
    return _buildCustomBanner(widget.customBanners[index]);
  }

  @override
  Widget build(BuildContext context) {
    final count = _totalCount;
    if (count == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.md,
        10,
        AppSpace.md,
        6,
      ),
      height: 176,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 5),
            spreadRadius: -3,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: count == 1
            ? _buildBannerAt(0)
            : NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification) {
                    _timer?.cancel();
                  } else if (notification is ScrollEndNotification) {
                    _startAutoSlide();
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (idx) {
                    _virtualPage = idx;
                  },
                  itemBuilder: (context, idx) => _buildBannerAt(idx % count),
                ),
              ),
      ),
    );
  }
}

class HomeBannerTemplate {
  const HomeBannerTemplate({
    required this.gradient,
    required this.badgeBg,
    required this.badgeTextColor,
    this.radialLight,
  });

  final LinearGradient gradient;
  final Color badgeBg;
  final Color badgeTextColor;
  final RadialGradient? radialLight;
}

HomeBannerTemplate? getHomeBannerTemplate(String template) {
  switch (template.toLowerCase()) {
    // Amazon
    case 'amazon_light':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFFEA580C), Color(0xFFF59E0B), Color(0xFFFFFFFF)],
          stops: [0.0, 0.34, 0.86],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF131921),
        badgeTextColor: Color(0xFFFF9900),
      );
    case 'amazon_warm':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFFFFB300), Color(0xFFFB8C00), Color(0xFFE65100)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF131921),
        badgeTextColor: Color(0xFFFF9900),
        radialLight: RadialGradient(
          colors: [Color(0x75FFEE58), Color(0x28FB8C00), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'amazon_prime_dark':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF002F6C), Color(0xFF00A8E1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF00A8E1),
        badgeTextColor: Color(0xFF0F172A),
        radialLight: RadialGradient(
          colors: [Color(0x7500A8E1), Color(0x30004D99), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'amazon_gif_royal':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF7F1D1D), Color(0xFFB91C1C), Color(0xFFF59E0B)],
          stops: [0.0, 0.45, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF78350F),
        radialLight: RadialGradient(
          colors: [Color(0x80FEF08A), Color(0x35F59E0B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'amazon_fire_tangerine':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF4C0519), Color(0xFFC2410C), Color(0xFFF97316)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFF7ED),
        badgeTextColor: Color(0xFF9A3412),
        radialLight: RadialGradient(
          colors: [Color(0x75FDBA74), Color(0x30EA580C), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'amazon_pay_emerald':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFECFDF5),
        badgeTextColor: Color(0xFF065F46),
        radialLight: RadialGradient(
          colors: [Color(0x78A7F3D0), Color(0x3010B981), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'amazon_fresh':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF14532D), Color(0xFF15803D), Color(0xFF84CC16)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFF7FEE7),
        badgeTextColor: Color(0xFF365314),
        radialLight: RadialGradient(
          colors: [Color(0x78D9F99D), Color(0x3084CC16), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'amazon_lightning':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF09090B), Color(0xFF18181B), Color(0xFF27272A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFBBF24),
        badgeTextColor: Color(0xFF18181B),
        radialLight: RadialGradient(
          colors: [Color(0x78FBBF24), Color(0x30F59E0B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );

    // Flipkart
    case 'flipkart_light':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6), Color(0xFFFFFFFF)],
          stops: [0.0, 0.34, 0.86],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFF2E63),
        badgeTextColor: Colors.white,
      );
    case 'flipkart_electric':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF0284C7), Color(0xFF0369A1), Color(0xFF075985)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFF2E63),
        badgeTextColor: Colors.white,
        radialLight: RadialGradient(
          colors: [Color(0x7538BDF8), Color(0x300284C7), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'flipkart_bbd_carnival':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF2E1065), Color(0xFF4C1D95), Color(0xFFF59E0B)],
          stops: [0.0, 0.45, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFDE047),
        badgeTextColor: Color(0xFF3B0764),
        radialLight: RadialGradient(
          colors: [Color(0x80FDE047), Color(0x38A855F7), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'flipkart_supercoin':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFFFBBF24)],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF1E3A8A),
        radialLight: RadialGradient(
          colors: [Color(0x80FEF08A), Color(0x382563EB), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'flipkart_neon_cyber':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF030712), Color(0xFF0F172A), Color(0xFF06B6D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF22D3EE),
        badgeTextColor: Color(0xFF0F172A),
        radialLight: RadialGradient(
          colors: [Color(0x8022D3EE), Color(0x3006B6D4), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'flipkart_sunset':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF7C3AED), Color(0xFFF43F5E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFE4E6),
        badgeTextColor: Color(0xFF9F1239),
        radialLight: RadialGradient(
          colors: [Color(0x75FB7185), Color(0x307C3AED), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'flipkart_grocery':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF065F46), Color(0xFF0284C7), Color(0xFF38BDF8)],
          stops: [0.0, 0.6, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFD1FAE5),
        badgeTextColor: Color(0xFF065F46),
        radialLight: RadialGradient(
          colors: [Color(0x786EE7B7), Color(0x300284C7), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'flipkart_festive_ruby':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF4C0519), Color(0xFF1E1B4B), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFECDD3),
        badgeTextColor: Color(0xFF881337),
        radialLight: RadialGradient(
          colors: [Color(0x65F43F5E), Color(0x353B82F6), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );

    // Myntra
    case 'myntra_light':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFFBE123C), Color(0xFFE11D48), Color(0xFFFFFFFF)],
          stops: [0.0, 0.34, 0.86],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF9F1239),
        badgeTextColor: Colors.white,
      );
    case 'myntra_vivid':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFFFF1768), Color(0xFFE11D48), Color(0xFFBE123C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF881337),
        badgeTextColor: Colors.white,
        radialLight: RadialGradient(
          colors: [Color(0x78FF71A3), Color(0x30E11D48), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'myntra_eors':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF831843), Color(0xFFDB2777), Color(0xFFF97316)],
          stops: [0.0, 0.45, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF831843),
        radialLight: RadialGradient(
          colors: [Color(0x78FEF08A), Color(0x3ADB2777), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'myntra_glam_gold':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF18181B), Color(0xFF27272A), Color(0xFF713F12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF451A03),
        radialLight: RadialGradient(
          colors: [Color(0x75FACC15), Color(0x30CA8A04), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'myntra_barbiecore':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFFEC4899), Color(0xFFF472B6), Color(0xFFC084FC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Colors.white,
        badgeTextColor: Color(0xFFBE185D),
        radialLight: RadialGradient(
          colors: [Color(0x90FFFFFF), Color(0x3CF472B6), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'myntra_streetwear':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF09090B), Color(0xFF18181B), Color(0xFF84CC16)],
          stops: [0.0, 0.6, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFA3E635),
        badgeTextColor: Color(0xFF18181B),
        radialLight: RadialGradient(
          colors: [Color(0x78A3E635), Color(0x3084CC16), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'myntra_pastel_chic':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFFF43F5E), Color(0xFFFB7185), Color(0xFFFED7AA)],
          stops: [0.0, 0.45, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Colors.white,
        badgeTextColor: Color(0xFF9F1239),
        radialLight: RadialGradient(
          colors: [Color(0x80FED7AA), Color(0x30FB7185), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'myntra_runway_purple':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF3B0764), Color(0xFF6B21A8), Color(0xFFD946EF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFAE8FF),
        badgeTextColor: Color(0xFF701A75),
        radialLight: RadialGradient(
          colors: [Color(0x75E879F9), Color(0x30A855F7), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );

    // AJIO
    case 'ajio_light':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF475569), Color(0xFFFFFFFF)],
          stops: [0.0, 0.36, 0.86],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF0F172A),
        badgeTextColor: Colors.white,
      );
    case 'ajio_midnight':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF334155), Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF020617),
        badgeTextColor: Colors.white,
        radialLight: RadialGradient(
          colors: [Color(0x6094A3B8), Color(0x30334155), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'ajio_all_stars':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF881337), Color(0xFFE2E8F0)],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Colors.white,
        badgeTextColor: Color(0xFF0F172A),
        radialLight: RadialGradient(
          colors: [Color(0x70F43F5E), Color(0x30E2E8F0), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'ajio_luxe_noir':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF0A0A0A), Color(0xFF1C1917), Color(0xFF78350F)],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFDE68A),
        badgeTextColor: Color(0xFF1C1917),
        radialLight: RadialGradient(
          colors: [Color(0x65FDE68A), Color(0x3078350F), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'ajio_avant_garde':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF14532D), Color(0xFFC2410C)],
          stops: [0.0, 0.45, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFEDD5),
        badgeTextColor: Color(0xFF7C2D12),
        radialLight: RadialGradient(
          colors: [Color(0x75FB923C), Color(0x3014532D), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'ajio_denim_drift':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6), Color(0xFF93C5FD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFEFF6FF),
        badgeTextColor: Color(0xFF1E3A8A),
        radialLight: RadialGradient(
          colors: [Color(0x80DBEAFE), Color(0x303B82F6), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'ajio_crimson_mania':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF4C0519), Color(0xFF9F1239), Color(0xFFEF4444)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF2F2),
        badgeTextColor: Color(0xFF991B1B),
        radialLight: RadialGradient(
          colors: [Color(0x75FECACA), Color(0x30EF4444), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );

    // Nykaa
    case 'nykaa_pink_glam':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF831843), Color(0xFFBE185D), Color(0xFFF472B6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFDF2F8),
        badgeTextColor: Color(0xFF9D174D),
        radialLight: RadialGradient(
          colors: [Color(0x80FBCFE8), Color(0x3CF472B6), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'nykaa_cherry_velvet':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF370617), Color(0xFF6A040F), Color(0xFF9D0208)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFE3E0),
        badgeTextColor: Color(0xFF6A040F),
        radialLight: RadialGradient(
          colors: [Color(0x75FFBAB4), Color(0x309D0208), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'nykaa_coral_blush':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFFBE123C), Color(0xFFFB7185), Color(0xFFFDBA74)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFF7ED),
        badgeTextColor: Color(0xFF9A3412),
        radialLight: RadialGradient(
          colors: [Color(0x80FED7AA), Color(0x30FB7185), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'nykaa_luxe_nude':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF44281D), Color(0xFF78350F), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF3C7),
        badgeTextColor: Color(0xFF78350F),
        radialLight: RadialGradient(
          colors: [Color(0x75FEF3C7), Color(0x30D97706), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'nykaa_lavender_haze':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF6366F1), Color(0xFFC084FC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFF3E8FF),
        badgeTextColor: Color(0xFF581C87),
        radialLight: RadialGradient(
          colors: [Color(0x75E9D5FF), Color(0x30C084FC), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );

    // Shopsy & Meesho
    case 'shopsy_vibrant_orange':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFFC2410C), Color(0xFFEA580C), Color(0xFFFBBF24)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF9A3412),
        radialLight: RadialGradient(
          colors: [Color(0x80FEF08A), Color(0x30EA580C), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'shopsy_peppy_red':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF991B1B), Color(0xFFDC2626), Color(0xFFF43F5E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFE4E6),
        badgeTextColor: Color(0xFF991B1B),
        radialLight: RadialGradient(
          colors: [Color(0x75FECDD3), Color(0x30DC2626), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'meesho_maha_blockbuster':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF3B0764), Color(0xFF581C87), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF3B0764),
        radialLight: RadialGradient(
          colors: [Color(0x75FEF08A), Color(0x38A855F7), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'meesho_mint_fresh':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF0D9488), Color(0xFF2DD4BF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFCCFBF1),
        badgeTextColor: Color(0xFF0F766E),
        radialLight: RadialGradient(
          colors: [Color(0x8099F6E4), Color(0x300D9488), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'meesho_saffron_burst':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF7C2D12), Color(0xFFB45309), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF3C7),
        badgeTextColor: Color(0xFF78350F),
        radialLight: RadialGradient(
          colors: [Color(0x75FEF3C7), Color(0x30F59E0B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );

    // Tata CLiQ
    case 'tatacliq_luxury_noir':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF09090B), Color(0xFF1C1917), Color(0xFF44403C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFF5D0C5),
        badgeTextColor: Color(0xFF44403C),
        radialLight: RadialGradient(
          colors: [Color(0x60F5D0C5), Color(0x2878716C), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'tatacliq_emerald_royale':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF022C22), Color(0xFF064E3B), Color(0xFFB45309)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF3C7),
        badgeTextColor: Color(0xFF064E3B),
        radialLight: RadialGradient(
          colors: [Color(0x65FEF3C7), Color(0x38064E3B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'tatacliq_velvet_sapphire':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF64748B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFF1F5F9),
        badgeTextColor: Color(0xFF0F172A),
        radialLight: RadialGradient(
          colors: [Color(0x65E2E8F0), Color(0x301E3A8A), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );

    // Tech & Gaming
    case 'tech_cyberpunk_neon':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF09090B), Color(0xFF0F172A), Color(0xFF0891B2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF06B6D4),
        badgeTextColor: Color(0xFF09090B),
        radialLight: RadialGradient(
          colors: [Color(0x8006B6D4), Color(0x300369A1), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'tech_titanium_matrix':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF09090B), Color(0xFF18181B), Color(0xFF15803D)],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF22C55E),
        badgeTextColor: Color(0xFF09090B),
        radialLight: RadialGradient(
          colors: [Color(0x7522C55E), Color(0x3015803D), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'tech_plasma_violet':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF09090B), Color(0xFF3B0764), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFA78BFA),
        badgeTextColor: Color(0xFF09090B),
        radialLight: RadialGradient(
          colors: [Color(0x75A78BFA), Color(0x308B5CF6), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'tech_aurora_stream':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF042F2E), Color(0xFF0F766E), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF6EE7B7),
        badgeTextColor: Color(0xFF042F2E),
        radialLight: RadialGradient(
          colors: [Color(0x756EE7B7), Color(0x3010B981), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );

    // Festive & Specials
    case 'dealbuster_light':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFFFFFFF)],
          stops: [0.0, 0.34, 0.86],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF312E81),
        badgeTextColor: Color(0xFFF59E0B),
      );
    case 'dealbuster_dark_supernova':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF4338CA), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF1E1B4B),
        radialLight: RadialGradient(
          colors: [Color(0x80FEF08A), Color(0x3CF59E0B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'festive_emerald_light':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF065F46), Color(0xFF059669), Color(0xFFFFFFFF)],
          stops: [0.0, 0.34, 0.86],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF064E3B),
        badgeTextColor: Color(0xFFFDE047),
        radialLight: RadialGradient(
          colors: [Color(0x65FDE047), Color(0x25059669), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'festive_diwali_gold':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF881337), Color(0xFFB91C1C), Color(0xFFF59E0B)],
          stops: [0.0, 0.45, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF3C7),
        badgeTextColor: Color(0xFF78350F),
        radialLight: RadialGradient(
          colors: [Color(0x80FEF3C7), Color(0x3CF59E0B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'festive_holi_rainbow':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFEC4899), Color(0xFFFBBF24)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Colors.white,
        badgeTextColor: Color(0xFF7C3AED),
        radialLight: RadialGradient(
          colors: [Color(0x90FFFFFF), Color(0x3CEC4899), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'minimal_frosted_slate':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF475569)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFF8FAFC),
        badgeTextColor: Color(0xFF0F172A),
        radialLight: RadialGradient(
          colors: [Color(0x75FFFFFF), Color(0x3094A3B8), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    // Flash & Midnight Sales
    case 'flash_midnight_madness':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF090014), Color(0xFF1C0038), Color(0xFF450A0A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFF0055),
        badgeTextColor: Color(0xFFFFFFFF),
        radialLight: RadialGradient(
          colors: [Color(0x7AFF0055), Color(0x331C0038), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'flash_rush_hour':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF1F2937), Color(0xFF854D0E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFACC15),
        badgeTextColor: Color(0xFF000000),
        radialLight: RadialGradient(
          colors: [Color(0x80FACC15), Color(0x33854D0E), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'flash_drop_alert':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF050505), Color(0xFF141F0A), Color(0xFF2E4A07)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFCCFF00),
        badgeTextColor: Color(0xFF000000),
        radialLight: RadialGradient(
          colors: [Color(0x73CCFF00), Color(0x332E4A07), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'flash_price_crash':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF500724), Color(0xFF831843), Color(0xFFEA580C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFF1F2),
        badgeTextColor: Color(0xFF9F1239),
        radialLight: RadialGradient(
          colors: [Color(0x7AFB923C), Color(0x38831843), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'flash_countdown_red':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF18181B), Color(0xFF7F1D1D), Color(0xFFDC2626)],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFEF4444),
        badgeTextColor: Color(0xFFFFFFFF),
        radialLight: RadialGradient(
          colors: [Color(0x7AEF4444), Color(0x337F1D1D), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    // Electronics & Audio
    case 'gadget_cyber_hologram':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF030712), Color(0xFF1E1B4B), Color(0xFF4338CA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF818CF8),
        badgeTextColor: Color(0xFF0F172A),
        radialLight: RadialGradient(
          colors: [Color(0x7A818CF8), Color(0x334338CA), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'gadget_acoustic_bass':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF1C1917), Color(0xFF292524), Color(0xFF78350F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFED7AA),
        badgeTextColor: Color(0xFF451A03),
        radialLight: RadialGradient(
          colors: [Color(0x73FDBA74), Color(0x3378350F), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'gadget_oled_infinite':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF020617), Color(0xFF0F172A), Color(0xFF581C87)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFC084FC),
        badgeTextColor: Color(0xFF3B0764),
        radialLight: RadialGradient(
          colors: [Color(0x7AC084FC), Color(0x38581C87), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'gadget_smart_wear':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF082F49), Color(0xFF0C4A6E), Color(0xFF0284C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF38BDF8),
        badgeTextColor: Color(0xFF082F49),
        radialLight: RadialGradient(
          colors: [Color(0x8038BDF8), Color(0x330284C7), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'gadget_pure_titanium':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF64748B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFF1F5F9),
        badgeTextColor: Color(0xFF0F172A),
        radialLight: RadialGradient(
          colors: [Color(0x8CFFFFFF), Color(0x3864748B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    // Sneakers & Streetwear
    case 'sneaker_grail_vault':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF18181B), Color(0xFF27272A), Color(0xFF991B1B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFF2E63),
        badgeTextColor: Color(0xFFFFFFFF),
        radialLight: RadialGradient(
          colors: [Color(0x7AFF2E63), Color(0x33991B1B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'sneaker_retro_dunk':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF1E40AF), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFDE68A),
        badgeTextColor: Color(0xFF1E3A8A),
        radialLight: RadialGradient(
          colors: [Color(0x80FDE68A), Color(0x38D97706), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'sneaker_cloud_foam':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF818CF8), Color(0xFFC7D2FE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFFFFF),
        badgeTextColor: Color(0xFF4338CA),
        radialLight: RadialGradient(
          colors: [Color(0x99FFFFFF), Color(0x4DC7D2FE), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'sneaker_urban_graffiti':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF142013), Color(0xFF283618), Color(0xFF606C38)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFF6F00),
        badgeTextColor: Color(0xFFFFFFFF),
        radialLight: RadialGradient(
          colors: [Color(0x7AFF6F00), Color(0x33606C38), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    // Luxury & High Fashion
    case 'luxe_monaco_gold':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF0C0A09), Color(0xFF1C1917), Color(0xFF451A03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFDE047),
        badgeTextColor: Color(0xFF000000),
        radialLight: RadialGradient(
          colors: [Color(0x7AFDE047), Color(0x40451A03), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'luxe_rose_champagne':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF4C0519), Color(0xFF831843), Color(0xFFBE185D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFE4E6),
        badgeTextColor: Color(0xFF881337),
        radialLight: RadialGradient(
          colors: [Color(0x80FECDD3), Color(0x38BE185D), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'luxe_versailles_emerald':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF022C22), Color(0xFF064E3B), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF022C22),
        radialLight: RadialGradient(
          colors: [Color(0x7AFEF08A), Color(0x380F766E), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'luxe_ivory_pearl':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF78716C), Color(0xFFA8A29E), Color(0xFFE7E5E4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF1C1917),
        badgeTextColor: Color(0xFFF5F5F4),
        radialLight: RadialGradient(
          colors: [Color(0x94FFFFFF), Color(0x4DE7E5E4), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    // Beauty, Skincare & Fragrance
    case 'beauty_rosewater_dew':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF9D174D), Color(0xFFBE185D), Color(0xFFF472B6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFDF2F8),
        badgeTextColor: Color(0xFF831843),
        radialLight: RadialGradient(
          colors: [Color(0x94FFFFFF), Color(0x47F472B6), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'beauty_vitamin_c_glow':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF9A3412), Color(0xFFC2410C), Color(0xFFF97316)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFEDD5),
        badgeTextColor: Color(0xFF7C2D12),
        radialLight: RadialGradient(
          colors: [Color(0x85FED7AA), Color(0x38F97316), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'beauty_matcha_detox':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF14532D), Color(0xFF166534), Color(0xFF4ADE80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFDCFCE7),
        badgeTextColor: Color(0xFF14532D),
        radialLight: RadialGradient(
          colors: [Color(0x85BBF7D0), Color(0x404ADE80), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'beauty_midnight_serum':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF38BDF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFE0F2FE),
        badgeTextColor: Color(0xFF0369A1),
        radialLight: RadialGradient(
          colors: [Color(0x807DD3FC), Color(0x3838BDF8), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    // Super Saver & Budget Bazaar
    case 'budget_99_store':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF7C2D12), Color(0xFFC2410C), Color(0xFFFACC15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF7C2D12),
        radialLight: RadialGradient(
          colors: [Color(0x8CFACC15), Color(0x38C2410C), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'budget_dhamaal_deals':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF4C1D95), Color(0xFF6D28D9), Color(0xFFF43F5E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFE4E6),
        badgeTextColor: Color(0xFF881337),
        radialLight: RadialGradient(
          colors: [Color(0x80FB7185), Color(0x38F43F5E), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'budget_super_combo':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF042F2E), Color(0xFF115E59), Color(0xFF84CC16)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFECFCCB),
        badgeTextColor: Color(0xFF14532D),
        radialLight: RadialGradient(
          colors: [Color(0x85D9F99D), Color(0x4084CC16), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'budget_paisa_vasool':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF881337), Color(0xFF9F1239), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF881337),
        radialLight: RadialGradient(
          colors: [Color(0x85FEF08A), Color(0x40F59E0B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    // Home, Kitchen & Appliances
    case 'home_scandinavian_warm':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF57534E), Color(0xFF78716C), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF3C7),
        badgeTextColor: Color(0xFF451A03),
        radialLight: RadialGradient(
          colors: [Color(0x80FEF3C7), Color(0x33D97706), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'home_chef_copper':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF1C1917), Color(0xFF44403C), Color(0xFFC2410C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFEDD5),
        badgeTextColor: Color(0xFF7C2D12),
        radialLight: RadialGradient(
          colors: [Color(0x7AFB923C), Color(0x38C2410C), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'home_smart_breeze':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF0369A1), Color(0xFF0284C7), Color(0xFFE0F2FE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFF0C4A6E),
        badgeTextColor: Color(0xFFFFFFFF),
        radialLight: RadialGradient(
          colors: [Color(0x94FFFFFF), Color(0x4DE0F2FE), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'home_cozy_botanical':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF047857), Color(0xFFFDE047)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF064E3B),
        radialLight: RadialGradient(
          colors: [Color(0x7AFDE047), Color(0x33047857), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    // Grocery, Fresh & Nutrition
    case 'fresh_farm_orchard':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF15803D), Color(0xFF16A34A), Color(0xFFF97316)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFF7ED),
        badgeTextColor: Color(0xFF15803D),
        radialLight: RadialGradient(
          colors: [Color(0x80FDBA74), Color(0x38F97316), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'fresh_berry_crunch':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF3B0764), Color(0xFF701A75), Color(0xFFE11D48)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFE4E6),
        badgeTextColor: Color(0xFF701A75),
        radialLight: RadialGradient(
          colors: [Color(0x7AFB7185), Color(0x33E11D48), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'fresh_whey_power':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF09090B), Color(0xFF1C1917), Color(0xFFEAB308)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFACC15),
        badgeTextColor: Color(0xFF000000),
        radialLight: RadialGradient(
          colors: [Color(0x85FACC15), Color(0x38EAB308), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'fresh_golden_spice':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF7C2D12), Color(0xFFB45309), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF3C7),
        badgeTextColor: Color(0xFF7C2D12),
        radialLight: RadialGradient(
          colors: [Color(0x85FEF3C7), Color(0x40F59E0B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    // Festive, Seasons & Celebrations
    case 'festive_rakhi_celebration':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF0C4A6E), Color(0xFF0369A1), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF0C4A6E),
        radialLight: RadialGradient(
          colors: [Color(0x80FEF08A), Color(0x38F59E0B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'festive_monsoon_splash':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF0E7490), Color(0xFF06B6D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFCFFAFE),
        badgeTextColor: Color(0xFF0E7490),
        radialLight: RadialGradient(
          colors: [Color(0x8067E8F9), Color(0x3806B6D4), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'festive_durgapuja_sindoor':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF450A0A), Color(0xFF991B1B), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFEF08A),
        badgeTextColor: Color(0xFF7F1D1D),
        radialLight: RadialGradient(
          colors: [Color(0x85FEF08A), Color(0x40F59E0B), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'festive_eid_crescent':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF022C22), Color(0xFF064E3B), Color(0xFF94A3B8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFF1F5F9),
        badgeTextColor: Color(0xFF064E3B),
        radialLight: RadialGradient(
          colors: [Color(0x80F1F5F9), Color(0x3894A3B8), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'festive_new_year_glitz':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFF09090B), Color(0xFF1E1B4B), Color(0xFFE0E7FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFFFFF),
        badgeTextColor: Color(0xFF1E1B4B),
        radialLight: RadialGradient(
          colors: [Color(0x9EFFFFFF), Color(0x4DE0E7FF), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    case 'baby_candyland_fun':
      return const HomeBannerTemplate(
        gradient: LinearGradient(
          colors: [Color(0xFFF472B6), Color(0xFF38BDF8), Color(0xFFA7F3D0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badgeBg: Color(0xFFFFFFFF),
        badgeTextColor: Color(0xFFDB2777),
        radialLight: RadialGradient(
          colors: [Color(0x9EFFFFFF), Color(0x4DF472B6), Colors.transparent],
          stops: [0.0, 0.55, 0.85],
        ),
      );
    default:
      return null;
  }
}

// Backwards-compatible private alias
HomeBannerTemplate? _getHomeBannerTemplate(String template) =>
    getHomeBannerTemplate(template);

class _CustomBannerCard extends StatelessWidget {
  const _CustomBannerCard({required this.banner});

  final HomeBannerItem banner;

  Future<void> _launch() async {
    final raw = banner.link.trim();
    if (raw.isEmpty) return;
    try {
      final uri = Uri.parse(raw);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _buildStoreLogo(String store, String fallbackName) {
    final s = store.toLowerCase().trim();
    final key = s.contains('_') ? s.split('_')[0] : s;
    switch (key) {
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

  @override
  Widget build(BuildContext context) {
    final tpl = banner.isTemplate ? _getHomeBannerTemplate(banner.template) : null;

    if (tpl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Template Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: tpl.gradient,
            ),
          ),

          // Radial light effect behind cutout image
          if (tpl.radialLight != null)
            Positioned(
              right: 10,
              top: 10,
              bottom: 10,
              width: MediaQuery.of(context).size.width * 0.44,
              child: Center(
                child: Container(
                  width: 145,
                  height: 145,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: tpl.radialLight,
                  ),
                ),
              ),
            ),

          // Right-side product cutout image
          if (banner.fullImageUrl.isNotEmpty)
            Positioned(
              right: 12,
              top: 14,
              bottom: 14,
              width: MediaQuery.of(context).size.width * 0.44,
              child: Align(
                alignment: Alignment.centerRight,
                child: CachedNetworkImage(
                  imageUrl: banner.fullImageUrl,
                  fit: BoxFit.contain,
                  fadeInDuration: const Duration(milliseconds: 150),
                  fadeOutDuration: const Duration(milliseconds: 150),
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),

          // Content layer (Top logo pill + vertically centered text lines)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Store Badge + Deal Badge
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _buildStoreLogo(banner.store, banner.storeName),
                      ),
                      if (banner.badgeText != null && banner.badgeText!.trim().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: tpl.badgeBg,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Text(
                            banner.badgeText!.trim().toUpperCase(),
                            style: TextStyle(
                              color: tpl.badgeTextColor,
                              fontSize: 9.8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Text Lines (vertically centered in remaining space)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.52,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: banner.effectiveLines.map((line) {
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
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Click / Tap Handler
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: banner.link.trim().isNotEmpty ? _launch : null,
                splashColor: Colors.white.withValues(alpha: 0.15),
                highlightColor: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full background image
        if (banner.fullImageUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: banner.fullImageUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_bg0, _bg1, _bg2],
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_bg0, _bg1, _bg2],
                ),
              ),
            ),
          )
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_bg0, _bg1, _bg2],
              ),
            ),
          ),

        // Readability gradient overlay (only when opted in via admin dashboard)
        if (banner.applyEffect)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.42),
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.88),
                ],
                stops: const [0.0, 0.42, 1.0],
              ),
            ),
          ),

        // Content layer (Top logo pill + vertically centered text lines, matching Store Banner)
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Store Badge + Deal Badge
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _buildStoreLogo(banner.store, banner.storeName),
                    ),
                    if (banner.badgeText != null && banner.badgeText!.trim().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          banner.badgeText!.trim().toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                // Text Lines (vertically centered in remaining space like Store Banner)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.54,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: banner.effectiveLines.map((line) {
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
                  ),
                ),
              ],
            ),
          ),
        ),

        // Click / Tap Handler
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: banner.link.trim().isNotEmpty ? _launch : null,
              splashColor: Colors.white.withValues(alpha: 0.15),
              highlightColor: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
      ],
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.t,
    required this.s,
    required this.w,
    required this.h,
    required this.liveDealCount,
  });

  final double t, s, w, h;
  final int liveDealCount;

  @override
  Widget build(BuildContext context) {
    // ---- badge idle motion --------------------------------------------
    final ping = 0.5 - 0.5 * math.cos(t * 2.4);

    // ---- bag ----------------------------------------------------------
    final bagX = _pop(t, 332, 0, _Cues.bagIn, 1.0);
    final bagS = _pop(t, 0.86, 1, _Cues.bagIn + 0.15, 0.8);
    final bagOutS = _exit(t, 1, 0.2, _Cues.bagOut + 0.95, 0.55);
    final bagOutO = _clamp(_exit(t, 1, 0, _Cues.bagOut + 1.05, 0.45), 0, 1);
    final bagBob = math.sin((t - _Cues.bagIn) * 2.1) * 3;
    final flipOpen = _pop(t, 0, 168, _Cues.products - 0.55, 0.6);
    final flipShut = _clamp(_anim(t, 0, 1, _Cues.bagOut + 0.6, 0.45, _easeOutCubic), 0, 1);
    final flip = flipOpen * (1 - flipShut);

    final bagAnchor = Offset(375 + 311 / 2, h / s / 2); // right stage centre

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // ---------------------------------------------------------- left column
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 250,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 210),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LiveBadge(count: liveDealCount, ping: ping),
                    const SizedBox(height: 10),
                    Text(
                      'Deals that\ndon\'t wait.',
                      style: GoogleFonts.sora(
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
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Fresh price drops tracked\naround the clock.',
                      style: GoogleFonts.inter(
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
                  ],
                ),
              ),
            ),
          ),
        ),

        // ---------------------------------------------------------- bag + products
        Positioned.fill(
          child: Opacity(
            opacity: bagOutO,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < _products.length; i++)
                  _productLayer(i, s, bagAnchor + Offset(bagX, bagBob), bagOutS),
                _bagLayer(s, bagS, flip, bagAnchor + Offset(bagX, bagBob), bagOutS),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // one product: pops out of the bag, then drops back in
  Widget _productLayer(int i, double s, Offset anchor, double outS) {
    final p = _products[i];
    final st = _Cues.products + p.delay;
    final px = _pop(t, 0, p.dx, st, 0.7);
    final py = _pop(t, 25, p.dy, st, 0.7);
    final ps = _pop(t, 0, 1, st, 0.7);
    final po = _clamp(_enter(t, 0, 1, st, 0.25), 0, 1);
    final rt = _Cues.bagOut + 0.06 + (3 - i) * 0.12;
    final back = _clamp(_anim(t, 0, 1, rt, 0.5, _easeInCubic), 0, 1);
    final wob = math.sin((t - st) * 2.3 + i) * 2 * (1 - back);

    final fx = px * (1 - back);
    final fy = py + (28 - py) * back;
    final fs = _clamp(ps * (1 - 0.55 * back), 0, 2) * outS;
    final fo = _clamp(po * (1 - back), 0, 1);

    return Positioned(
      left: (anchor.dx + fx * outS - p.size / 2) * s,
      top: (anchor.dy + (fy + wob) * outS - p.size / 2) * s,
      width: p.size * s,
      height: p.size * s,
      child: Opacity(
        opacity: fo,
        child: Transform.rotate(
          angle: p.rot * ps * (1 - back) * math.pi / 180,
          child: Transform.scale(
            scale: fs,
            child: SvgPicture.asset(p.asset, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  // bag: back handle (behind body) / body / front handle (folds forward)
  Widget _bagLayer(double s, double bagS, double flip, Offset anchor, double outS) {
    const box = 139.0;
    const hinge = 34.0;
    final size = box * s;
    final scale = bagS * 1.3 * outS;

    Matrix4 hingeFlip() => Matrix4.identity()
      ..setEntry(3, 2, 1 / (330 * s))
      ..rotateX(flip * math.pi / 180);

    return Positioned(
      left: (anchor.dx - box / 2) * s,
      top: (anchor.dy - box / 2 + 25) * s,
      width: size,
      height: size,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scale(scale)
          ..setEntry(3, 2, 1 / (588 * s))
          ..rotateY(-13 * math.pi / 180)
          ..rotateX(6 * math.pi / 180)
          ..rotateZ(-1 * math.pi / 180),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // soft ground shadow
              Positioned(
                left: 6 * s,
                top: 130 * s,
                width: 126 * s,
                height: 20 * s,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.elliptical(63 * s, 10 * s)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.42),
                        blurRadius: 14 * s,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
              // back handle, clipped away as it rotates behind the body
              Positioned.fill(
                child: ClipRect(
                  clipper: _TopInset(math.min(flip * 2.5, 64) / 260 * size),
                  child: Transform(
                    alignment: Alignment(0, (hinge / box) * 2 - 1),
                    transform: hingeFlip(),
                    child: SvgPicture.string(_bagHandleBack, fit: BoxFit.contain),
                  ),
                ),
              ),
              // body (artwork below the rim)
              Positioned.fill(
                child: ClipRect(
                  clipper: _TopInset(hinge * s),
                  child: SvgPicture.asset('assets/icons/shopping-bag.svg', fit: BoxFit.contain),
                ),
              ),
              // front handle: folds forward, nothing drawn above the rim once open
              Positioned.fill(
                child: ClipRect(
                  clipper: _TopInset(math.min(flip / 55, 1) * hinge * s),
                  child: Transform(
                    alignment: Alignment(0, (hinge / box) * 2 - 1),
                    transform: hingeFlip(),
                    child: ClipRect(
                      clipper: _BottomInset((1 - math.min(flip / 22, 1)) * 92 / 139 * size),
                      child: SvgPicture.string(_bagHandleFront, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- helpers
class _TopInset extends CustomClipper<Rect> {
  _TopInset(this.top);
  final double top;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);
  @override
  bool shouldReclip(_TopInset old) => old.top != top;
}

class _BottomInset extends CustomClipper<Rect> {
  _BottomInset(this.bottom);
  final double bottom;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width, size.height - bottom);
  @override
  bool shouldReclip(_BottomInset old) => old.bottom != bottom;
}

// --------------------------------------------------------------- live badge
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.count, required this.ping});
  final int count;
  final double ping;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6CFFB0).withOpacity(0.75 + 0.25 * ping),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6CFFB0),
                  blurRadius: 3 + 2 * ping,
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$count deals live now',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- handle art
const _bagHandleBack = '''
<svg viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg"><path fill="#d1d1d6" fill-rule="evenodd" clip-rule="evenodd" d="m319.109 183.808v-99.554c0-15.342-6.282-29.296-16.403-39.416-10.121-10.121-24.074-16.403-39.416-16.403s-29.295 6.282-39.416 16.403c-10.121 10.12-16.403 24.074-16.403 39.416h-.031l.001 99.555h-15.938l-.001-99.555h-.031c0-19.759 8.077-37.716 21.09-50.729s30.97-21.09 50.729-21.09 37.716 8.078 50.729 21.09c13.013 13.013 21.09 30.97 21.09 50.729v99.555h-16z"/></svg>
''';

const _bagHandleFront = '''
<svg viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg"><path fill="#eceff1" fill-rule="evenodd" clip-rule="evenodd" d="m280.175 183.374c0 4.418-3.582 8-8 8s-8-3.582-8-8v-99.555c0-15.342-6.282-29.296-16.403-39.416-10.121-10.121-24.074-16.403-39.416-16.403s-29.295 6.282-39.416 16.403-16.403 24.074-16.403 39.416h-.031l.001 99.555c0 4.401-3.568 7.969-7.969 7.969s-7.969-3.568-7.969-7.969l-.001-99.555h-.031c0-19.759 8.077-37.716 21.09-50.729 13.014-13.013 30.97-21.09 50.729-21.09s37.716 8.077 50.729 21.09 21.09 30.97 21.09 50.729z"/></svg>
''';
