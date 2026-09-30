import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../services/search_service.dart';
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

  String _lastQuery = '';
  List<Product> _cachedResults = [];
  List<String> _cachedSuggestions = [];

  @override
  void initState() {
    super.initState();
    _all = widget.initialProducts;
    _controller.addListener(_onQueryChanged);
    if (_all.isEmpty) {
      _loading = true;
      _api.fetchProducts().then((products) {
        if (!mounted) return;
        setState(() {
          _all = products;
          _loading = false;
          _lastQuery = '';
          _onQueryChanged();
        });
      });
    } else {
      _onQueryChanged();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final query = _controller.text.trim();
    if (query == _lastQuery) return;
    _lastQuery = query;
    if (query.isEmpty) {
      _cachedResults = [];
      _cachedSuggestions = [];
    } else {
      _cachedResults = SearchService.search(_all, query);
      _cachedSuggestions = query.length >= 2
          ? SearchService.getSuggestions(_all, query, limit: 6)
          : [];
    }
    if (mounted) setState(() {});
  }

  void _openProduct(Product product) {
    FocusScope.of(context).unfocus();
    showProductDetailSheet(context, product);
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final results = _cachedResults;
    final suggestions = _cachedSuggestions;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: AppColors.bg,
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    child: DealSearchBar(
                      editable: true,
                      autofocus: true,
                      controller: _controller,
                      onChanged: (_) => _onQueryChanged(),
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                        scrollDirection: Axis.horizontal,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final s = suggestions[i];
                          return Material(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(10),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                _controller.text = s;
                                _controller.selection = TextSelection.fromPosition(
                                  TextPosition(offset: s.length),
                                );
                                setState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 11),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.search_rounded,
                                      size: 16,
                                      color: Color(0xFF555B62),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      s,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF2D3135),
                                        letterSpacing: -0.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
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
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(
                                AppSpace.md,
                                10,
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
