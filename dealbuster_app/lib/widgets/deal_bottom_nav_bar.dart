import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class DealBottomNavBar extends StatelessWidget {
  const DealBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.isVisible,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isVisible;

  static const double barHeight = 54.0;

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sliding & collapsing Tab Bar (Deals, Stores, Offers, Feed)
        ClipRect(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            height: isVisible ? barHeight : 0.0,
            child: OverflowBox(
              minHeight: barHeight,
              maxHeight: barHeight,
              alignment: Alignment.topCenter,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubic,
                offset: isVisible ? Offset.zero : const Offset(0, 1.0),
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    border: const Border(
                      top: BorderSide(
                        color: AppColors.hairline,
                        width: 0.8,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF14121F).withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _NavBarItem(
                        index: 0,
                        label: 'Deals',
                        selectedIcon: Icons.local_fire_department_rounded,
                        unselectedIcon: Icons.local_fire_department_outlined,
                        isSelected: currentIndex == 0,
                        onTap: () => _handleTap(0),
                        iconSize: 26.0,
                      ),
                      _NavBarItem(
                        index: 1,
                        label: 'Stores',
                        selectedIcon: Icons.storefront_rounded,
                        unselectedIcon: Icons.storefront_outlined,
                        isSelected: currentIndex == 1,
                        onTap: () => _handleTap(1),
                      ),
                      _NavBarItem(
                        index: 2,
                        label: 'Offers',
                        selectedIcon: Icons.confirmation_number_rounded,
                        unselectedIcon: Icons.confirmation_number_outlined,
                        isSelected: currentIndex == 2,
                        onTap: () => _handleTap(2),
                      ),
                      _NavBarItem(
                        index: 3,
                        label: 'Feed',
                        selectedIcon: Icons.explore_rounded,
                        unselectedIcon: Icons.explore_outlined,
                        isSelected: currentIndex == 3,
                        onTap: () => _handleTap(3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // System Navigation Bar Safe Area: Solid white on scroll up, semi-transparent frosted white on scroll down
        if (bottomPadding > 0)
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: isVisible ? 0.0 : 16.0,
                sigmaY: isVisible ? 0.0 : 16.0,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubic,
                height: bottomPadding,
                decoration: BoxDecoration(
                  color: isVisible ? AppColors.bg : const Color(0xD9FFFFFF),
                  border: Border(
                    top: BorderSide(
                      color: isVisible ? Colors.transparent : const Color(0x18000000),
                      width: 0.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _handleTap(int index) {
    HapticFeedback.selectionClick();
    onTap(index);
  }
}

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.index,
    required this.label,
    required this.selectedIcon,
    required this.unselectedIcon,
    required this.isSelected,
    required this.onTap,
    this.iconSize = 24.0,
  });

  final int index;
  final String label;
  final IconData selectedIcon;
  final IconData unselectedIcon;
  final bool isSelected;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.brand : const Color(0xFF717171);

    return Expanded(
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        splashFactory: InkRipple.splashFactory,
        radius: 36,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 2.5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    isSelected ? selectedIcon : unselectedIcon,
                    key: ValueKey<bool>(isSelected),
                    size: iconSize,
                    color: color,
                  ),
                ),
                const SizedBox(height: 1.5),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    height: 1.15,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
