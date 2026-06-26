import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../features/notifications/presentation/providers/notifications_provider.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    _NavTab(
      route: AppRoutes.home,
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
    ),
    _NavTab(
      route: AppRoutes.search,
      icon: Icons.search_outlined,
      activeIcon: Icons.search,
      label: 'Search',
    ),
    _NavTab(
      route: AppRoutes.notifications,
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      label: 'Activity',
      isNotifications: true,
    ),
    _NavTab(
      route: AppRoutes.profile,
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
    ),
  ];

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = _selectedIndex(context);
    final unreadCount = ref.watch(unreadNotificationsCountProvider);

    return Scaffold(
      body: child,
      floatingActionButton: _PostFAB(),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _BottomBar(
        selectedIndex: selectedIndex,
        unreadCount: unreadCount,
        onTabTapped: (i) => context.go(_tabs[i].route),
        tabs: _tabs,
      ),
    );
  }
}

class _PostFAB extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        gradient: AppColors.goldGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x66F9A825),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () => context.push(AppRoutes.newPost),
          child: const Icon(Icons.add, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.selectedIndex,
    required this.unreadCount,
    required this.onTabTapped,
    required this.tabs,
  });

  final int selectedIndex;
  final int unreadCount;
  final ValueChanged<int> onTabTapped;
  final List<_NavTab> tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68 + MediaQuery.of(context).padding.bottom,
      decoration: const BoxDecoration(
        color: AppColors.darkSurface,
        border: Border(
          top: BorderSide(color: AppColors.darkBorder, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Left two tabs
            for (int i = 0; i < 2; i++)
              Expanded(
                  child: _NavItem(
                tab: tabs[i],
                isSelected: selectedIndex == i,
                badge: 0,
                onTap: () => onTabTapped(i),
              )),

            // Center spacer for FAB
            const SizedBox(width: 72),

            // Right two tabs
            for (int i = 2; i < tabs.length; i++)
              Expanded(
                  child: _NavItem(
                tab: tabs[i],
                isSelected: selectedIndex == i,
                badge: tabs[i].isNotifications ? unreadCount : 0,
                onTap: () => onTabTapped(i),
              )),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.isSelected,
    required this.badge,
    required this.onTap,
  });

  final _NavTab tab;
  final bool isSelected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? tab.activeIcon : tab.icon,
                  color: isSelected
                      ? AppColors.secondary
                      : AppColors.textDarkSecondary,
                  size: 26,
                ),
                if (badge > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      constraints: const BoxConstraints(
                          minWidth: 16, minHeight: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.darkSurface, width: 1.5),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 3),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavTab {
  const _NavTab({
    required this.route,
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.isNotifications = false,
  });

  final String route;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isNotifications;
}
