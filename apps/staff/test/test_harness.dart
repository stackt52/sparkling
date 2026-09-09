import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/app/app.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Per-test demo repositories. Bootstrapping does real file I/O (Hive), so it
/// must run in [setUp] (outside the FakeAsync zone of `testWidgets`).
class DemoHarness {
  late Directory _dir;
  late Repositories repos;

  /// Registers setUp/tearDown for the enclosing group / file.
  void install() {
    setUp(() async {
      SparklingTypography.useGoogleFonts = false;
      _dir = await Directory.systemTemp.createTemp('sparkling_staff_test_');
      HiveStore.reset();
      repos = await SparklingCore.bootstrap(
        demo: true,
        clientApp: 'staff',
        hivePath: _dir.path,
        demoUser: DemoPersonas.technician,
      );
    });
    tearDown(() async {
      // A test that failed mid-write can leave a Hive write parked on the
      // FakeAsync zone; bound the wait so the suite keeps going.
      Future<void> bounded(Future<dynamic> f) => f
          .then<void>((_) {})
          .timeout(const Duration(seconds: 5), onTimeout: () {});
      await bounded(repos.dispose());
      await bounded(Hive.deleteFromDisk());
      await bounded(Hive.close());
      HiveStore.reset();
      if (_dir.existsSync()) _dir.deleteSync(recursive: true);
    });
  }
}

/// Pumps the app at a phone-sized (412×915) or tablet-sized viewport as the
/// given demo persona.
Future<void> pumpStaffApp(
  WidgetTester tester,
  Repositories repos, {
  AuthUser persona = DemoPersonas.technician,
  Size size = const Size(412, 915),
}) async {
  if (repos.auth.currentUser?.uid != persona.uid) {
    await repos.auth.signInWithEmail(persona.email!, 'demo');
  }
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StaffApp(repositories: repos));
  await tester.pump();
  // Demo repositories add ~120 ms latency; settle streams.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Lets real I/O started inside the FakeAsync zone (Hive writes for
/// settings / drafts / queue) complete before the test ends. Call at the end
/// of every test.
Future<void> flushIo(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  await tester.pump();
}

/// Scrolls the top-most [Scrollable] until [finder] is visible (lazy lists
/// only build on-screen children). Tries downwards first, then upwards.
Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollable,
}) async {
  // Single-line text fields carry a horizontal Scrollable; skip those.
  final target =
      scrollable ??
      find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
  try {
    await tester.scrollUntilVisible(finder, 160, scrollable: target);
  } catch (_) {
    await tester.scrollUntilVisible(finder, -160, scrollable: target);
  }
  await tester.pump(const Duration(milliseconds: 200));
}

/// Pumps a few frames without waiting for infinite animations.
Future<void> settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Awaits a repository future inside the test's FakeAsync zone by pumping
/// frames until it completes (demo repositories use `Future.delayed`).
Future<T> pumpUntil<T>(WidgetTester tester, Future<T> future) async {
  T? value;
  Object? error;
  var done = false;
  future.then((v) {
    value = v;
    done = true;
  }, onError: (Object e) {
    error = e;
    done = true;
  });
  for (var i = 0; i < 50 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (!done) throw StateError('Future did not complete');
  if (error != null) throw error!;
  return value as T;
}
