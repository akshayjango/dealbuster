import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/svg_icons.dart';
import '../widgets/category_tabs.dart';
import '../widgets/hero_banner.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import 'product_detail_screen.dart';
import 'search_screen.dart';

const _telegramUrl = 'https://t.me/dealbusterindia';
const _whatsappUrl = 'https://whatsapp.com/channel/0029Vb8eJlcA2pLCSwCSi00V';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _api = ApiService();
  final _scrollController = ScrollController();
  final _showScrollTop = ValueNotifier(false);
  final _hasNewDeals = ValueNotifier(false);
  Timer? _autoRefreshTimer;

  static const _kAutoRefreshInterval = Duration(minutes: 5);
  static const _kScrollTopThreshold = 400.0;
  // Anything under this is treated as "already at the top" — a new card
  // can just pop in there instead of needing a scroll-position adjustment.
  static const _kAtTopEpsilon = 2.0;

  List<Product> _all = [];
  String _category = 'all';
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addObserver(this);
    _autoRefreshTimer = Timer.periodic(
      _kAutoRefreshInterval,
      (_) => _autoRefresh(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _scrollController.dispose();
    _showScrollTop.dispose();
    _hasNewDeals.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoRefresh();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    final currentOffset = _scrollController.offset;
    final userDirection = _scrollController.position.userScrollDirection;

    bool show = false;

    // Only show button if past threshold
    if (currentOffset > _kScrollTopThreshold) {
      if (userDirection == ScrollDirection.forward) {
        // User is scrolling UP (dragging content down)
        show = true;
      } else if (userDirection == ScrollDirection.reverse) {
        // User is scrolling DOWN (dragging content up)
        show = false;
      } else {
        // Keep previous state when idle/holding
        show = _showScrollTop.value;
      }
    } else {
      // Below threshold: always hide
      show = false;
    }

    if (_showScrollTop.value != show) {
      _showScrollTop.value = show;
    }
  }

  void _scrollToTop() {
    _hasNewDeals.value = false;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final products = await _api.fetchProductsFresh();
      if (!mounted) return;
      if (products == null) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      } else {
        setState(() {
          _all = products;
          _loading = false;
          _failed = products.isEmpty;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  // Background refresh — on the 5-minute timer and whenever the app is
  // foregrounded. Unlike [_load], this never shows a spinner or error
  // state: it silently merges in whatever's new and leaves everything
  // else untouched. New items are prepended (matching how the feed itself
  // adds deals at the top); existing ones are refreshed in place (price
  // drops etc.) without moving position, per the site's own rule.
  Future<void> _autoRefresh() async {
    if (_loading) return;
    try {
      // fetchProductsFresh (not fetchProducts) — on any failure we want to
      // know and retry, not silently get served the stale on-disk cache
      // and wrongly conclude "checked, nothing new". A resume is exactly
      // when the radio can still be reconnecting, so the first attempt
      // failing is common enough to need this retry.
      var fetched = await _api.fetchProductsFresh();
      if (fetched == null) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        fetched = await _api.fetchProductsFresh();
      }
      if (!mounted || fetched == null || fetched.isEmpty) return;

      final fetchedById = {for (final p in fetched) p.id: p};
      final oldIds = {for (final p in _all) p.id};
      final newOnly = fetched.where((p) => !oldIds.contains(p.id)).toList();
      final updatedExisting = _all
          .where((p) => fetchedById.containsKey(p.id))
          .map((p) => fetchedById[p.id]!)
          .toList();

      if (newOnly.isEmpty) {
        setState(() => _all = updatedExisting);
        return;
      }

      final hasScroll = _scrollController.hasClients;
      final oldPixels = hasScroll ? _scrollController.position.pixels : 0.0;
      final oldMaxExtent =
          hasScroll ? _scrollController.position.maxScrollExtent : 0.0;
      final atTop = !hasScroll || oldPixels <= _kAtTopEpsilon;

      setState(() => _all = [...newOnly, ...updatedExisting]);

      if (atTop) return;

      // Scrolled down: nudge the dot and silently correct the scroll
      // offset by however much the new cards pushed everything down by,
      // so the viewport keeps showing exactly what it was showing.
      _hasNewDeals.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final delta = _scrollController.position.maxScrollExtent - oldMaxExtent;
        if (delta > 0) _scrollController.jumpTo(oldPixels + delta);
      });
    } catch (_) {
      // Silent — a background tick shouldn't surface errors to the user.
    }
  }

  List<Product> get _filtered {
    if (_category == 'all') return _all;
    if (_category == 'deals') {
      return _all.where((p) {
        final price =
            double.tryParse(p.price.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
        final discountPct = int.tryParse(p.disc.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final hasCoupon = p.couponPercent != null;
        final isLowestPrice = p.lowestPriceText != null && p.lowestPriceText!.isNotEmpty;

        return (price > 0 && price < 500) ||
            (discountPct >= 70) ||
            hasCoupon ||
            isLowestPrice;
      }).toList();
    }
    return _all.where((p) => p.category == _category).toList();
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openProduct(Product product) {
    showProductDetailSheet(context, product);
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _load,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(child: _TopBar(onLaunch: _launch)),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: HomeHeaderDelegate(
                      searchBar: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
                        child: DealSearchBar(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SearchScreen(initialProducts: _all),
                            ),
                          ),
                        ),
                      ),
                      heroBanner: HeroBanner(liveDealCount: _all.length),
                      categoryTabs: CategoryTabs(
                        selected: _category,
                        onSelect: (c) {
                          if (_category != c) {
                            setState(() => _category = c);
                            if (_scrollController.hasClients) {
                              final currentOffset = _scrollController.offset;
                              if (currentOffset > 0.0) {
                                _scrollController.jumpTo(250.0);
                              } else {
                                _scrollController.jumpTo(0.0);
                              }
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  if (_loading)
                    const _GridSkeleton()
                  else if (_failed)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _ErrorState(onRetry: _load),
                    )
                  else if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(category: _category),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.md,
                        AppSpace.md,
                        AppSpace.md,
                        AppSpace.xl,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.68,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => ProductCard(
                            product: items[i],
                            onTap: () => _openProduct(items[i]),
                            onNetworkError: () {
                              if (!_failed && !_loading) {
                                setState(() {
                                  _failed = true;
                                });
                              }
                            },
                          ),
                          childCount: items.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: ValueListenableBuilder<bool>(
                valueListenable: _showScrollTop,
                builder: (context, show, child) => IgnorePointer(
                  ignoring: !show,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: show ? 1 : 0,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      offset: show ? Offset.zero : const Offset(0, 0.3),
                      child: child,
                    ),
                  ),
                ),
                child: _ScrollTopButton(
                  hasNewDeals: _hasNewDeals,
                  onTap: _scrollToTop,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollTopButton extends StatelessWidget {
  const _ScrollTopButton({required this.hasNewDeals, required this.onTap});

  final ValueListenable<bool> hasNewDeals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Shadow lives on this outer, unclipped box; the frosted glass fill
    // (blur + a translucent tint, so the grid behind stays faintly
    // visible) is clipped to the circle inside.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration:
              BoxDecoration(shape: BoxShape.circle, boxShadow: cardShadow()),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Material(
                color: AppColors.ink.withValues(alpha: 0.55),
                child: InkWell(
                  onTap: onTap,
                  child: const Center(
                    child: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: -2,
          right: -2,
          child: ValueListenableBuilder<bool>(
            valueListenable: hasNewDeals,
            builder: (context, hasNew, _) {
              if (!hasNew) return const SizedBox.shrink();
              return Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bg, width: 2),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onLaunch});
  final Future<void> Function(String) onLaunch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
      child: Row(
        children: [
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.headlineMedium,
              children: const [
                TextSpan(text: 'Deal'),
                TextSpan(
                    text: 'Buster', style: TextStyle(color: AppColors.brand)),
              ],
            ),
          ),
          const Spacer(),
          _IconPill(
            icon: SvgIcons.telegram,
            color: const Color(0xFF29A9EA),
            onTap: () => onLaunch(_telegramUrl),
          ),
          const SizedBox(width: 8),
          _IconPill(
            icon: SvgIcons.whatsapp,
            color: const Color(0xFF25D366),
            onTap: () => onLaunch(_whatsappUrl),
          ),
        ],
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill(
      {required this.icon, required this.color, required this.onTap});
  final String icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: SvgIcon(icon, size: 17, color: Colors.white)),
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(AppSpace.md),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.68,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => const _ShimmerCard(),
          childCount: 6,
        ),
      ),
    );
  }
}

class _ShimmerCard extends StatefulWidget {
  const _ShimmerCard();

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: cardShadow(opacity: 0.3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: const [
                        AppColors.hairline,
                        Color(0xFFF9F8FD),
                        AppColors.hairline,
                      ],
                      stops: const [
                        0.3,
                        0.5,
                        0.7,
                      ],
                      transform: _SlidingGradientTransform(
                        slidePercent: _controller.value,
                      ),
                    ).createShader(bounds);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image placeholder
                      Container(
                        height: 130,
                        width: double.infinity,
                        color: Colors.white,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Title placeholders (two lines)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 10,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    height: 10,
                                    width: width * 0.7,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ],
                              ),
                              // Price & MRP placeholder (third line)
                              Row(
                                children: [
                                  Container(
                                    height: 14,
                                    width: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    height: 10,
                                    width: 30,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ],
                              ),
                              // Savings pill placeholder (fourth line)
                              Container(
                                height: 16,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({
    required this.slidePercent,
  });

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
        bounds.width * (slidePercent - 0.5) * 2, 0.0, 0.0);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.category});
  final String category;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 40, color: AppColors.ink400),
            const SizedBox(height: 12),
            Text(
              'No deals in "$category" right now',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 40, color: AppColors.ink400),
            const SizedBox(height: 12),
            Text(
              'Couldn\'t load deals',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Check your connection and try again.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  HomeHeaderDelegate({
    required this.searchBar,
    required this.heroBanner,
    required this.categoryTabs,
  });

  final Widget searchBar;
  final Widget heroBanner;
  final Widget categoryTabs;

  @override
  double get minExtent => 62.0 + 60.0;

  @override
  double get maxExtent => 62.0 + 206.0 + 60.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double collapsePercent =
        (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final showShadow = overlapsContent || collapsePercent > 0.9;

    return Material(
      color: AppColors.bg,
      elevation: showShadow ? 2 : 0,
      shadowColor: AppColors.ink.withValues(alpha: 0.08),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // 1. Hero Banner (collapses/fades out as we scroll) - bottom layer
          Positioned(
            top: 62.0 - (collapsePercent * 206.0),
            left: 0,
            right: 0,
            height: 206.0,
            child: Opacity(
              opacity: (1.0 - collapsePercent * 1.8).clamp(0.0, 1.0),
              child: heroBanner,
            ),
          ),

          // 2. Category Tabs (pins below Search Bar when collapsed) - middle layer
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 60.0,
            child: categoryTabs,
          ),

          // 3. Search Bar at the very top (always visible, pinned, solid background) - top layer
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 62.0,
            child: Container(
              color: AppColors.bg,
              child: searchBar,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant HomeHeaderDelegate oldDelegate) => true;
}
