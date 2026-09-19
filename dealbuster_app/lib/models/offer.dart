class Offer {
  const Offer({
    required this.id,
    required this.title,
    required this.description,
    required this.campaignName,
    required this.campaignId,
    required this.offerType,
    required this.couponCode,
    this.originalPrice,
    this.discountPrice,
    this.percentOff,
    this.startDate,
    this.endDate,
    required this.trackingUrl,
    this.imageUrl,
    this.terms,
    this.status,
  });

  final String id;
  final String title;
  final String description;
  final String campaignName;
  final String campaignId;
  final String offerType;
  final String couponCode;
  final String? originalPrice;
  final String? discountPrice;
  final String? percentOff;
  final String? startDate;
  final String? endDate;
  final String trackingUrl;
  final String? imageUrl;
  final String? terms;
  final String? status;

  bool get isCoupon =>
      offerType.toLowerCase() == 'coupon' || couponCode.trim().isNotEmpty;

  /// Returns a clean discount callout, e.g. "FLAT 40% OFF" or "90% OFF"
  String? get discountBadge {
    if (percentOff != null && percentOff!.trim().isNotEmpty) {
      final clean = percentOff!.replaceAll('%', '').trim();
      if (clean.isNotEmpty) {
        return '$clean% OFF';
      }
    }
    if (discountPrice != null && originalPrice != null) {
      try {
        final disc = double.tryParse(discountPrice!.replaceAll(RegExp(r'[^\d.]'), ''));
        final orig = double.tryParse(originalPrice!.replaceAll(RegExp(r'[^\d.]'), ''));
        if (disc != null && orig != null && orig > disc) {
          final diff = (orig - disc).round();
          if (diff > 0) return 'SAVE ₹$diff';
        }
      } catch (_) {}
    }
    return null;
  }

  /// Extracts and formats ONLY the expiry date (e.g. "30 Sep 2026", "4 days", "Today")
  String? get formattedExpiry {
    if (endDate == null || endDate!.trim().isEmpty) return null;
    final raw = endDate!.trim();
    try {
      final date = DateTime.tryParse(raw.split(' ').first);
      if (date == null) return raw;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(date.year, date.month, date.day);
      final differenceInDays = target.difference(today).inDays;

      if (differenceInDays == 0) {
        return 'Today';
      } else if (differenceInDays == 1) {
        return 'Tomorrow';
      } else if (differenceInDays > 1 && differenceInDays <= 5) {
        return '$differenceInDays days';
      }

      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final monthStr = months[date.month - 1];
      return '${date.day} $monthStr ${date.year}';
    } catch (_) {
      return raw;
    }
  }

  factory Offer.fromJson(Map<String, dynamic> json) {
    return Offer(
      id: json['id']?.toString() ?? '',
      title: (json['title'] ?? '').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      campaignName: (json['campaign_name'] ?? json['campaign']?['name'] ?? 'Partner Store')
          .toString()
          .trim(),
      campaignId: json['campaign_id']?.toString() ?? '',
      offerType: (json['offer_type'] ?? 'deal').toString().trim(),
      couponCode: (json['coupon_code'] ?? '').toString().trim(),
      originalPrice: json['original_price']?.toString(),
      discountPrice: json['discount_price']?.toString(),
      percentOff: json['percent_off']?.toString(),
      startDate: json['start_date']?.toString(),
      endDate: json['end_date']?.toString(),
      trackingUrl: (json['tracking_url'] ?? json['url'] ?? '').toString().trim(),
      imageUrl: (json['image_url'] ?? json['campaign_image'])?.toString(),
      terms: json['terms']?.toString(),
      status: json['status']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'campaign_name': campaignName,
      'campaign_id': campaignId,
      'offer_type': offerType,
      'coupon_code': couponCode,
      'original_price': originalPrice,
      'discount_price': discountPrice,
      'percent_off': percentOff,
      'start_date': startDate,
      'end_date': endDate,
      'tracking_url': trackingUrl,
      'image_url': imageUrl,
      'terms': terms,
      'status': status,
    };
  }
}
