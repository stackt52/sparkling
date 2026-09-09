import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Shared 44px circular step indicator.
class StepIndicator extends StatelessWidget {
  const StepIndicator.done({super.key})
    : state = IndicatorState.done,
      locked = false;
  const StepIndicator.current({super.key})
    : state = IndicatorState.current,
      locked = false;
  const StepIndicator.upcoming({super.key, this.locked = false})
    : state = IndicatorState.upcoming;

  final IndicatorState state;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    return switch (state) {
      IndicatorState.done => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: x.success.withValues(alpha: context.isDark ? 0.55 : 1),
        ),
        child: Icon(
          Symbols.check_rounded,
          color: context.isDark ? cs.onSurface : x.onSuccess,
          size: 22,
          weight: 700,
        ),
      ),
      IndicatorState.current => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: cs.primary, width: 3),
        ),
      ),
      IndicatorState.upcoming => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: cs.outline.withValues(alpha: locked ? 0.6 : 1),
            width: 2,
          ),
        ),
      ),
    };
  }
}

enum IndicatorState { done, current, upcoming }

/// Completed step (STF-024): green check, struck-through title, 65% opacity,
/// "09:20 · Pieter v." timestamp + actor. Pending-sync results show a
/// "Queued" chip (STF-034).
class DoneStepTile extends StatelessWidget {
  const DoneStepTile({super.key, required this.step, required this.result});
  final ChecklistStep step;
  final StepResult result;

  static String shortName(String? name) {
    if (name == null || name.trim().isEmpty) return 'staff';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last[0]}.';
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final at = result.completedAt;
    final meta = [
      if (at != null) SparklingDates.hhmm(at),
      shortName(result.actorName),
    ].join(' · ');
    return ListTileCard(
      opacity: 0.65,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      leading: const StepIndicator.done(),
      title: Text(
        step.title,
        style: SparklingTypography.titleLarge.copyWith(
          fontSize: 18,
          color: cs.onSurface,
          decoration: TextDecoration.lineThrough,
          decorationColor: cs.onSurface,
        ),
      ),
      subtitle: Text(meta),
      trailing: result.pendingSync
          ? const StatusChip(
              label: 'Queued',
              tone: StatusChipTone.gold,
              icon: Symbols.cloud_sync_rounded,
              dense: true,
            )
          : null,
    );
  }
}

/// Collapsed upcoming step with a type hint; numeric steps preview the mono
/// input, the supervisor step shows a lock while locked (STF-033).
class UpcomingStepTile extends StatelessWidget {
  const UpcomingStepTile({
    super.key,
    required this.step,
    this.locked = false,
    this.onTap,
  });
  final ChecklistStep step;
  final bool locked;
  final VoidCallback? onTap;

  static String describe(ChecklistStep step) {
    final base = switch (step.type) {
      StepType.confirm => 'Confirmation',
      StepType.ack => 'Acknowledgement',
      StepType.text => 'Note',
      StepType.numeric => 'Numeric input',
      StepType.select => 'Choose one',
      StepType.photo => 'Photo proof',
      StepType.supervisorVerify => 'Supervisor verification',
    };
    if (step.type == StepType.supervisorVerify) {
      return step.hint ?? 'Locked until all required steps pass';
    }
    return step.hint == null ? base : '$base · ${step.hint}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final muted = cs.onSurfaceVariant;
    Widget? trailing;
    if (step.isSupervisorVerify && locked) {
      trailing = Icon(Symbols.lock_rounded, color: muted, fill: 1, size: 22);
    } else if (step.type == StepType.numeric) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '__ ${step.unit ?? ''}'.trim(),
          style: SparklingTypography.mono(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      );
    }
    return ListTileCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      leading: StepIndicator.upcoming(locked: locked),
      title: Text(
        step.title,
        style: SparklingTypography.titleLarge.copyWith(
          fontSize: 18,
          color: locked ? muted : cs.onSurface,
        ),
      ),
      subtitle: Text(describe(step)),
      trailing: trailing,
    );
  }
}

/// Value collected for a step before submission.
class StepInputValue {
  const StepInputValue({this.value, this.attachmentId, this.photoPaths = const []});
  final dynamic value;
  final String? attachmentId;
  final List<String> photoPaths;
}

/// Expanded current step (2b): primaryContainer card with 2px primary border,
/// REQUIRED badge, per-type input, "Complete step" / "Mark blocked".
class CurrentStepCard extends StatefulWidget {
  const CurrentStepCard({
    super.key,
    required this.step,
    required this.onComplete,
    required this.onBlock,
    this.blockedNote,
    this.busy = false,
    this.initialDraft,
    this.onDraftChanged,
  });

  final ChecklistStep step;
  final Future<void> Function(StepInputValue value) onComplete;
  final VoidCallback onBlock;

  /// Note of an earlier "blocked" result on this step, if any.
  final String? blockedNote;
  final bool busy;
  final String? initialDraft;
  final ValueChanged<String>? onDraftChanged;

  @override
  State<CurrentStepCard> createState() => _CurrentStepCardState();
}

class _CurrentStepCardState extends State<CurrentStepCard> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialDraft ?? '',
  );
  String? _selected;
  bool _acked = false;
  final List<String> _photos = [];
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  dynamic get _value => switch (widget.step.type) {
    StepType.numeric => double.tryParse(_text.text.replaceAll(',', '.')),
    StepType.text => _text.text.trim(),
    StepType.select => _selected,
    StepType.ack => _acked,
    StepType.photo => {'photos': _photos.length},
    StepType.confirm => true,
    StepType.supervisorVerify => true,
  };

  String? get _attachmentId =>
      _photos.isEmpty ? null : 'local:${_photos.last.split('/').last}';

  Future<void> _complete() async {
    final step = widget.step;
    if (step.type == StepType.ack && !_acked) {
      setState(() => _error = 'Tick to acknowledge before completing');
      return;
    }
    final err = step.validate(value: _value, attachmentId: _attachmentId);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _error = null);
    await widget.onComplete(
      StepInputValue(
        value: _value,
        attachmentId: _attachmentId,
        photoPaths: List.unmodifiable(_photos),
      ),
    );
  }

  Future<void> _takePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _photos.add(picked.path);
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Camera unavailable — try again');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final step = widget.step;
    final subtitle = [
      if (step.required) 'Required',
      if (step.needsPhoto) 'photo proof' else if (step.hint != null) step.hint!,
    ].join(' · ');
    final fg = cs.onPrimaryContainer;

    final buttons = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PillButton(
          label: 'Complete step',
          expand: true,
          minHeight: 56,
          loading: widget.busy,
          onPressed: _complete,
        ),
        const SizedBox(height: 10),
        PillButton(
          label: 'Mark blocked',
          variant: PillButtonVariant.outlinedError,
          expand: true,
          minHeight: 52,
          onPressed: widget.busy ? null : widget.onBlock,
        ),
      ],
    );

    return Semantics(
      container: true,
      label: 'Current step: ${step.title}',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(SparklingShapes.card),
          border: Border.all(color: cs.primary, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StepIndicator.current(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: SparklingTypography.titleLarge.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: SparklingTypography.bodyLarge.copyWith(
                            fontSize: 14,
                            color: fg.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                ),
                if (step.required) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: ShapeDecoration(
                      color: cs.primary,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'REQUIRED',
                      style: SparklingTypography.labelSmall.copyWith(
                        fontSize: 11,
                        letterSpacing: 0.6,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (widget.blockedNote != null) ...[
              const SizedBox(height: 12),
              InfoBanner(
                tone: InfoTone.error,
                icon: Symbols.block_rounded,
                title: 'Previously blocked',
                text: widget.blockedNote!,
              ),
            ],
            const SizedBox(height: 14),
            if (step.needsPhoto)
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 360;
                  final photos = _PhotoRow(
                    photos: _photos,
                    onAdd: _takePhoto,
                    onRemove: (p) => setState(() => _photos.remove(p)),
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [photos, const SizedBox(height: 14), buttons],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      photos,
                      const SizedBox(width: 14),
                      Expanded(child: buttons),
                    ],
                  );
                },
              )
            else ...[
              _input(context),
              if (step.type != StepType.confirm) const SizedBox(height: 14),
              buttons,
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Symbols.error_rounded, size: 18, color: cs.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: SparklingTypography.bodyMedium.copyWith(
                        color: cs.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _input(BuildContext context) {
    final cs = context.colors;
    final step = widget.step;
    switch (step.type) {
      case StepType.numeric:
        final range = [
          if (step.min != null) _fmt(step.min!),
          if (step.max != null) _fmt(step.max!),
        ].join('–');
        return TextField(
          controller: _text,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: SparklingTypography.mono(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
          onChanged: (v) {
            widget.onDraftChanged?.call(v);
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            hintText: '__',
            suffixText: step.unit,
            suffixStyle: SparklingTypography.mono(
              fontSize: 16,
              color: cs.onSurfaceVariant,
            ),
            helperText: range.isEmpty
                ? step.hint
                : 'Target $range ${step.unit ?? ''}'.trim(),
          ),
        );
      case StepType.text:
        return TextField(
          controller: _text,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) {
            widget.onDraftChanged?.call(v);
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(hintText: step.hint ?? 'Add a note…'),
        );
      case StepType.select:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in step.options)
              ChoiceChip(
                label: Text(o),
                selected: _selected == o,
                onSelected: (_) => setState(() {
                  _selected = o;
                  _error = null;
                }),
              ),
          ],
        );
      case StepType.ack:
        return CheckboxListTile(
          value: _acked,
          onChanged: (v) => setState(() {
            _acked = v ?? false;
            _error = null;
          }),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          tileColor: Colors.transparent,
          title: Text(
            step.hint ?? 'I have read and acknowledge this step',
            style: SparklingTypography.bodyLarge.copyWith(
              color: cs.onPrimaryContainer,
            ),
          ),
        );
      case StepType.confirm:
      case StepType.photo:
      case StepType.supervisorVerify:
        return const SizedBox.shrink();
    }
  }

  static String _fmt(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });
  final List<String> photos;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    if (photos.isEmpty) {
      tiles.add(const PhotoPlaceholder(size: 80, caption: 'exterior\nphoto'));
    } else {
      for (final p in photos) {
        tiles.add(
          PhotoPlaceholder(
            size: 80,
            onRemove: () => onRemove(p),
            child: Image.file(File(p), fit: BoxFit.cover),
          ),
        );
      }
    }
    tiles.add(
      PhotoPlaceholder.add(
        size: 80,
        icon: Symbols.photo_camera_rounded,
        onTap: onAdd,
      ),
    );
    return Wrap(spacing: 10, runSpacing: 10, children: tiles);
  }
}

/// Supervisor verification card (STF-033): locked until required steps pass;
/// only supervisors/managers can sign off. Technicians see "Complete task"
/// once their required steps are done.
class SupervisorStepCard extends StatelessWidget {
  const SupervisorStepCard({
    super.key,
    required this.step,
    required this.unlocked,
    required this.canSupervise,
    required this.taskStatus,
    required this.onVerify,
    required this.onCompleteTask,
    this.busy = false,
  });

  final ChecklistStep step;
  final bool unlocked;
  final bool canSupervise;
  final WorkStatus taskStatus;
  final VoidCallback onVerify;
  final VoidCallback onCompleteTask;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    if (!unlocked) {
      return UpcomingStepTile(step: step, locked: true);
    }
    final canVerify = canSupervise && taskStatus != WorkStatus.verified;
    final subtitle = canSupervise
        ? 'All required steps passed · sign off to release the vehicle'
        : taskStatus == WorkStatus.completed
        ? 'Awaiting supervisor sign-off'
        : 'Complete the task, then a supervisor signs off';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(SparklingShapes.card),
        border: Border.all(color: cs.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const StepIndicator.current(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: SparklingTypography.titleLarge.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: SparklingTypography.bodyLarge.copyWith(
                        fontSize: 14,
                        color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (canVerify)
            PillButton(
              label: 'Verify & sign off',
              icon: Symbols.verified_rounded,
              expand: true,
              minHeight: 56,
              loading: busy,
              onPressed: onVerify,
            )
          else if (!canSupervise && taskStatus == WorkStatus.inProgress)
            PillButton(
              label: 'Complete task',
              icon: Symbols.task_alt_rounded,
              expand: true,
              minHeight: 56,
              loading: busy,
              onPressed: onCompleteTask,
            )
          else
            const AuditNote(
              icon: Symbols.lock_rounded,
              text: 'Only a supervisor or manager can complete this step.',
            ),
        ],
      ),
    );
  }
}
