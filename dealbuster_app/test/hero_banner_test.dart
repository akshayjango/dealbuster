import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dealbuster_app/models/home_banner_item.dart';
import 'package:dealbuster_app/screens/home_screen.dart';
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

  testWidgets('HeroBanner renders PageView when multiple banners are present', (tester) async {
    final b1 = const HomeBannerItem(
      id: 'b1',
      store: 'flipkart',
      storeName: 'Flipkart',
      title: 'Flipkart Fest',
      subtitle: 'Big Savings',
      imageUrl: '',
      link: 'https://flipkart.com',
    );
    final b2 = const HomeBannerItem(
      id: 'b2',
      store: 'myntra',
      storeName: 'Myntra',
      title: 'Fashion carnival',
      subtitle: 'Up to 80% off',
      imageUrl: '',
      link: 'https://myntra.com',
      applyEffect: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeroBanner(
            liveDealCount: 10,
            showDefaultAnimatedBanner: false,
            customBanners: [b1, b2],
          ),
        ),
      ),
    );

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('Flipkart Fest'), findsOneWidget);
  });

  testWidgets('HeroBanner renders template-based custom banner with badge and lines', (tester) async {
    final tplBanner = const HomeBannerItem(
      id: 'tpl_banner_1',
      store: 'amazon',
      storeName: 'Amazon',
      template: 'amazon_light',
      badgeText: 'FESTIVE SALE',
      title: 'Mega Tech Deals',
      subtitle: 'Up to 50% off',
      imageUrl: '',
      link: 'https://amazon.in',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeroBanner(
            liveDealCount: 15,
            showDefaultAnimatedBanner: false,
            customBanners: [tplBanner],
          ),
        ),
      ),
    );

    expect(find.byType(HeroBanner), findsOneWidget);
    expect(find.text('FESTIVE SALE'), findsOneWidget);
    expect(find.text('Mega Tech Deals'), findsOneWidget);
    expect(find.text('Up to 50% off'), findsOneWidget);
  });

  testWidgets('HomeHeaderDelegate allocates 192dp height when banner or skeleton is active', (tester) async {
    final delegate = HomeHeaderDelegate(
      searchBar: const SizedBox(),
      heroBanner: const SizedBox(height: 176),
      categoryTabs: const SizedBox(),
      hasBanner: true,
    );
    expect(delegate.hasBanner, isTrue);
    expect(delegate.bannerHeight, 192.0);
    expect(delegate.maxExtent, 62.0 + 192.0 + 48.0);
  });
}
