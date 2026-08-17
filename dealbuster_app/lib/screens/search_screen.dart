import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import 'product_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  // The home screen already has the full catalog in memory by the time
  // search is reachable — passing it straight in makes results appear
  // instantly instead of re-fetching over the network on every open.
  // [initialProducts] only falls back to a fresh fetch if it's empty.
  const SearchScreen({super.key, this.initialProducts = const []});

  final List<Product> initialProducts;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _api = ApiService();
  final _controller = TextEditingController();

  late List<Product> _all;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _all = widget.initialProducts;
    if (_all.isEmpty) {
      _loading = true;
      _api.fetchProducts().then((products) {
        if (!mounted) return;
        setState(() {
          _all = products;
          _loading = false;
        });
      });
    }
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
    FocusScope.of(context).unfocus();
    showProductDetailSheet(context, product);
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
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
              child: DealSearchBar(
                editable: true,
                autofocus: true,
                controller: _controller,
                onChanged: (_) => setState(() {}),
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: query.isEmpty
                  ? const SizedBox.shrink()
                  : _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.brand,
                          ),
                        )
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
                                childAspectRatio: 0.68,
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
