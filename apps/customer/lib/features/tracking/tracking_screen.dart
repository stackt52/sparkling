import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../widgets/common.dart';
import 'pickup_otp_card.dart';

/// Live service tracking timeline (1h) with offline degradation (1l).
///
/// Subscribes to `customer.watchBooking` (realtime via Supabase in live mode,
/// store change events in demo). When the device is offline the last
/// received snapshot is shown with an [OfflineBanner], a "Last sync" chip and
/// a desaturated progress ring (CUS-054, ARC-004).
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  StreamSubscription<Booking>? _sub;
  StreamSubscription<bool>? _conn;
  Timer? _ticker;
  Booking? _booking;
  Object? _error;
  DateTime? _lastSync;
  bool _online = true;
  bool _notify = true;
  bool _notifyQueued = false;

  String get _notifyKey => 'notify_ready:${widget.bookingId}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final repos = context.repos;
    _online = repos.connectivity.lastKnown;
    final cached = repos.cache.get(_notifyKey)?.data;
    if (cached is bool) _notify = cached;
    _lastSync = repos.cache.lastSyncedAt('booking:${widget.bookingId}');
    _subscribe();
    _conn = repos.connectivity.online.listen((v) {
      if (!mounted) return;
      setState(() => _online = v);
      if (v) {
        _notifyQueued = false;
        _subscribe();
      }
    });
    // Re-render "x min ago" labels.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _subscribe() {
    _sub?.cancel();
    setState(() => _error = null);
    _sub = context.repos.customer
        .watchBooking(widget.bookingId)
        .listen(
          (b) {
            if (!mounted) return;
            setState(() {
              _booking = b;
              _lastSync = DateTime.now();
              _error = null;
            });
          },
          onError: (e) {
            if (!mounted) return;
            // Keep the last snapshot; surface the error only when we have nothing.
            setState(() => _error = _booking == null ? e : null);
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _conn?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _setNotify(bool v) async {
    AppHaptics.selection(context);
    setState(() {
      _notify = v;
      _notifyQueued = !_online;
    });
    await context.repos.cache.put(_notifyKey, v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final b = _booking;
    final lastSyncLabel = _lastSync == null
        ? null
        : SparklingDates.hhmm(_lastSync!);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (!_online)
              OfflineBanner(
                lastSyncLabel: lastSyncLabel,
                margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                onRetry: () async {
                  final ok = await context.repos.connectivity.isOnline();
                  if (ok) _subscribe();
                },
              ),
            ScreenHeader(
              title: b?.ref ?? 'Tracking',
              titleWidget: b == null
                  ? null
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        b.ref,
                        style: SparklingTypography.mono(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
              subtitle: b == null
                  ? null
                  : [
                      b.vehicle?.shortName,
                      b.vehicle?.registrationNo,
                    ].whereType<String>().join(' · '),
              trailing: b == null
                  ? null
                  : _online
                  ? StatusChip(
                      label: 'Live · ${_agoLabel(b)}',
                      tone: StatusChipTone.live,
                    )
                  : SyncChip(
                      state: SyncState.offline,
                      label: 'Last sync ${lastSyncLabel ?? '—'}',
                    ),
            ),
            Expanded(
              child: b == null
                  ? (_error != null
                        ? ErrorView(error: _error, onRetry: _subscribe)
                        : const LoadingView())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      children: [
                        _StageCard(booking: b, online: _online),
                        if (b.isReadyForCollection) ...[
                          const SizedBox(height: 14),
                          PickupOtpCard(booking: b),
                        ],
                        const SizedBox(height: 20),
                        if (b.timeline.isEmpty)
                          InfoBanner(
                            tone: InfoTone.info,
                            icon: Symbols.schedule_rounded,
                            title: b.status == BookingStatus.cancelled
                                ? 'Booking cancelled'
                                : 'Waiting for check-in',
                            text: b.status == BookingStatus.cancelled
                                ? 'This booking was cancelled${b.cancelReason == null ? '.' : ': ${b.cancelReason}'}'
                                : 'Your timeline starts when ${shortOutletName(b.outlet?.name)} scans your disc at the bay (${SparklingDates.relativeSlot(b.slotStart)}).',
                          )
                        else
                          for (var i = 0; i < b.timeline.length; i++)
                            _timelineTile(b.timeline, i),
                        const SizedBox(height: 8),
                        if (b.status != BookingStatus.completed &&
                            b.status != BookingStatus.cancelled)
                          ListTileCard(
                            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                            leading: Icon(
                              Symbols.notifications_active_rounded,
                              color: cs.primary,
                              fill: 1,
                            ),
                            title: const Text('Notify me when ready'),
                            trailing: Switch(
                              value: _notify,
                              onChanged: _setNotify,
                            ),
                          ),
                        if (_notifyQueued && !_online) ...[
                          const SizedBox(height: 12),
                          InfoBanner(
                            tone: InfoTone.azure,
                            icon: Symbols.sync_rounded,
                            text: 'Your "notify me" change is queued and will sync automatically when you\'re back online.',
                          ),
                        ],
                        if (b.status == BookingStatus.completed) ...[
                          const SizedBox(height: 4),
                          InfoBanner(
                            tone: InfoTone.success,
                            icon: b.workOrder?.isCollected ?? false
                                ? Symbols.car_tag_rounded
                                : null,
                            title: b.workOrder?.isCollected ?? false
                                ? 'Keys released ${SparklingDates.hhmm(b.workOrder!.collectedAt!)}'
                                : 'Service complete',
                            text:
                                '+${b.pointsPending} pts were added to your balance. Thanks for choosing Sparkling!',
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _agoLabel(Booking b) {
    final at = b.workOrder?.updatedAt ?? b.updatedAt ?? _lastSync;
    return at == null ? 'now' : SparklingDates.ago(at);
  }

  Widget _timelineTile(List<TimelineEntry> entries, int i) {
    final e = entries[i];
    final state = switch (e.state) {
      TimelineEntryState.done => TimelineState.done,
      TimelineEntryState.current => TimelineState.current,
      TimelineEntryState.pending => TimelineState.pending,
    };
    final time = e.at == null ? null : SparklingDates.hhmm(e.at!);
    final subtitle = switch (e.state) {
      TimelineEntryState.done => [
        time,
        e.note ?? (e.actorName == null ? 'completed' : 'by ${e.actorName}'),
      ].whereType<String>().join(' · '),
      TimelineEntryState.current =>
        _online
            ? 'In progress${time == null ? '' : ' · started $time'}'
            : 'In progress at last sync',
      TimelineEntryState.pending =>
        e.note ?? (e.key == 'ready' ? null : 'Pending'),
    };
    return TimelineTile(
      title: e.title,
      subtitle: subtitle,
      state: state,
      isFirst: i == 0,
      isLast: i == entries.length - 1,
      icon: e.key == 'ready' && state == TimelineState.pending
          ? Symbols.flag_rounded
          : null,
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.booking, required this.online});
  final Booking booking;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final wo = b.workOrder;
    final dark = context.isDark;
    final cs = context.colors;
    final progress = (wo?.progress ?? 0).clamp(0.0, 1.0);
    final eta = wo?.etaAt;
    final title =
        wo?.stageTitle ??
        (b.status == BookingStatus.completed
            ? (wo?.isCollected ?? false ? 'Collected' : 'Ready for collection')
            : b.status.label);
    final stage = wo == null || wo.stageCount == 0
        ? null
        : 'Stage ${wo.stage} of ${wo.stageCount}';
    final assignee = wo?.assigneeFirstName;
    final complete = b.status == BookingStatus.completed;
    final subtitle = [
      stage,
      if (!online)
        'as of last sync'
      else if (complete && wo?.bay != null)
        'Collect at ${wo!.bay}'
      else if (!complete && assignee != null)
        '$assignee is on your vehicle'
      else if (wo?.bay != null)
        'Bay ${wo!.bay}',
    ].whereType<String>().join(' · ');

    final card = Row(
      children: [
        ProgressRing(
          value: progress,
          size: 64,
          strokeWidth: 6,
          desaturated: !online,
          label: '${(progress * 100).round()}%',
          trackColor: dark && !online
              ? cs.outline.withValues(alpha: 0.6)
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: SparklingTypography.headlineSmall.copyWith(
                  fontSize: 21,
                  color: Colors.white,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: SparklingTypography.bodyLarge.copyWith(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (eta != null && online) ...[
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'READY BY',
                style: SparklingTypography.overline.copyWith(
                  fontSize: 11.5,
                  letterSpacing: 1.2,
                  color: dark ? cs.primary : const Color(0xFF8BD2FF),
                ),
              ),
              Text(
                SparklingDates.eta(eta),
                style: SparklingTypography.headlineMedium.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ],
    );

    if (!online && dark) {
      // 1l: muted card while offline in dark mode.
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(SparklingShapes.hero),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: cs.onSurface),
          child: card,
        ),
      );
    }
    return HeroCard.navy(child: card);
  }
}
