import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';

/// Opens the vehicle hand-over sheet for a verified work order: the customer
/// reads their 5-digit collection OTP at the counter, staff type it and the
/// keys are released (`POST /work-orders/:id/pickup/verify`).
///
/// Returns the [PickupVerifyResult] when the keys were released, otherwise
/// `null` (dismissed).
Future<PickupVerifyResult?> showHandoverSheet(
  BuildContext context, {
  required String workOrderId,
  required String ref,
  String? customerName,
  String? vehicleLabel,
}) {
  return showModalBottomSheet<PickupVerifyResult>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (ctx) => HandoverSheet(
      workOrderId: workOrderId,
      ref: ref,
      customerName: customerName,
      vehicleLabel: vehicleLabel,
    ),
  );
}

/// Bottom-sheet body (public so the tablet detail pane and tests can host it).
class HandoverSheet extends StatefulWidget {
  const HandoverSheet({
    super.key,
    required this.workOrderId,
    required this.ref,
    this.customerName,
    this.vehicleLabel,
    this.resendCooldown = const Duration(seconds: 60),
  });

  final String workOrderId;
  final String ref;
  final String? customerName;
  final String? vehicleLabel;

  /// Client-side cooldown before "Resend OTP" is offered again.
  final Duration resendCooldown;

  @override
  State<HandoverSheet> createState() => _HandoverSheetState();
}

enum _Phase { input, busy, released, locked }

class _HandoverSheetState extends State<HandoverSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  _Phase _phase = _Phase.input;
  String? _error;
  int? _attemptsLeft;
  DateTime? _collectedAt;
  bool _resending = false;
  int _cooldownLeft = 0;
  Timer? _cooldown;

  static const int otpLength = 5;

  /// Wrong codes tolerated by the API before `rate_limited` (docs/API.md).
  static const int maxAttempts = 5;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_error != null) setState(() => _error = null);
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _complete => _controller.text.length == otpLength;

  Future<void> _verify() async {
    if (!_complete || _phase == _Phase.busy) return;
    setState(() {
      _phase = _Phase.busy;
      _error = null;
    });
    try {
      final result = await context.repositories.staff.verifyPickupOtp(
        widget.workOrderId,
        _controller.text,
      );
      if (!mounted) return;
      StaffHaptics.success(context);
      setState(() {
        _phase = _Phase.released;
        _collectedAt = result.collectedAt ?? DateTime.now();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      StaffHaptics.error(context);
      if (e.isRateLimited) {
        setState(() {
          _phase = _Phase.locked;
          _error = e.message;
          _attemptsLeft = 0;
        });
      } else if (e.isInvalidOtp) {
        final left = e.attemptsLeft;
        // Clear before showing the error: the text listener resets `_error`.
        _controller.clear();
        _focus.requestFocus();
        setState(() {
          _phase = _Phase.input;
          _attemptsLeft = left;
          _error = left == null
              ? 'Incorrect code. Ask the customer to read it again.'
              : left == 1
              ? 'Incorrect code · 1 attempt left before a new OTP is required.'
              : 'Incorrect code · $left attempts left.';
        });
      } else {
        setState(() {
          _phase = _Phase.input;
          _error = e.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.input;
        _error = ErrorState.messageFor(e);
      });
    }
  }

  Future<void> _resend() async {
    if (_resending || _cooldownLeft > 0) return;
    setState(() => _resending = true);
    try {
      await context.repositories.staff.resendPickupOtp(widget.workOrderId);
      if (!mounted) return;
      StaffHaptics.tap(context);
      _controller.clear();
      setState(() {
        _error = null;
        _attemptsLeft = null;
        if (_phase == _Phase.locked) _phase = _Phase.input;
      });
      _startCooldown(widget.resendCooldown);
      StaffSnack.show(
        context,
        'New OTP sent to ${widget.customerName ?? 'the customer'} by WhatsApp',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isRateLimited) {
        // Server cooldown: mirror it locally (message carries the seconds).
        final secs = int.tryParse(
          RegExp(r'(\d+)\s*s').firstMatch(e.message)?.group(1) ?? '',
        );
        _startCooldown(
          Duration(seconds: secs ?? widget.resendCooldown.inSeconds),
        );
      }
      StaffSnack.error(context, e);
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _startCooldown(Duration d) {
    _cooldown?.cancel();
    setState(() => _cooldownLeft = d.inSeconds);
    _cooldown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldownLeft = (_cooldownLeft - 1).clamp(0, 1 << 20));
      if (_cooldownLeft == 0) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final insets = MediaQuery.viewInsetsOf(context);
    final subtitle = [
      widget.ref,
      widget.vehicleLabel,
      widget.customerName,
    ].whereType<String>().where((s) => s.isNotEmpty).join('  ·  ');

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: DragHandle()),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hand over vehicle',
                          style: SparklingTypography.headlineSmall.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: SparklingTypography.mono(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconTileButton(
                    icon: Symbols.close_rounded,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(
                      _phase == _Phase.released
                          ? PickupVerifyResult(
                              verified: true,
                              collectedAt: _collectedAt,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_phase == _Phase.released)
                _ReleasedState(
                  collectedAt: _collectedAt ?? DateTime.now(),
                  customerName: widget.customerName,
                  onDone: () => Navigator.of(context).pop(
                    PickupVerifyResult(
                      verified: true,
                      collectedAt: _collectedAt,
                    ),
                  ),
                )
              else ...[
                Text(
                  'Ask the customer for the 5-digit collection OTP from their '
                  'WhatsApp / app, then release the keys.',
                  style: SparklingTypography.bodyLarge.copyWith(
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _OtpField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: _phase == _Phase.input,
                  hasError: _error != null && _phase != _Phase.locked,
                  onSubmitted: _verify,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  InfoBanner(
                    key: const ValueKey('handover-error'),
                    tone: InfoTone.error,
                    icon: _phase == _Phase.locked
                        ? Symbols.lock_clock_rounded
                        : Symbols.error_rounded,
                    bordered: _phase == _Phase.locked,
                    title: _phase == _Phase.locked ? 'Too many attempts' : null,
                    text: _phase == _Phase.locked
                        ? 'Five incorrect codes in a row. Wait a minute or send '
                              'the customer a new OTP, then try again.'
                        : _error!,
                  ),
                ],
                const SizedBox(height: 16),
                PillButton(
                  label: 'Verify & release keys',
                  icon: Symbols.key_rounded,
                  expand: true,
                  minHeight: 56,
                  loading: _phase == _Phase.busy,
                  onPressed: _complete && _phase == _Phase.input
                      ? _verify
                      : null,
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  key: const ValueKey('handover-resend'),
                  onPressed: _resending || _cooldownLeft > 0 ? null : _resend,
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: _resending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Symbols.forward_to_inbox_rounded, size: 20),
                  label: Text(
                    _cooldownLeft > 0
                        ? 'OTP sent · resend in ${_cooldownLeft}s'
                        : 'Resend OTP to customer',
                  ),
                ),
                if (_attemptsLeft != null && _phase == _Phase.input)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '$_attemptsLeft of $maxAttempts attempts left',
                      textAlign: TextAlign.center,
                      style: SparklingTypography.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                const AuditNote(
                  icon: Symbols.verified_user_rounded,
                  text: 'Verification is recorded against your ID with the time; the customer is notified when the keys are released.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Large numeric field for the 5-digit OTP (≥ 56 px, numeric keyboard).
class _OtpField extends StatelessWidget {
  const _OtpField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hasError,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Semantics(
      label: 'Collection OTP, 5 digits',
      textField: true,
      child: TextField(
        key: const ValueKey('handover-otp-field'),
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(_HandoverSheetState.otpLength),
        ],
        autofillHints: const [AutofillHints.oneTimeCode],
        textAlign: TextAlign.center,
        onSubmitted: (_) => onSubmitted(),
        style: SparklingTypography.mono(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: 14,
          color: cs.onSurface,
        ),
        decoration: InputDecoration(
          hintText: '•••••',
          hintStyle: SparklingTypography.mono(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: 14,
            color: cs.outline,
          ),
          counterText: '',
          filled: true,
          fillColor: cs.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SparklingShapes.tile),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SparklingShapes.tile),
            borderSide: hasError
                ? BorderSide(color: cs.error, width: 2)
                : BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SparklingShapes.tile),
            borderSide: BorderSide(
              color: hasError ? cs.error : cs.primary,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Green check state after a successful verification.
class _ReleasedState extends StatelessWidget {
  const _ReleasedState({
    required this.collectedAt,
    required this.onDone,
    this.customerName,
  });

  final DateTime collectedAt;
  final String? customerName;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final x = context.sparkling;
    return Column(
      key: const ValueKey('handover-released'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: x.successContainer,
            borderRadius: BorderRadius.circular(SparklingShapes.card),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: x.success,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.check_rounded,
                  size: 36,
                  color: x.onSuccess,
                  weight: 700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Keys released · collected at ${SparklingDates.hhmm(collectedAt)}',
                textAlign: TextAlign.center,
                style: SparklingTypography.titleLarge.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: x.onSuccessContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${customerName ?? 'The customer'} has been notified. Thanks for a sparkling hand-over!',
                textAlign: TextAlign.center,
                style: SparklingTypography.bodyMedium.copyWith(
                  color: x.onSuccessContainer.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PillButton(
          label: 'Done',
          expand: true,
          minHeight: 56,
          onPressed: onDone,
        ),
      ],
    );
  }
}
