import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import 'product_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _api = ApiService();
  final _controller = TextEditingController();

  List<Product> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api.fetchProducts().then((products) {
      if (!mounted) return;
      setState(() {
        _all = products;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Product> get _results {
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return [];
    return _all.where((p) => p.title.toLowerCase().contains(query)).toList();
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
    final query = _controller.text.trim();
    final results = _results;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: DealSearchBar(
                      editable: true,
                      autofocus: true,
                      controller: _controller,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                  : query.isEmpty
                      ? const _SearchPrompt()
                      : results.isEmpty
                          ? _NoResults(query: query)
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpace.md,
                                0,
                                AppSpace.md,
                                AppSpace.xl,
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 0.56,
                              ),
                              itemCount: results.length,
                              itemBuilder: (context, i) => ProductCard(
                                product: results[i],
                                onTap: () => _openProduct(results[i]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.travel_explore_rounded, size: 42, color: AppColors.ink400),
            const SizedBox(height: 12),
            Text(
              'Find deals by product name',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 42, color: AppColors.ink400),
            const SizedBox(height: 12),
            Text(
              'No deals found for "$query"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
