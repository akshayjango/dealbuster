import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dealbuster_app/models/home_banner_item.dart';
import 'package:dealbuster_app/widgets/hero_banner.dart';

void main() {
  testWidgets('HeroBanner renders default animated banner when enabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeroBanner(
            liveDealCount: 42,
            showDefaultAnimatedBanner: true,
            customBanners: [],
          ),
        ),
      ),
    );

    expect(find.byType(HeroBanner), findsOneWidget);
    expect(find.text("Deals that\ndon't wait."), findsOneWidget);
    expect(find.text('42 deals live now'), findsOneWidget);
  });

  testWidgets('HeroBanner renders custom banner when provided', (tester) async {
    final customBanner = HomeBannerItem(
      id: 'test_hbanner_1',
      store: 'amazon',
      storeName: 'Amazon',
      badgeText: 'MEGA SALE',
      title: 'Top Electronics Deals',
      subtitle: 'Up to 70% Off on Smartphones',
      imageUrl: '',
      link: 'https://dealbuster.in',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeroBanner(
            liveDealCount: 10,
            showDefaultAnimatedBanner: false,
            customBanners: [customBanner],
          ),
        ),
      ),
    );

    expect(find.byType(HeroBanner), findsOneWidget);
    expect(find.byType(SvgPicture), findsWidgets);
    expect(find.text('MEGA SALE'), findsOneWidget);
    expect(find.text('Top Electronics Deals'), findsOneWidget);
    expect(find.text('Up to 70% Off on Smartphones'), findsOneWidget);
  });

  testWidgets('HeroBanner returns shrink SizedBox when default is disabled and custom is empty', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeroBanner(
            liveDealCount: 10,
            showDefaultAnimatedBanner: false,
            customBanners: [],
          ),
        ),
      ),
    );

    final heroFinder = find.byType(HeroBanner);
    expect(heroFinder, findsOneWidget);
    // Inside HeroBanner, child is SizedBox.shrink()
    expect(find.byType(PageView), findsNothing);
    expect(find.text("Deals that\ndon't wait."), findsNothing);
  });
}
