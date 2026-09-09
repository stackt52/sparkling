import 'package:flutter/material.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Reason sheet for "Mark blocked" (STF-023): quick-pick chips + free text.
/// Returns the reason or null when cancelled.
Future<String?> showBlockedReasonSheet(
  BuildContext context, {
  required String stepTitle,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (ctx) => _BlockedReasonSheet(stepTitle: stepTitle),
  );
}

class _BlockedReasonSheet extends StatefulWidget {
  const _BlockedReasonSheet({required this.stepTitle});
  final String stepTitle;

  @override
  State<_BlockedReasonSheet> createState() => _BlockedReasonSheetState();
}

class _BlockedReasonSheetState extends State<_BlockedReasonSheet> {
  static const _quick = [
    'Out of stock — substitute needed',
    'Waiting for parts',
    'Equipment fault',
    'Customer query',
    'Vehicle damage found',
  ];

  final _controller = TextEditingController();
  String? _picked;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _reason =>
      _controller.text.trim().isNotEmpty ? _controller.text.trim() : _picked ?? '';

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DragHandle(),
              Text(
                'Mark blocked',
                style: SparklingTypography.headlineMedium.copyWith(
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.stepTitle} · the supervisor is notified and the task moves to Blocked.',
                style: SparklingTypography.bodyMedium.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in _quick)
                    ChoiceChip(
                      label: Text(q),
                      selected: _picked == q,
                      onSelected: (_) => setState(() => _picked = q),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Add detail (optional)…',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              const AuditNote(
                text: 'Blocked reasons are audited — actor, time and reason are recorded.',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: 'Cancel',
                      variant: PillButtonVariant.outlined,
                      expand: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PillButton(
                      label: 'Mark blocked',
                      variant: PillButtonVariant.outlinedError,
                      expand: true,
                      onPressed: _reason.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(_reason),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
