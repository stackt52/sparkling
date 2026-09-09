import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../features/booking/booking_flow.dart';
import 'app_scope.dart';
import 'app_settings.dart';
import 'router.dart';
import 'session.dart';

/// Root widget: wires repositories, session, settings, router and theme.
class CustomerApp extends StatefulWidget {
  const CustomerApp({super.key, required this.repositories});

  final Repositories repositories;

  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  late final SessionController _session = SessionController(
    widget.repositories,
  );
  late final AppSettings _settings = AppSettings(widget.repositories.cache);
  late final BookingFlowController _flow = BookingFlowController(
    widget.repositories,
  );
  late final GoRouter _router = buildRouter(_session);

  @override
  void dispose() {
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
