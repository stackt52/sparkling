import 'package:flutter/material.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../app/scope.dart';
import 'feedback.dart';

/// One action in a [FabMenu].
class FabMenuAction {
  const FabMenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.key,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Widget key for the rendered item (tests / semantics).
  final Key? key;

  /// Rendered with the primary container colours (the menu's headline action).
  final bool primary;
}

/// M3 Expressive-style FAB menu: a single primary FAB that expands into a
/// stack of labelled actions above it (closest action first). While open a
/// scrim dims the screen; tapping it, the FAB, or an action closes the menu.
///
/// Place [FabMenu] in `Scaffold.floatingActionButton` and, for the scrim,
/// wrap the body with [FabMenuScrim] driven by the same [FabMenuController].
class FabMenuController extends ChangeNotifier {
  bool _open = false;
  bool get isOpen => _open;

  void open() => _set(true);
  void close() => _set(false);
  void toggle() => _set(!_open);

  void _set(bool v) {
    if (_open == v) return;
    _open = v;
    notifyListeners();
  }
}

class FabMenu extends StatefulWidget {
  const FabMenu({
    super.key,
    required this.controller,
    required this.actions,
    this.icon = Symbols.add_rounded,
    this.tooltip = 'Actions',
  }) : assert(actions.length > 0);

  final FabMenuController controller;

  /// Bottom-up order: the first action sits closest to the FAB.
  final List<FabMenuAction> actions;
  final IconData icon;
  final String tooltip;

  @override
  State<FabMenu> createState() => _FabMenuState();
}

class _FabMenuState extends State<FabMenu> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: SparklingMotion.medium,
    reverseDuration: SparklingMotion.fast,
  );

  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _anim.value = widget.controller.isOpen ? 1 : 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = context.settings.reducedMotion;
  }

  @override
  void didUpdateWidget(covariant FabMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _anim.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (widget.controller.isOpen) {
      _reducedMotion ? _anim.value = 1 : _anim.forward();
    } else {
      _reducedMotion ? _anim.value = 0 : _anim.reverse();
    }
  }

  void _toggle() {
    StaffHaptics.tap(context);
    widget.controller.toggle();
  }

  void _run(FabMenuAction a) {
    // Collapse instantly: the pushed route's transition covers the close, and
    // an offstage route's ticker is muted, so a reverse animation would freeze
    // half-open (leaving the items in the tree) until the user came back.
    widget.controller.close();
    _anim.value = 0;
    a.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final open = widget.controller.isOpen;
    final n = widget.actions.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Actions, rendered top-down so the first action ends up nearest the FAB.
        for (var i = n - 1; i >= 0; i--)
          _MenuItem(
            action: widget.actions[i],
            // Staggered: the item closest to the FAB animates first.
            animation: CurvedAnimation(
              parent: _anim,
              curve: Interval(
                (i / n) * 0.5,
                0.5 + (i / n) * 0.5,
                curve: Curves.easeOutBack,
              ),
              reverseCurve: Curves.easeIn,
            ),
            visible: open || _anim.isAnimating,
            onTap: () => _run(widget.actions[i]),
          ),
        AnimatedBuilder(
          animation: _anim,
          builder: (context, _) => FloatingActionButton(
            key: const ValueKey('fab-menu'),
            heroTag: 'fab-menu',
            tooltip: open ? 'Close' : widget.tooltip,
            backgroundColor: Color.lerp(
              cs.primaryContainer,
              cs.primary,
              _anim.value,
            ),
            foregroundColor: Color.lerp(
              cs.onPrimaryContainer,
              cs.onPrimary,
              _anim.value,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                lerpDouble(16, 28, _anim.value)!,
              ),
            ),
            onPressed: _toggle,
            child: Transform.rotate(
              angle: _anim.value * 0.785398, // 45° → "+" becomes "×"
              child: Icon(widget.icon, fill: 0, size: 28),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.action,
    required this.animation,
    required this.visible,
    required this.onTap,
  });

  final FabMenuAction action;
  final Animation<double> animation;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final bg = action.primary ? cs.primaryContainer : cs.secondaryContainer;
    final fg = action.primary ? cs.onPrimaryContainer : cs.onSecondaryContainer;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value.clamp(0.0, 1.0);
        if (t == 0 && !visible) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 16),
              child: Transform.scale(
                scale: 0.85 + 0.15 * t,
                alignment: Alignment.bottomRight,
                child: IgnorePointer(ignoring: t < 0.6, child: child),
              ),
            ),
          ),
        );
      },
      child: Material(
        key: action.key,
        color: bg,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, fill: 0, size: 22, color: fg),
                const SizedBox(width: 12),
                Text(
                  action.label,
                  style: context.text.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dims and blocks the page behind an open [FabMenu]; tapping it closes the
/// menu. Wrap the scaffold body: `FabMenuScrim(controller: c, child: body)`.
class FabMenuScrim extends StatelessWidget {
  const FabMenuScrim({
    super.key,
    required this.controller,
    required this.child,
  });

  final FabMenuController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          child,
          IgnorePointer(
            ignoring: !controller.isOpen,
            child: AnimatedOpacity(
              opacity: controller.isOpen ? 1 : 0,
              duration: context.settings.reducedMotion
                  ? Duration.zero
                  : SparklingMotion.fast,
              child: GestureDetector(
                key: const ValueKey('fab-menu-scrim'),
                behavior: HitTestBehavior.opaque,
                onTap: controller.close,
                child: ColoredBox(
                  color: context.colors.scrim.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double? lerpDouble(num a, num b, double t) => a + (b - a) * t;
