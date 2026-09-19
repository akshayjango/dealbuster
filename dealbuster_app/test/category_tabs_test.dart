import 'package:dealbuster_app/widgets/category_tabs.dart';
import 'package:dealbuster_app/widgets/sort_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CategoryTabs displays Under 500, Sort: New, and other categories', (tester) async {
    String selectedCategory = 'sort';
    String sortOption = 'new';
    bool sortTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryTabs(
            selected: selectedCategory,
            sortOption: sortOption,
            onSortTap: () => sortTapped = true,
            onSelect: (cat) => selectedCategory = cat,
          ),
        ),
      ),
    );

    // Verify presence of Under 500 tab
    expect(find.text('Under 500'), findsOneWidget);

    // Verify presence of dynamic Sort tab
    expect(find.text('Sort: New'), findsOneWidget);

    // Verify presence of standard categories
    expect(find.text('Beauty'), findsOneWidget);
    expect(find.text('Fashion'), findsOneWidget);

    // Tap Under 500 tab
    await tester.tap(find.text('Under 500'));
    await tester.pump();
    expect(selectedCategory, 'under_500');

    // Tap Sort tab
    await tester.tap(find.text('Sort: New'));
    await tester.pump();
    expect(selectedCategory, 'sort');
    expect(sortTapped, isTrue);
  });

  testWidgets('CategoryTabs updates label when sort option changes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryTabs(
            selected: 'sort',
            sortOption: 'lowest_price',
            onSortTap: () {},
            onSelect: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Sort: Lowest price'), findsOneWidget);
  });

  testWidgets('Tapping an active sort tab deselects it with sort_reset', (tester) async {
    String selectedAction = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryTabs(
            selected: 'sort',
            sortOption: 'lowest_price',
            onSortTap: () {},
            onSelect: (cat) => selectedAction = cat,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sort: Lowest price'));
    await tester.pump();
    expect(selectedAction, 'sort_reset');
  });

  testWidgets('SortBottomSheet shows all 6 required sort options and selects', (tester) async {
    String chosenSort = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showSortBottomSheet(
                  context: context,
                  currentSort: 'new',
                  onSelectSort: (s) => chosenSort = s,
                );
              },
              child: const Text('Open Sort'),
            ),
          ),
        ),
      ),
    );

    // Open sheet
    await tester.tap(find.text('Open Sort'));
    await tester.pumpAndSettle();

    // Verify all 6 options are present
    expect(find.text('Sort'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Lowest price'), findsOneWidget);
    expect(find.text('Coupon'), findsOneWidget);
    expect(find.text('Discount'), findsOneWidget);
    expect(find.text('Price - low to high'), findsOneWidget);
    expect(find.text('Price - high to low'), findsOneWidget);

    // Tap 'Price - low to high'
    await tester.tap(find.text('Price - low to high'));
    await tester.pumpAndSettle();

    expect(chosenSort, 'low_to_high');
  });
}
