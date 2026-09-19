import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/banner_item.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/store_banner_card.dart';

class StoresScreen extends StatefulWidget {
  const StoresScreen({
    super.key,
    this.isTabBarVisible,
  });

  final ValueNotifier<bool>? isTabBarVisible;

  @override
  State<StoresScreen> createState() => StoresScreenState();
}

class StoresScreenState extends State<StoresScreen> {
  final ApiService _api = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<BannerItem> _banners = [];
  bool _isLoading = true;
  String _selectedStoreFilter = 'all'; // 'all', 'myntra', 'flipkart', 'ajio', 'amazon'

  final List<Map<String, String>> _storeFilters = const [
    {'id': 'all', 'label': 'All Stores'},
    {'id': 'myntra', 'label': 'Myntra'},
    {'id': 'flipkart', 'label': 'Flipkart'},
    {'id': 'ajio', 'label': 'AJIO'},
    {'id': 'amazon', 'label': 'Amazon'},
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadBanners();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void resetToDefault() {
    if (_selectedStoreFilter != 'all') {
      setState(() {
        _selectedStoreFilter = 'all';
      });
    }
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.jumpTo(0);
    }
  }

  void _onScroll() {
    if (widget.isTabBarVisible == null) return;
    if (_scrollController.position.userScrollDirection ==
        ScrollDirection.reverse) {
      if (widget.isTabBarVisible!.value) {
        widget.isTabBarVisible!.value = false;
      }
    } else if (_scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      if (!widget.isTabBarVisible!.value) {
        widget.isTabBarVisible!.value = true;
      }
    }
  }

  Future<void> _loadBanners() async {
    final banners = await _api.fetchBanners();
    if (mounted) {
      setState(() {
        _banners = banners;
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    final fresh = await _api.fetchBannersFresh();
    if (fresh != null && mounted) {
      setState(() {
        _banners = fresh;
      });
    }
  }

  List<BannerItem> get _filteredBanners {
    if (_selectedStoreFilter == 'all') return _banners;
    return _banners
        .where((b) => b.storeKey == _selectedStoreFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredBanners;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.brand,
          onRefresh: _onRefresh,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    'Stores',
                    style: GoogleFonts.sora(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _StoresTabHeaderDelegate(
                  filters: _storeFilters,
                  selectedFilter: _selectedStoreFilter,
                  onSelectFilter: (id) {
                    setState(() {
                      _selectedStoreFilter = id;
                    });
                  },
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.brand,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.brand.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            size: 32,
                            color: AppColors.brand,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Store Banners Available',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Pull down to refresh or check back shortly.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.ink700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 90),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final banner = filtered[index];
                        return StoreBannerCard(
                          key: ValueKey(banner.id),
                          banner: banner,
                        );
                      },
                      childCount: filtered.length,
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

class _StoresTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<Map<String, String>> filters;
  final String selectedFilter;
  final ValueChanged<String> onSelectFilter;

  _StoresTabHeaderDelegate({
    required this.filters,
    required this.selectedFilter,
    required this.onSelectFilter,
  });

  @override
  double get minExtent => 53.0;

  @override
  double get maxExtent => 53.0;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: 53.0,
      color: AppColors.bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 46,
            child: ListView.separated(
              clipBehavior: Clip.none,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = filters[index];
                final isSelected = item['id'] == selectedFilter;

                return Center(
                  child: InkWell(
                    onTap: () => onSelectFilter(item['id']!),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 7.5,
                      ),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFFFF7243),
                                  Color(0xFFFF4222),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              )
                            : null,
                        color: isSelected ? null : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: isSelected
                            ? null
                            : Border.all(
                                color: AppColors.cardStroke,
                                width: 1,
                              ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFFF4222)
                                      .withValues(alpha: 0.20),
                                  blurRadius: 5,
                                  offset: const Offset(0, 1.5),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        item['label']!,
                        style: GoogleFonts.inter(
                          color: isSelected ? Colors.white : AppColors.ink,
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 1,
            color: AppColors.cardStroke,
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StoresTabHeaderDelegate oldDelegate) {
    return oldDelegate.selectedFilter != selectedFilter ||
        oldDelegate.filters != filters;
  }
}
