import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../features/booking/booking_flow.dart';
import 'app_scope.dart';
import 'app_settings.dart';
import 'push_messages.dart';
import 'router.dart';
import 'session.dart';

/// Root widget: wires repositories, session, settings, router and theme.
class CustomerApp extends StatefulWidget {
  const CustomerApp({super.key, required this.repositories});

  final Repositories repositories;

  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp>
    with WidgetsBindingObserver {
  late final SessionController _session = SessionController(
    widget.repositories,
  );
  late final AppSettings _settings = AppSettings(widget.repositories.cache);
  late final BookingFlowController _flow = BookingFlowController(
    widget.repositories,
  );
  late final GoRouter _router = buildRouter(_session);
  final GlobalKey<ScaffoldMessengerState> _messenger =
      GlobalKey<ScaffoldMessengerState>();
  PushMessages? _push;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Live mode only: demo runs without Firebase.
    if (!widget.repositories.demo) {
      _push = PushMessages(router: _router, messenger: _messenger);
      unawaited(_push!.start());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the background: refetch every live stream so a quote
    // sent or a booking changed meanwhile shows without a manual refresh,
    // even when the realtime socket dropped while suspended.
    if (state == AppLifecycleState.resumed && !widget.repositories.demo) {
      announceLocalChange('app_resumed');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _push?.dispose();
    _router.dispose();
    _flow.dispose();
    _settings.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoriesScope(
      repositories: widget.repositories,
      child: AppScope(
        session: _session,
        settings: _settings,
        bookingFlow: _flow,
        child: ListenableBuilder(
          listenable: Listenable.merge([_settings, _session]),
          builder: (context, _) {
            final reduced = _session.profile?.reducedMotion ?? false;
            return SparklingMotionScope(
              reducedMotion: reduced,
              child: MaterialApp.router(
                title: 'Sparkling',
                scaffoldMessengerKey: _messenger,
                debugShowCheckedModeBanner: false,
                theme: SparklingTheme.light(),
                darkTheme: SparklingTheme.dark(),
                themeMode: _settings.themeMode,
                routerConfig: _router,
              ),
            );
          },
        ),
      ),
    );
  }
}
