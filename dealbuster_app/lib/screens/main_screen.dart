import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/deal_bottom_nav_bar.dart';
import 'home_screen.dart';
import 'offers_screen.dart';
import 'placeholder_screens.dart';
import 'stores_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final ValueNotifier<bool> _isTabBarVisible = ValueNotifier<bool>(true);
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final GlobalKey<StoresScreenState> _storesKey = GlobalKey<StoresScreenState>();
  final GlobalKey<OffersScreenState> _offersKey = GlobalKey<OffersScreenState>();

  @override
  void dispose() {
    _isTabBarVisible.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) {
      if (index == 0) {
        // Tapped active Deals tab -> reset to Sort: New, scroll to top, and refresh
        _homeKey.currentState?.handleDealsTabTap();
      } else if (index == 1) {
        // Tapped active Stores tab -> reset to All Stores and scroll to top
        _storesKey.currentState?.resetToDefault();
      } else if (index == 2) {
        // Tapped active Offers tab -> reset to Coupons tab, scroll to top and clear search if active
        _offersKey.currentState?.handleOffersTabTap();
      }
      return;
    }

    final previousIndex = _currentIndex;
    setState(() {
      _currentIndex = index;
    });

    if (index == 0) {
      // Switched to Deals tab -> reset to Sort: New, scroll to top, and refresh
      _homeKey.currentState?.handleDealsTabTap();
    } else if (index == 1) {
      // Returning back to Stores tab -> reset to All Stores (default)
      _storesKey.currentState?.resetToDefault();
    } else if (index == 2) {
      // Returning back to Offers tab -> reset to Coupons tab (default), clear search and show top
      _offersKey.currentState?.resetSearchAndScrollToTop();
    }

    if (previousIndex == 1 && index != 1) {
      // Switched away from Stores tab -> reset to All Stores
      _storesKey.currentState?.resetToDefault();
    } else if (previousIndex == 2 && index != 2) {
      // Switched away from Offers tab -> reset to Coupons, clear search and reset to top
      _offersKey.currentState?.resetSearchAndScrollToTop();
    }

    // Always restore tab bar visibility when switching tabs
    if (!_isTabBarVisible.value) {
      _isTabBarVisible.value = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 0) {
          if (_currentIndex == 1) {
            _storesKey.currentState?.resetToDefault();
          } else if (_currentIndex == 2) {
            _offersKey.currentState?.resetSearchAndScrollToTop();
          }
          setState(() => _currentIndex = 0);
          _isTabBarVisible.value = true;
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: [
                HomeScreen(
                  key: _homeKey,
                  isTabBarVisible: _isTabBarVisible,
                ),
                StoresScreen(
                  key: _storesKey,
                  isTabBarVisible: _isTabBarVisible,
                ),
                OffersScreen(
                  key: _offersKey,
                  isTabBarVisible: _isTabBarVisible,
                ),
                const FeedPlaceholderScreen(),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ValueListenableBuilder<bool>(
                valueListenable: _isTabBarVisible,
                builder: (context, isVisible, _) {
                  return DealBottomNavBar(
                    currentIndex: _currentIndex,
                    onTap: _onTabTapped,
                    isVisible: isVisible,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
