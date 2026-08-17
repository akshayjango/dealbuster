import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';

class ApiService {
  static const String _productsUrl =
      'https://dealbuster-admin-api.vakshay083.workers.dev/public/products.json';
  static const String _cacheKey = 'db_products_cache_v1';

  // Fetch live products with dynamic updates. Falls back to the on-disk
  // cache on failure, so callers that just want "something to show" (the
  // initial screen load) can't tell fresh data from a stale fallback —
  // use [fetchProductsFresh] instead when that distinction matters (e.g.
  // background refresh, where silently re-serving stale cached data would
  // look like "checked and there's nothing new" when it's really "the
  // request failed").
  Future<List<Product>> fetchProducts() async {
    return await fetchProductsFresh() ?? await getCachedProducts();
  }

  // Same fetch, but returns null on any failure instead of masking it
  // with the local cache.
  Future<List<Product>?> fetchProductsFresh() async {
    try {
      final response = await http.get(Uri.parse(_productsUrl)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final String body = response.body;
        // Cache the response string
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, body);

        return _parseProducts(body);
      }
    } catch (e) {
      // Log connection or timeout errors — caller decides how to handle it.
      print('ApiService Error: $e');
    }
    return null;
  }

  // Retrieve cached products
  Future<List<Product>> getCachedProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cacheKey);
      if (cachedData != null) {
        return _parseProducts(cachedData);
      }
    } catch (e) {
      print('Cache retrieval error: $e');
    }
    return [];
  }

  // Parse products from string body, filtering out hidden, dead, or zero-price products
  List<Product> _parseProducts(String jsonBody) {
    final parsed = jsonDecode(jsonBody);
    final List<dynamic> list = parsed is List ? parsed : (parsed['products'] ?? []);
    
    return list
        .map<Product>((json) => Product.fromJson(json))
        .where((p) => 
            !p.hidden && 
            !p.outOfStock &&
            p.price.isNotEmpty && 
            p.price != '₹0' && 
            p.price != '₹')
        .toList();
  }
}
