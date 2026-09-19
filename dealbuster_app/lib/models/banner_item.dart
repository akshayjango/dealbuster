class BannerLine {
  const BannerLine({
    required this.text,
    this.isBig = false,
  });

  final String text;
  final bool isBig;

  factory BannerLine.fromJson(Map<String, dynamic> json) {
    final size = (json['size'] as String? ?? '').toLowerCase();
    final isBig = size == 'big' || json['isBig'] == true;
    return BannerLine(
      text: json['text'] as String? ?? '',
      isBig: isBig,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'size': isBig ? 'big' : 'small',
  };
}

class BannerItem {
  const BannerItem({
    required this.id,
    required this.store,
    required this.storeName,
    this.badgeText,
    required this.lines,
    required this.imageUrl,
    required this.link,
    this.active = true,
    this.order = 0,
  });

  final String id;
  final String store; // 'myntra', 'flipkart', 'ajio', 'amazon'
  final String storeName;
  final String? badgeText;
  final List<BannerLine> lines;
  final String imageUrl;
  final String link;
  final bool active;
  final int order;

  String get fullImageUrl {
    if (imageUrl.isEmpty) return '';
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    final clean = imageUrl.startsWith('/') ? imageUrl.substring(1) : imageUrl;
    return 'https://dealbuster.in/$clean';
  }

  factory BannerItem.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] as List<dynamic>? ?? [];
    return BannerItem(
      id: json['id'] as String? ?? '',
      store: (json['store'] as String? ?? 'myntra').toLowerCase(),
      storeName: json['storeName'] as String? ?? 'Store',
      badgeText: json['badgeText'] as String?,
      lines: rawLines
          .map((l) => BannerLine.fromJson(l as Map<String, dynamic>))
          .toList(),
      imageUrl: json['imageUrl'] as String? ?? '',
      link: json['link'] as String? ?? '',
      active: json['active'] as bool? ?? true,
      order: json['order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'store': store,
    'storeName': storeName,
    'badgeText': badgeText,
    'lines': lines.map((l) => l.toJson()).toList(),
    'imageUrl': imageUrl,
    'link': link,
    'active': active,
    'order': order,
  };
}
