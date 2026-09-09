import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Bottom navigation shell: Home / Bookings / Rewards / Profile (1a).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(
            icon: Icon(Symbols.home_rounded),
            selectedIcon: Icon(Symbols.home_rounded, fill: 1),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Symbols.calendar_month_rounded),
            selectedIcon: Icon(Symbols.calendar_month_rounded, fill: 1),
            label: 'Bookings',
          ),
          NavigationDestination(
            icon: Icon(Symbols.loyalty_rounded),
            selectedIcon: Icon(Symbols.loyalty_rounded, fill: 1),
            label: 'Rewards',
          ),
          NavigationDestination(
            icon: Icon(Symbols.person_rounded),
            selectedIcon: Icon(Symbols.person_rounded, fill: 1),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
