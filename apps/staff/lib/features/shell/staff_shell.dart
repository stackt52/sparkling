import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/adaptive.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

/// 5-item navigation shell: Tasks / Ops (supervisor+) or Scan / Rank /
/// Stock / Profile. Bottom [NavigationBar] on phones, [NavigationRail] on
/// tablets (≥ 840dp).
class StaffShell extends StatelessWidget {
  const StaffShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  List<_Destination> _destinations(bool canSupervise) => [
    const _Destination(Routes.tasks, 'Tasks', Symbols.checklist_rounded),
    canSupervise
        ? const _Destination(Routes.ops, 'Ops', Symbols.dashboard_rounded)
        : const _Destination(
            Routes.scan,
            'Scan',
            Symbols.qr_code_scanner_rounded,
          ),
    const _Destination(
      Routes.leaderboard,
      'Rank',
      Symbols.social_leaderboard_rounded,
    ),
    const _Destination(Routes.inventory, 'Stock', Symbols.inventory_2_rounded),
    const _Destination(
      Routes.profile,
      'Profile',
      Symbols.account_circle_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final items = _destinations(session.canSupervise);
        var index = items.indexWhere((d) => location.startsWith(d.path));
        if (index < 0) index = 0;
        void go(int i) {
          if (i == index) return;
          context.go(items[i].path);
        }

        if (Breakpoints.isExpanded(context)) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: index,
                    onDestinationSelected: go,
                    minWidth: 84,
                    groupAlignment: -0.6,
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: SparklingLogo(height: 28),
                    ),
                    destinations: [
                      for (final d in items)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.icon, fill: 1),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: go,
            destinations: [
              for (final d in items)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.icon, fill: 1),
                  label: d.label,
                ),
            ],
          ),
        );
      },
    );
  }
}
