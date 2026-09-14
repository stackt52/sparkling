import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../widgets/adaptive.dart';
import '../../widgets/feedback.dart';
import 'customer_step.dart';
import 'payment_step.dart';
import 'service_step.dart';
import 'vehicle_step.dart';
import 'walk_in_flow.dart';

/// Arguments for [WalkInScreen] (`/walk-in`, passed as `extra`).
class WalkInArgs {
  const WalkInArgs({this.scanned});

  /// Disc scanned on the review screen for a plate without a booking.
  final DiscScanResult? scanned;
}

/// Walk-in booking flow shell (STF-010/012): four steps in a non-swipeable
/// [PageView] with shared-axis fades — Customer → Vehicle → Service & time →
/// Payment & confirm. The draft lives in [WalkInFlowController] and survives
/// restarts; on tablets a step rail sits left of the current step.
class WalkInScreen extends StatefulWidget {
  const WalkInScreen({super.key, this.args});

  final WalkInArgs? args;

  @override
  State<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends State<WalkInScreen> {
  WalkInFlowController? _flow;
  final _pages = PageController();
  WalkInStep _step = WalkInStep.customer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_flow == null) {
      final flow = WalkInFlowController(
        context.repositories,
        scanned: widget.args?.scanned,
      );
      _flow = flow;
      // Resume a restored draft at its furthest reachable step, but never
      // skip the customer step when a fresh scan needs a customer first.
      final resume = widget.args?.scanned != null && flow.customer == null
          ? WalkInStep.customer
          : flow.maxStep;
      if (resume != WalkInStep.customer) {
        _step = resume;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pages.hasClients) _pages.jumpToPage(resume.index);
        });
      }
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _flow?.dispose();
    super.dispose();
  }

  void _goTo(WalkInStep step) {
    if (step == _step) return;
    final flow = _flow!;
    if (step.index > flow.maxStep.index) return;
    StaffHaptics.tap(context);
    setState(() => _step = step);
    if (_pages.hasClients) {
      _pages.animateToPage(
        step.index,
        duration: SparklingMotion.durationFor(context, SparklingMotion.medium),
        curve: SparklingMotion.emphasized,
      );
    }
  }

  void _next() {
    final i = _step.index + 1;
    if (i < WalkInStep.values.length) _goTo(WalkInStep.values[i]);
  }

  void _back() {
    if (_step == WalkInStep.customer) {
      _exit();
      return;
    }
    _goTo(WalkInStep.values[_step.index - 1]);
  }

  Future<void> _exit() async {
    final flow = _flow!;
    if (flow.hasDraft) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave walk-in?'),
          content: const Text(
            'Your draft is kept on this device — you can pick it up again '
            'from the Walk-in button.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Discard draft'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep draft'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (discard == true) flow.reset();
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.tasks);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flow!;
    final pages = PageView(
      controller: _pages,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        CustomerStep(flow: flow, onNext: _next, onBack: _back),
        VehicleStep(flow: flow, onNext: _next, onBack: _back),
        ServiceStep(flow: flow, onNext: _next, onBack: _back),
        PaymentStep(flow: flow, onBack: _back),
      ],
    );

    final body = ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        // A change that invalidates later steps (e.g. "Change customer")
        // pulls the pager back to the furthest valid step.
        if (_step.index > flow.maxStep.index) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _goTo(flow.maxStep),
          );
        }
        if (!Breakpoints.isExpanded(context)) return pages;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 280,
              child: _StepRail(
                current: _step,
                max: flow.maxStep,
                flow: flow,
                onSelect: _goTo,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: pages,
                ),
              ),
            ),
          ],
        );
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(body: SafeArea(bottom: false, child: body)),
    );
  }
}

/// Tablet-only list of the four steps with their current values.
class _StepRail extends StatelessWidget {
  const _StepRail({
    required this.current,
    required this.max,
    required this.flow,
    required this.onSelect,
  });

  final WalkInStep current;
  final WalkInStep max;
  final WalkInFlowController flow;
  final ValueChanged<WalkInStep> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    String valueFor(WalkInStep s) => switch (s) {
      WalkInStep.customer => flow.customer?.fullName ?? 'Search or register',
      WalkInStep.vehicle =>
        flow.vehicle?.registrationNo ?? 'Pick or add a vehicle',
      WalkInStep.service =>
        flow.service == null
            ? 'Service & time'
            : '${flow.service!.name} · ${flow.bookNow ? 'now' : (flow.slotStart == null ? 'pick a slot' : SparklingDates.hhmm(flow.slotStart!))}',
      WalkInStep.payment => flow.payment.label,
    };
    const titles = ['Customer', 'Vehicle', 'Service & time', 'Payment'];
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
            child: Text(
              'Walk-in booking',
              style: SparklingTypography.headlineMedium.copyWith(
                color: cs.onSurface,
              ),
            ),
          ),
          for (final s in WalkInStep.values) ...[
            ListTileCard(
              onTap: s.index <= max.index ? () => onSelect(s) : null,
              opacity: s.index <= max.index ? 1 : 0.55,
              borderColor: s == current ? cs.primary : null,
              color: s == current ? cs.primaryContainer : null,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.index < current.index
                      ? context.sparkling.success
                      : (s == current ? cs.primary : cs.surfaceContainerHigh),
                ),
                alignment: Alignment.center,
                child: s.index < current.index
                    ? Icon(
                        Symbols.check_rounded,
                        size: 18,
                        color: context.sparkling.onSuccess,
                      )
                    : Text(
                        '${s.index + 1}',
                        style: SparklingTypography.labelLarge.copyWith(
                          color: s == current
                              ? cs.onPrimary
                              : cs.onSurfaceVariant,
                        ),
                      ),
              ),
              title: Text(titles[s.index]),
              subtitle: Text(
                valueFor(s),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
