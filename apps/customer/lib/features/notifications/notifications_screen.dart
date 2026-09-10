import 'package:flutter/material.dart' hide Page;
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';

/// In-app notification inbox (push / WhatsApp mirror), paged via [Page].
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Page<AppNotification>? _page;
  Object? _error;
  bool _loadingMore = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_page == null && _error == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _page = null;
      _error = null;
    });
    try {
      final page = await context.repos.notifications.list(limit: 20);
      if (mounted) setState(() => _page = page);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadMore() async {
    final current = _page;
    if (current == null || !current.hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await context.repos.notifications.list(
        limit: 20,
        cursor: current.nextCursor,
      );
      if (mounted) setState(() => _page = current.append(next));
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.isRead) {
      try {
        await context.repos.notifications.markRead(n.id);
        if (mounted) {
          setState(() {
            _page = Page(
              items: _page!.items
                  .map(
                    (x) =>
                        x.id == n.id ? x.copyWith(readAt: DateTime.now()) : x,
                  )
                  .toList(),
              nextCursor: _page!.nextCursor,
            );
          });
        }
      } catch (_) {}
    }
    if (!mounted) return;
    final type = n.linkType;
    final id = n.linkId;
    if (id == null) return;
    switch (type) {
      case 'booking':
        context.push(Routes.bookingDetail(id));
      case 'work_order':
      case 'tracking':
        context.push(Routes.track(id));
      case 'quotation':
        context.push(Routes.quote(id));
      case 'loyalty':
      case 'reward':
        context.go(Routes.loyalty);
      default:
        break;
    }
  }

  IconData _icon(AppNotification n) => switch (n.templateKey) {
    final k when k.contains('otp') || k.contains('pickup') =>
      Symbols.key_rounded,
    final k when k.contains('ready') => Symbols.task_alt_rounded,
    final k when k.contains('quote') => Symbols.request_quote_rounded,
    final k when k.contains('loyalty') || k.contains('points') =>
      Symbols.loyalty_rounded,
    final k when k.contains('payment') || k.contains('receipt') =>
      Symbols.receipt_long_rounded,
    _ => Symbols.notifications_rounded,
  };

  /// Unread dot and/or the delivery double-tick (WhatsApp / push confirmed
  /// delivered by the provider).
  Widget? _trailing(BuildContext context, AppNotification n) {
    final delivered = n.isDelivered;
    if (n.isRead && !delivered) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (delivered)
          Tooltip(
            message: n.deliveredAt == null
                ? 'Delivered'
                : 'Delivered ${SparklingDates.hhmm(n.deliveredAt!)}',
            child: Semantics(
              label: 'Delivered',
              child: Icon(
                Symbols.done_all_rounded,
                key: const ValueKey('delivered-tick'),
                size: 20,
                color: context.sparkling.success,
              ),
            ),
          ),
        if (!n.isRead) ...[
          if (delivered) const SizedBox(width: 8),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: context.sparkling.azure,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final page = _page;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(
              title: 'Notifications',
              subtitle: 'Booking updates, quotes and rewards',
            ),
            Expanded(
              child: _error != null
                  ? ErrorView(error: _error, onRetry: _load)
                  : page == null
                  ? const LoadingView()
                  : page.isEmpty
                  ? const EmptyState(
                      icon: Symbols.notifications_off_rounded,
                      title: "You're all caught up",
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: page.items.length + (page.hasMore ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          if (i == page.items.length) {
                            return Center(
                              child: PillButton(
                                label: 'Load more',
                                variant: PillButtonVariant.tonal,
                                loading: _loadingMore,
                                onPressed: _loadMore,
                              ),
                            );
                          }
                          final n = page.items[i];
                          return ListTileCard(
                            onTap: () => _open(n),
                            color: n.isRead
                                ? null
                                : cs.primaryContainer.withValues(
                                    alpha: context.isDark ? 0.5 : 0.45,
                                  ),
                            leading: TintedIconTile(
                              icon: _icon(n),
                              size: 44,
                              radius: 14,
                              background: n.isRead
                                  ? cs.surfaceContainerHigh
                                  : cs.primaryContainer,
                              foreground: n.isRead
                                  ? cs.onSurfaceVariant
                                  : cs.primary,
                            ),
                            title: Text(
                              n.title ?? n.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: n.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (n.title != null) n.body,
                                if (n.createdAt != null)
                                  SparklingDates.relativeSlot(n.createdAt!),
                                n.channel.db == 'whatsapp'
                                    ? 'WhatsApp'
                                    : 'Push',
                              ].join(' · '),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: _trailing(context, n),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
