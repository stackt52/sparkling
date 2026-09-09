import 'package:flutter/widgets.dart';
import 'package:sparkling_core/sparkling_core.dart';

import '../features/booking/booking_flow.dart';
import 'app_settings.dart';
import 'session.dart';

/// App-level controllers, available anywhere below [CustomerApp].
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.session,
    required this.settings,
    required this.bookingFlow,
    required super.child,
  });

  final SessionController session;
  final AppSettings settings;
  final BookingFlowController bookingFlow;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      session != oldWidget.session ||
      settings != oldWidget.settings ||
      bookingFlow != oldWidget.bookingFlow;
}

extension AppScopeX on BuildContext {
  SessionController get session => AppScope.of(this).session;
  AppSettings get settings => AppScope.of(this).settings;
  BookingFlowController get bookingFlow => AppScope.of(this).bookingFlow;
  Repositories get repos => RepositoriesScope.of(this);
}
