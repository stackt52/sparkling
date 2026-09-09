import 'package:flutter/widgets.dart';

/// M3 window-size-class breakpoints used by the staff app (UX-005, §4.3).
abstract final class Breakpoints {
  /// Tablet / landscape: two-pane master-detail layouts.
  static const double expanded = 840;

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expanded;

  /// Max content width on very wide screens so cards don't stretch.
  static const double maxContentWidth = 1200;
}

/// Master-detail scaffold body: [master] on the left (fixed width), [detail]
/// on the right, or just [master] when the window is compact.
class MasterDetail extends StatelessWidget {
  const MasterDetail({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth = 420,
  });

  final Widget master;
  final Widget detail;
  final double masterWidth;

  @override
  Widget build(BuildContext context) {
    if (!Breakpoints.isExpanded(context)) return master;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: masterWidth, child: master),
        Expanded(child: detail),
      ],
    );
  }
}
