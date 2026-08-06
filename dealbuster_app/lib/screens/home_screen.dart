import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../widgets/animated_banner.dart';
import '../widgets/search_bar.dart';
import '../widgets/category_tabs.dart';
import '../widgets/product_card.dart';
import 'product_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;
  bool _isError = false;
  String _activeTab = 'all';

  // Social URLs
  static const String _telegramUrl = 'https://t.me/dealbusterindia';
  static const String _whatsappUrl = 'https://whatsapp.com/channel/0029Va9g5AX3AzNYTk4Bd12W';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    // Try reading from cache first for instant load
    final cache = await _apiService.getCachedProducts();
    if (cache.isNotEmpty) {
      if (mounted) {
        setState(() {
          _allProducts = cache;
          _applyFilters();
          _isLoading = false;
        });
      }
    }

    // Refresh with live network data
    _refreshData();
  }

  Future<void> _refreshData() async {
    final liveProducts = await _apiService.fetchProducts();
    
    if (mounted) {
      if (liveProducts.isNotEmpty) {
        setState(() {
          _allProducts = liveProducts;
          _applyFilters();
          _isLoading = false;
          _isError = false;
        });
      } else if (_allProducts.isEmpty) {
        setState(() {
          _isLoading = false;
          _isError = true;
        });
      }
    }
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    List<Product> results = [];

    for (final p in _allProducts) {
      // 1. Tab Filter
      bool matchesTab = false;
      if (_activeTab == 'all') {
        matchesTab = true;
      } else if (_activeTab == 'deals') {
        // "Deals" Filters items under ₹500
        final priceVal = double.tryParse(p.price.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
        matchesTab = priceVal > 0.0 && priceVal < 500.0;
      } else {
        matchesTab = p.category == _activeTab;
      }

      // 2. Search Query Filter
      final matchesSearch = query.isEmpty || p.title.toLowerCase().contains(query);

      if (matchesTab && matchesSearch) {
        results.add(p);
      }
    }

    setState(() {
      _filteredProducts = results;
    });
  }

  void _onTabChanged(String tabId) {
    setState(() {
      _activeTab = tabId;
      _applyFilters();
    });
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isError && _allProducts.isEmpty) {
      return _buildOfflineScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF6C47FF),
          onRefresh: _refreshData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── 1. Scrollable Header (Logo + JOIN badges) ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Logo Wrap
                      Row(
                        children: [
                          const Text(
                            'DEAL',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: Color(0xFF1A1D2E),
                              letterSpacing: -0.5,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(left: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFB6F24C),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'BUSTER',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: Color(0xFF1A1D2E),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Social Join Group
                      Row(
                        children: [
                          const Text(
                            'JOIN',
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: Color(0xFF1A1D2E),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Telegram Button (36x36, Icon-only rounded)
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF2FA6DE),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              icon: const Icon(Icons.telegram, size: 22),
                              onPressed: () => _launchUrl(_telegramUrl),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // WhatsApp Button (36x36, Icon-only rounded)
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              icon: const Icon(Icons.chat_bubble_outline, size: 18),
                              onPressed: () => _launchUrl(_whatsappUrl),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── 2. Animated Deal Buster Banner ──
              SliverToBoxAdapter(
                child: AnimatedBanner(
                  onTap: () {
                    // Tap focuses on search input or resets search
                    _searchController.clear();
                    _applyFilters();
                  },
                ),
              ),

              // ── 3. Sticky Search Bar + Tabs Strip ──
              SliverPersistentHeader(
                pinned: true,
                delegate: SearchAndTabsHeaderDelegate(
                  controller: _searchController,
                  activeTab: _activeTab,
                  onTabChanged: _onTabChanged,
                  onSearchClear: () {
                    setState(() {
                      _searchController.clear();
                      _applyFilters();
                    });
                  },
                ),
              ),

              // ── 4. 2-Column Product Grid ──
              _isLoading
                  ? _buildShimmerGrid()
                  : _buildProductGrid(),
            ],
          ),
        ),
      ),
    );
  }

  // ── 2-Column Grid Layout with Infinite Scroll Logic ──
  Widget _buildProductGrid() {
    if (_filteredProducts.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off_outlined, size: 48, color: Color(0xFF6E7385)),
              const SizedBox(height: 12),
              Text(
                'No deals found for "${_searchController.text.trim()}"',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Color(0xFF6E7385),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Loop infinitely if search query is empty and we have a large product set
    final isLooping = _searchController.text.isEmpty && _filteredProducts.length >= 30;

    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.63, // Tightly fitted child size aspect ratio
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final product = isLooping
                ? _filteredProducts[index % _filteredProducts.length]
                : _filteredProducts[index];

            return ProductCard(
              product: product,
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) {
                    return FractionallySizedBox(
                      heightFactor: 0.9,
                      child: ProductDetailScreen(product: product),
                    );
                  },
                );
              },
            );
          },
          childCount: isLooping ? 10000 : _filteredProducts.length,
        ),
      ),
    );
  }

  // Shimmer skeleton placeholder cards loader
  Widget _buildShimmerGrid() {
    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.63,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildShimmerCard(),
          childCount: 8,
        ),
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7E8F0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image box placeholder
          Container(
            height: 130,
            padding: const EdgeInsets.all(10),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7FB),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title lines
                  Container(
                    width: double.infinity,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F7FB),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 80,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F7FB),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Spacer(),
                  // Prices placeholder
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F7FB),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 30,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F7FB),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Button
                  Container(
                    width: double.infinity,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F7FB),
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
  }

  // ── Offline Custom Screen ──
  Widget _buildOfflineScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon offline custom SVG design outline
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF17192B).withValues(alpha: 0.04),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: SvgPicture.string(
                  '''<svg viewBox="0 0 24 24" fill="none" stroke="#6E7385" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <line x1="1" y1="1" x2="23" y2="23"/>
                    <path d="M16.72 11.06A10.94 10.94 0 0 1 19 12.55"/>
                    <path d="M5 12.55a10.94 10.94 0 0 1 5.17-2.39"/>
                    <path d="M10.71 5.05A16 16 0 0 1 22.58 9"/>
                    <path d="M1.42 9a15.91 15.91 0 0 1 4.7-2.88"/>
                    <path d="M8.53 16.11a6 6 0 0 1 6.95 0"/>
                    <line x1="12" y1="20" x2="12.01" y2="20"/>
                  </svg>''',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'No Internet Connection',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: Color(0xFF1A1D2E),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Check your Wi-Fi or mobile data and try again — your deals will be right here waiting.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  color: Color(0xFF6E7385),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C47FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: _loadInitialData,
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
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

// ── Custom Sliver Persistent Header Delegate for Pinned Bar ──
class SearchAndTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController controller;
  final String activeTab;
  final ValueChanged<String> onTabChanged;
  final VoidCallback onSearchClear;

  SearchAndTabsHeaderDelegate({
    required this.controller,
    required this.activeTab,
    required this.onTabChanged,
    required this.onSearchClear,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // If headers is scrolled past index, consider stuck
    final isStuck = shrinkOffset > 8.0;

    return Container(
      color: const Color(0xFFF6F7FB),
      child: Column(
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: CustomSearchBar(
              controller: controller,
              onSearch: (_) {},
              onClear: onSearchClear,
            ),
          ),
          // Scrollable category tabs
          Expanded(
            child: CategoryTabs(
              activeTab: activeTab,
              onTabChanged: onTabChanged,
              isStuck: isStuck,
            ),
          ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 124.0; // 48 (search) + 76 (unstuck tabs)

  @override
  double get minExtent => 92.0; // 48 (search) + 44 (stuck tabs)

  @override
  bool shouldRebuild(covariant SearchAndTabsHeaderDelegate oldDelegate) {
    return oldDelegate.activeTab != activeTab ||
        oldDelegate.controller != controller;
  }
}
