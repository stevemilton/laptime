import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'route_names.dart';
import '../../features/recording/presentation/record_screen.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/sectors/presentation/sectors_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/disclaimer/presentation/disclaimer_screen.dart';
import '../../features/recording/presentation/recording_screen.dart';
import '../../features/session/presentation/session_detail_screen.dart';
import '../../features/session/presentation/session_edit_screen.dart';
import '../../features/session/presentation/session_summary_screen.dart';
import '../../features/session/presentation/sessions_list_screen.dart';
import '../../features/session/presentation/lap_detail_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/garage/presentation/car_form_screen.dart';
import '../../features/garage/presentation/garage_screen.dart';
import '../../features/sectors/presentation/sector_creation_screen.dart';
import '../../features/sectors/presentation/sector_from_lap_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/legal_screen.dart';
import '../../features/social/presentation/following_screen.dart';
import '../../features/social/presentation/teams_screen.dart';
import '../../features/social/presentation/team_detail_screen.dart';
import '../../features/social/presentation/team_search_screen.dart';
import '../../features/social/presentation/team_join_requests_screen.dart';
import '../../features/social/presentation/create_team_screen.dart';
import '../../features/social/presentation/crew_detail_screen.dart';
import '../../features/telemetry/presentation/lap_comparison_screen.dart';
import '../theme/app_colors.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Notifier that triggers GoRouter redirect re-evaluation when auth
/// or disclaimer state changes — without recreating the router.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    _subs = [
      ref.listen<bool>(isAuthenticatedProvider, (_, _) => notifyListeners()),
      ref.listen<AsyncValue<bool>>(
          hasAcceptedDisclaimerProvider, (_, _) => notifyListeners()),
    ];
  }

  late final List<ProviderSubscription<dynamic>> _subs;

  @override
  void dispose() {
    for (final s in _subs) {
      s.close();
    }
    super.dispose();
  }
}

/// GoRouter provider — created once, uses [refreshListenable] so that
/// auth / disclaimer changes trigger redirect re-evaluation without
/// destroying and recreating the router (which caused GlobalKey conflicts
/// and navigation state loss).
final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  ref.onDispose(() => notifier.dispose());

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/record',
    refreshListenable: notifier,
    redirect: (context, state) {
      final isAuthenticated = ref.read(isAuthenticatedProvider);
      final disclaimerAsync = ref.read(hasAcceptedDisclaimerProvider);

      final path = state.uri.path;
      final onLogin = path == '/login';
      final onVerifyEmail = path == '/verify-email';
      final onDisclaimer = path == '/disclaimer';

      // Not authenticated -> login (but allow verify-email screen)
      if (!isAuthenticated) {
        return (onLogin || onVerifyEmail) ? null : '/login';
      }

      // Authenticated but on login or verify -> redirect away
      if (onLogin || onVerifyEmail) {
        return '/disclaimer';
      }

      // Check disclaimer acceptance
      final hasAccepted = disclaimerAsync.when(
        data: (accepted) => accepted,
        loading: () => false,
        error: (_, _) => false,
      );

      // Need disclaimer acceptance
      if (!hasAccepted) {
        return onDisclaimer ? null : '/disclaimer';
      }

      // On disclaimer but already accepted -> go to record
      if (onDisclaimer) {
        return '/record';
      }

      // No redirect needed
      return null;
    },
    routes: [
      // Auth
      GoRoute(
        path: '/login',
        name: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        name: RouteNames.verifyEmail,
        builder: (context, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return VerifyEmailScreen(email: email);
        },
      ),
      GoRoute(
        path: '/disclaimer',
        name: RouteNames.disclaimer,
        builder: (context, state) => const DisclaimerScreen(),
      ),

      // Full-screen recording (no bottom tabs)
      GoRoute(
        path: '/recording',
        name: RouteNames.recording,
        builder: (context, state) => const RecordingScreen(),
      ),

      // All sessions list (full-screen, no bottom tabs)
      GoRoute(
        path: '/sessions',
        name: RouteNames.sessions,
        builder: (context, state) => const SessionsListScreen(),
      ),

      // Session detail (full-screen, no bottom tabs)
      GoRoute(
        path: '/session/:id',
        name: RouteNames.sessionDetail,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return SessionDetailScreen(sessionId: id);
        },
      ),

      // Session summary (post-recording, full-screen)
      GoRoute(
        path: '/session/:id/summary',
        name: RouteNames.sessionSummary,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return SessionSummaryScreen(sessionId: id);
        },
      ),

      // Session edit (full-screen, no bottom tabs)
      GoRoute(
        path: '/session/:id/edit',
        name: RouteNames.sessionEdit,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return SessionEditScreen(sessionId: id);
        },
      ),

      // Lap detail (full-screen, no bottom tabs)
      GoRoute(
        path: '/session/:id/lap/:lapId',
        name: RouteNames.lapDetail,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final lapId = state.pathParameters['lapId']!;
          return LapDetailScreen(sessionId: id, lapId: lapId);
        },
      ),

      // Lap comparison (full-screen, no bottom tabs)
      GoRoute(
        path: '/session/:id/compare',
        name: RouteNames.lapComparison,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final lap1 = state.uri.queryParameters['lap1'] ?? '';
          final lap2 = state.uri.queryParameters['lap2'] ?? '';
          return LapComparisonScreen(
            sessionId: id,
            lap1Id: lap1,
            lap2Id: lap2,
          );
        },
      ),

      // Edit profile (full-screen)
      GoRoute(
        path: '/edit-profile',
        name: RouteNames.editProfile,
        builder: (context, state) => const EditProfileScreen(),
      ),

      // Garage list (full-screen)
      GoRoute(
        path: '/garage',
        name: RouteNames.garage,
        builder: (context, state) => const GarageScreen(),
      ),

      // Car form - new or edit (full-screen)
      GoRoute(
        path: '/car/new',
        name: '${RouteNames.carForm}-new',
        builder: (context, state) => const CarFormScreen(),
      ),
      GoRoute(
        path: '/car/:id',
        name: RouteNames.carForm,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return CarFormScreen(carId: id);
        },
      ),

      // Sector creation (full-screen)
      GoRoute(
        path: '/sector/create',
        name: RouteNames.sectorCreation,
        builder: (context, state) => const SectorCreationScreen(),
      ),

      // Sector from lap (full-screen)
      GoRoute(
        path: '/sector/from-lap',
        name: RouteNames.sectorFromLap,
        builder: (context, state) => const SectorFromLapScreen(),
      ),

      // Settings (full-screen)
      GoRoute(
        path: '/settings',
        name: RouteNames.settings,
        builder: (context, state) => const SettingsScreen(),
      ),


      // Legal screens (full-screen)
      GoRoute(
        path: '/privacy-policy',
        name: RouteNames.privacyPolicy,
        builder: (context, state) => const LegalScreen(
          title: 'Privacy Policy',
          assetPath: 'assets/legal/privacy.md',
        ),
      ),
      GoRoute(
        path: '/terms',
        name: RouteNames.terms,
        builder: (context, state) => const LegalScreen(
          title: 'Terms and Conditions',
          assetPath: 'assets/legal/terms.md',
        ),
      ),
      GoRoute(
        path: '/legal-disclaimer',
        name: RouteNames.legalDisclaimer,
        builder: (context, state) => const LegalScreen(
          title: 'Disclaimer',
          assetPath: 'assets/legal/disclaimer.md',
        ),
      ),

      // Social screens (full-screen)
      GoRoute(
        path: '/following',
        name: RouteNames.following,
        builder: (context, state) => const FollowingScreen(),
      ),
      GoRoute(
        path: '/teams',
        name: RouteNames.teams,
        builder: (context, state) => const TeamsScreen(),
      ),
      GoRoute(
        path: '/team/create',
        name: RouteNames.createTeam,
        builder: (context, state) => const CreateTeamScreen(),
      ),
      GoRoute(
        path: '/team-search',
        name: RouteNames.teamSearch,
        builder: (context, state) => const TeamSearchScreen(),
      ),
      GoRoute(
        path: '/team/:id',
        name: RouteNames.teamDetail,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return TeamDetailScreen(teamId: id);
        },
      ),
      GoRoute(
        path: '/team/:id/requests',
        name: RouteNames.teamJoinRequests,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return TeamJoinRequestsScreen(teamId: id);
        },
      ),
      GoRoute(
        path: '/crew/:id',
        name: RouteNames.crewDetail,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return CrewDetailScreen(crewId: id);
        },
      ),

      // Main app shell with bottom tabs
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
});

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
                color: selectedIndex == 0
                    ? AppColors.purple
                    : AppColors.textTertiary,
              ),
              label: 'Record',
            ),
            NavigationDestination(
              icon: Icon(
                LucideIcons.rss,
                color: selectedIndex == 1
                    ? AppColors.purple
                    : AppColors.textTertiary,
              ),
              label: 'Feed',
            ),
            NavigationDestination(
              icon: Icon(
                LucideIcons.flag,
                color: selectedIndex == 2
                    ? AppColors.purple
                    : AppColors.textTertiary,
              ),
              label: 'Sectors',
            ),
            NavigationDestination(
              icon: Icon(
                LucideIcons.user,
                color: selectedIndex == 3
                    ? AppColors.purple
                    : AppColors.textTertiary,
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
