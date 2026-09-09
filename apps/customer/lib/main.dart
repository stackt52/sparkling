import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase (Auth + Messaging) is only needed against the live backend;
  // demo mode runs fully on-device (SparklingCore demo repositories).
  if (!Env.demoMode) {
    await Firebase.initializeApp();
  }
  final repositories = await SparklingCore.bootstrap(clientApp: 'customer');
  runApp(CustomerApp(repositories: repositories));
}
