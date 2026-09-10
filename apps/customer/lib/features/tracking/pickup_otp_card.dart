import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../widgets/common.dart';

/// "Ready for collection" card shown on the tracking screen and booking
/// detail while a completed booking still carries its collection OTP
/// (`work_order.pickup_otp`). The code is rendered in large mono digits so it
/// can be read across a counter; tapping it copies the code.
class PickupOtpCard extends StatelessWidget {
  const PickupOtpCard({super.key, required this.booking, this.compact = false});

  final Booking booking;

  /// Tighter padding / smaller digits (booking detail).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final otp = booking.pickupOtp;
    if (otp == null) return const SizedBox.shrink();
    final cs = context.colors;
    final x = context.sparkling;
    final outlet = shortOutletName(booking.outlet?.name);
    final digits = otp.split('').join(' ');

    return Semantics(
      container: true,
      label:
          'Ready for collection. Collection OTP ${otp.split('').join(' ')}. Show this at the counter to collect your keys.',
      child: Container(
        padding: EdgeInsets.all(compact ? 16 : 20),
        decoration: BoxDecoration(
          color: x.successContainer,
          borderRadius: BorderRadius.circular(SparklingShapes.card),
          border: Border.all(
            color: x.success.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: x.success,
                    borderRadius: BorderRadius.circular(SparklingShapes.plate),
                  ),
                  child: Icon(
                    Symbols.key_rounded,
                    color: x.onSuccess,
                    fill: 1,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ready for collection',
                        style: SparklingTypography.titleLarge.copyWith(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: x.onSuccessContainer,
                        ),
                      ),
                      Text(
                        outlet.isEmpty
                            ? 'Your vehicle is waiting for you'
                            : 'Your vehicle is waiting at $outlet',
                        style: SparklingTypography.bodyMedium.copyWith(
                          color: x.onSuccessContainer.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 14 : 18),
            Material(
              color: cs.surface.withValues(alpha: context.isDark ? 0.25 : 0.7),
              borderRadius: BorderRadius.circular(SparklingShapes.tile),
              child: InkWell(
                borderRadius: BorderRadius.circular(SparklingShapes.tile),
                onTap: () async {
                  AppHaptics.selection(context);
                  await Clipboard.setData(ClipboardData(text: otp));
                  if (context.mounted) showSnack(context, 'OTP $otp copied');
                },
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: compact ? 12 : 16),
                  child: Column(
                    children: [
                      Text(
                        'COLLECTION OTP',
                        style: SparklingTypography.overline.copyWith(
                          fontSize: 11,
                          letterSpacing: 1.6,
                          color: x.onSuccessContainer.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          digits,
                          key: const ValueKey('pickup-otp-digits'),
                          style: SparklingTypography.mono(
                            fontSize: compact ? 38 : 46,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: x.onSuccessContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 12 : 14),
            Text(
              'Show this at the counter to collect your keys.',
              style: SparklingTypography.bodyLarge.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: x.onSuccessContainer,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Symbols.done_all_rounded,
                  size: 16,
                  color: x.onSuccessContainer.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Also sent to you by WhatsApp and push notification.',
                    style: SparklingTypography.bodySmall.copyWith(
                      color: x.onSuccessContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
