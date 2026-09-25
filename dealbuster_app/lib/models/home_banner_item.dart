import 'banner_item.dart';

class HomeBannerItem {
  const HomeBannerItem({
    required this.id,
    required this.store,
    required this.storeName,
    this.badgeText,
    this.lines = const [],
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.link,
    this.template = 'full_bg',
    this.applyEffect = false,
    this.active = true,
    this.order = 0,
    this.colors = const [],
    this.radialColor,
    this.badgeBg,
    this.badgeTextColor,
    this.background,
    this.radialLight,
  });

  final String id;
  final String store;
  final String storeName;
  final String template;
  final String? badgeText;
  final List<BannerLine> lines;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String link;
  final bool applyEffect;
  final bool active;
  final int order;
  final List<String> colors;
  final String? radialColor;
  final String? badgeBg;
  final String? badgeTextColor;
  final String? background;
  final String? radialLight;

  bool get isTemplate => template.isNotEmpty && template != 'full_bg';

  String get fullImageUrl {
    if (imageUrl.isEmpty) return '';
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    final clean = imageUrl.startsWith('/') ? imageUrl.substring(1) : imageUrl;
    return 'https://dealbuster.in/$clean';
  }

  List<BannerLine> get effectiveLines {
    if (lines.isNotEmpty) return lines;
    final res = <BannerLine>[];
    if (title.isNotEmpty) res.add(BannerLine(text: title, isBig: true));
    if (subtitle.isNotEmpty) res.add(BannerLine(text: subtitle, isBig: false));
    return res;
  }

  factory HomeBannerItem.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] as List<dynamic>?;
    final title = json['title'] as String? ?? '';
    final subtitle = json['subtitle'] as String? ?? '';
    final List<BannerLine> parsedLines = [];

    if (rawLines != null && rawLines.isNotEmpty) {
      for (final l in rawLines) {
        if (l is Map<String, dynamic>) {
          parsedLines.add(BannerLine.fromJson(l));
        }
      }
    } else {
      if (title.isNotEmpty) {
        parsedLines.add(BannerLine(text: title, isBig: true));
      }
      if (subtitle.isNotEmpty) {
        parsedLines.add(BannerLine(text: subtitle, isBig: false));
      }
    }

    final effectiveTitle = title.isNotEmpty
        ? title
        : (parsedLines.isNotEmpty ? parsedLines.first.text : '');
    final effectiveSubtitle = subtitle.isNotEmpty
        ? subtitle
        : (parsedLines.length > 1
            ? parsedLines.skip(1).map((l) => l.text).join(' ')
            : '');

    final rawColors = json['colors'] as List<dynamic>?;
    final List<String> parsedColors = rawColors != null
        ? rawColors.map((c) => c.toString()).toList()
        : const [];

    return HomeBannerItem(
      id: json['id'] as String? ?? '',
      store: (json['store'] as String? ?? 'amazon').toLowerCase(),
      storeName: json['storeName'] as String? ?? 'Amazon',
      template: json['template'] as String? ?? 'full_bg',
      badgeText: json['badgeText'] as String?,
      lines: parsedLines,
      title: effectiveTitle,
      subtitle: effectiveSubtitle,
      imageUrl: json['imageUrl'] as String? ?? '',
      link: json['link'] as String? ?? '',
      applyEffect: json['applyEffect'] as bool? ?? false,
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
    'storeName': storeName,
    'template': template,
    'badgeText': badgeText,
    'lines': lines.map((l) => l.toJson()).toList(),
    'title': title,
    'subtitle': subtitle,
    'imageUrl': imageUrl,
    'link': link,
    'applyEffect': applyEffect,
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
