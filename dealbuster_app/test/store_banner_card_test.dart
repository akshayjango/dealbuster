import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dealbuster_app/models/banner_item.dart';
import 'package:dealbuster_app/widgets/store_banner_card.dart';

void main() {
  testWidgets('StoreBannerCard renders successfully for all stores with SVG logos', (tester) async {
    final stores = ['myntra', 'flipkart', 'ajio', 'amazon'];

    for (final store in stores) {
      final banner = BannerItem(
        id: 'test_$store',
        store: store,
        storeName: store.toUpperCase(),
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
