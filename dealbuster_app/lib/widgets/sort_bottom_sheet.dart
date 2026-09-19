import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../utils/svg_icons.dart';

class SortOption {
  final String key;
  final String label;

  const SortOption(this.key, this.label);
}

const List<SortOption> kSortOptions = [
  SortOption('new', 'New'),
  SortOption('lowest_price', 'Lowest price'),
  SortOption('coupon', 'Coupon'),
  SortOption('discount', 'Discount'),
  SortOption('low_to_high', 'Price - low to high'),
  SortOption('high_to_low', 'Price - high to low'),
];

String getSortLabel(String key) {
  for (final opt in kSortOptions) {
    if (opt.key == key) return opt.label;
  }
  return 'New';
}

/// Displays the Sort bottom sheet modal as shown in reference design.
Future<void> showSortBottomSheet({
  required BuildContext context,
  required String currentSort,
  required ValueChanged<String> onSelectSort,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _SortSheet(
      currentSort: currentSort,
      onSelect: (selectedKey) {
        Navigator.of(ctx).pop();
        onSelectSort(selectedKey);
      },
    ),
  );
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({
    required this.currentSort,
    required this.onSelect,
  });

  final String currentSort;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header Row: Icon + Title on left, Close button on right
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
              child: Row(
                children: [
                  const SvgIcon(
                    SvgIcons.sort,
                    size: 20,
                    color: AppColors.brand,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sort',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    splashRadius: 22,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: AppColors.ink,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: AppColors.hairline),
            // Options List
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: kSortOptions.length,
              itemBuilder: (context, index) {
                final option = kSortOptions[index];
                final isSelected = option.key == currentSort;

                return InkWell(
                  onTap: () => onSelect(option.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.label,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.brand
                                  : AppColors.ink700,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_rounded,
                            color: AppColors.brand,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: bottomInset > 0 ? 8 : 16),
          ],
        ),
      ),
    );
  }
}