import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import 'booking_flow.dart';
import 'booking_widgets.dart';

/// Step 2 of 3 — date chips + slot grid (1c).
class SlotPickerScreen extends StatefulWidget {
  const SlotPickerScreen({super.key, this.daysAhead = 14});

  final int daysAhead;

  @override
  State<SlotPickerScreen> createState() => _SlotPickerScreenState();
}

class _SlotPickerScreenState extends State<SlotPickerScreen> {
  late DateTime _day;
  Future<List<AvailabilitySlot>>? _slots;

  BookingFlowController get _flow => context.bookingFlow;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_slots == null) {
      final start = _flow.slotStart;
      if (start != null) _day = DateTime(start.year, start.month, start.day);
      _reload();
    }
  }

  void _reload() {
    final flow = _flow;
    if (flow.outlet == null || flow.service == null) return;
    setState(() {
      _slots = context.repos.catalogue.availability(
        outletId: flow.outlet!.id,
        serviceId: flow.service!.id,
        date: _day,
      );
    });
  }

  void _selectDay(DateTime d) {
    if (_day == d) return;
    AppHaptics.selection(context);
    setState(() => _day = d);
    final start = _flow.slotStart;
    if (start != null &&
        !(start.year == d.year &&
            start.month == d.month &&
            start.day == d.day)) {
      _flow.setSlot(null);
    }
    _reload();
  }

  bool _isOpen(DateTime d) => _flow.outlet?.hoursFor(d.weekday) != null;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final flow = _flow;
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) =>
          flow.canPickSlot ? _body(context, cs, flow) : _incomplete(context),
    );
  }

  Widget _incomplete(BuildContext context) {
    {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const ScreenHeader(title: 'Date & time'),
              EmptyState(
                icon: Symbols.event_busy_rounded,
                title: 'Pick a service first',
                actionLabel: 'Back to services',
                onAction: () => context.go(Routes.bookService),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _body(
    BuildContext context,
    ColorScheme cs,
    BookingFlowController flow,
  ) {
    final today = DateTime.now();
    final days = List.generate(
      widget.daysAhead,
      (i) => DateTime(today.year, today.month, today.day + i),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Builder(
          builder: (context) => Column(
            children: [
              BookingStepHeader(
                title: 'Date & time',
                step: 2,
                subtitle: flow.service!.name,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    Text(
                      DateFormat('MMMM yyyy').format(_day),
                      style: SparklingTypography.headlineSmall.copyWith(
                        fontSize: 20,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // 5-up on a phone; chips stay tappable (≥44px).
                        final w = ((constraints.maxWidth - 4 * 10) / 5).clamp(
                          56.0,
                          80.0,
                        );
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          child: Row(
                            children: [
                              for (final d in days) ...[
                                DateChip(
                                  weekday: SparklingDates.weekday(d),
                                  day: '${d.day}',
                                  width: w,
                                  selected: d == _day,
                                  enabled: _isOpen(d),
                                  onTap: () => _selectDay(d),
                                ),
                                const SizedBox(width: 10),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Text.rich(
                      TextSpan(
                        text: 'Available slots',
                        style: SparklingTypography.headlineSmall.copyWith(
                          fontSize: 20,
                          color: cs.onSurface,
                        ),
                        children: [
                          TextSpan(
                            text: ' · revalidated on submit',
                            style: SparklingTypography.bodyMedium.copyWith(
                              fontSize: 15,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    AsyncView<List<AvailabilitySlot>>(
                      future: _slots!,
                      onRetry: _reload,
                      builder: (context, slots) {
                        if (slots.isEmpty) {
                          return EmptyState(
                            icon: Symbols.event_busy_rounded,
                            title: 'Closed on this day',
                            message: 'Choose another date.',
                          );
                        }
                        return _SlotGrid(
                          slots: slots,
                          selected: flow.slotStart,
                          onSelect: (s) {
                            AppHaptics.selection(context);
                            flow.setSlot(s.slotStart);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    if (flow.slotStart != null) _SummaryBanner(flow: flow),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: BottomActionBar(
                  leadingLabel: 'Total',
                  leadingValue: Money.formatZarCompact(flow.service!.priceCents)
                      .replaceFirst('R', 'R '),
                  child: PillButton(
                    label: 'Review & pay',
                    trailingIcon: Symbols.arrow_forward_rounded,
                    expand: true,
                    onPressed: flow.canPay
                        ? () {
                            AppHaptics.light(context);
                            context.push(Routes.bookPay);
                          }
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.slots,
    required this.selected,
    required this.onSelect,
  });

  final List<AvailabilitySlot> slots;
  final DateTime? selected;
  final ValueChanged<AvailabilitySlot> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final w = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in slots)
              SizedBox(
                width: w,
                child: SlotChip(
                  label: SparklingDates.hhmm(s.slotStart),
                  height: 48,
                  state: !s.available
                      ? SlotState.booked
                      : (selected != null &&
                            selected!.isAtSameMomentAs(s.slotStart))
                      ? SlotState.selected
                      : SlotState.available,
                  onTap: () => onSelect(s),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.flow});
  final BookingFlowController flow;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final start = flow.slotStart!;
    final fg = cs.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(SparklingShapes.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.event_available_rounded, color: cs.primary, fill: 1),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: SparklingTypography.bodyLarge.copyWith(
                  fontSize: 15,
                  height: 1.5,
                  color: fg,
                ),
                children: [
                  TextSpan(
                    text: SparklingDates.long(start),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        ' at ${shortOutletName(flow.outlet!.name)} · ${flow.service!.name}, ±${flow.service!.durationMinutes} min.\nFree cancellation until 2 h before.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
