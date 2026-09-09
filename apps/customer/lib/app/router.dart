import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';

import '../features/auth/reset_password_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/sign_up_screen.dart';
import '../features/booking/confirmation_screen.dart';
import '../features/booking/payment_screen.dart';
import '../features/booking/service_select_screen.dart';
import '../features/booking/slot_picker_screen.dart';
import '../features/bookings/booking_detail_screen.dart';
import '../features/bookings/bookings_screen.dart';
import '../features/home/home_screen.dart';
import '../features/loyalty/loyalty_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/quotes/quote_detail_screen.dart';
import '../features/quotes/quote_request_screen.dart';
import '../features/quotes/quotes_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/sync/sync_status_screen.dart';
import '../features/tracking/tracking_screen.dart';
import '../features/vehicles/scan_review_screen.dart';
import '../features/vehicles/scan_screen.dart';
import '../features/vehicles/vehicle_form_screen.dart';
import '../features/vehicles/vehicles_screen.dart';
import '../widgets/transitions.dart';
import 'session.dart';

/// Route paths (single source of truth for `context.go/push`).
abstract final class Routes {
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const reset = '/reset-password';

  static const home = '/home';
  static const bookings = '/bookings';
  static const loyalty = '/loyalty';
  static const profile = '/profile';

  static const bookService = '/book';
  static const bookSlot = '/book/slot';
  static const bookPay = '/book/pay';
  static String bookDone(String id) => '/booked/$id';

  static String bookingDetail(String id) => '/bookings/$id';
  static String track(String id) => '/bookings/$id/track';

  static const vehicles = '/vehicles';
  static const vehicleAdd = '/vehicles/add';
  static String vehicleEdit(String id) => '/vehicles/$id/edit';
  static const scan = '/vehicles/scan';
  static const scanReview = '/vehicles/scan/review';

  static const quotes = '/quotes';
  static const quoteNew = '/quotes/new';
  static String quote(String id) => '/quotes/$id';

  static const notifications = '/notifications';
  static const sync = '/sync';
}

GoRouter buildRouter(SessionController session) {
  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: session,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final authRoute =
          loc == Routes.signIn || loc == Routes.signUp || loc == Routes.reset;
      if (!session.isSignedIn) return authRoute ? null : Routes.signIn;
      if (authRoute) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.signIn,
        pageBuilder: (c, s) => fadePage(s, const SignInScreen()),
      ),
      GoRoute(
        path: Routes.signUp,
        pageBuilder: (c, s) => sharedAxisPage(s, const SignUpScreen()),
      ),
      GoRoute(
        path: Routes.reset,
        pageBuilder: (c, s) => sharedAxisPage(s, const ResetPasswordScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                pageBuilder: (c, s) => fadePage(s, const HomeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.bookings,
                pageBuilder: (c, s) => fadePage(s, const BookingsScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.loyalty,
                pageBuilder: (c, s) => fadePage(s, const LoyaltyScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                pageBuilder: (c, s) => fadePage(s, const ProfileScreen()),
              ),
            ],
          ),
        ],
      ),
      // ---- Booking detail & live tracking (full screen) ----
      GoRoute(
        path: '/bookings/:id',
        pageBuilder: (c, s) => sharedAxisPage(
          s,
          BookingDetailScreen(
            bookingId: s.pathParameters['id']!,
            initial: s.extra is Booking ? s.extra as Booking : null,
          ),
        ),
        routes: [
          GoRoute(
            path: 'track',
            pageBuilder: (c, s) => sharedAxisPage(
              s,
              TrackingScreen(bookingId: s.pathParameters['id']!),
            ),
          ),
        ],
      ),
      // ---- Booking flow (shared-axis X between steps) ----
      GoRoute(
        path: Routes.bookService,
        pageBuilder: (c, s) => sharedAxisPage(s, const ServiceSelectScreen()),
        routes: [
          GoRoute(
            path: 'slot',
            pageBuilder: (c, s) => sharedAxisPage(s, const SlotPickerScreen()),
          ),
          GoRoute(
            path: 'pay',
            pageBuilder: (c, s) => sharedAxisPage(s, const PaymentScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/booked/:id',
        pageBuilder: (c, s) => fadeThroughPage(
          s,
          ConfirmationScreen(
            bookingId: s.pathParameters['id']!,
            initial: s.extra is Booking ? s.extra as Booking : null,
          ),
        ),
      ),
      // ---- Vehicles ----
      GoRoute(
        path: Routes.vehicles,
        pageBuilder: (c, s) => sharedAxisPage(s, const VehiclesScreen()),
        routes: [
          GoRoute(
            path: 'add',
            pageBuilder: (c, s) => sharedAxisPage(
              s,
              VehicleFormScreen(
                prefill: s.extra is DiscScanResult
                    ? s.extra as DiscScanResult
                    : null,
              ),
            ),
          ),
          GoRoute(
            path: 'scan',
            pageBuilder: (c, s) => fadeThroughPage(s, const ScanScreen()),
            routes: [
              GoRoute(
                path: 'review',
                pageBuilder: (c, s) => fadeThroughPage(
                  s,
                  ScanReviewScreen(result: s.extra as DiscScanResult),
                ),
              ),
            ],
          ),
          GoRoute(
            path: ':id/edit',
            pageBuilder: (c, s) => sharedAxisPage(
              s,
              VehicleFormScreen(
                vehicleId: s.pathParameters['id'],
                existing: s.extra is Vehicle ? s.extra as Vehicle : null,
              ),
            ),
          ),
        ],
      ),
      // ---- Quotations ----
      GoRoute(
        path: Routes.quotes,
        pageBuilder: (c, s) => sharedAxisPage(s, const QuotesScreen()),
        routes: [
          GoRoute(
            path: 'new',
            pageBuilder: (c, s) =>
                sharedAxisPage(s, const QuoteRequestScreen()),
          ),
          GoRoute(
            path: ':id',
            pageBuilder: (c, s) => sharedAxisPage(
              s,
              QuoteDetailScreen(quotationId: s.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.notifications,
        pageBuilder: (c, s) => sharedAxisPage(s, const NotificationsScreen()),
      ),
      GoRoute(
        path: Routes.sync,
        pageBuilder: (c, s) => sharedAxisPage(s, const SyncStatusScreen()),
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
}
