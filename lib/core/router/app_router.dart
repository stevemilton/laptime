import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'route_names.dart';
import '../../features/recording/presentation/record_screen.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/sectors/presentation/sectors_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../theme/app_colors.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/record',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return AppShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/record',
          name: RouteNames.record,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: RecordScreen(),
          ),
        ),
        GoRoute(
          path: '/feed',
          name: RouteNames.feed,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: FeedScreen(),
          ),
        ),
        GoRoute(
          path: '/sectors',
          name: RouteNames.sectors,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SectorsScreen(),
          ),
        ),
        GoRoute(
          path: '/profile',
          name: RouteNames.profile,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ProfileScreen(),
          ),
        ),
      ],
    ),
  ],
);

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  static int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/record')) return 0;
    if (location.startsWith('/feed')) return 1;
    if (location.startsWith('/sectors')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) {
            switch (index) {
              case 0:
                context.go('/record');
              case 1:
                context.go('/feed');
              case 2:
                context.go('/sectors');
              case 3:
                context.go('/profile');
            }
          },
          backgroundColor: AppColors.white,
          indicatorColor: Colors.transparent,
          elevation: 0,
          height: 84,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: Icon(
                LucideIcons.timer,
                color: selectedIndex == 0 ? AppColors.purple : AppColors.textTertiary,
              ),
              label: 'Record',
            ),
            NavigationDestination(
              icon: Icon(
                LucideIcons.rss,
                color: selectedIndex == 1 ? AppColors.purple : AppColors.textTertiary,
              ),
              label: 'Feed',
            ),
            NavigationDestination(
              icon: Icon(
                LucideIcons.flag,
                color: selectedIndex == 2 ? AppColors.purple : AppColors.textTertiary,
              ),
              label: 'Sectors',
            ),
            NavigationDestination(
              icon: Icon(
                LucideIcons.user,
                color: selectedIndex == 3 ? AppColors.purple : AppColors.textTertiary,
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
