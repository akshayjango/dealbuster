import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dealbuster_app/models/banner_item.dart';
import 'package:dealbuster_app/widgets/store_banner_card.dart';

void main() {
  testWidgets('StoreBannerCard renders successfully for all stores with SVG logos', (tester) async {
    final templates = [
      'myntra', 'flipkart', 'ajio', 'amazon',
      'flipkart_1', 'flipkart_2', 'flipkart_3',
      'amazon_1', 'amazon_2', 'amazon_3',
      'myntra_1', 'myntra_2', 'myntra_3',
      'ajio_1', 'ajio_2', 'ajio_3',
    ];

    for (final t in templates) {
      final banner = BannerItem(
        id: 'test_$t',
        store: t,
        storeName: t.toUpperCase(),
        badgeText: 'TEST BADGE',
        imageUrl: '',
        link: 'https://dealbuster.in',
        lines: const [
          BannerLine(text: 'Special Deal', isBig: false),
          BannerLine(text: '70% Off', isBig: true),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StoreBannerCard(banner: banner),
            ),
          ),
        ),
      );

      expect(find.byType(StoreBannerCard), findsOneWidget);
      expect(find.text('TEST BADGE'), findsOneWidget);
      expect(find.text('Special Deal'), findsOneWidget);
      expect(find.text('70% Off'), findsOneWidget);
    }
  });
}
