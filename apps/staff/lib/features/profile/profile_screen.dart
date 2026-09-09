import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/avatar_tile.dart';
import '../../widgets/feedback.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/segmented_pills.dart';

/// Profile: outlet(s), role, availability, theme, reduced motion / haptics,
/// sync centre and sign out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<List<Outlet>>? _outlets;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _outlets ??= context.repositories.catalogue.outlets();
  }

  Future<void> _mirrorToProfile(ProfileUpdate update) async {
    try {
      await context.repositories.customer.updateMe(update);
    } catch (_) {
      // Preference is device-local first; the profile mirror is best-effort.
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final session = context.session;
    final settings = context.settings;
    final user = session.user;
    final initials = _initials(session.displayName);

    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([session, settings]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const ScreenHeader(title: 'Profile'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTileCard(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        AvatarTile(
                          initials: initials,
                          size: 64,
                          radius: 20,
                          tone: AvatarTile.toneFor(user?.uid ?? ''),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.displayName,
                                style: SparklingTypography.titleLarge.copyWith(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                              if (user?.email != null)
                                Text(
                                  user!.email!,
                                  style: SparklingTypography.bodyMedium
                                      .copyWith(color: cs.onSurfaceVariant),
                                ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  StatusChip(
                                    label: _roleLabel(session.role),
                                    tone: StatusChipTone.primary,
                                    icon: Symbols.badge_rounded,
                                    dense: true,
                                  ),
                                  if (session.demo)
                                    const StatusChip(
                                      label: 'Demo',
                                      tone: StatusChipTone.gold,
                                      dense: true,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(title: 'Outlets'),
                  FutureBuilder<List<Outlet>>(
                    future: _outlets,
                    builder: (context, snap) {
                      final mine = (snap.data ?? const <Outlet>[])
                          .where((o) => session.outletIds.contains(o.id))
                          .toList();
                      if (mine.isEmpty) {
                        return ListTileCard(
                          leading: Icon(
                            Symbols.storefront_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                          title: Text(
                            snap.connectionState == ConnectionState.waiting
                                ? 'Loading…'
                                : 'No outlet assigned',
                          ),
                          subtitle: const Text(
                            'Ask your manager to add you to an outlet.',
                          ),
                        );
                      }
                      return Column(
                        children: [
                          for (final o in mine) ...[
                            ListTileCard(
                              leading: Icon(
                                Symbols.storefront_rounded,
                                color: cs.primary,
                                fill: 1,
                              ),
                              title: Text(o.name),
                              subtitle: Text(o.addressLabel),
                              trailing: o.id == session.outletId
                                  ? const StatusChip(
                                      label: 'Primary',
                                      tone: StatusChipTone.success,
                                      dense: true,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SectionHeader(title: 'Availability'),
                  SegmentedPills<AvailabilityStatus>(
                    selected: settings.availability,
                    onChanged: (v) {
                      settings.setAvailability(v);
                      StaffHaptics.tap(context);
                    },
                    segments: const [
                      PillSegment(
                        value: AvailabilityStatus.available,
                        label: 'Available',
                      ),
                      PillSegment(value: AvailabilityStatus.busy, label: 'Busy'),
                      PillSegment(
                        value: AvailabilityStatus.onBreak,
                        label: 'Break',
                      ),
                      PillSegment(value: AvailabilityStatus.off, label: 'Off'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const AuditNote(
                    icon: Symbols.groups_rounded,
                    text:
                        'Supervisors see this on the team load board when assigning work.',
                  ),
                  const SizedBox(height: 12),
                  SectionHeader(title: 'Appearance'),
                  SegmentedPills<ThemeMode>(
                    selected: settings.themeMode,
                    onChanged: settings.setThemeMode,
                    segments: const [
                      PillSegment(value: ThemeMode.dark, label: 'Dark'),
                      PillSegment(value: ThemeMode.light, label: 'Light'),
                      PillSegment(value: ThemeMode.system, label: 'System'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SwitchCard(
                    icon: Symbols.animation_rounded,
                    title: 'Reduced motion',
                    subtitle: 'Turns off non-essential animation (UX-004).',
                    value: settings.reducedMotion,
                    onChanged: (v) {
                      settings.setReducedMotion(v);
                      _mirrorToProfile(ProfileUpdate(reducedMotion: v));
                    },
                  ),
                  const SizedBox(height: 10),
                  _SwitchCard(
                    icon: Symbols.vibration_rounded,
                    title: 'Haptics',
                    subtitle: 'Vibrate on scan success and completed steps.',
                    value: settings.haptics,
                    onChanged: (v) {
                      settings.setHaptics(v);
                      _mirrorToProfile(ProfileUpdate(haptics: v));
                    },
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(title: 'Data'),
                  ListTileCard(
                    onTap: () => context.push(Routes.sync),
                    leading: Icon(
                      Symbols.cloud_sync_rounded,
                      color: cs.primary,
                      fill: 1,
                    ),
                    title: const Text('Sync centre'),
                    subtitle: ListenableBuilder(
                      listenable: context.syncStatus,
                      builder: (context, _) => Text(context.syncStatus.label),
                    ),
                    trailing: Icon(
                      Symbols.arrow_forward_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (session.demo) ...[
                    PillButton(
                      label: 'Switch demo persona',
                      icon: Symbols.swap_horiz_rounded,
                      variant: PillButtonVariant.tonal,
                      expand: true,
                      onPressed: session.signOut,
                    ),
                    const SizedBox(height: 10),
                  ],
                  PillButton(
                    label: 'Sign out',
                    icon: Symbols.logout_rounded,
                    variant: PillButtonVariant.outlinedError,
                    expand: true,
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Sign out?'),
                          content: const Text(
                            'Queued offline changes are cleared from this device.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Sign out'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await session.signOut();
                    },
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      '${Env.appName} ${Env.appVersion}${Env.demoMode ? ' · demo' : ''}',
                      style: SparklingTypography.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _roleLabel(UserRole role) => switch (role) {
    UserRole.technician => 'Technician',
    UserRole.supervisor => 'Supervisor',
    UserRole.manager => 'Manager',
    UserRole.admin => 'Admin',
    UserRole.finance => 'Finance',
    UserRole.customer => 'Customer',
  };

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return ListTileCard(
      onTap: () => onChanged(!value),
      leading: Icon(icon, color: cs.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}
