import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../widgets/avatar_tile.dart';

/// Outcome of the assign sheet.
class AssignChoice {
  const AssignChoice({required this.member, this.reason});
  final StaffMember member;
  final String? reason;
}

/// Modal bottom sheet (2d, r32 + drag handle) listing outlet staff as radio
/// cards with availability + skill chips; at-capacity rows render at 55%.
/// Returns the chosen member (and optional audited reason) or null.
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

  @override
  void initState() {
    super.initState();
    final candidates = widget.team.where(
      (m) => !m.atCapacity && m.id != widget.task.assigneeId,
    );
    _selected = candidates.isEmpty ? null : candidates.first;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final task = widget.task;
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
                    'Reassign ${task.ref}',
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
                      label: _selected == null
                          ? 'Assign'
                          : 'Assign to ${_selected!.firstName}',
                      expand: true,
                      minHeight: 56,
                      onPressed: _selected == null
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
