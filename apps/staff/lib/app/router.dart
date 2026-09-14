import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/lock_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/checklist/checklist_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/leaderboard/leaderboard_screen.dart';
import '../features/ops/ops_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/quote/quote_confirmation_screen.dart';
import '../features/quote/quote_detail_screen.dart';
import '../features/quote/raise_quote_controller.dart';
import '../features/quote/raise_quote_screen.dart';
import '../features/scanner/scan_review_screen.dart';
import '../features/scanner/scan_screen.dart';
import '../features/shell/staff_shell.dart';
import '../features/sync/sync_centre_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/walk_in/walk_in_confirmation_screen.dart';
import '../features/walk_in/walk_in_flow.dart';
import '../features/walk_in/walk_in_screen.dart';
import '../widgets/page_transitions.dart';
import 'session.dart';

/// Route paths.
abstract final class Routes {
  static const signIn = '/sign-in';
  static const locked = '/locked';
  static const tasks = '/tasks';
  static const ops = '/ops';
  static const scan = '/scan';
  static const scanReview = '/scan/review';
  static const leaderboard = '/leaderboard';
  static const inventory = '/inventory';
  static const profile = '/profile';
  static const sync = '/sync';
  static const walkIn = '/walk-in';
  static const walkInScan = '/walk-in/scan';
  static const quoteNew = '/quote/new';

  static String checklist(String workOrderId) => '/tasks/$workOrderId';
  static String walkInConfirmation(String bookingId) =>
      '/walk-in/confirmation/$bookingId';
  static String quoteConfirmation(String quotationId) =>
      '/quote/confirmation/$quotationId';
  static String quoteDetail(String quotationId) => '/quotes/$quotationId';
}

GoRouter buildRouter(SessionController session) {
  return GoRouter(
    initialLocation: Routes.tasks,
    refreshListenable: session,
    redirect: (context, state) {
      final path = state.uri.path;
      if (!session.isSignedIn) {
        return path == Routes.signIn ? null : Routes.signIn;
      }
      if (session.locked) {
        return path == Routes.locked ? null : Routes.locked;
      }
      if (path == Routes.signIn || path == Routes.locked) return Routes.tasks;
      if (path == Routes.ops && !session.canSupervise) return Routes.scan;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.signIn,
        pageBuilder: (context, state) =>
            fadeThroughPage(state: state, child: const SignInScreen()),
      ),
      GoRoute(
        path: Routes.locked,
        pageBuilder: (context, state) =>
            fadeThroughPage(state: state, child: const LockScreen()),
      ),
      GoRoute(
        path: Routes.sync,
        pageBuilder: (context, state) => containerTransformPage(
          state: state,
          child: const SyncCentreScreen(),
        ),
      ),
      GoRoute(
        path: Routes.scanReview,
        pageBuilder: (context, state) => containerTransformPage(
          state: state,
          child: ScanReviewScreen(args: state.extra as ScanReviewArgs?),
        ),
      ),
      GoRoute(
        path: Routes.walkIn,
        pageBuilder: (context, state) => containerTransformPage(
          state: state,
          child: WalkInScreen(args: state.extra as WalkInArgs?),
        ),
      ),
      GoRoute(
        path: Routes.walkInScan,
        pageBuilder: (context, state) => containerTransformPage(
          state: state,
          child: const ScanScreen(pickResult: true),
        ),
      ),
      GoRoute(
        path: '/walk-in/confirmation/:bookingId',
        pageBuilder: (context, state) => fadeThroughPage(
          state: state,
          child: WalkInConfirmationScreen(
            bookingId: state.pathParameters['bookingId']!,
            outcome: state.extra as WalkInOutcome?,
          ),
        ),
      ),
      GoRoute(
        path: Routes.quoteNew,
        pageBuilder: (context, state) => containerTransformPage(
          state: state,
          child: RaiseQuoteScreen(args: state.extra as RaiseQuoteArgs?),
        ),
      ),
      GoRoute(
        path: '/quote/confirmation/:quotationId',
        pageBuilder: (context, state) => fadeThroughPage(
          state: state,
          child: QuoteConfirmationScreen(
            quotationId: state.pathParameters['quotationId']!,
            outcome: state.extra as RaiseQuoteOutcome?,
          ),
        ),
      ),
      GoRoute(
        path: '/quotes/:quotationId',
        pageBuilder: (context, state) => containerTransformPage(
          state: state,
          child: QuoteDetailScreen(
            quotationId: state.pathParameters['quotationId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/tasks/:workOrderId',
        pageBuilder: (context, state) => containerTransformPage(
          state: state,
          child: ChecklistScreen(
            workOrderId: state.pathParameters['workOrderId']!,
          ),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            StaffShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: Routes.tasks,
            pageBuilder: (context, state) =>
                fadeThroughPage(state: state, child: const TasksScreen()),
          ),
          GoRoute(
            path: Routes.ops,
            pageBuilder: (context, state) =>
                fadeThroughPage(state: state, child: const OpsScreen()),
          ),
          GoRoute(
            path: Routes.scan,
            pageBuilder: (context, state) =>
                fadeThroughPage(state: state, child: const ScanScreen()),
          ),
          GoRoute(
            path: Routes.leaderboard,
            pageBuilder: (context, state) => fadeThroughPage(
              state: state,
              child: const LeaderboardScreen(),
            ),
          ),
          GoRoute(
            path: Routes.inventory,
            pageBuilder: (context, state) =>
                fadeThroughPage(state: state, child: const InventoryScreen()),
          ),
          GoRoute(
            path: Routes.profile,
            pageBuilder: (context, state) =>
                fadeThroughPage(state: state, child: const ProfileScreen()),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri}')),
    ),
  );
}
