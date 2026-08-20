class PricePoint {
  final DateTime date;
  final double price;

  PricePoint({required this.date, required this.price});

  factory PricePoint.fromJson(Map<String, dynamic> json) {
    // Parse price string (e.g. "₹418") to double
    final priceStr = json['price']?.toString() ?? '0';
    final parsedPrice = double.tryParse(priceStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    
    // Parse date
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(json['date']?.toString() ?? DateTime.now().toIso8601String());
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return PricePoint(date: parsedDate, price: parsedPrice);
  }
}

class Product {
  final String id;
  final String? asin;
  final String title;
  final String price;
  final String mrp;
  final String disc;
  final String image;
  final String link;
  final String category;
  final List<String> highlights;
  final String? lowestPriceText;
  final bool featured;
  final bool hidden;
  final bool outOfStock;
  final int order;
  final String addedAt;
  final double rating;
  final List<PricePoint> priceHistory;

  Product({
    required this.id,
    this.asin,
    required this.title,
    required this.price,
    required this.mrp,
    required this.disc,
    required this.image,
    required this.link,
    required this.category,
    required this.highlights,
    this.lowestPriceText,
    required this.featured,
    required this.hidden,
    required this.outOfStock,
    required this.order,
    required this.addedAt,
    required this.rating,
    required this.priceHistory,
  });

  // Replicate web logic for displaying title: title.split('|')[0].trim()
  // Also strips leading bracketed tags like "[Apply 5% Coupon] [MRP Error]"
  // that some feeds prepend to the title.
  String get displayTitle {
    final base = title.split('|')[0].trim();
    final stripped =
        base.replaceFirst(RegExp(r'^(\s*\[[^\]]*\]\s*)+'), '').trim();
    return stripped.isEmpty ? base : stripped;
  }

  // Pulls a coupon percentage (e.g. "5%") out of a leading "[Apply 5%
  // Coupon]"-style tag, if the feed prepended one — null for plain "[Bank
  // Offer ICICI/HDFC]" tags with no coupon percentage, or no tags at all.
  String? get couponPercent {
    final base = title.split('|')[0].trim();
    final leading = RegExp(r'^(\s*\[[^\]]*\]\s*)+').firstMatch(base);
    if (leading == null) return null;
    for (final tag in RegExp(r'\[([^\]]*)\]').allMatches(leading.group(0)!)) {
      final label = tag.group(1) ?? '';
      if (!label.toLowerCase().contains('coupon')) continue;
      final pct = RegExp(r'(\d+)\s*%').firstMatch(label);
      if (pct != null) return '${pct.group(1)}%';
    }
    return null;
  }

  // Replicate savings calculation logic
  int get savingsAmount {
    final cur = int.tryParse(price.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final ori = int.tryParse(mrp.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    return (ori > cur) ? (ori - cur) : 0;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    var historyList = json['priceHistory'] as List?;
    List<PricePoint> history = historyList != null
        ? historyList.map((h) => PricePoint.fromJson(h)).toList()
        : [];
        
    // Sort history by date
    history.sort((a, b) => a.date.compareTo(b.date));

    return Product(
      id: json['id']?.toString() ?? '',
      asin: json['asin']?.toString(),
      title: decodeHtmlEntities(json['title']?.toString() ?? ''),
      price: json['price']?.toString() ?? '₹0',
      mrp: json['mrp']?.toString() ?? '₹0',
      disc: json['disc']?.toString() ?? '0%',
      image: json['image']?.toString() ?? '',
      link: json['link']?.toString() ?? '',
      category: (json['category']?.toString() ?? 'other').toLowerCase(),
      highlights: List<String>.from(json['highlights'] ?? [])
          .map((h) => decodeHtmlEntities(h))
          .toList(),
      lowestPriceText: json['lowestPriceText']?.toString(),
      featured: json['featured'] == true,
      hidden: json['hidden'] == true,
      outOfStock: json['outOfStock'] == true,
      order: json['order'] is int ? json['order'] : 0,
      addedAt: json['addedAt']?.toString() ?? '',
      rating: double.tryParse(json['rating']?.toString() ?? '0.0') ?? 0.0,
      priceHistory: history,
    );
  }
}

String decodeHtmlEntities(String text) {
  if (text.isEmpty) return text;
  var decoded = text;
  
  // Named entities
  decoded = decoded.replaceAll('&quot;', '"');
  decoded = decoded.replaceAll('&apos;', "'");
  decoded = decoded.replaceAll('&amp;', '&');
  decoded = decoded.replaceAll('&lt;', '<');
  decoded = decoded.replaceAll('&gt;', '>');
  decoded = decoded.replaceAll('&nbsp;', ' ');
  
  // Decimal numeric entities
  decoded = decoded.replaceAll('&#34;', '"');
  decoded = decoded.replaceAll('&#39;', "'");
  decoded = decoded.replaceAll('&#38;', '&');
  decoded = decoded.replaceAll('&#60;', '<');
  decoded = decoded.replaceAll('&#62;', '>');
  decoded = decoded.replaceAll('&#160;', ' ');
  
  // Typographic smart quotes and dashes
  decoded = decoded.replaceAll('&#8211;', '–');
  decoded = decoded.replaceAll('&#8212;', '—');
  decoded = decoded.replaceAll('&#8216;', '‘');
  decoded = decoded.replaceAll('&#8217;', '’');
  decoded = decoded.replaceAll('&#8220;', '“');
  decoded = decoded.replaceAll('&#8221;', '”');
  
  return decoded;
}
