import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../widgets/adaptive.dart';
import '../../widgets/feedback.dart';
import '../walk_in/customer_step.dart';
import '../walk_in/vehicle_step.dart';
import 'items_step.dart';
import 'raise_quote_controller.dart';
import 'review_step.dart';

/// Raise-quote flow shell (STF-010/012, CUS-030..034): Customer → Vehicle →
/// What needs attention → Review & send, in a non-swipeable [PageView].
/// Steps 1–2 are the walk-in steps; the draft lives in
/// [RaiseQuoteController] and survives restarts.
class RaiseQuoteScreen extends StatefulWidget {
  const RaiseQuoteScreen({super.key, this.args});

  final RaiseQuoteArgs? args;

  static const String title = 'Raise quote';

  @override
  State<RaiseQuoteScreen> createState() => _RaiseQuoteScreenState();
}

class _RaiseQuoteScreenState extends State<RaiseQuoteScreen> {
  RaiseQuoteController? _flow;
  final _pages = PageController();
  RaiseQuoteStep _step = RaiseQuoteStep.customer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_flow == null) {
      final flow = RaiseQuoteController(context.repositories, args: widget.args);
      _flow = flow;
      final resume = widget.args?.scanned != null && flow.customer == null
          ? RaiseQuoteStep.customer
          : flow.maxStep == RaiseQuoteStep.review
          ? RaiseQuoteStep.items
          : flow.maxStep;
      if (resume != RaiseQuoteStep.customer) {
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

  void _goTo(RaiseQuoteStep step) {
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
    if (i < RaiseQuoteStep.values.length) _goTo(RaiseQuoteStep.values[i]);
  }

  void _back() {
    if (_step == RaiseQuoteStep.customer) {
      _exit();
      return;
    }
    _goTo(RaiseQuoteStep.values[_step.index - 1]);
  }

  Future<void> _exit() async {
    final flow = _flow!;
    if (flow.hasDraft) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave quote?'),
          content: const Text(
            'Your draft is kept on this device — you can pick it up again '
            'from the Raise quote button.',
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
        CustomerStep(
          flow: flow,
          onNext: _next,
          onBack: _back,
          title: RaiseQuoteScreen.title,
        ),
        VehicleStep(
          flow: flow,
          onNext: _next,
          onBack: _back,
          title: RaiseQuoteScreen.title,
          nextLabel: 'What needs attention',
        ),
        ItemsStep(flow: flow, onNext: _next, onBack: _back),
        ReviewStep(flow: flow, onBack: _back),
      ],
    );

    final body = ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
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

  final RaiseQuoteStep current;
  final RaiseQuoteStep max;
  final RaiseQuoteController flow;
  final ValueChanged<RaiseQuoteStep> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    String valueFor(RaiseQuoteStep s) => switch (s) {
      RaiseQuoteStep.customer => flow.customer?.fullName ?? 'Search or register',
      RaiseQuoteStep.vehicle =>
        flow.vehicle?.registrationNo ?? 'Pick or add a vehicle',
      RaiseQuoteStep.items => flow.items.isEmpty
          ? 'Add attention items'
          : '${flow.items.length} item${flow.items.length == 1 ? '' : 's'} · ${Money.formatZar(flow.totalCents)}',
      RaiseQuoteStep.review => flow.sendToCustomer
          ? 'Send push + WhatsApp'
          : 'Keep for later',
    };
    const titles = ['Customer', 'Vehicle', 'What needs attention', 'Review & send'];
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
            child: Text(
              RaiseQuoteScreen.title,
              style: SparklingTypography.headlineMedium.copyWith(
                color: cs.onSurface,
              ),
            ),
          ),
          for (final s in RaiseQuoteStep.values) ...[
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
