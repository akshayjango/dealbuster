import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/svg_icons.dart';

/// Horizontally scrolling icon-over-label tab strip for the seven fixed
/// categories, underlined divider below and a small indicator bar marking
/// the selected tab — a plain tab bar rather than filled pill chips.
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
      height: 60.0,
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(24, 8, AppSpace.md, 0),
              itemCount: kCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 30),
              itemBuilder: (context, i) {
                final cat = kCategories[i];
                final isSelected = cat.key == selected;
                return _Tab(
                  label: cat.label,
                  icon: cat.icon,
                  selected: isSelected,
                  onTap: () => onSelect(cat.key),
                );
              },
            ),
          ),
          Container(height: 1, color: AppColors.hairline),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
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
    final color = selected ? AppColors.ink : AppColors.ink400;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SvgIcon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 12.5,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 3.5,
            width: 38,
            decoration: BoxDecoration(
              color: selected ? AppColors.brand : Colors.transparent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the tab strip pinned under the app bar while scrolling the grid.
class CategoryTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  CategoryTabsHeaderDelegate({required this.child, this.height = 60});

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
