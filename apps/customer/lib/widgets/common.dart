import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../app/app_scope.dart';

// ---------------------------------------------------------------------------
// Errors & feedback
// ---------------------------------------------------------------------------

/// Human-readable, actionable message for any error (UX-010).
String describeError(Object? error) {
  if (error is ApiException) return error.message;
  if (error is AuthException) return error.message;
  if (error is DiscParseException) return error.message;
  return 'Something went wrong. Please try again.';
}

void showSnack(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

/// Haptic feedback that honours the profile `haptics` preference.
abstract final class AppHaptics {
  static bool enabled(BuildContext context) =>
      AppScope.of(context).session.profile?.haptics ?? true;

  static void light(BuildContext context) {
    if (enabled(context)) HapticFeedback.lightImpact();
  }

  static void success(BuildContext context) {
    if (enabled(context)) HapticFeedback.mediumImpact();
  }

  static void selection(BuildContext context) {
    if (enabled(context)) HapticFeedback.selectionClick();
  }
}

// ---------------------------------------------------------------------------
// Layout primitives
// ---------------------------------------------------------------------------

/// Back tile + title + subtitle header used on every pushed screen (1b/1e/1f).
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleWidget,
    this.trailing,
    this.onBack,
    this.showBack = true,
    this.backIcon = Symbols.arrow_back_rounded,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 12),
  });

  final String title;
  final String? subtitle;
  final Widget? titleWidget;
  final Widget? trailing;
  final VoidCallback? onBack;
  final bool showBack;
  final IconData backIcon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showBack) ...[
            IconTileButton(
              icon: backIcon,
              tooltip: 'Back',
              onPressed:
                  onBack ??
                  () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  },
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleWidget ??
                    Text(
                      title,
                      style: SparklingTypography.headlineMedium.copyWith(
                        fontSize: 24,
                        color: cs.onSurface,
                      ),
                    ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: SparklingTypography.bodyLarge.copyWith(
                      fontSize: 14.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// Sticky bottom bar with an optional left label/value and a full pill CTA
/// (1b/1c bottom bars).
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.child,
    this.leadingLabel,
    this.leadingValue,
  });

  final Widget child;
  final String? leadingLabel;
  final String? leadingValue;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        children: [
          if (leadingValue != null) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingLabel != null)
                  Text(
                    leadingLabel!,
                    style: SparklingTypography.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                Text(
                  leadingValue!,
                  style: SparklingTypography.headlineMedium.copyWith(
                    fontSize: 22,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
          ],
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 1px dashed horizontal rule (payment summary).
class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, this.color, this.height = 1});

  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.outline;
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 6.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          children: List.generate(
            count,
            (_) => Container(
              width: dash,
              height: height,
              margin: const EdgeInsets.only(right: gap),
              color: c,
            ),
          ),
        );
      },
    );
  }
}

/// 44×32 r8 navy plate with the card brand (VISA) or an EFT glyph.
class BrandPlate extends StatelessWidget {
  const BrandPlate({super.key, required this.brand, this.large = false});

  final String? brand;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final x = context.sparkling;
    final dark = context.isDark;
    final w = large ? 86.0 : 44.0;
    final h = large ? 62.0 : 32.0;
    final label = switch (brand) {
      'visa' => 'VISA',
      'mastercard' => 'MC',
      'amex' => 'AMEX',
      'eft' => null,
      _ => 'CARD',
    };
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: dark ? context.colors.primaryContainer : x.navy,
        borderRadius: BorderRadius.circular(
          large ? SparklingShapes.iconTile : SparklingShapes.plate,
        ),
      ),
      alignment: Alignment.center,
      child: label == null
          ? Icon(
              Symbols.account_balance_rounded,
              size: large ? 30 : 18,
              color: dark ? context.colors.onPrimaryContainer : Colors.white,
              fill: 1,
            )
          : Text(
              label,
              style: SparklingTypography.font(
                fontSize: large ? 20 : 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: dark ? context.colors.onPrimaryContainer : Colors.white,
              ),
            ),
    );
  }
}

/// Navy 44px initials tile (app bar avatar).
class AvatarTile extends StatelessWidget {
  const AvatarTile({
    super.key,
    required this.initials,
    this.size = 44,
    this.onTap,
  });

  final String initials;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconTileButton(
      tone: IconTileTone.navy,
      size: size,
      onPressed: onTap,
      tooltip: 'Profile',
      child: Text(
        initials,
        style: SparklingTypography.font(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: context.isDark
              ? context.colors.onPrimaryContainer
              : Colors.white,
        ),
      ),
    );
  }
}

/// Segmented pill row (Silver / Gold / Platinum, Week / Month …).
class SegmentedPills extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final dark = context.isDark;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              button: true,
              selected: i == selected,
              child: Material(
                color: i == selected
                    ? (dark ? cs.primaryContainer : x.navy)
                    : cs.surfaceContainer,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onSelected(i),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: SparklingSpacing.touchTarget,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: SparklingTypography.titleMedium.copyWith(
                        fontWeight: i == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i == selected
                            ? (dark ? cs.onPrimaryContainer : Colors.white)
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A tinted square icon tile (service icon in payment summary, quote rows).
class TintedIconTile extends StatelessWidget {
  const TintedIconTile({
    super.key,
    required this.icon,
    this.size = 56,
    this.radius = SparklingShapes.tile,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final double size;
  final double radius;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? cs.primaryContainer,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        icon,
        size: size * 0.45,
        color: foreground ?? cs.primary,
        fill: 1,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Async helpers
// ---------------------------------------------------------------------------

/// Loading / error / data switch for a [Future] with retry (UX-010).
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    this.onRetry,
    this.loading,
    this.initialData,
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;
  final T? initialData;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      initialData: initialData,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView(error: snap.error, onRetry: onRetry);
        }
        if (!snap.hasData) {
          return loading ?? const LoadingView();
        }
        return builder(context, snap.data as T);
      },
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 16 : 48),
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, this.error, this.onRetry, this.compact = false});
  final Object? error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(compact ? 0 : 20),
      child: InfoBanner(
        tone: InfoTone.error,
        title: 'Could not load',
        text: describeError(error),
        actionLabel: onRetry == null ? null : 'Retry',
        onAction: onRetry,
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(SparklingShapes.card),
            ),
            child: Icon(icon, size: 30, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: SparklingTypography.titleLarge.copyWith(color: cs.onSurface),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: SparklingTypography.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 18),
            PillButton(
              label: actionLabel!,
              onPressed: onAction,
              variant: PillButtonVariant.tonal,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Domain helpers
// ---------------------------------------------------------------------------

/// Maps catalogue icon names (Material Symbols) to rounded glyphs.
IconData serviceIcon(String? name) => switch (name) {
  'water_drop' => Symbols.water_drop_rounded,
  'local_car_wash' => Symbols.local_car_wash_rounded,
  'auto_awesome' => Symbols.auto_awesome_rounded,
  'cleaning_services' => Symbols.cleaning_services_rounded,
  'car_crash' => Symbols.car_crash_rounded,
  'bolt' => Symbols.bolt_rounded,
  'percent' => Symbols.percent_rounded,
  'loyalty' => Symbols.loyalty_rounded,
  _ => Symbols.local_car_wash_rounded,
};

LoyaltyTierKind tierKind(LoyaltyTier tier) => switch (tier) {
  LoyaltyTier.silver => LoyaltyTierKind.silver,
  LoyaltyTier.gold => LoyaltyTierKind.gold,
  LoyaltyTier.platinum => LoyaltyTierKind.platinum,
};

StatusChipTone bookingTone(BookingStatus status) => switch (status) {
  BookingStatus.confirmed => StatusChipTone.success,
  BookingStatus.inService => StatusChipTone.primary,
  BookingStatus.pending => StatusChipTone.warning,
  BookingStatus.completed => StatusChipTone.neutral,
  BookingStatus.cancelled => StatusChipTone.error,
  BookingStatus.draft => StatusChipTone.neutral,
};

StatusChipTone quotationTone(QuotationStatus status) => switch (status) {
  QuotationStatus.quoted => StatusChipTone.gold,
  QuotationStatus.accepted ||
  QuotationStatus.converted => StatusChipTone.success,
  QuotationStatus.declined || QuotationStatus.expired => StatusChipTone.error,
  QuotationStatus.assessing => StatusChipTone.primary,
  QuotationStatus.requested => StatusChipTone.neutral,
};

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// "Sparkling Rosebank" → "Rosebank" for tight labels.
String shortOutletName(String? name) {
  if (name == null) return '';
  const prefix = 'Sparkling ';
  return name.startsWith(prefix) ? name.substring(prefix.length) : name;
}
