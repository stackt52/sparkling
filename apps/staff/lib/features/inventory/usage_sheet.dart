import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Result of the usage sheet.
class UsageEntry {
  const UsageEntry({required this.quantity, this.note});
  final double quantity;
  final String? note;
}

/// "Log usage" sheet (STF-042): quantity stepper with ≥48px targets + note.
Future<UsageEntry?> showUsageSheet(
  BuildContext context, {
  required InventoryItem item,
}) {
  return showModalBottomSheet<UsageEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    useRootNavigator: true,
    builder: (ctx) => _UsageSheet(item: item),
  );
}

class _UsageSheet extends StatefulWidget {
  const _UsageSheet({required this.item});
  final InventoryItem item;

  @override
  State<_UsageSheet> createState() => _UsageSheetState();
}

class _UsageSheetState extends State<_UsageSheet> {
  double _qty = 1;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _qtyLabel =>
      _qty % 1 == 0 ? _qty.toInt().toString() : _qty.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final item = widget.item;
    final max = item.onHand;
    final insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DragHandle(),
              Text(
                'Log usage',
                style: SparklingTypography.headlineMedium.copyWith(
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${item.name} · ${item.levelLabel}',
                style: SparklingTypography.bodyMedium.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconTileButton(
                    icon: Symbols.remove_rounded,
                    size: 56,
                    tooltip: 'Less',
                    onPressed: _qty > 1
                        ? () => setState(() => _qty -= 1)
                        : null,
                  ),
                  SizedBox(
                    width: 120,
                    child: Column(
                      children: [
                        Text(
                          _qtyLabel,
                          textAlign: TextAlign.center,
                          style: SparklingTypography.mono(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          '${item.unit}${_qty == 1 ? '' : 's'}',
                          style: SparklingTypography.labelLarge.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconTileButton(
                    icon: Symbols.add_rounded,
                    size: 56,
                    tooltip: 'More',
                    onPressed: _qty < max
                        ? () => setState(() => _qty += 1)
                        : null,
                  ),
                ],
              ),
              if (max <= 0) ...[
                const SizedBox(height: 12),
                const InfoBanner(
                  tone: InfoTone.error,
                  text: 'Nothing on hand — request a reorder instead.',
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Note or work order (optional)',
                ),
              ),
              const SizedBox(height: 16),
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
                    flex: 2,
                    child: PillButton(
                      label: 'Log $_qtyLabel ${item.unit}',
                      expand: true,
                      onPressed: max <= 0
                          ? null
                          : () => Navigator.of(context).pop(
                              UsageEntry(
                                quantity: _qty,
                                note: _note.text.trim().isEmpty
                                    ? null
                                    : _note.text.trim(),
                              ),
                            ),
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
