import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dealbuster_app/screens/stores_screen.dart';
import 'package:dealbuster_app/screens/offers_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    // RefreshIndicator contains the main column and scrollable content
    expect(find.descendant(of: refreshFinder, matching: find.byType(Column)), findsWidgets);
    expect(find.descendant(of: refreshFinder, matching: find.byType(ListView)), findsWidgets);
  });
}
