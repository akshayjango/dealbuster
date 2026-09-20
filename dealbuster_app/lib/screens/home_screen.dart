import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/home_banner_item.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../utils/svg_icons.dart';
import '../widgets/category_tabs.dart';
import '../widgets/deal_bottom_nav_bar.dart';
import '../widgets/hero_banner.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/sort_bottom_sheet.dart';
import 'product_detail_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

const _telegramUrl = 'https://t.me/dealbusterindia';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.isTabBarVisible,
  });

  final ValueNotifier<bool>? isTabBarVisible;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _api = ApiService();
  final _scrollController = ScrollController();
  final _categoryScrollController = ScrollController();
  final _showScrollTop = ValueNotifier(false);
  final _hasNewDeals = ValueNotifier(false);
  Timer? _autoRefreshTimer;

  static const _kAutoRefreshInterval = Duration(minutes: 5);
  static const _kScrollTopThreshold = 400.0;
  // Anything under this is treated as "already at the top" — a new card
  // can just pop in there instead of needing a scroll-position adjustment.
  static const _kAtTopEpsilon = 2.0;
  static const _kScrollUpDeltaThreshold = 90.0;
  double _scrollUpStartOffset = 0.0;

  List<Product> _all = [];
  bool _bannersLoading = true;
  bool _showDefaultAnimatedBanner = false;
  List<HomeBannerItem> _homeBanners = const [];
  String _category = 'sort';
  String _sortOption = 'new';
  bool _loading = true;
  bool _failed = false;
  String? _pendingDeepLinkProductId;

  DateTime? _lastPausedTime;
  DateTime _lastInteractionTime = DateTime.now();
  static const _kIdleResetDuration = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addObserver(this);
    _startTimer();

    // Listen for push notification deal taps
    PushNotificationService.instance.productToOpen.addListener(_handlePushNotificationTap);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePushNotificationTap();
    });
  }

  void _handlePushNotificationTap() {
    final productId = PushNotificationService.instance.productToOpen.value;
    if (productId == null || productId.isEmpty) return;
    PushNotificationService.instance.productToOpen.value = null;

    if (_loading || _all.isEmpty) {
      _pendingDeepLinkProductId = productId;
    } else {
      _openProductById(productId);
    }
  }

  void _checkPendingDeepLink() {
    if (_pendingDeepLinkProductId != null) {
      final id = _pendingDeepLinkProductId!;
      _pendingDeepLinkProductId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openProductById(id);
      });
    }
  }

  void _openProductById(String productId) {
    final cleanId = productId.trim().toUpperCase();
    final match = _all.cast<Product?>().firstWhere(
      (p) {
        if (p == null) return false;
        if (p.id.toUpperCase() == cleanId) return true;
        if (p.asin != null && p.asin!.toUpperCase() == cleanId) return true;
        return false;
      },
      orElse: () => null,
    );

    if (match != null && mounted) {
      showProductDetailSheet(context, match);
    }
  }

  void _startTimer() {
    _autoRefreshTimer?.cancel();
    final interval = _failed ? const Duration(seconds: 4) : _kAutoRefreshInterval;
    _autoRefreshTimer = Timer.periodic(
      interval,
      (_) {
        final now = DateTime.now();
        if (now.difference(_lastInteractionTime) >= _kIdleResetDuration) {
          if (_category != 'sort' || _sortOption != 'new') {
            setState(() {
              _category = 'sort';
              _sortOption = 'new';
            });
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0.0);
            }
          }
        }
        if (_failed || _all.isEmpty) {
          _load();
        } else {
          _autoRefresh();
        }
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushNotificationService.instance.productToOpen.removeListener(_handlePushNotificationTap);
    _autoRefreshTimer?.cancel();
    _scrollController.dispose();
    _categoryScrollController.dispose();
    _showScrollTop.dispose();
    _hasNewDeals.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _lastPausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      final wasPausedOver10m = _lastPausedTime != null &&
          now.difference(_lastPausedTime!) >= _kIdleResetDuration;
      final wasIdleOver10m =
          now.difference(_lastInteractionTime) >= _kIdleResetDuration;

      if (wasPausedOver10m || wasIdleOver10m) {
        setState(() {
          _category = 'sort';
          _sortOption = 'new';
        });
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0.0);
        }
      }
      _lastPausedTime = null;
      _lastInteractionTime = now;

      if (_failed || _all.isEmpty) {
        _load();
      } else {
        _autoRefresh();
      }
    }
  }

  void _handleScroll() {
    _lastInteractionTime = DateTime.now();
    if (!_scrollController.hasClients) return;

    final currentOffset = _scrollController.offset;
    final userDirection = _scrollController.position.userScrollDirection;

    // Coordinate bottom tab bar visibility:
    // Disappear on scroll down, reappear on scroll up, and stay visible at the top.
    if (widget.isTabBarVisible != null) {
      if (currentOffset <= _kAtTopEpsilon || userDirection == ScrollDirection.forward) {
        if (!widget.isTabBarVisible!.value) {
          widget.isTabBarVisible!.value = true;
        }
      } else if (userDirection == ScrollDirection.reverse && currentOffset > 20) {
        if (widget.isTabBarVisible!.value) {
          widget.isTabBarVisible!.value = false;
        }
      }
    }

    bool show = false;

    // Only show button if past threshold
    if (currentOffset > _kScrollTopThreshold) {
      if (userDirection == ScrollDirection.reverse) {
        // User is scrolling DOWN: track start of future scroll-up and hide button
        _scrollUpStartOffset = currentOffset;
        show = false;
      } else if (userDirection == ScrollDirection.forward) {
        // User is scrolling UP: only show once user has scrolled up by _kScrollUpDeltaThreshold
        if (currentOffset > _scrollUpStartOffset) {
          _scrollUpStartOffset = currentOffset;
        }
        final upwardDelta = _scrollUpStartOffset - currentOffset;
        if (upwardDelta >= _kScrollUpDeltaThreshold) {
          show = true;
        } else {
          // Keep showing if already visible and continuing to scroll up
          show = _showScrollTop.value;
        }
      } else {
        // Idle/holding: keep current visibility as long as we're past the top threshold
        show = _showScrollTop.value;
      }
    } else {
      // Below threshold: always hide
      _scrollUpStartOffset = currentOffset;
      show = false;
    }

    if (_showScrollTop.value != show) {
      _showScrollTop.value = show;
    }
  }

  void scrollToTop() {
    _hasNewDeals.value = false;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void handleDealsTabTap() {
    _hasNewDeals.value = false;
    _lastInteractionTime = DateTime.now();

    final needsFilterReset = (_category != 'sort' || _sortOption != 'new');

    if (needsFilterReset) {
      setState(() {
        _category = 'sort';
        _sortOption = 'new';
      });
    }

    if (_categoryScrollController.hasClients) {
      _categoryScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }

    if (_scrollController.hasClients && _scrollController.offset > 0.0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }

    _refreshFromDealsTab();
  }

  Future<void> _refreshFromDealsTab() async {
    if (_failed || _all.isEmpty) {
      await _load();
      return;
    }
    _loadBanners();
    try {
      final fetched = await _api.fetchProductsFresh();
      if (!mounted || fetched == null || fetched.isEmpty) return;
      setState(() {
        _all = fetched;
        _failed = false;
        _loading = false;
      });
      _hasNewDeals.value = false;
      _startTimer();
    } catch (_) {
      // Keep existing
    }
  }

  Future<void> _loadBanners() async {
    // 1. Immediately read cached banners (if available) so cached state renders in 1-2 ms
    try {
      final cached = await _api.getCachedHomeBanners();
      if (mounted && cached != null) {
        setState(() {
          _showDefaultAnimatedBanner = cached.showDefaultAnimatedBanner;
          _homeBanners = cached.banners;
          _bannersLoading = false;
        });
      }
    } catch (_) {}

    // 2. Fetch fresh banners from network in parallel
    try {
      final fresh = await _api.fetchHomeBannersFresh();
      if (mounted && fresh != null) {
        setState(() {
          _showDefaultAnimatedBanner = fresh.showDefaultAnimatedBanner;
          _homeBanners = fresh.banners;
          _bannersLoading = false;
        });
      } else if (mounted && _bannersLoading) {
        setState(() {
          _bannersLoading = false;
        });
      }
    } catch (_) {
      if (mounted && _bannersLoading) {
        setState(() {
          _bannersLoading = false;
        });
      }
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
      _bannersLoading = true;
    });

    _loadBanners();

    try {
      var products = await _api.fetchProductsFresh();
      if (!mounted) return;
      if (products == null || products.isEmpty) {
        products = await _api.getCachedProducts();
      }
      if (products.isEmpty) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      } else {
        setState(() {
          _all = products!;
          _loading = false;
          _failed = false;
        });
        _checkPendingDeepLink();
      }
    } catch (_) {
      if (!mounted) return;
      final cached = await _api.getCachedProducts();
      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _all = cached;
          _loading = false;
          _failed = false;
        });
        _checkPendingDeepLink();
      } else {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
    _startTimer();
  }

  // Background refresh — on the 5-minute timer and whenever the app is
  // foregrounded. Unlike [_load], this never shows a spinner or error
  // state: it silently merges in whatever's new and leaves everything
  // else untouched. New items are prepended (matching how the feed itself
  // adds deals at the top); existing ones are refreshed in place (price
  // drops etc.) without moving position, per the site's own rule.
  Future<void> _autoRefresh() async {
    if (_loading) return;
    if (_failed || _all.isEmpty) {
      await _load();
      return;
    }

    _api.fetchHomeBannersFresh().then((data) {
      if (mounted && data != null) {
        setState(() {
          _showDefaultAnimatedBanner = data.showDefaultAnimatedBanner;
          _homeBanners = data.banners;
        });
      }
    }).catchError((_) {});

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

      final hasScroll = _scrollController.hasClients;
      final oldPixels = hasScroll ? _scrollController.position.pixels : 0.0;
      final oldMaxExtent =
          hasScroll ? _scrollController.position.maxScrollExtent : 0.0;
      final atTop = !hasScroll || oldPixels <= _kAtTopEpsilon;

      if (atTop) {
        // User is at the top of the feed: cleanly adopt the true server order
        setState(() {
          _all = fetched!;
          _failed = false;
          _loading = false;
        });
        _startTimer();
        return;
      }

      // If user is scrolled down: only genuinely newer deals should be prepended.
      final oldIds = {for (final p in _all) p.id};
      DateTime latestExistingTime = DateTime.fromMillisecondsSinceEpoch(0);
      for (final p in _all) {
        if (!p.featured) {
          final t = DateTime.tryParse(p.addedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
          if (t.isAfter(latestExistingTime)) latestExistingTime = t;
        }
      }

      final brandNew = fetched.where((p) {
        if (oldIds.contains(p.id)) return false;
        final t = DateTime.tryParse(p.addedAt);
        return t != null && t.isAfter(latestExistingTime);
      }).toList();

      final fetchedById = {for (final p in fetched) p.id: p};
      final updatedExisting = _all
          .where((p) => fetchedById.containsKey(p.id))
          .map((p) => fetchedById[p.id]!)
          .toList();

      if (brandNew.isEmpty) {
        setState(() {
          _all = updatedExisting;
          _failed = false;
          _loading = false;
        });
        _startTimer();
        return;
      }

      setState(() {
        _all = [...brandNew, ...updatedExisting];
        _failed = false;
        _loading = false;
      });
      _startTimer();

      // Scrolled down: nudge the dot and silently correct the scroll offset
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
    if (_category == 'under_500' || _category == 'deals') {
      return _all.where((p) {
        final price =
            double.tryParse(p.price.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
        return price > 0 && price <= 500;
      }).toList();
    }
    if (_category == 'sort' || _category == 'all') {
      if (_sortOption == 'lowest_price') {
        final lowest = _all
            .where((p) =>
                p.lowestPriceText != null && p.lowestPriceText!.isNotEmpty)
            .toList();
        if (lowest.isNotEmpty) return lowest;
        final sorted = [..._all];
        sorted.sort((a, b) {
          final pa =
              double.tryParse(a.price.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                  0.0;
          final pb =
              double.tryParse(b.price.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                  0.0;
          return pa.compareTo(pb);
        });
        return sorted;
      }
      if (_sortOption == 'coupon') {
        return _all
            .where((p) =>
                p.couponPercent != null ||
                p.title.toLowerCase().contains('coupon'))
            .toList();
      }
      if (_sortOption == 'discount') {
        final sorted = [..._all];
        sorted.sort((a, b) {
          final da =
              int.tryParse(a.disc.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          final db =
              int.tryParse(b.disc.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          return db.compareTo(da);
        });
        return sorted;
      }
      if (_sortOption == 'low_to_high') {
        final sorted = [..._all];
        sorted.sort((a, b) {
          final pa =
              double.tryParse(a.price.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                  0.0;
          final pb =
              double.tryParse(b.price.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                  0.0;
          return pa.compareTo(pb);
        });
        return sorted;
      }
      if (_sortOption == 'high_to_low') {
        final sorted = [..._all];
        sorted.sort((a, b) {
          final pa =
              double.tryParse(a.price.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                  0.0;
          final pb =
              double.tryParse(b.price.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                  0.0;
          return pb.compareTo(pa);
        });
        return sorted;
      }
      // 'new' / default: original feed order (newest first)
      return _all;
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

  void _openSortSheet() {
    _lastInteractionTime = DateTime.now();
    showSortBottomSheet(
      context: context,
      currentSort: _sortOption,
      onSelectSort: (opt) {
        _lastInteractionTime = DateTime.now();
        setState(() {
          _category = 'sort';
          _sortOption = opt;
        });
        _resetScrollPositionAfterFilter();
      },
    );
  }

  static const double _headerCollapseOffset = 240.0;

  void _resetScrollPositionAfterFilter() {
    if (_scrollController.hasClients) {
      final currentOffset = _scrollController.offset;
      if (currentOffset > 0.0) {
        _scrollController.jumpTo(_headerCollapseOffset);
      } else {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  void _openSettings() {
    _lastInteractionTime = DateTime.now();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const SettingsScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide = Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);
          return SlideTransition(position: slide, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _load,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: _TopBar(
                      onLaunch: _launch,
                      onOpenSettings: _openSettings,
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: HomeHeaderDelegate(
                      hasBanner: _bannersLoading ||
                          _showDefaultAnimatedBanner ||
                          _homeBanners.isNotEmpty,
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
                      heroBanner: _bannersLoading
                          ? const _BannerSkeleton()
                          : HeroBanner(
                              liveDealCount: _all.length,
                              showDefaultAnimatedBanner: _showDefaultAnimatedBanner,
                              customBanners: _homeBanners,
                            ),
                      categoryTabs: CategoryTabs(
                        controller: _categoryScrollController,
                        selected: _category,
                        sortOption: _sortOption,
                        onSortTap: _openSortSheet,
                        onSelect: (c) {
                          _lastInteractionTime = DateTime.now();
                          if (c == 'sort_reset') {
                            // Tapped an already-selected sort tab again -> deselect and reset to default Sort: New
                            setState(() {
                              _category = 'sort';
                              _sortOption = 'new';
                            });
                            _resetScrollPositionAfterFilter();
                          } else if (c == 'sort') {
                            if (_category != 'sort') {
                              setState(() => _category = 'sort');
                              _resetScrollPositionAfterFilter();
                            }
                          } else if (_category == c) {
                            // Tapped the already-selected category tab again -> deselect and reset to default Sort: New
                            setState(() {
                              _category = 'sort';
                              _sortOption = 'new';
                            });
                            _resetScrollPositionAfterFilter();
                          } else {
                            setState(() => _category = c);
                            _resetScrollPositionAfterFilter();
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
                      padding: EdgeInsets.fromLTRB(
                        AppSpace.md,
                        12.0,
                        AppSpace.md,
                        AppSpace.xl + DealBottomNavBar.barHeight + bottomPadding,
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
            ValueListenableBuilder<bool>(
              valueListenable:
                  widget.isTabBarVisible ?? ValueNotifier<bool>(false),
              builder: (context, isBarVisible, _) {
                final double bottomPos = 16.0 +
                    bottomPadding +
                    (isBarVisible ? DealBottomNavBar.barHeight : 0.0);

                return AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOutCubic,
                  right: 16,
                  bottom: bottomPos,
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
                      onTap: scrollToTop,
                    ),
                  ),
                );
              },
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF14121F).withValues(alpha: 0.08),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF14121F).withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF14121F).withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: const Center(
                child: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: Color(0xFF3F3B49),
                  size: 28,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: -1,
          right: 0,
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
                  border: Border.all(color: Colors.white, width: 2),
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
  const _TopBar({required this.onLaunch, required this.onOpenSettings});
  final Future<void> Function(String) onLaunch;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46.0,
      child: Padding(
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
            _TelegramButton(
              onTap: () => onLaunch(_telegramUrl),
            ),
            const SizedBox(width: 8),
            _MenuButton(
              onTap: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.cardStroke, width: 0.6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF14121F).withValues(alpha: 0.09),
              blurRadius: 10,
              offset: const Offset(0, 3),
              spreadRadius: -1,
            ),
            BoxShadow(
              color: const Color(0xFF14121F).withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 14,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  height: 2.2,
                  width: 20,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(1.1),
                  ),
                ),
                Container(
                  height: 2.2,
                  width: 13,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(1.1),
                  ),
                ),
                Container(
                  height: 2.2,
                  width: 17,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(1.1),
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

class _TelegramButton extends StatelessWidget {
  const _TelegramButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFF25D3C),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF25D3C).withValues(alpha: 0.32),
                blurRadius: 9,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: const Color(0xFF14121F).withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: const Center(
            child: SvgIcon(
              SvgIcons.telegram,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
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
        border: Border.all(color: AppColors.cardStroke, width: 0.6),
        boxShadow: dealCardShadow(opacity: 0.5),
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

class _BannerSkeleton extends StatefulWidget {
  const _BannerSkeleton();

  @override
  State<_BannerSkeleton> createState() => _BannerSkeletonState();
}

class _BannerSkeletonState extends State<_BannerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

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
      margin: const EdgeInsets.fromLTRB(
        AppSpace.md,
        10,
        AppSpace.md,
        6,
      ),
      height: 176,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.cardStroke, width: 0.6),
        boxShadow: dealCardShadow(opacity: 0.4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: AnimatedBuilder(
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
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left side: Text placeholders
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Small pill placeholder (store badge / live counter)
                          Container(
                            height: 20,
                            width: 72,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Big headline placeholder
                          Container(
                            height: 22,
                            width: 145,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Subtitle placeholder
                          Container(
                            height: 13,
                            width: 110,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Right side: Image cutout placeholder
                    Container(
                      width: 95,
                      height: 95,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.category});
  final String category;

  @override
  Widget build(BuildContext context) {
    final displayLabel = category == 'sort'
        ? 'this sort'
        : (category == 'under_500' ? 'Under 500' : category);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 40, color: AppColors.ink400),
            const SizedBox(height: 12),
            Text(
              'No deals in "$displayLabel" right now',
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
            const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.ink400),
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
    this.hasBanner = true,
  });

  final Widget searchBar;
  final Widget heroBanner;
  final Widget categoryTabs;
  final bool hasBanner;

  static const double searchBarHeight = 62.0;
  double get bannerHeight => hasBanner ? 192.0 : 0.0;
  static const double tabsHeight = 48.0;

  @override
  double get minExtent => searchBarHeight + tabsHeight;

  @override
  double get maxExtent => searchBarHeight + bannerHeight + tabsHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double diff = maxExtent - minExtent;
    final double collapsePercent =
        diff > 0 ? (shrinkOffset / diff).clamp(0.0, 1.0) : 0.0;
    final showShadow = overlapsContent || collapsePercent > 0.9;

    return Material(
      color: AppColors.bg,
      elevation: showShadow ? 1.5 : 0,
      shadowColor: AppColors.ink.withValues(alpha: 0.05),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // 1. Hero Banner (collapses/fades out as we scroll) - bottom layer
          if (hasBanner)
            Positioned(
              top: searchBarHeight - (collapsePercent * bannerHeight),
              left: 0,
              right: 0,
              height: bannerHeight,
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
            height: tabsHeight,
            child: categoryTabs,
          ),

          // 3. Search Bar at the very top (always visible, pinned, solid background) - top layer
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: searchBarHeight,
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
