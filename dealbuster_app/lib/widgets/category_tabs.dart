import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../utils/svg_icons.dart';
import 'sort_bottom_sheet.dart';

/// Horizontally scrolling fully rounded rectangle capsule (pill) tab strip.
///
/// Features capsule chips with subtle borders, active states tinted with brand
/// color, and dynamic sort label support with bottom sheet modal trigger.
class CategoryTabs extends StatelessWidget {
  const CategoryTabs({
    super.key,
    required this.selected,
    required this.onSelect,
    this.sortOption = 'new',
    this.onSortTap,
    this.controller,
  });

  final String selected;
  final ValueChanged<String> onSelect;
  final String sortOption;
  final VoidCallback? onSortTap;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      height: 48.0,
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                6,
                AppSpace.md,
                10,
              ),
              itemCount: kCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, i) {
                final cat = kCategories[i];
                final isSort = cat.key == 'sort';
                // Do not show selected state for Sort: New (since it is default);
                // show selected state for other sort options and other tabs.
                final isSelected = isSort
                    ? (selected == 'sort' && sortOption != 'new')
                    : (cat.key == selected);

                final label = isSort
                    ? 'Sort: ${getSortLabel(sortOption)}'
                    : cat.label;

                return _CapsuleTab(
                  label: label,
                  icon: cat.icon,
                  selected: isSelected,
                  isSort: isSort,
                  onTap: () {
                    if (isSort) {
                      if (isSelected) {
                        onSelect('sort_reset');
                      } else {
                        onSelect('sort');
                        onSortTap?.call();
                      }
                    } else {
                      onSelect(cat.key);
                    }
                  },
                );
              },
            ),
          ),
          Container(
            height: 0.6,
            color: const Color(0xFF14121F).withValues(alpha: 0.06),
          ),
        ],
      ),
    );
  }
}

class _CapsuleTab extends StatelessWidget {
  const _CapsuleTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isSort,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool selected;
  final bool isSort;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // No fill for selected state; background remains clean surface
    const bgColor = AppColors.surface;

    // Reduced stroke color: delicate hairline stroke instead of heavy outline
    final borderColor = selected
        ? AppColors.brand
        : const Color(0xFFEDEAF2);

    final textColor = selected
        ? AppColors.brand
        : AppColors.ink700;

    const iconColor = AppColors.brand;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: borderColor,
              width: 0.9,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SvgIcon(icon, size: 13.5, color: iconColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: textColor,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  height: 1.1,
                ),
              ),
              if (isSort) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: textColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps the tab strip pinned under the app bar while scrolling the grid.
class CategoryTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  CategoryTabsHeaderDelegate({required this.child, this.height = 48.0});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: AppColors.bg,
      elevation: overlapsContent ? 2 : 0,
      shadowColor: AppColors.ink.withValues(alpha: 0.08),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant CategoryTabsHeaderDelegate oldDelegate) =>
      oldDelegate.child != child;
}
