import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/svg_icons.dart';

/// Horizontally scrolling pill selector for the seven fixed categories.
class CategoryTabs extends StatelessWidget {
  const CategoryTabs({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        itemCount: kCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = kCategories[i];
          final isSelected = cat.key == selected;
          return _Chip(
            label: cat.label,
            icon: cat.icon,
            selected: isSelected,
            onTap: () => onSelect(cat.key),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgIcon(
              icon,
              size: 16,
              color: selected ? Colors.white : AppColors.ink700,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    color: selected ? Colors.white : AppColors.ink700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps the tab strip pinned under the app bar while scrolling the grid.
class CategoryTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  CategoryTabsHeaderDelegate({required this.child, this.height = 56});

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
