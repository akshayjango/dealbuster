import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dealbuster_app/screens/stores_screen.dart';
import 'package:dealbuster_app/screens/offers_screen.dart';

import 'package:dealbuster_app/screens/feed_screen.dart';
import 'package:dealbuster_app/widgets/deal_badges.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FeedScreen displays title, illustration, and Coming Soon text without buttons or cards', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FeedScreen(),
      ),
    );
    await tester.pump();

    // Verify title "Feed"
    expect(find.text('Feed'), findsOneWidget);

    // Verify headline "Coming Soon"
    expect(find.text('Coming Soon'), findsOneWidget);

    // Verify description
    expect(
      find.text('Discover the latest deals, price drops, shopping updates, and connect with a growing community of deal hunters.'),
      findsOneWidget,
    );

    // Verify image asset
    expect(find.byType(Image), findsOneWidget);

    // Verify no buttons or cards
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('StoresScreen has root RefreshIndicator', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StoresScreen(),
      ),
    );
    await tester.pump();

    // Verify RefreshIndicator is at the root of the body inside SafeArea
    final refreshFinder = find.byType(RefreshIndicator);
    expect(refreshFinder, findsOneWidget);

    final safeAreaFinder = find.byType(SafeArea);
    expect(safeAreaFinder, findsOneWidget);

    // RefreshIndicator is a descendant of SafeArea
    expect(find.descendant(of: safeAreaFinder, matching: refreshFinder), findsOneWidget);

    // CustomScrollView is descendant of RefreshIndicator
    expect(find.descendant(of: refreshFinder, matching: find.byType(CustomScrollView)), findsOneWidget);
  });

  testWidgets('OffersScreen has root RefreshIndicator', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OffersScreen(),
      ),
    );
    await tester.pump();

    // Verify RefreshIndicator is at root under SafeArea
    final refreshFinder = find.byType(RefreshIndicator);
    expect(refreshFinder, findsOneWidget);

    final safeAreaFinder = find.byType(SafeArea);
    expect(safeAreaFinder, findsOneWidget);

    // RefreshIndicator is a descendant of SafeArea
    expect(find.descendant(of: safeAreaFinder, matching: refreshFinder), findsOneWidget);

    // CustomScrollView is descendant of RefreshIndicator
    expect(find.descendant(of: refreshFinder, matching: find.byType(CustomScrollView)), findsOneWidget);

    // Sticky header contains search bar and tabs in Column
    expect(find.descendant(of: refreshFinder, matching: find.byType(Column)), findsWidgets);
  });

  testWidgets('PriceDropBadge renders with graph arrow line down icon and text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PriceDropBadge(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Price Drop'), findsOneWidget);
    expect(find.byIcon(Icons.trending_down_rounded), findsOneWidget);
  });
}
