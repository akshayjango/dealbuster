import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Text(
          'Stores & Offers',
          style: TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.4,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Column(
            children: [
              // Store filter pills bar
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _storeFilters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = _storeFilters[index];
                    final isSelected = item['id'] == _selectedStoreFilter;

                    return Center(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedStoreFilter = item['id']!;
                          });
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.brand
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.brand
                                  : AppColors.cardStroke,
                              width: 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color:
                                          AppColors.brand.withValues(alpha: 0.25),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            item['label']!,
                            style: TextStyle(
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
              const SizedBox(height: 8),
              Container(
                height: 0.6,
                color: AppColors.cardStroke,
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.brand,
                strokeWidth: 2.5,
              ),
            )
          : RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _onRefresh,
              child: filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.45,
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
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 8, bottom: 90),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final banner = filtered[index];
                        return StoreBannerCard(
                          key: ValueKey(banner.id),
                          banner: banner,
                        );
                      },
                    ),
            ),
    );
  }
}
