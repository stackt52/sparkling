import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';

import 'app/app.dart';

/// Sparkling Outlet Staff app entry point.
///
/// * `--dart-define-from-file=env/demo.json` → in-memory demo repositories,
///   no Firebase / network.
/// * `--dart-define-from-file=env/dev.json` → Firebase Auth + REST API +
///   Supabase realtime.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.demoMode) {
    await Firebase.initializeApp();
  }
  final repositories = await SparklingCore.bootstrap(
    clientApp: 'staff',
    clientVersion: Env.appVersion,
  );
  runApp(StaffApp(repositories: repositories));
}
