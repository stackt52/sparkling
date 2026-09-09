import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'app_settings.dart';
import 'router.dart';
import 'scope.dart';
import 'session.dart';
import 'sync_status.dart';

/// Root widget: wires repositories, settings, session and sync controllers,
/// the dark-first theme, reduced-motion scope and the router.
class StaffApp extends StatefulWidget {
  const StaffApp({super.key, required this.repositories, this.idleTimeout});

  final Repositories repositories;

  /// Override the session idle timeout (tests).
  final Duration? idleTimeout;

  @override
  State<StaffApp> createState() => _StaffAppState();
}

class _StaffAppState extends State<StaffApp> with WidgetsBindingObserver {
  late final AppSettings _settings = AppSettings(widget.repositories.drafts);
  late final SessionController _session = SessionController(
    widget.repositories,
    idleTimeout: widget.idleTimeout ?? const Duration(minutes: 30),
  );
  late final SyncStatusController _sync = SyncStatusController(
    widget.repositories,
  );
  late final GoRouter _router = buildRouter(_session);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _session.resumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    _sync.dispose();
    _session.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoriesScope(
      repositories: widget.repositories,
      child: AppScope(
        settings: _settings,
        session: _session,
        sync: _sync,
        child: ListenableBuilder(
          listenable: _settings,
          builder: (context, _) => SparklingMotionScope(
            reducedMotion: _settings.reducedMotion,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _session.touch(),
              child: MaterialApp.router(
                title: Env.appName,
                debugShowCheckedModeBanner: false,
                theme: SparklingTheme.light(),
                darkTheme: SparklingTheme.dark(),
                themeMode: _settings.themeMode,
                routerConfig: _router,
                builder: (context, child) => MediaQuery(
                  // Keep layouts usable for large accessibility text (UX-003).
                  data: MediaQuery.of(context).copyWith(
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(minScaleFactor: 0.9, maxScaleFactor: 1.6),
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
