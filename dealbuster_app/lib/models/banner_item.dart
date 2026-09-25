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
    String? template,
    this.colors = const [],
    this.radialColor,
    this.badgeBg,
    this.badgeTextColor,
    this.background,
    this.radialLight,
  }) : _template = template;

  final String id;
  final String store; // 'myntra', 'flipkart', 'ajio', 'amazon' or with variant 'flipkart_2'
  final String storeName;
  final String? badgeText;
  final List<BannerLine> lines;
  final String imageUrl;
  final String link;
  final bool active;
  final int order;
  final String? _template;
  final List<String> colors;
  final String? radialColor;
  final String? badgeBg;
  final String? badgeTextColor;
  final String? background;
  final String? radialLight;

  String get storeKey {
    final s = store.toLowerCase().trim();
    if (s.contains('_')) return s.split('_')[0];
    return s;
  }

  String get template {
    if (_template != null && _template!.trim().isNotEmpty) {
      return _template!.toLowerCase().trim();
    }
    final s = store.toLowerCase().trim();
    if (s.contains('_')) return s;
    return '${s}_1';
  }

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
    final rawStore = (json['store'] as String? ?? 'myntra').toLowerCase();
    final rawTemplate = json['template'] as String? ?? json['theme'] as String?;
    final rawColors = json['colors'] as List<dynamic>?;
    final List<String> parsedColors = rawColors != null
        ? rawColors.map((c) => c.toString()).toList()
        : const [];

    return BannerItem(
      id: json['id'] as String? ?? '',
      store: rawStore,
      template: rawTemplate,
      storeName: json['storeName'] as String? ?? 'Store',
      badgeText: json['badgeText'] as String?,
      lines: rawLines
          .map((l) => BannerLine.fromJson(l as Map<String, dynamic>))
          .toList(),
      imageUrl: json['imageUrl'] as String? ?? '',
      link: json['link'] as String? ?? '',
      active: json['active'] as bool? ?? true,
      order: json['order'] as int? ?? 0,
      colors: parsedColors,
      radialColor: json['radialColor'] as String?,
      badgeBg: json['badgeBg'] as String?,
      badgeTextColor: json['badgeTextColor'] as String?,
      background: json['background'] as String?,
      radialLight: json['radialLight'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'store': store,
    'template': template,
    'storeName': storeName,
    'badgeText': badgeText,
    'lines': lines.map((l) => l.toJson()).toList(),
    'imageUrl': imageUrl,
    'link': link,
    'active': active,
    'order': order,
    if (colors.isNotEmpty) 'colors': colors,
    if (radialColor != null) 'radialColor': radialColor,
    if (badgeBg != null) 'badgeBg': badgeBg,
    if (badgeTextColor != null) 'badgeTextColor': badgeTextColor,
    if (background != null) 'background': background,
    if (radialLight != null) 'radialLight': radialLight,
  };
}
