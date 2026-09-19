class HomeBannerItem {
  const HomeBannerItem({
    required this.id,
    required this.store,
    required this.storeName,
    this.badgeText,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.link,
    this.active = true,
    this.order = 0,
  });

  final String id;
  final String store;
  final String storeName;
  final String? badgeText;
  final String title;
  final String subtitle;
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

  factory HomeBannerItem.fromJson(Map<String, dynamic> json) {
    return HomeBannerItem(
      id: json['id'] as String? ?? '',
      store: (json['store'] as String? ?? 'amazon').toLowerCase(),
      storeName: json['storeName'] as String? ?? 'Amazon',
      badgeText: json['badgeText'] as String?,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
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
    'title': title,
    'subtitle': subtitle,
    'imageUrl': imageUrl,
    'link': link,
    'active': active,
    'order': order,
  };
}

class HomeBannersData {
  const HomeBannersData({
    this.showDefaultAnimatedBanner = true,
    this.banners = const [],
  });

  final bool showDefaultAnimatedBanner;
  final List<HomeBannerItem> banners;

  factory HomeBannersData.fromJson(Map<String, dynamic> json) {
    final rawBanners = json['banners'] as List<dynamic>? ?? [];
    return HomeBannersData(
      showDefaultAnimatedBanner: json['showDefaultAnimatedBanner'] as bool? ?? true,
      banners: rawBanners
          .map((b) => HomeBannerItem.fromJson(b as Map<String, dynamic>))
          .where((b) => b.active)
          .toList(),
    );
  }
}
