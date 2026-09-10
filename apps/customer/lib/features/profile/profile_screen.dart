import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import '../sync/sync_indicator.dart';

/// Profile & preferences (PATCH /me), appearance, garage, sign out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _saving = false;

  Future<void> _patch(ProfileUpdate update) async {
    setState(() => _saving = true);
    try {
      await context.session.updateProfile(update);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editDetails(Profile p) async {
    final name = TextEditingController(text: p.fullName);
    final phone = TextEditingController(text: p.phone ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Your details'),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                helperText: 'Used for WhatsApp updates',
              ),
            ),
            const SizedBox(height: 16),
            PillButton(
              label: 'Save',
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      await _patch(
        ProfileUpdate(
          fullName: name.text.trim().isEmpty ? null : name.text.trim(),
          phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
        ),
      );
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Cached bookings and queued changes on this device will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await context.session.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final session = context.session;
    final settings = context.settings;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([session, settings]),
          builder: (context, _) {
            final p = session.profile;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Profile',
                        style: SparklingTypography.headlineLarge.copyWith(
                          fontSize: 30,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SyncIndicator(),
                  ],
                ),
                const SizedBox(height: 16),
                // Profile-dependent sections. When the API is unreachable the
                // user still gets Appearance, Data and Sign out below.
                if (p == null && session.error != null)
                  ErrorView(
                    error: session.error,
                    compact: true,
                    onRetry: session.serverUnreachable
                        ? session.retryBootstrap
                        : session.refreshProfile,
                  )
                else if (p == null)
                  const LoadingView()
                else ...[
                  ListTileCard(
                    onTap: () => _editDetails(p),
                    leading: AvatarTile(initials: p.initials, size: 52),
                    title: Text(p.fullName),
                    subtitle: Text(
                      [p.email, p.phone].whereType<String>().join(' · '),
                    ),
                    trailing: Icon(Symbols.edit_rounded, color: cs.primary),
                  ),
                  const SizedBox(height: 22),
                  const SectionHeader(title: 'Garage & quotes'),
                  _NavTile(
                    icon: Symbols.directions_car_rounded,
                    title: 'Your vehicles',
                    subtitle: 'Scan a disc or add manually',
                    onTap: () => context.push(Routes.vehicles),
                  ),
                  const SizedBox(height: 8),
                  _NavTile(
                    icon: Symbols.request_quote_rounded,
                    title: 'Repair quotes',
                    subtitle: 'Requests, offers and decisions',
                    onTap: () => context.push(Routes.quotes),
                  ),
                  const SizedBox(height: 8),
                  _NavTile(
                    icon: Symbols.notifications_rounded,
                    title: 'Notifications',
                    subtitle: 'Inbox',
                    onTap: () => context.push(Routes.notifications),
                  ),
                  const SizedBox(height: 22),
                  const SectionHeader(title: 'Updates'),
                  _SwitchTile(
                    icon: Symbols.chat_rounded,
                    title: 'WhatsApp updates',
                    subtitle: 'Booking confirmations and "ready" alerts',
                    value: p.whatsappOptIn,
                    onChanged: (v) => _patch(ProfileUpdate(whatsappOptIn: v)),
                  ),
                  const SizedBox(height: 8),
                  _SwitchTile(
                    icon: Symbols.notifications_active_rounded,
                    title: 'Push notifications',
                    subtitle: 'Live service progress',
                    value: p.pushOptIn,
                    onChanged: (v) => _patch(ProfileUpdate(pushOptIn: v)),
                  ),
                  const SizedBox(height: 8),
                  _SwitchTile(
                    icon: Symbols.campaign_rounded,
                    title: 'Offers and news',
                    subtitle: 'Optional marketing (POPIA consent)',
                    value: p.marketingOptIn,
                    onChanged: (v) => _patch(ProfileUpdate(marketingOptIn: v)),
                  ),
                  const SizedBox(height: 22),
                  const SectionHeader(title: 'Accessibility'),
                  _SwitchTile(
                    icon: Symbols.animation_rounded,
                    title: 'Reduce motion',
                    subtitle: 'Turns off non-essential animation',
                    value: p.reducedMotion,
                    onChanged: (v) => _patch(ProfileUpdate(reducedMotion: v)),
                  ),
                  const SizedBox(height: 8),
                  _SwitchTile(
                    icon: Symbols.vibration_rounded,
                    title: 'Haptic feedback',
                    subtitle: 'Buzz on scan success and selections',
                    value: p.haptics,
                    onChanged: (v) => _patch(ProfileUpdate(haptics: v)),
                  ),
                ],
                const SizedBox(height: 22),
                const SectionHeader(title: 'Appearance'),
                SegmentedPills(
                  labels: const ['System', 'Light', 'Dark'],
                  selected: switch (settings.themeMode) {
                    ThemeMode.system => 0,
                    ThemeMode.light => 1,
                    ThemeMode.dark => 2,
                  },
                  onSelected: (i) => settings.setThemeMode(
                    const [
                      ThemeMode.system,
                      ThemeMode.light,
                      ThemeMode.dark,
                    ][i],
                  ),
                ),
                const SizedBox(height: 22),
                const SectionHeader(title: 'Data'),
                _NavTile(
                  icon: Symbols.cloud_sync_rounded,
                  title: 'Sync status',
                  subtitle: 'Offline queue and last sync',
                  onTap: () => context.push(Routes.sync),
                ),
                const SizedBox(height: 22),
                PillButton(
                  label: 'Sign out',
                  icon: Symbols.logout_rounded,
                  variant: PillButtonVariant.outlined,
                  expand: true,
                  onPressed: _saving ? null : _signOut,
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Sparkling ${Env.appVersion}${context.repos.demo ? ' · demo mode' : ''}',
                    style: SparklingTypography.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return ListTileCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      leading: TintedIconTile(icon: icon, size: 44, radius: 14),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Symbols.chevron_right_rounded, color: cs.onSurfaceVariant),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
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
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      leading: Icon(icon, color: cs.primary, fill: 1),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}
