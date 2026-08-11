import 'package:flutter/material.dart';
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
const _whatsappUrl = 'https://whatsapp.com/channel/0029Va9g5AX3AzNYTk4Bd12W';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();

  List<Product> _all = [];
  String _category = 'deals';
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final products = await _api.fetchProducts();
      if (!mounted) return;
      setState(() {
        _all = products;
        _loading = false;
        _failed = products.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  List<Product> get _filtered {
    if (_category == 'all') return _all;
    if (_category == 'deals') {
      return _all.where((p) {
        final price =
            double.tryParse(p.price.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                0.0;
        return price > 0 && price < 500;
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: ProductDetailScreen(product: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.brand,
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _TopBar(onLaunch: _launch)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.md,
                  AppSpace.sm,
                  AppSpace.md,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: DealSearchBar(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SearchScreen()),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: HeroBanner(liveDealCount: _all.length),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: CategoryTabsHeaderDelegate(
                  child: CategoryTabs(
                    selected: _category,
                    onSelect: (c) => setState(() => _category = c),
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
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.56,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => ProductCard(
                        product: items[i],
                        onTap: () => _openProduct(items[i]),
                      ),
                      childCount: items.length,
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onLaunch});
  final Future<void> Function(String) onLaunch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
      child: Row(
        children: [
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.headlineMedium,
              children: const [
                TextSpan(text: 'Deal'),
                TextSpan(text: 'Buster', style: TextStyle(color: AppColors.brand)),
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
  const _IconPill({required this.icon, required this.color, required this.onTap});
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
          childAspectRatio: 0.56,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          childCount: 6,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 40, color: AppColors.ink400),
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
