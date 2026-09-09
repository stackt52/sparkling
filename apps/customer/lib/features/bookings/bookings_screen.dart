import 'dart:async';

import 'package:flutter/material.dart' hide Page;
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import '../sync/sync_indicator.dart';

/// Bookings tab: upcoming + history with incremental loading (CUS-070/071).
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  int _segment = 0; // 0 upcoming, 1 history
  Page<Booking>? _page;
  Object? _error;
  bool _loadingMore = false;
  StreamSubscription<List<Booking>>? _live;

  static const int _pageSize = 10;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_page == null && _error == null) _load(reset: true);
    _live ??= context.repos.customer.watchBookings().listen((_) {
      if (mounted && !_loadingMore) _load(reset: true, silent: true);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  bool _matches(Booking b) =>
      _segment == 0 ? b.status.isActive : !b.status.isActive;

  /// Live API exposes cursor pagination; demo/offline data is paged locally so
  /// the UI behaves identically ("Load more" appends a [Page]).
  Future<Page<Booking>> _fetch({String? cursor}) async {
    final repos = context.repos;
    final api = repos.api;
    if (api != null && repos.connectivity.lastKnown) {
      final page = await api.bookings(limit: _pageSize, cursor: cursor);
      return Page(
        items: page.items.where(_matches).toList(),
        nextCursor: page.nextCursor,
      );
    }
    final all = (await repos.customer.bookings()).where(_matches).toList()
      ..sort(
        (a, b) => _segment == 0
            ? a.slotStart.compareTo(b.slotStart)
            : b.slotStart.compareTo(a.slotStart),
      );
    final start = int.tryParse(cursor ?? '') ?? 0;
    final items = all.skip(start).take(_pageSize).toList();
    final next = start + _pageSize < all.length ? '${start + _pageSize}' : null;
    return Page(items: items, nextCursor: next);
  }

  Future<void> _load({bool reset = false, bool silent = false}) async {
    if (reset && !silent) setState(() => _page = null);
    setState(() => _error = null);
    try {
      final first = await _fetch();
      if (mounted) setState(() => _page = first);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadMore() async {
    final current = _page;
    if (current == null || !current.hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _fetch(cursor: current.nextCursor);
      if (mounted) setState(() => _page = current.append(next));
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final page = _page;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bookings',
                      style: SparklingTypography.headlineLarge.copyWith(
                        fontSize: 30,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SyncIndicator(),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedPills(
                labels: const ['Upcoming', 'History'],
                selected: _segment,
                onSelected: (i) {
                  if (i == _segment) return;
                  setState(() => _segment = i);
                  _load(reset: true);
                },
              ),
              const SizedBox(height: 16),
              if (_error != null)
                ErrorView(error: _error, compact: true, onRetry: _load)
              else if (page == null)
                const LoadingView()
              else if (page.isEmpty)
                EmptyState(
                  icon: Symbols.calendar_month_rounded,
                  title: _segment == 0
                      ? 'No upcoming bookings'
                      : 'No past bookings yet',
                  message: _segment == 0
                      ? 'Book a wash and it will show up here.'
                      : null,
                  actionLabel: _segment == 0 ? 'Book a wash' : null,
                  onAction: () => context.push(Routes.bookService),
                )
              else ...[
                for (final b in page.items) ...[
                  _BookingTile(booking: b),
                  const SizedBox(height: 10),
                ],
                if (page.hasMore)
                  Center(
                    child: PillButton(
                      label: 'Load more',
                      variant: PillButtonVariant.tonal,
                      loading: _loadingMore,
                      onPressed: _loadMore,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final b = booking;
    return ListTileCard(
      onTap: () => context.push(Routes.bookingDetail(b.id), extra: b),
      leading: TintedIconTile(icon: serviceIcon(b.service?.icon), size: 48),
      title: Text(b.title.isEmpty ? b.ref : b.title),
      subtitle: Text(
        '${shortOutletName(b.outlet?.name)} · ${SparklingDates.relativeSlot(b.slotStart)}',
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(
            label: b.status.label,
            tone: bookingTone(b.status),
            dense: true,
          ),
          const SizedBox(height: 4),
          Text(
            b.ref,
            style: SparklingTypography.mono(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
