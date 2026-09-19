import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/offer.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/deal_bottom_nav_bar.dart';
import '../widgets/search_bar.dart';

enum OfferTab { coupons, discounts }

class OffersScreen extends StatefulWidget {
  const OffersScreen({
    super.key,
    this.isTabBarVisible,
  });

  final ValueNotifier<bool>? isTabBarVisible;

  @override
  State<OffersScreen> createState() => OffersScreenState();
}

class OffersScreenState extends State<OffersScreen> {
  final ApiService _api = ApiService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  static const double _kScrollTopThreshold = 300.0;
  static const double _kScrollUpDeltaThreshold = 60.0;
  final ValueNotifier<bool> _showScrollTop = ValueNotifier<bool>(false);
  double _scrollUpStartOffset = 0.0;

  OfferTab _selectedTab = OfferTab.coupons;
  List<Offer> _allOffers = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _errorMessage;
  String _searchQuery = '';
  Timer? _searchDebounceTimer;
  List<Offer>? _serverSearchResults;
  bool _isSearchingServer = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _loadOffers();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _showScrollTop.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final currentOffset = _scrollController.offset;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final userDirection = _scrollController.position.userScrollDirection;

    // Bottom tab bar show/hide coordination
    if (widget.isTabBarVisible != null) {
      if (currentOffset <= 20 || userDirection == ScrollDirection.forward) {
        if (!widget.isTabBarVisible!.value) {
          widget.isTabBarVisible!.value = true;
        }
      } else if (userDirection == ScrollDirection.reverse && currentOffset > 40) {
        if (widget.isTabBarVisible!.value) {
          widget.isTabBarVisible!.value = false;
        }
      }
    }

    // Scroll-to-top button visibility
    _updateScrollTopButton(_scrollController);

    // Infinite scroll trigger: when scrolled near bottom
    if (currentOffset >= maxOffset - 300) {
      if (!_isLoadingMore && _hasMore && !_isLoading && !_isRefreshing && _searchQuery.isEmpty) {
        _loadMoreOffers();
      }
    }
  }

  void _updateScrollTopButton(ScrollController sc) {
    if (!sc.hasClients) return;
    final currentOffset = sc.offset;
    final userDirection = sc.position.userScrollDirection;

    bool show = false;

    if (currentOffset > _kScrollTopThreshold) {
      if (userDirection == ScrollDirection.reverse) {
        _scrollUpStartOffset = currentOffset;
        show = false;
      } else if (userDirection == ScrollDirection.forward) {
        if (currentOffset > _scrollUpStartOffset) {
          _scrollUpStartOffset = currentOffset;
        }
        final upwardDelta = _scrollUpStartOffset - currentOffset;
        if (upwardDelta >= _kScrollUpDeltaThreshold) {
          show = true;
        } else {
          show = _showScrollTop.value;
        }
      } else {
        show = _showScrollTop.value;
      }
    } else {
      _scrollUpStartOffset = currentOffset;
      show = false;
    }

    if (_showScrollTop.value != show) {
      _showScrollTop.value = show;
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
    _showScrollTop.value = false;
  }

  void handleOffersTabTap() {
    resetSearchAndScrollToTop();
  }

  void resetSearchAndScrollToTop() {
    _searchDebounceTimer?.cancel();
    _searchFocusNode.unfocus();
    if (_searchController.text.isNotEmpty ||
        _searchQuery.isNotEmpty ||
        _serverSearchResults != null ||
        _isSearchingServer) {
      _searchController.clear();
      _searchQuery = '';
      _serverSearchResults = null;
      _isSearchingServer = false;
    }

    if (_selectedTab != OfferTab.coupons) {
      _selectedTab = OfferTab.coupons;
    }

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _showScrollTop.value = false;
    if (mounted) setState(() {});
  }

  void _onTabSelected(OfferTab tab) {
    if (_selectedTab != tab) {
      setState(() {
        _selectedTab = tab;
      });
      if (_scrollController.hasClients && _scrollController.offset > 44.0) {
        _scrollController.jumpTo(44.0);
      }
      _updateScrollTopButton(_scrollController);
    }
  }

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      if (_searchQuery.isNotEmpty || _serverSearchResults != null || _isSearchingServer) {
        setState(() {
          _searchQuery = '';
          _serverSearchResults = null;
          _isSearchingServer = false;
        });
      }
      return;
    }

    if (query != _searchQuery) {
      setState(() {
        _searchQuery = query;
        _isSearchingServer = true;
      });

      _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
        try {
          final results = await Future.wait([
            _api.fetchOffersFresh(query: query, page: 1),
            _api.fetchOffersFresh(query: query, page: 2),
          ]);

          if (!mounted || _searchController.text.trim() != query) return;

          final combinedServer = <Offer>[];
          final seen = <String>{};
          for (final list in results) {
            if (list != null) {
              for (final o in list) {
                final key = o.id.isNotEmpty ? o.id : '${o.title}_${o.couponCode}';
                if (seen.add(key)) {
                  combinedServer.add(o);
                }
              }
            }
          }

          setState(() {
            _serverSearchResults = combinedServer;
            _isSearchingServer = false;
          });
        } catch (_) {
          if (mounted && _searchController.text.trim() == query) {
            setState(() => _isSearchingServer = false);
          }
        }
      });
    }
  }

  Future<void> _loadOffers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      // Fetch initial 4 pages in parallel for an instant 150+ offers catalog
      final results = await Future.wait([
        _api.fetchOffers(page: 1),
        _api.fetchOffersFresh(page: 2),
        _api.fetchOffersFresh(page: 3),
        _api.fetchOffersFresh(page: 4),
      ]);

      final combined = <Offer>[];
      final seenIds = <String>{};
      int highestPageLoaded = 1;

      for (int i = 0; i < results.length; i++) {
        final list = results[i];
        if (list != null && list.isNotEmpty) {
          highestPageLoaded = i + 1;
          for (final offer in list) {
            final key = offer.id.isNotEmpty ? offer.id : '${offer.title}_${offer.couponCode}';
            if (seenIds.add(key)) {
              combined.add(offer);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _allOffers = combined.isNotEmpty ? combined : [];
          _currentPage = highestPageLoaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Couldn\'t load offers. Please check connection.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreOffers() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    final nextPage = _currentPage + 1;
    try {
      final more = await _api.fetchOffersFresh(page: nextPage);
      if (mounted) {
        if (more != null) {
          if (more.isNotEmpty) {
            final seenIds = _allOffers
                .map((o) => o.id.isNotEmpty ? o.id : '${o.title}_${o.couponCode}')
                .toSet();
            final newUnique = more.where((o) {
              final key = o.id.isNotEmpty ? o.id : '${o.title}_${o.couponCode}';
              return seenIds.add(key);
            }).toList();

            setState(() {
              _currentPage = nextPage;
              _allOffers.addAll(newUnique);
              _isLoadingMore = false;
              if (more.length < 5) {
                _hasMore = false;
              }
            });
          } else {
            // Truly no more items in feed
            setState(() {
              _hasMore = false;
              _isLoadingMore = false;
            });
          }
        } else {
          // Network timeout/glitch: allow future retry on next scroll, don't permanently kill pagination
          setState(() {
            _isLoadingMore = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    try {
      final results = await Future.wait([
        _api.fetchOffersFresh(page: 1),
        _api.fetchOffersFresh(page: 2),
        _api.fetchOffersFresh(page: 3),
        _api.fetchOffersFresh(page: 4),
      ]);

      final combined = <Offer>[];
      final seenIds = <String>{};
      int highestPageLoaded = 1;

      for (int i = 0; i < results.length; i++) {
        final list = results[i];
        if (list != null && list.isNotEmpty) {
          highestPageLoaded = i + 1;
          for (final offer in list) {
            final key = offer.id.isNotEmpty ? offer.id : '${offer.title}_${offer.couponCode}';
            if (seenIds.add(key)) {
              combined.add(offer);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          if (combined.isNotEmpty) {
            _allOffers = combined;
            _currentPage = highestPageLoaded;
            _hasMore = true;
            _errorMessage = null;
          }
          _isRefreshing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  List<Offer> get _filteredCoupons {
    if (_searchQuery.isEmpty) {
      return _allOffers.where((o) => o.isCoupon).toList();
    }
    final q = _searchQuery.toLowerCase();
    final localMatches = _allOffers.where((o) {
      return o.isCoupon &&
          (o.title.toLowerCase().contains(q) ||
              o.campaignName.toLowerCase().contains(q) ||
              o.couponCode.toLowerCase().contains(q) ||
              o.description.toLowerCase().contains(q));
    }).toList();

    if (_serverSearchResults == null) return localMatches;

    final combined = <Offer>[...localMatches];
    final seen = combined
        .map((o) => o.id.isNotEmpty ? o.id : '${o.title}_${o.couponCode}')
        .toSet();

    for (final o in _serverSearchResults!) {
      if (!o.isCoupon) continue;
      final key = o.id.isNotEmpty ? o.id : '${o.title}_${o.couponCode}';
      if (seen.add(key)) {
        combined.add(o);
      }
    }
    return combined;
  }

  List<Offer> get _filteredDiscounts {
    if (_searchQuery.isEmpty) {
      return _allOffers.where((o) => !o.isCoupon).toList();
    }
    final q = _searchQuery.toLowerCase();
    final localMatches = _allOffers.where((o) {
      return !o.isCoupon &&
          (o.title.toLowerCase().contains(q) ||
              o.campaignName.toLowerCase().contains(q) ||
              o.description.toLowerCase().contains(q));
    }).toList();

    if (_serverSearchResults == null) return localMatches;

    final combined = <Offer>[...localMatches];
    final seen = combined
        .map((o) => o.id.isNotEmpty ? o.id : '${o.title}_${o.couponCode}')
        .toSet();

    for (final o in _serverSearchResults!) {
      if (o.isCoupon) continue;
      final key = o.id.isNotEmpty ? o.id : '${o.title}_${o.couponCode}';
      if (seen.add(key)) {
        combined.add(o);
      }
    }
    return combined;
  }


  Future<void> _handleCouponTap(Offer offer) async {
    // 1. Copy code to clipboard
    if (offer.couponCode.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: offer.couponCode));
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Code "${offer.couponCode}" copied! Opening store...',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E1B2E),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.only(bottom: 70, left: 16, right: 16),
          ),
        );
      }
    }

    // 2. Open tracking URL
    _openUrl(offer.trackingUrl);
  }

  Future<void> _handleDiscountTap(Offer offer) async {
    _openUrl(offer.trackingUrl);
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final isCoupons = _selectedTab == OfferTab.coupons;
    final activeItems = isCoupons ? _filteredCoupons : _filteredDiscounts;

    return PopScope(
      canPop: !_searchFocusNode.hasFocus && _searchQuery.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        } else if (_searchQuery.isNotEmpty) {
          _searchDebounceTimer?.cancel();
          _searchController.clear();
          setState(() {
            _searchQuery = '';
            _serverSearchResults = null;
            _isSearchingServer = false;
          });
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                RefreshIndicator(
                  color: AppColors.brand,
                  onRefresh: _handleRefresh,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      // ── Top Header Title (Scrolls away on scroll down) ──
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Offers',
                              style: GoogleFonts.sora(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ── Sticky Search Bar & Segmented Tabs (Pinned on scroll down) ──
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _OffersStickyHeaderDelegate(
                          searchBar: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: DealSearchBar(
                              editable: true,
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              hintText: 'Search coupons, deals or stores...',
                              trailing: _isSearchingServer
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.brand,
                                      ),
                                    )
                                  : null,
                              onClear: () {
                                _searchDebounceTimer?.cancel();
                                _searchFocusNode.unfocus();
                                setState(() {
                                  _searchQuery = '';
                                  _serverSearchResults = null;
                                  _isSearchingServer = false;
                                });
                              },
                            ),
                          ),
                          tabs: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              height: 42,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1EFF6),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final tabWidth = constraints.maxWidth / 2;
                                  return Stack(
                                    children: [
                                      // Animated sliding white background pill
                                      AnimatedPositioned(
                                        duration:
                                            const Duration(milliseconds: 250),
                                        curve: Curves.easeInOutCubic,
                                        left: _selectedTab == OfferTab.coupons
                                            ? 0
                                            : tabWidth,
                                        top: 0,
                                        bottom: 0,
                                        width: tabWidth,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(19),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF14121F)
                                                    .withValues(alpha: 0.08),
                                                blurRadius: 4,
                                                offset: const Offset(0, 1.5),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Tab buttons on top
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildTabButton(
                                              tab: OfferTab.coupons,
                                              label: 'Coupons',
                                              icon: Icons
                                                  .confirmation_number_rounded,
                                            ),
                                          ),
                                          Expanded(
                                            child: _buildTabButton(
                                              tab: OfferTab.discounts,
                                              label: 'Discounts',
                                              icon: Icons.local_offer_rounded,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ── Main Content Area ──
                      if (_isLoading)
                        _buildLoadingSkeletonSliver()
                      else if (_errorMessage != null && _allOffers.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildErrorState(),
                        )
                      else if (activeItems.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _isSearchingServer
                              ? _buildLoadingSkeletonWidget()
                              : _buildEmptyState(isCoupons: isCoupons),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index == activeItems.length) {
                                  return const Padding(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: AppColors.brand,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final offer = activeItems[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: offer.isCoupon
                                      ? _CouponCard(
                                          offer: offer,
                                          onTap: () =>
                                              _handleCouponTap(offer),
                                        )
                                      : _DiscountCard(
                                          offer: offer,
                                          onTap: () =>
                                              _handleDiscountTap(offer),
                                        ),
                                );
                              },
                              childCount: activeItems.length +
                                  (_isLoadingMore ? 1 : 0),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // ── Scroll to Top Button (Synced with active tab & bottom bar) ──
                ValueListenableBuilder<bool>(
                  valueListenable:
                      widget.isTabBarVisible ?? ValueNotifier<bool>(true),
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
                          onTap: _scrollToTop,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required OfferTab tab,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _selectedTab == tab;
    return GestureDetector(
      onTap: () => _onTabSelected(tab),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? AppColors.brand : AppColors.ink400,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.brand : AppColors.ink400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF14121F).withValues(alpha: 0.05),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 80, height: 16, color: const Color(0xFFF3F2F7)),
              const Spacer(),
              Container(width: 90, height: 16, color: const Color(0xFFF3F2F7)),
            ],
          ),
          const SizedBox(height: 14),
          Container(width: double.infinity, height: 18, color: const Color(0xFFF3F2F7)),
          const SizedBox(height: 8),
          Container(width: 200, height: 14, color: const Color(0xFFF3F2F7)),
          const Spacer(),
          Container(width: double.infinity, height: 38, color: const Color(0xFFF3F2F7)),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeletonSliver() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildSkeletonCard(),
          ),
          childCount: 4,
        ),
      ),
    );
  }

  Widget _buildLoadingSkeletonWidget() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      child: Column(
        children: List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildSkeletonCard(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool isCoupons}) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _searchQuery.isNotEmpty
                  ? 'No matching offers found'
                  : isCoupons
                      ? 'No coupons available right now'
                      : 'No discounts available right now',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try searching with another store name or discount keyword.'
                  : 'Check back soon for freshly added verified store offers!',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.ink400,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.ink400),
            const SizedBox(height: 12),
            const Text(
              'Couldn\'t load offers',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please check your internet connection and try again.',
              style: TextStyle(fontSize: 13, color: AppColors.ink400),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadOffers,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OffersStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget searchBar;
  final Widget tabs;

  _OffersStickyHeaderDelegate({
    required this.searchBar,
    required this.tabs,
  });

  static const double headerHeight = 113.0;

  @override
  double get minExtent => headerHeight;

  @override
  double get maxExtent => headerHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: headerHeight,
      color: AppColors.bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          searchBar,
          const SizedBox(height: 8),
          tabs,
          const SizedBox(height: 8),
          Container(
            height: 1,
            color: AppColors.cardStroke,
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _OffersStickyHeaderDelegate oldDelegate) => true;
}

// ── Custom Painter for Dashed Border on Coupon Chip ───────────────────────────
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.dashWidth = 4.0,
    this.dashSpace = 3.0,
    this.borderRadius = 8.0,
  });

  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(borderRadius),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final len = (distance + dashWidth < metric.length)
            ? dashWidth
            : metric.length - distance;
        final extractPath = metric.extractPath(distance, distance + len);
        canvas.drawPath(extractPath, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      dashWidth != oldDelegate.dashWidth ||
      dashSpace != oldDelegate.dashSpace ||
      borderRadius != oldDelegate.borderRadius;
}

// ── Coupon Voucher Card (GrabOn & Ticket voucher style) ──────────────────────────
class _CouponCard extends StatelessWidget {
  const _CouponCard({
    required this.offer,
    required this.onTap,
  });

  final Offer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final expiry = offer.formattedExpiry;
    final discount = offer.discountBadge;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF14121F).withValues(alpha: 0.08),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14121F).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top metadata row: Merchant + Verified + Expiry
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                // Store pill (constrained so long store names don't push expiry off screen)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 125),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F1F7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      offer.campaignName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Verified badge
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF16A34A)),
                    SizedBox(width: 3),
                    Text(
                      'Verified',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // ONLY Expiry Date fully shown without ellipsis, strictly right-aligned
                if (expiry != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(Icons.schedule_rounded, size: 13, color: AppColors.ink400),
                      const SizedBox(width: 4),
                      Text(
                        expiry,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink400,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Divider
          Divider(
            height: 1,
            thickness: 0.8,
            color: const Color(0xFF14121F).withValues(alpha: 0.06),
          ),

          // Body: Left discount badge + Right title & description
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Ticket Notch Callout (Orange theme with very light orange background)
                Container(
                  width: 76,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF6F0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.brand.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.confirmation_number_rounded,
                        size: 20,
                        color: AppColors.brand,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        discount ?? 'COUPON',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brand,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Right Title & Description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                          height: 1.25,
                        ),
                      ),
                      if (offer.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          offer.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.ink400,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom Action: Stylized Dashed Coupon Code Chip + Single-line Copy & Visit Button
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Dashed coupon code chip (matching height: 30px)
                if (offer.couponCode.isNotEmpty) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: SizedBox(
                      height: 30,
                      child: CustomPaint(
                        painter: _DashedBorderPainter(
                          color: AppColors.brand.withValues(alpha: 0.55),
                          strokeWidth: 1.0,
                          dashWidth: 4.0,
                          dashSpace: 3.0,
                          borderRadius: 7.0,
                        ),
                        child: Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.content_cut_rounded, size: 12, color: AppColors.brand),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  offer.couponCode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.brand,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Copy & Visit Store Button with buy-button arrow style & single line ellipsis (matching height: 30px)
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E1B2E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded, size: 12),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Copy & Visit Store',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_outward_rounded,
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Discount Deal Card ──────────────────────────────────────────────────────────
class _DiscountCard extends StatelessWidget {
  const _DiscountCard({
    required this.offer,
    required this.onTap,
  });

  final Offer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final expiry = offer.formattedExpiry;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF14121F).withValues(alpha: 0.08),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14121F).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top metadata row: Merchant + Verified + Expiry
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                // Store pill (constrained so long store names don't push expiry off screen)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 125),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F1F7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      offer.campaignName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Verified badge
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF16A34A)),
                    SizedBox(width: 3),
                    Text(
                      'Verified',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // ONLY Expiry Date fully shown without ellipsis, strictly right-aligned
                if (expiry != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(Icons.schedule_rounded, size: 13, color: AppColors.ink400),
                      const SizedBox(width: 4),
                      Text(
                        expiry,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink400,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Divider
          Divider(
            height: 1,
            thickness: 0.8,
            color: const Color(0xFF14121F).withValues(alpha: 0.06),
          ),

          // Body: Title & description & prices (moved to left)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1.25,
                  ),
                ),
                if (offer.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    offer.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.ink400,
                      height: 1.3,
                    ),
                  ),
                ],
                if (offer.discountPrice != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '₹${offer.discountPrice}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      if (offer.originalPrice != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '₹${offer.originalPrice}',
                          style: const TextStyle(
                            fontSize: 12,
                            decoration: TextDecoration.lineThrough,
                            color: AppColors.ink400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Bottom Action: Get Offer Button with right arrow icon
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Get Offer',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollTopButton extends StatelessWidget {
  const _ScrollTopButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}
