import 'package:flutter/material.dart' hide Page;
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../widgets/common.dart';

/// Rewards tab (1i): tier card, tier pills, redeemable rewards, ledger.
class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  Stream<LoyaltyAccountSummary>? _account;
  Future<List<Reward>>? _rewards;
  Page<LedgerEntry>? _ledger;
  Object? _ledgerError;
  bool _loadingMore = false;
  int? _tierSegment;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_account == null) _init();
  }

  void _init() {
    final repos = context.repos;
    _account = repos.loyalty.watchAccount();
    _rewards = repos.loyalty.rewards();
    _loadLedger();
  }

  Future<void> _loadLedger() async {
    setState(() {
      _ledger = null;
      _ledgerError = null;
    });
    try {
      final page = await context.repos.loyalty.ledger(limit: 10);
      if (mounted) setState(() => _ledger = page);
    } catch (e) {
      if (mounted) setState(() => _ledgerError = e);
    }
  }

  Future<void> _loadMore() async {
    final current = _ledger;
    if (current == null || !current.hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await context.repos.loyalty.ledger(
        limit: 10,
        cursor: current.nextCursor,
      );
      if (mounted) setState(() => _ledger = current.append(next));
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _redeem(Reward reward, LoyaltyAccountSummary acc) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => _RedeemSheet(reward: reward, balance: acc.balance),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await context.repos.loyalty.redeem(reward.id);
      if (!mounted) return;
      AppHaptics.success(context);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reward issued'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Show this code at the outlet:'),
              const SizedBox(height: 10),
              KeyValueTile(label: 'Code', value: r.code, mono: true),
              if (r.balanceAfter != null) ...[
                const SizedBox(height: 10),
                Text('New balance ${Money.formatPointsLabel(r.balanceAfter!)}'),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      _loadLedger();
      setState(() => _rewards = context.repos.loyalty.rewards());
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => setState(_init),
          child: StreamBuilder<LoyaltyAccountSummary>(
            stream: _account,
            builder: (context, snap) {
              final acc = snap.data;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Text(
                    'Rewards',
                    style: SparklingTypography.headlineLarge.copyWith(
                      fontSize: 30,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (snap.hasError && acc == null)
                    ErrorView(
                      error: snap.error,
                      compact: true,
                      onRetry: () => setState(_init),
                    )
                  else if (acc == null)
                    const HeroCard.gold(
                      child: SizedBox(height: 150, child: LoadingView()),
                    )
                  else ...[
                    _TierCard(account: acc),
                    const SizedBox(height: 14),
                    SegmentedPills(
                      labels: LoyaltyTier.values.map((t) => t.label).toList(),
                      selected: _tierSegment ?? acc.tier.index,
                      onSelected: (i) => setState(() => _tierSegment = i),
                    ),
                    const SizedBox(height: 10),
                    _TierBenefits(
                      account: acc,
                      tier: LoyaltyTier.values[_tierSegment ?? acc.tier.index],
                    ),
                    const SizedBox(height: 22),
                    const SectionHeader(title: 'Redeem points'),
                    FutureBuilder<List<Reward>>(
                      future: _rewards,
                      builder: (context, rs) {
                        if (rs.hasError) {
                          return ErrorView(
                            error: rs.error,
                            compact: true,
                            onRetry: () => setState(
                              () => _rewards = context.repos.loyalty.rewards(),
                            ),
                          );
                        }
                        final rewards = rs.data;
                        if (rewards == null) {
                          return const LoadingView(compact: true);
                        }
                        if (rewards.isEmpty) {
                          return const EmptyState(
                            icon: Symbols.redeem_rounded,
                            title: 'No rewards available yet',
                          );
                        }
                        return _RewardGrid(
                          rewards: rewards,
                          account: acc,
                          onRedeem: (r) => _redeem(r, acc),
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    const SectionHeader(title: 'Points activity'),
                    if (_ledgerError != null)
                      ErrorView(
                        error: _ledgerError,
                        compact: true,
                        onRetry: _loadLedger,
                      )
                    else if (_ledger == null)
                      const LoadingView(compact: true)
                    else
                      _LedgerCard(
                        page: _ledger!,
                        loadingMore: _loadingMore,
                        onLoadMore: _loadMore,
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.account});
  final LoyaltyAccountSummary account;

  @override
  Widget build(BuildContext context) {
    final acc = account;
    final progress = acc.progressToNextTier;
    final white = Colors.white;
    return HeroCard.gold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TierPill(
                tier: tierKind(acc.tier),
                label: '${acc.tier.label} member',
                uppercase: true,
                icon: null,
              ),
              const Spacer(),
              const SparklingLogo(height: 28, onDark: true),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Points balance',
            style: SparklingTypography.bodyLarge.copyWith(
              fontSize: 16,
              color: white.withValues(alpha: 0.8),
            ),
          ),
          Text(
            Money.formatPoints(acc.balance),
            style: SparklingTypography.displayLarge.copyWith(color: white),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                acc.tier.label,
                style: SparklingTypography.titleMedium.copyWith(color: white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  acc.nextTierLabel ?? 'Top tier reached',
                  textAlign: TextAlign.end,
                  style: SparklingTypography.bodyMedium.copyWith(
                    fontSize: 13.5,
                    color: white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearLevelBar.progress(
            value: progress.clamp(0, 1),
            height: 8,
            trackColor: white.withValues(alpha: 0.22),
          ),
        ],
      ),
    );
  }
}

class _TierBenefits extends StatelessWidget {
  const _TierBenefits({required this.account, required this.tier});
  final LoyaltyAccountSummary account;
  final LoyaltyTier tier;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final cfg = account.tierConfig.where((t) => t.tier == tier).firstOrNull;
    if (cfg == null) return const SizedBox.shrink();
    final isCurrent = tier == account.tier;
    final parts = [
      cfg.qualifyRange,
      if (cfg.discountPct > 0) '${cfg.discountPct}% off every wash',
      if (cfg.earnMultiplier != 1) '${cfg.earnMultiplier}× points',
    ];
    return Text(
      '${isCurrent ? 'Your tier · ' : ''}${parts.join(' · ')}',
      style: SparklingTypography.bodyMedium.copyWith(
        fontSize: 13.5,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}

class _RewardGrid extends StatelessWidget {
  const _RewardGrid({
    required this.rewards,
    required this.account,
    required this.onRedeem,
  });

  final List<Reward> rewards;
  final LoyaltyAccountSummary account;
  final ValueChanged<Reward> onRedeem;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final w = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < rewards.length; i++)
              SizedBox(
                width: w,
                child: _RewardCard(
                  reward: rewards[i],
                  primary: i.isEven,
                  affordable: rewards[i].affordableWith(account.balance),
                  onRedeem: () => onRedeem(rewards[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.reward,
    required this.primary,
    required this.affordable,
    required this.onRedeem,
  });

  final Reward reward;
  final bool primary;
  final bool affordable;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final bg = primary ? cs.primaryContainer : cs.secondaryContainer;
    final fg = primary ? cs.onPrimaryContainer : cs.onSecondaryContainer;
    final accent = primary
        ? cs.primary
        : (context.isDark ? cs.secondary : context.sparkling.navy);
    return Semantics(
      label:
          '${reward.name}, ${Money.formatPointsLabel(reward.pointsCost)}${affordable ? '' : ', not enough points'}',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(SparklingShapes.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(serviceIcon(reward.icon), color: accent, fill: 1, size: 30),
            const SizedBox(height: 18),
            Text(
              reward.name,
              style: SparklingTypography.titleLarge.copyWith(
                fontSize: 17,
                color: fg,
              ),
            ),
            if (reward.description != null)
              Text(
                reward.description!,
                style: SparklingTypography.bodySmall.copyWith(
                  color: fg.withValues(alpha: 0.75),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Money.formatPointsLabel(reward.pointsCost),
                      maxLines: 1,
                      style: SparklingTypography.titleLarge.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ),
                PillButton(
                  label: 'Redeem',
                  dense: true,
                  variant: primary
                      ? PillButtonVariant.filled
                      : PillButtonVariant.navy,
                  onPressed: affordable ? onRedeem : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RedeemSheet extends StatelessWidget {
  const _RedeemSheet({required this.reward, required this.balance});
  final Reward reward;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final after = balance - reward.pointsCost;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: 'Redeem ${reward.name}?'),
            Row(
              children: [
                TintedIconTile(icon: serviceIcon(reward.icon), size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reward.description ?? reward.name,
                        style: SparklingTypography.bodyLarge.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${Money.formatPointsLabel(reward.pointsCost)} · balance after ${Money.formatPointsLabel(after)}',
                        style: SparklingTypography.bodyMedium.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const AuditNote(
              icon: Symbols.receipt_long_rounded,
              text: 'Redemptions are recorded as a ledger entry and cannot be reversed in-app.',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Cancel',
                    variant: PillButtonVariant.outlined,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: PillButton(
                    label:
                        'Redeem ${Money.formatPoints(reward.pointsCost)} pts',
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(true),
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

class _LedgerCard extends StatelessWidget {
  const _LedgerCard({
    required this.page,
    required this.loadingMore,
    required this.onLoadMore,
  });

  final Page<LedgerEntry> page;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    if (page.isEmpty) {
      return const EmptyState(
        icon: Symbols.history_rounded,
        title: 'No points activity yet',
        message: 'Points post when a service is completed.',
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(SparklingShapes.card),
      ),
      child: Column(
        children: [
          for (var i = 0; i < page.items.length; i++) ...[
            if (i > 0) Divider(color: cs.outlineVariant),
            _LedgerRow(entry: page.items[i]),
          ],
          if (page.hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: PillButton(
                label: 'Load more',
                variant: PillButtonVariant.tonal,
                dense: true,
                loading: loadingMore,
                onPressed: onLoadMore,
              ),
            ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});
  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final e = entry;
    final credit = e.isCredit;
    final color = credit ? x.success : cs.error;
    final when = e.createdAt == null
        ? ''
        : SparklingDates.dayMonth(e.createdAt!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            credit
                ? Symbols.add_circle_rounded
                : Symbols.do_not_disturb_on_rounded,
            color: color,
            fill: 1,
            size: 26,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title.isEmpty ? e.type.label : e.title,
                  style: SparklingTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  [when, e.type.label].where((s) => s.isNotEmpty).join(' · '),
                  style: SparklingTypography.bodyMedium.copyWith(
                    fontSize: 13.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            Money.formatDelta(e.delta),
            style: SparklingTypography.titleLarge.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
