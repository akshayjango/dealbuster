import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/banner_item.dart';
import '../models/offer.dart';
import '../models/product.dart';

class ApiService {
  static const String _productsUrl =
      'https://dealbuster-admin-api.vakshay083.workers.dev/public/products.json';
  static const String _cacheKey = 'db_products_cache_v1';
  static const String _offersUrl =
      'https://dealbuster-admin-api.vakshay083.workers.dev/public/offers';
  static const String _offersCacheKey = 'db_offers_cache_v1';
  static const String _bannersUrl =
      'https://dealbuster-admin-api.vakshay083.workers.dev/public/banners';
  static const String _bannersCacheKey = 'db_banners_cache_v1';

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
      // Log connection or timeout errors
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
      // Cache retrieval error
    }
    return [];
  }

  // Parse products from string body, filtering out hidden, dead, or zero-price products
  List<Product> _parseProducts(String jsonBody) {
    final parsed = jsonDecode(jsonBody);
    final List<dynamic> list = parsed is List ? parsed : (parsed['products'] ?? []);
    
    final uptoRegex = RegExp(r'\b(?:up\s*to|upto)\s*\d+\s*(?:%|percent)\s*off\b', caseSensitive: false);
    return list
        .map<Product>((json) => Product.fromJson(json))
        .where((p) => 
            !p.hidden && 
            !p.outOfStock &&
            p.price.isNotEmpty && 
            p.price != '₹0' && 
            p.price != '₹' &&
            !uptoRegex.hasMatch(p.title))
        .toList();
  }

  // ── CueLinks Offers (Coupons & Discounts) ─────────────────────────────
  Future<List<Offer>> fetchOffers({String? query, String? type, int page = 1}) async {
    return await fetchOffersFresh(query: query, type: type, page: page) ??
        await getCachedOffers();
  }

  Future<List<Offer>?> fetchOffersFresh({String? query, String? type, int page = 1}) async {
    try {
      final uri = Uri.parse(_offersUrl).replace(queryParameters: {
        'per_page': '50',
        'page': page.toString(),
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
      });

      final response = await http.get(uri).timeout(
        const Duration(seconds: 12),
      );

      if (response.statusCode == 200) {
        final String body = response.body;
        if (page == 1 && (query == null || query.isEmpty) && (type == null || type.isEmpty)) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_offersCacheKey, body);
        }
        return _parseOffers(body);
      }
    } catch (_) {
      // Fall through to return null so caller can decide or use cached
    }
    return null;
  }

  Future<List<Offer>> getCachedOffers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_offersCacheKey);
      if (cachedData != null) {
        return _parseOffers(cachedData);
      }
    } catch (_) {}
    return [];
  }

  List<Offer> _parseOffers(String jsonBody) {
    try {
      final parsed = jsonDecode(jsonBody);
      final List<dynamic> list = parsed is Map
          ? (parsed['offers'] ?? [])
          : (parsed is List ? parsed : []);

      return list
          .map<Offer>((item) => Offer.fromJson(item as Map<String, dynamic>))
          .where((o) => o.title.isNotEmpty && o.trackingUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Store Banners ──────────────────────────────────────────────────────────
  Future<List<BannerItem>> fetchBanners() async {
    return await fetchBannersFresh() ?? await getCachedBanners();
  }

  Future<List<BannerItem>?> fetchBannersFresh() async {
    try {
      final response = await http.get(Uri.parse(_bannersUrl)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final String body = response.body;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_bannersCacheKey, body);
        return _parseBanners(body);
      }
    } catch (_) {
      // Fall through to cache/fallback
    }
    return null;
  }

  Future<List<BannerItem>> getCachedBanners() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_bannersCacheKey);
      if (cachedData != null) {
        final banners = _parseBanners(cachedData);
        if (banners.isNotEmpty) return banners;
      }
    } catch (_) {}
    return _initialFallbackBanners;
  }

  List<BannerItem> _parseBanners(String jsonBody) {
    try {
      final parsed = jsonDecode(jsonBody);
      final List<dynamic> list = parsed is Map
          ? (parsed['banners'] ?? [])
          : (parsed is List ? parsed : []);

      return list
          .map<BannerItem>((item) => BannerItem.fromJson(item as Map<String, dynamic>))
          .where((b) => b.active && b.lines.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static const List<BannerItem> _initialFallbackBanners = [
    BannerItem(
      id: 'banner_myntra_1',
      store: 'myntra',
      storeName: 'Myntra',
      badgeText: 'LIMITED DEAL',
      lines: [
        BannerLine(text: 'Personal Care', isBig: false),
        BannerLine(text: 'Under', isBig: true),
        BannerLine(text: '₹1200', isBig: true),
      ],
      imageUrl: 'images/banners/myntra_personal_care.png',
      link: 'https://myntr.it/LbZjwv4',
    ),
    BannerItem(
      id: 'banner_myntra_2',
      store: 'myntra',
      storeName: 'Myntra',
      badgeText: 'HOT DEAL',
      lines: [
        BannerLine(text: 'WFH Casual Wear', isBig: false),
        BannerLine(text: 'Under', isBig: true),
        BannerLine(text: '₹399', isBig: true),
      ],
      imageUrl: '',
      link: 'https://myntr.it/p4q8L5W',
    ),
    BannerItem(
      id: 'banner_flipkart_1',
      store: 'flipkart',
      storeName: 'Flipkart',
      badgeText: 'SUMMER DEAL',
      lines: [
        BannerLine(text: 'Min 50% Off', isBig: true),
        BannerLine(text: 'on Best Selling', isBig: false),
        BannerLine(text: 'Watches', isBig: true),
      ],
      imageUrl: 'images/banners/flipkart_sunscreen.png',
      link: 'https://fktr.in/A11kK4v',
    ),
    BannerItem(
      id: 'banner_ajio_1',
      store: 'ajio',
      storeName: 'AJIO',
      badgeText: 'TRENDING DEAL',
      lines: [
        BannerLine(text: 'Upto', isBig: true),
        BannerLine(text: '75% Off', isBig: true),
        BannerLine(text: 'on Skybags', isBig: false),
        BannerLine(text: 'Backpacks', isBig: false),
      ],
      imageUrl: 'images/banners/ajio_skybags.png',
      link: 'https://ajiio.in/v9Nk4S1',
    ),
    BannerItem(
      id: 'banner_amazon_1',
      store: 'amazon',
      storeName: 'Amazon',
      badgeText: 'AMAZON EXCLUSIVE',
      lines: [
        BannerLine(text: 'Upto', isBig: true),
        BannerLine(text: '30% Off', isBig: true),
        BannerLine(text: 'on Action Cameras', isBig: false),
      ],
      imageUrl: '',
      link: 'https://link.amazon/B036zv4CE',
    ),
  ];
}
