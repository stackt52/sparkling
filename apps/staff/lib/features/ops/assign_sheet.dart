import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../widgets/async_view.dart';
import '../../widgets/avatar_tile.dart';
import '../../widgets/feedback.dart';

/// Outcome of the assign sheet.
class AssignChoice {
  const AssignChoice({required this.member, this.reason});
  final StaffMember member;
  final String? reason;
}

/// Modal bottom sheet (2d, r32 + drag handle) listing outlet staff as radio
/// cards with availability + skill chips; at-capacity rows render at 55%.
/// Returns the chosen member (and optional audited reason) or null.
///
/// Work orders whose vehicle has not been checked in yet cannot be assigned
/// (`POST /tasks/:id/assign` → 409 `not_checked_in`): the sheet disables
/// **Assign** and offers **Confirm check-in** (optional bay), which calls
/// `POST /work-orders/:id/checkin` and unlocks assignment in place.
Future<AssignChoice?> showAssignSheet(
  BuildContext context, {
  required Task task,
  required List<StaffMember> team,
}) {
  return showModalBottomSheet<AssignChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (ctx) => _AssignSheet(task: task, team: team),
  );
}

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.task, required this.team});
  final Task task;
  final List<StaffMember> team;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  StaffMember? _selected;
  final _reason = TextEditingController();
  final _bay = TextEditingController();

  /// The task as last seen — replaced by the server copy after a check-in.
  late Task _task = widget.task;
  bool _checkingIn = false;
  String? _checkInError;

  /// Set once this sheet confirmed the check-in (drives the success banner).
  DateTime? _checkedInHere;
  String? _autoAssignedTo;

  /// Unknown card (no `work_order` expansion) → let the server decide.
  bool get _checkedIn => _task.workOrder?.isCheckedIn ?? true;

  @override
  void initState() {
    super.initState();
    _pickDefault();
  }

  void _pickDefault() {
    final candidates = widget.team.where(
      (m) => !m.atCapacity && m.id != _task.assigneeId,
    );
    _selected = candidates.isEmpty ? null : candidates.first;
  }

  @override
  void dispose() {
    _reason.dispose();
    _bay.dispose();
    super.dispose();
  }

  Future<void> _confirmCheckIn() async {
    setState(() {
      _checkingIn = true;
      _checkInError = null;
    });
    final bay = _bay.text.trim();
    try {
      final result = await context.repositories.staff.checkInWorkOrder(
        _task.workOrderId,
        bay: bay.isEmpty ? null : bay,
      );
      if (!mounted) return;
      final wo = result.workOrder;
      final updated = result.task ?? _task;
      final card = (updated.workOrder ?? _task.workOrder)?.copyWith(
        checkedInAt: wo.checkedInAt,
        checkedInBy: wo.checkedInBy,
        bay: wo.bay,
        status: updated.status,
      );
      setState(() {
        _task = updated.copyWith(
          assigneeName: updated.assigneeName ?? _task.assigneeName,
          workOrder: card,
        );
        _checkingIn = false;
        _checkedInHere = wo.checkedInAt ?? DateTime.now();
        final assignee = _task.assigneeId;
        _autoAssignedTo =
            assignee == null || assignee == widget.task.assigneeId
            ? null
            : (_task.assigneeName ??
                  widget.team
                      .where((m) => m.id == assignee)
                      .firstOrNull
                      ?.fullName ??
                  'a team member');
        if (_selected == null || _selected!.id == assignee) _pickDefault();
      });
      StaffHaptics.success(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingIn = false;
        _checkInError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingIn = false;
        _checkInError = ErrorState.messageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final task = _task;
    final wo = task.workOrder;
    final subtitle = [
      wo?.title ?? task.title,
      if (task.assigneeName != null) 'currently ${task.assigneeName}',
    ].join(' · ');
    final sorted = [...widget.team]
      ..sort((a, b) {
        final c = (a.atCapacity ? 1 : 0).compareTo(b.atCapacity ? 1 : 0);
        return c != 0 ? c : a.activeTasks.compareTo(b.activeTasks);
      });
    final insets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) => Column(
          children: [
            const DragHandle(),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  Text(
                    '${widget.task.assigneeId == null ? 'Assign' : 'Reassign'} ${task.ref}',
                    style: SparklingTypography.headlineMedium.copyWith(
                      fontSize: 26,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: SparklingTypography.bodyLarge.copyWith(
                      fontSize: 15,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!_checkedIn) ...[
                    const InfoBanner(
                      key: ValueKey('awaiting-checkin-banner'),
                      tone: InfoTone.warning,
                      icon: Symbols.login_rounded,
                      title: 'Awaiting check-in',
                      text:
                          'The vehicle has not been checked in yet. Confirm the '
                          'check-in once it is on site to unlock assignment.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('check-in-bay'),
                      controller: _bay,
                      textCapitalization: TextCapitalization.words,
                      enabled: !_checkingIn,
                      decoration: const InputDecoration(
                        hintText: 'Bay (optional)',
                        prefixIcon: Icon(Symbols.garage_rounded),
                      ),
                    ),
                    if (_checkInError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _checkInError!,
                        style: SparklingTypography.bodyMedium.copyWith(
                          color: cs.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    PillButton(
                      key: const ValueKey('confirm-check-in'),
                      label: 'Confirm check-in',
                      icon: Symbols.login_rounded,
                      variant: PillButtonVariant.tonal,
                      expand: true,
                      minHeight: 52,
                      loading: _checkingIn,
                      onPressed: _checkingIn ? null : _confirmCheckIn,
                    ),
                    const SizedBox(height: 18),
                  ] else if (_checkedInHere != null) ...[
                    InfoBanner(
                      key: const ValueKey('checked-in-banner'),
                      tone: InfoTone.success,
                      icon: Symbols.check_circle_rounded,
                      title: 'Checked in ${SparklingDates.hhmm(_checkedInHere!)}',
                      text: _autoAssignedTo == null
                          ? 'The vehicle is on site — pick who takes it.'
                          : 'Auto-assigned to $_autoAssignedTo. Pick someone '
                                'else below to reassign, or cancel to keep it.',
                    ),
                    const SizedBox(height: 18),
                  ],
                  for (final m in sorted) ...[
                    _StaffRadioCard(
                      member: m,
                      selected: _selected?.id == m.id,
                      isCurrent: m.id == task.assigneeId,
                      onSelected: () => setState(() => _selected = m),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (sorted.isEmpty)
                    const InfoBanner(
                      tone: InfoTone.warning,
                      text: 'No staff are rostered at this outlet.',
                    ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _reason,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Reason (optional, recorded in the audit log)',
                      prefixIcon: Icon(Symbols.history_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const AuditNote(
                    text:
                        'Assignment is audited — actor, time and reason are recorded.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: 'Cancel',
                      variant: PillButtonVariant.outlined,
                      expand: true,
                      minHeight: 56,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 3,
                    child: PillButton(
                      key: const ValueKey('assign-submit'),
                      label: _selected == null || !_checkedIn
                          ? 'Assign'
                          : 'Assign to ${_selected!.firstName}',
                      expand: true,
                      minHeight: 56,
                      onPressed: _selected == null || !_checkedIn
                          ? null
                          : () => Navigator.of(context).pop(
                              AssignChoice(
                                member: _selected!,
                                reason: _reason.text.trim().isEmpty
                                    ? null
                                    : _reason.text.trim(),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffRadioCard extends StatelessWidget {
  const _StaffRadioCard({
    required this.member,
    required this.selected,
    required this.isCurrent,
    required this.onSelected,
  });

  final StaffMember member;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final StatusChip availability;
    if (m.availability == AvailabilityStatus.off) {
      availability = const StatusChip(label: 'Off shift', dense: true);
    } else if (m.availability == AvailabilityStatus.onBreak) {
      availability = const StatusChip(
        label: 'On break',
        tone: StatusChipTone.warning,
        dense: true,
      );
    } else if (m.atCapacity) {
      availability = StatusChip(
        label: 'At capacity · ${m.activeTasks} tasks',
        tone: StatusChipTone.error,
        dense: true,
      );
    } else if (m.activeTasks == 0) {
      availability = const StatusChip(
        label: 'Available now',
        tone: StatusChipTone.success,
        dense: true,
      );
    } else {
      availability = StatusChip(
        label: '${m.activeTasks} of ${m.capacity} tasks',
        tone: StatusChipTone.gold,
        dense: true,
      );
    }

    return RadioCard(
      selected: selected,
      enabled: !m.atCapacity && !isCurrent,
      onChanged: (_) => onSelected(),
      radioPosition: RadioCardRadioPosition.trailing,
      padding: const EdgeInsets.all(14),
      leading: AvatarTile(
        initials: m.initials,
        size: 60,
        radius: 18,
        tone: AvatarTile.toneFor(m.id),
      ),
      title: Text(
        isCurrent ? '${m.fullName} · current' : m.fullName,
        style: SparklingTypography.titleLarge.copyWith(
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      footer: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          availability,
          for (final s in m.skills.take(3))
            StatusChip(
              label: s,
              tone: StatusChipTone.primary,
              outlined: true,
              dense: true,
            ),
        ],
      ),
    );
  }
}
