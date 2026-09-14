import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';
import 'membership_sheet.dart';
import 'walk_in_flow.dart';
import 'walk_in_widgets.dart';

/// Step 1 of 4 — find the customer (name / phone / e-mail / plate) or
/// register a walk-in profile (STF-012, CUS-020 on their behalf). Shared by
/// the walk-in booking and the raise-quote flow ([CustomerVehicleFlow]).
class CustomerStep extends StatefulWidget {
  const CustomerStep({
    super.key,
    required this.flow,
    required this.onNext,
    required this.onBack,
    this.title = 'Walk-in booking',
    this.nextLabel = 'Choose vehicle',
    this.totalSteps = 4,
  });

  final CustomerVehicleFlow flow;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final String title;
  final String nextLabel;
  final int totalSteps;

  @override
  State<CustomerStep> createState() => _CustomerStepState();
}

class _CustomerStepState extends State<CustomerStep> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<List<CustomerSummary>>? _results;

  @override
  void initState() {
    super.initState();
    final scanned = widget.flow.scannedVehicle;
    // A scanned plate is the natural first search.
    if (scanned != null && widget.flow.customer == null) {
      _search.text = scanned.registrationNoFormatted;
      _query = _search.text;
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _query = value.trim();
      _run();
    });
  }

  void _run() {
    setState(() {
      _results = _query.length < 2
          ? null
          : context.repositories.staff.searchCustomers(_query, limit: 20);
    });
  }

  Future<void> _register() async {
    final flow = widget.flow;
    final created = await Navigator.of(context).push<CustomerSummary>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RegisterCustomerScreen(
          initialName: _looksLikeName(_query) ? _query : null,
          initialPhone: _looksLikePhone(_query) ? _query : null,
          totalSteps: widget.totalSteps,
        ),
      ),
    );
    if (created == null || !mounted) return;
    flow.setCustomer(created);
    StaffHaptics.success(context);
  }

  static bool _looksLikePhone(String q) =>
      RegExp(r'^[+0-9 ]{6,}$').hasMatch(q.trim());
  static bool _looksLikeName(String q) =>
      q.trim().length >= 2 && RegExp(r'^[A-Za-z .\-]+$').hasMatch(q.trim());

  void _select(CustomerSummary c) {
    StaffHaptics.tap(context);
    widget.flow.setCustomer(c);
  }

  Future<void> _openMembership(CustomerSummary c) async {
    final flow = widget.flow;
    final updated = await showCustomerMembershipSheet(
      context,
      customer: c,
      summary: flow.membership,
    );
    if (updated != null && mounted) flow.setMembership(updated);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final flow = widget.flow;
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        final customer = flow.customer;
        if (customer != null && flow.membership == null) {
          // Fire-and-forget: the card shows a spinner until it lands.
          unawaited(flow.loadMembership(context.repositories));
        }
        return Column(
          children: [
            BookingStepHeader(
              title: widget.title,
              step: 1,
              total: widget.totalSteps,
              subtitle: 'Customer',
              onBack: widget.onBack,
            ),
            Expanded(
              child: customer != null
                  ? _selected(context, customer)
                  : _searchBody(context, cs),
            ),
            BottomActionBar(
              leadingLabel: 'Customer',
              leadingValue: customer?.firstName ?? '—',
              child: PillButton(
                label: widget.nextLabel,
                trailingIcon: Symbols.arrow_forward_rounded,
                expand: true,
                minHeight: 56,
                onPressed: customer == null ? null : widget.onNext,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _selected(BuildContext context, CustomerSummary c) {
    final flow = widget.flow;
    final scanned = flow.scannedVehicle;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      children: [
        if (flow.restoredAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(
              tone: InfoTone.info,
              icon: Symbols.history_rounded,
              text:
                  'Draft restored from ${SparklingDates.relativeSlot(flow.restoredAt!)}.',
              actionLabel: 'Discard',
              onAction: flow.reset,
            ),
          ),
        CustomerCard(customer: c, onChange: flow.clearCustomer),
        const SizedBox(height: 12),
        CustomerMembershipTile(
          summary: flow.membership,
          onTap: () => _openMembership(c),
        ),
        const SizedBox(height: 12),
        if (scanned != null)
          InfoBanner(
            tone: InfoTone.azure,
            icon: Symbols.qr_code_scanner_rounded,
            title: 'Scanned ${scanned.registrationNoFormatted}',
            text: 'Next: add this vehicle to ${c.firstName} and pick it.',
          ),
        if (c.vehicles.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionHeader(title: 'Vehicles on file'),
          for (final v in c.vehicles) ...[
            ListTileCard(
              leading: Icon(
                Symbols.directions_car_rounded,
                color: context.colors.primary,
                fill: 1,
              ),
              title: Text(
                v.registrationNo,
                style: SparklingTypography.mono(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: context.colors.onSurface,
                ),
              ),
              subtitle: Text(
                v.displayName.isEmpty ? 'No make / model' : v.displayName,
              ),
              trailing: v.discVerified
                  ? const StatusChip(
                      label: 'Disc verified',
                      tone: StatusChipTone.success,
                      dense: true,
                    )
                  : null,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  Widget _searchBody(BuildContext context, ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      children: [
        TextField(
          controller: _search,
          onChanged: _onChanged,
          onSubmitted: (_) {
            _debounce?.cancel();
            _query = _search.text.trim();
            _run();
          },
          textInputAction: TextInputAction.search,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'Name, phone, e-mail or plate',
            prefixIcon: const Icon(Symbols.search_rounded),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Symbols.close_rounded),
                    onPressed: () {
                      _search.clear();
                      _query = '';
                      _run();
                    },
                  ),
          ),
        ),
        const SizedBox(height: 14),
        if (_results == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Type at least 2 characters — the customer\'s name, mobile '
              'number, e-mail or registration plate.',
              style: SparklingTypography.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          FutureBuilder<List<CustomerSummary>>(
            future: _results,
            builder: (context, snap) => AsyncView<List<CustomerSummary>>(
              snapshot: snap,
              onRetry: _run,
              loading: const Padding(
                padding: EdgeInsets.all(24),
                child: LoadingState(label: 'Searching…'),
              ),
              builder: (context, list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Symbols.person_search_rounded,
                    title: 'No customer matches “$_query”',
                    text: 'Register them below — it takes a minute.',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      title: '${list.length} ${list.length == 1 ? 'match' : 'matches'}',
                    ),
                    for (final c in list) ...[
                      _CustomerResult(customer: c, onSelect: () => _select(c)),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        PillButton(
          label: 'Register new customer',
          icon: Symbols.person_add_rounded,
          variant: PillButtonVariant.outlined,
          expand: true,
          onPressed: _register,
        ),
      ],
    );
  }
}

class _CustomerResult extends StatelessWidget {
  const _CustomerResult({required this.customer, required this.onSelect});
  final CustomerSummary customer;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final c = customer;
    final plates = c.vehicles.map((v) => v.registrationNo).toList();
    return RadioCard(
      selected: false,
      onChanged: (_) => onSelect(),
      radioPosition: RadioCardRadioPosition.trailing,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(SparklingShapes.iconTileSmall),
        ),
        alignment: Alignment.center,
        child: Text(
          c.initials,
          style: SparklingTypography.titleMedium.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              c.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SparklingTypography.titleLarge.copyWith(fontSize: 17),
            ),
          ),
          if (c.loyalty != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: TierPill(
                  tier: tierKind(c.tier),
                  label: c.loyalty!.planLabel,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          if (c.phone != null) c.phone!,
          if (c.email != null) c.email!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      footer: plates.isEmpty
          ? Text(
              'No vehicles on file',
              style: SparklingTypography.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in plates)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      p,
                      style: SparklingTypography.mono(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Full-screen registration form → `POST /staff/customers`. Pops with the
/// created (or, on 409, the chosen existing) [CustomerSummary].
class RegisterCustomerScreen extends StatefulWidget {
  const RegisterCustomerScreen({
    super.key,
    this.initialName,
    this.initialPhone,
    this.totalSteps = 4,
  });

  final String? initialName;
  final String? initialPhone;
  final int totalSteps;

  @override
  State<RegisterCustomerScreen> createState() => _RegisterCustomerScreenState();
}

class _RegisterCustomerScreenState extends State<RegisterCustomerScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late final _phone = TextEditingController(text: widget.initialPhone ?? '');
  final _email = TextEditingController();
  bool _whatsapp = true;
  bool _marketing = false;
  bool _busy = false;

  /// Stable per form so a retried submit is idempotent.
  final _opId = SparklingApi.newOpId();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  String? get _normalisedPhone {
    final p = CustomerInput.normalisePhone(_phone.text);
    return p.length >= 10 ? p : null;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final staff = context.repositories.staff;
    try {
      final created = await staff.createCustomer(
        CustomerInput(
          fullName: _name.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          whatsappOptIn: _whatsapp,
          marketingOptIn: _marketing,
          clientOpId: _opId,
        ),
      );
      if (!mounted) return;
      StaffHaptics.success(context);
      Navigator.of(context).pop(created);
    } on ApiException catch (e) {
      if (!mounted) return;
      final existingJson = e.existingCustomer;
      if (e.isConflict && existingJson != null) {
        final existing = CustomerSummary.fromJson(existingJson);
        final use = await _showAlreadyRegistered(existing, e.message);
        if (!mounted) return;
        if (use) Navigator.of(context).pop(existing);
      } else {
        StaffSnack.error(context, e);
      }
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _showAlreadyRegistered(
    CustomerSummary existing,
    String message,
  ) async {
    final use = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Already registered'),
              InfoBanner(tone: InfoTone.info, text: message),
              const SizedBox(height: 12),
              CustomerCard(customer: existing),
              const SizedBox(height: 16),
              PillButton(
                label: 'Use ${existing.firstName}',
                icon: Symbols.person_check_rounded,
                expand: true,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'Edit details',
                variant: PillButtonVariant.outlined,
                expand: true,
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
    return use ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final normalised = _normalisedPhone;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            BookingStepHeader(
              title: 'Register customer',
              step: 1,
              total: widget.totalSteps,
              subtitle: 'New walk-in',
              onBack: _busy ? null : () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    TextFormField(
                      controller: _name,
                      autofocus: widget.initialName == null,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Symbols.person_rounded),
                      ),
                      validator: (v) => (v ?? '').trim().length < 2
                          ? 'Enter the customer\'s full name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                        LengthLimitingTextInputFormatter(16),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Mobile number',
                        hintText: '082 123 4567',
                        prefixIcon: const Icon(Symbols.call_rounded),
                        helperText: normalised == null
                            ? 'Saved as +27 … (South African numbers)'
                            : 'Saved as $normalised',
                      ),
                      validator: (v) =>
                          CustomerInput.normalisePhone(v ?? '').length < 10
                          ? 'Enter a valid mobile number'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'E-mail (optional)',
                        prefixIcon: Icon(Symbols.mail_rounded),
                        helperText:
                            'Lets them claim this profile when they install the app',
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return null;
                        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)
                            ? null
                            : 'Enter a valid e-mail address';
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                    _SwitchTile(
                      icon: Symbols.chat_rounded,
                      title: 'WhatsApp updates',
                      subtitle:
                          'Service started / ready and the collection code',
                      value: _whatsapp,
                      onChanged: (v) => setState(() => _whatsapp = v),
                    ),
                    const SizedBox(height: 10),
                    _SwitchTile(
                      icon: Symbols.campaign_rounded,
                      title: 'Marketing messages',
                      subtitle: 'Offers and loyalty news — off unless they ask',
                      value: _marketing,
                      onChanged: (v) => setState(() => _marketing = v),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Symbols.verified_user_rounded,
                          size: 20,
                          color: cs.onSurfaceVariant,
                          fill: 1,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tell the customer: Sparkling stores their name '
                            'and contact details to manage this booking, '
                            'send service updates and keep their loyalty '
                            'points (POPIA). They can update or delete the '
                            'profile from the Sparkling app at any time.',
                            style: SparklingTypography.bodyMedium.copyWith(
                              fontSize: 13.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            BottomActionBar(
              child: PillButton(
                label: 'Register customer',
                icon: Symbols.person_add_rounded,
                expand: true,
                minHeight: 56,
                loading: _busy,
                onPressed: _busy ? null : _submit,
              ),
            ),
          ],
        ),
      ),
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
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}
