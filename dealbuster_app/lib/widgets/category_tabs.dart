import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/svg_icons.dart';

class CategoryTabs extends StatelessWidget {
  final String activeTab;
  final ValueChanged<String> onTabChanged;
  final bool isStuck;

  const CategoryTabs({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    required this.isStuck,
  });

  static const List<Map<String, String>> _tabConfig = [
    {'id': 'deals', 'label': 'Deals', 'icon': SvgIcons.deals},
    {'id': 'all', 'label': 'All', 'icon': SvgIcons.all},
    {'id': 'beauty', 'label': 'Beauty', 'icon': SvgIcons.beauty},
    {'id': 'fashion', 'label': 'Fashion', 'icon': SvgIcons.fashion},
    {'id': 'health', 'label': 'Health', 'icon': SvgIcons.health},
    {'id': 'home', 'label': 'Home', 'icon': SvgIcons.home},
    {'id': 'electronics', 'label': 'Electronics', 'icon': SvgIcons.electronics},
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Exactly 5 tabs visible at a time
    final tabWidth = (screenWidth - 6) / 5;

    return Container(
      height: isStuck ? 44 : 76,
      decoration: const BoxDecoration(
        color: Color(0xFFF6F7FB),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabConfig.length,
        padding: const EdgeInsets.only(left: 4),
        itemBuilder: (context, index) {
          final tab = _tabConfig[index];
          final id = tab['id']!;
          final label = tab['label']!;
          final iconStr = tab['icon']!;
          final isActive = activeTab == id;

          return SizedBox(
            width: tabWidth,
            child: GestureDetector(
              onTap: () => onTabChanged(id),
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Color(0xFFE7E8F0),
                      width: 2,
                    ),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Tab Content (collapsing icons based on scroll state)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: isStuck ? 12 : 8,
                        horizontal: 6,
                      ),
                      child: isStuck
                          ? Text(
                              label,
                              style: TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 13,
                                color: isActive
                                    ? const Color(0xFF1A1D2E)
                                    : const Color(0xFF6E7385),
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: SvgPicture.string(
                                    iconStr,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                    fontSize: 11,
                                    color: isActive
                                        ? const Color(0xFF1A1D2E)
                                        : const Color(0xFF6E7385),
                                  ),
                                ),
                              ],
                            ),
                    ),

                    // Underline indicator
                    if (isActive)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 0,
                        child: Container(
                          height: 4.5,
                          decoration: const BoxDecoration(
                            color: Color(0xFF6E7385),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(5),
                              topRight: Radius.circular(5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
