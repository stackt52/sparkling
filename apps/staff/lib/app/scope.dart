import 'package:flutter/widgets.dart';

import 'app_settings.dart';
import 'session.dart';
import 'sync_status.dart';

/// App-level controllers available to every screen.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.session,
    required this.sync,
    required super.child,
  });

  final AppSettings settings;
  final SessionController session;
  final SyncStatusController sync;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      settings != oldWidget.settings ||
      session != oldWidget.session ||
      sync != oldWidget.sync;
}

extension AppScopeX on BuildContext {
  AppScope get app => AppScope.of(this);
  AppSettings get settings => AppScope.of(this).settings;
  SessionController get session => AppScope.of(this).session;
  SyncStatusController get syncStatus => AppScope.of(this).sync;
}
