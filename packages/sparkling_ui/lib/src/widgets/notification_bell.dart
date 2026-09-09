import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import 'icon_tile_button.dart';

/// Notification bell tile with an azure badge dot when [hasUnread] (1a).
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    this.hasUnread = false,
    this.count,
    this.onPressed,
    this.size = 44,
  });

  final bool hasUnread;

  /// Optional count rendered inside the badge (dot only when null).
  final int? count;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final showBadge = hasUnread || (count ?? 0) > 0;
    return Semantics(
      label: showBadge
          ? 'Notifications, ${count ?? 'new'} unread'
          : 'Notifications',
      button: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconTileButton(
            icon: Symbols.notifications_rounded,
            onPressed: onPressed,
            size: size,
          ),
          if (showBadge)
            Positioned(
              right: 8,
              top: 8,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 10,
                    minHeight: 10,
                  ),
                  padding: count == null
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: SparklingColors.azure,
                    shape: count == null ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: count == null
                        ? null
                        : BorderRadius.circular(8),
                    border: Border.all(
                      color: context.colors.surfaceContainer,
                      width: 1.5,
                    ),
                  ),
                  child: count == null
                      ? null
                      : Text(
                          count! > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
