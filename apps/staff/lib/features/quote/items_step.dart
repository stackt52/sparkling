import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/scope.dart';
import '../../widgets/feedback.dart';
import '../walk_in/walk_in_widgets.dart';
import 'quote_widgets.dart';
import 'raise_quote_controller.dart';

/// Picks a damage photo from [source]; tests override [ItemsStep.photoPicker]
/// to return fake bytes without the platform camera.
typedef QuotePhotoPicker =
    Future<QuotePhotoDraft?> Function(BuildContext context, ImageSource source);

Future<QuotePhotoDraft?> _defaultPhotoPicker(
  BuildContext context,
  ImageSource source,
) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2000,
    imageQuality: 85,
  );
  if (file == null) return null;
  return QuotePhotoDraft(
    id: SparklingApi.newOpId(),
    path: file.path,
    name: file.name,
    mimeType: file.mimeType,
  );
}

/// Step 3 of 4 — what needs attention: itemised attention areas (category,
/// title, description, optional auto-body service, amount), overall
/// description, damage photos (camera / gallery, captions, max 10), note
/// for the customer and the valid-until date.
class ItemsStep extends StatefulWidget {
  const ItemsStep({
    super.key,
    required this.flow,
    required this.onNext,
    required this.onBack,
  });

  final RaiseQuoteController flow;
  final VoidCallback onNext;
  final VoidCallback onBack;

  /// Overridable for widget tests (no platform camera).
  static QuotePhotoPicker photoPicker = _defaultPhotoPicker;

  @override
  State<ItemsStep> createState() => _ItemsStepState();
}

class _ItemsStepState extends State<ItemsStep> {
  late final _description = TextEditingController(
    text: widget.flow.description,
  );
  late final _note = TextEditingController(text: widget.flow.itemsNote);
  List<OutletService>? _services;
  bool _servicesRequested = false;
  bool _picking = false;

  RaiseQuoteController get _flow => widget.flow;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_servicesRequested) {
      _servicesRequested = true;
      _loadServices();
    }
  }

  Future<void> _loadServices() async {
    try {
      final catalogue = await context.repositories.catalogue.outletServices(
        context.session.outletId,
      );
      if (!mounted) return;
      setState(() {
        _services = catalogue
            .offersIn(ServiceGroups.autoBodyRepair)
            .where((s) => s.isAvailable)
            .toList();
      });
    } catch (_) {
      // The service picker is optional — items work without it.
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addOrEditItem([QuoteItemDraft? existing]) async {
    final result = await showModalBottomSheet<QuoteItemDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: QuoteItemSheet(
          existing: existing,
          services: _services ?? const [],
        ),
      ),
    );
    if (result == null || !mounted) return;
    StaffHaptics.tap(context);
    if (existing == null) {
      _flow.addItem(result);
    } else {
      _flow.updateItem(result);
    }
  }

  Future<void> _addPhoto() async {
    if (!_flow.canAddPhoto || _picking) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.photo_camera_rounded),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Symbols.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _picking = true);
    try {
      final photo = await ItemsStep.photoPicker(context, source);
      if (photo == null || !mounted) return;
      _flow.addPhoto(photo);
      StaffHaptics.success(context);
      await _editCaption(photo);
    } catch (_) {
      if (mounted) {
        StaffSnack.show(
          context,
          'Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}. Check permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _editCaption(QuotePhotoDraft photo) async {
    final caption = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _CaptionSheet(photo: photo),
      ),
    );
    if (caption == null || !mounted) return;
    _flow.setPhotoCaption(photo.id, caption);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _flow.validUntil.isBefore(now) ? now : _flow.validUntil,
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
      helpText: 'Quote valid until',
    );
    if (picked != null && mounted) _flow.setValidUntil(picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final flow = _flow;
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        final customer = flow.customer;
        final vehicle = flow.vehicle;
        if (customer == null || vehicle == null) {
          return Column(
            children: [
              BookingStepHeader(
                title: 'Raise quote',
                step: 3,
                subtitle: 'What needs attention',
                onBack: widget.onBack,
              ),
              Expanded(
                child: Center(
                  child: PillButton(
                    label: 'Choose a customer and vehicle first',
                    variant: PillButtonVariant.tonal,
                    onPressed: widget.onBack,
                  ),
                ),
              ),
            ],
          );
        }
        final days = flow.validityDays;
        return Column(
          children: [
            BookingStepHeader(
              title: 'Raise quote',
              step: 3,
              subtitle: 'What needs attention',
              onBack: widget.onBack,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                children: [
                  _VehicleSummaryCard(
                    customer: customer,
                    vehicle: vehicle,
                    onChange: widget.onBack,
                  ),
                  const SizedBox(height: 18),
                  SectionHeader(
                    title: 'Attention items',
                    trailing: flow.items.isEmpty
                        ? null
                        : Text(
                            Money.formatZar(flow.totalCents),
                            style: SparklingTypography.titleMedium.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  if (flow.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'One item per area — dent, scratch, bumper… Each '
                        'item carries its own amount; the quote total is '
                        'the sum.',
                        style: SparklingTypography.bodyMedium.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final item in flow.items) ...[
                    _ItemCard(
                      item: item,
                      onEdit: () => _addOrEditItem(item),
                      onRemove: () {
                        StaffHaptics.tap(context);
                        flow.removeItem(item.id);
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  PillButton(
                    key: const ValueKey('quote-add-item'),
                    label: flow.items.isEmpty ? 'Add item' : 'Add another item',
                    icon: Symbols.add_rounded,
                    variant: PillButtonVariant.outlined,
                    expand: true,
                    minHeight: 52,
                    onPressed: () => _addOrEditItem(),
                  ),
                  const SizedBox(height: 22),
                  const SectionHeader(title: 'Describe the damage'),
                  TextField(
                    key: const ValueKey('quote-description'),
                    controller: _description,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 600,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: flow.setDescription,
                    decoration: const InputDecoration(
                      hintText:
                          'e.g. Deep scratch and small dent on the left rear door, about 20 cm.',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 22),
                  SectionHeader(
                    title: 'Damage photos',
                    trailing: Text(
                      '${flow.photos.length} of ${RaiseQuoteController.maxPhotos}',
                      style: SparklingTypography.bodyLarge.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final p in flow.photos) ...[
                          DraftPhotoTile(
                            key: ValueKey('quote-photo-${p.id}'),
                            photo: p,
                            onTap: () => _editCaption(p),
                            onRemove: () => flow.removePhoto(p.id),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (flow.canAddPhoto)
                          PhotoPlaceholder.add(
                            key: const ValueKey('quote-add-photo'),
                            onTap: _picking ? null : _addPhoto,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap a photo to caption it. Photos go to the customer '
                    'with the quote and into the PDF.',
                    style: SparklingTypography.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const SectionHeader(title: 'Note for the customer'),
                  TextField(
                    controller: _note,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 240,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: flow.setItemsNote,
                    decoration: const InputDecoration(
                      hintText: 'Optional — e.g. parts on hand, 2 working days',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 22),
                  SectionHeader(
                    title: 'Valid until',
                    trailing: Text(
                      SparklingDates.dayMonth(flow.validUntil),
                      style: SparklingTypography.titleMedium.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  _ValidityChips(
                    selectedDays: days,
                    onDays: (d) {
                      StaffHaptics.tap(context);
                      flow.setValidForDays(d);
                    },
                    onPick: _pickDate,
                  ),
                ],
              ),
            ),
            BottomActionBar(
              leadingLabel: 'Total',
              leadingValue: flow.items.isEmpty
                  ? '—'
                  : compactZar(flow.totalCents),
              child: PillButton(
                label: 'Review & send',
                trailingIcon: Symbols.arrow_forward_rounded,
                expand: true,
                minHeight: 56,
                onPressed: flow.canReview ? widget.onNext : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VehicleSummaryCard extends StatelessWidget {
  const _VehicleSummaryCard({
    required this.customer,
    required this.vehicle,
    required this.onChange,
  });
  final CustomerSummary customer;
  final CustomerVehicleSummary vehicle;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return ListTileCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      borderColor: cs.primary.withValues(alpha: 0.45),
      leading: Icon(Symbols.directions_car_rounded, color: cs.primary, fill: 1),
      title: Text(
        vehicle.registrationNo,
        style: SparklingTypography.mono(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: cs.onSurface,
        ),
      ),
      subtitle: Text(
        [
          if (vehicle.displayName.isNotEmpty) vehicle.displayName,
          customer.fullName,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(
        onPressed: onChange,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: const Text('Change'),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.onEdit,
    required this.onRemove,
  });
  final QuoteItemDraft item;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final service = item.serviceName;
    final meta = [
      if (service != null && service.toLowerCase() != item.label.toLowerCase())
        service,
      if (item.description != null && item.description!.trim().isNotEmpty)
        item.description!,
    ].join(' · ');
    return ListTileCard(
      key: ValueKey('quote-item-${item.id}'),
      onTap: onEdit,
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CategoryChip(category: item.category),
                    const SizedBox(width: 10),
                    Text(
                      Money.formatZar(item.amountCents),
                      style: SparklingTypography.titleMedium.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.label,
                  style: SparklingTypography.titleLarge.copyWith(
                    fontSize: 16.5,
                    color: cs.onSurface,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SparklingTypography.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit item',
            icon: const Icon(Symbols.edit_rounded, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Remove item',
            icon: Icon(Symbols.delete_rounded, size: 20, color: cs.error),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _ValidityChips extends StatelessWidget {
  const _ValidityChips({
    required this.selectedDays,
    required this.onDays,
    required this.onPick,
  });
  final int selectedDays;
  final ValueChanged<int> onDays;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    const quick = [7, 14, 30];
    final custom = !quick.contains(selectedDays);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in quick)
          ChoiceChip(
            label: Text('$d days'),
            selected: selectedDays == d,
            onSelected: (_) => onDays(d),
          ),
        ChoiceChip(
          label: Text(custom ? 'Custom · $selectedDays d' : 'Pick date'),
          avatar: const Icon(Symbols.event_rounded, size: 18),
          selected: custom,
          onSelected: (_) => onPick(),
        ),
      ],
    );
  }
}

/// Add / edit an attention item: category chips, title, description,
/// optional auto-body service, amount in rand. Pops with the draft item.
class QuoteItemSheet extends StatefulWidget {
  const QuoteItemSheet({super.key, this.existing, this.services = const []});

  final QuoteItemDraft? existing;
  final List<OutletService> services;

  @override
  State<QuoteItemSheet> createState() => _QuoteItemSheetState();
}

class _QuoteItemSheetState extends State<QuoteItemSheet> {
  final _form = GlobalKey<FormState>();
  late String _category = widget.existing?.category ?? 'Dent';
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : (widget.existing!.amountCents / 100).toStringAsFixed(
            widget.existing!.amountCents % 100 == 0 ? 0 : 2,
          ),
  );
  late String? _serviceId = widget.existing?.serviceId;

  OutletService? get _service =>
      widget.services.where((s) => s.id == _serviceId).firstOrNull;

  @override
  void dispose() {
    _label.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _pickCategory(String c) {
    setState(() {
      _category = c;
      // Suggest the matching service and a title when they are still empty.
      final code = QuoteCategories.serviceCodeFor(c);
      if (_serviceId == null && code != null) {
        _serviceId = widget.services
            .where((s) => s.code == code)
            .firstOrNull
            ?.id;
        if (_amount.text.trim().isEmpty) _prefillAmount();
      }
      if (_label.text.trim().isEmpty) {
        _label.text = switch (c) {
          'Dent' => 'Dent repair',
          'Scratch' => 'Scratch repair',
          'Bumper' => 'Bumper repair',
          'Panel' => 'Panel repair',
          'Paint' => 'Respray',
          'Glass' => 'Glass replacement',
          _ => '',
        };
      }
    });
  }

  Future<void> _pickService() async {
    final chosen = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            const SectionHeader(title: 'Auto-body service'),
            RadioCard(
              selected: _serviceId == null,
              onChanged: (_) => Navigator.of(ctx).pop(''),
              leading: Icon(Symbols.block_rounded, color: ctx.colors.primary),
              title: const Text('No service link'),
              subtitle: const Text('Free-form item'),
            ),
            const SizedBox(height: 10),
            for (final s in widget.services) ...[
              RadioCard(
                key: ValueKey('quote-service-${s.code}'),
                selected: _serviceId == s.id,
                onChanged: (_) => Navigator.of(ctx).pop(s.id),
                leading: Icon(
                  serviceIcon(s.icon),
                  color: ctx.colors.primary,
                  fill: 1,
                ),
                title: Text(s.name),
                subtitle: Text(
                  s.description ?? '${s.durationMinutes} min',
                ),
                trailing: SizedBox(
                  width: 96,
                  child: Text(
                    s.priceLabel(VehicleSize.small),
                    textAlign: TextAlign.end,
                    style: SparklingTypography.labelLarge.copyWith(
                      color: ctx.colors.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _serviceId = chosen.isEmpty ? null : chosen;
      _prefillAmount();
    });
  }

  /// Quotation items are VAT-inclusive; catalogue auto-body prices are
  /// `excl` "from" prices, so the suggested amount is price × 1.15.
  void _prefillAmount() {
    final s = _service;
    final price = s?.priceFor(VehicleSize.small);
    if (s == null || price == null) return;
    final incl = s.vatMode == VatMode.excl
        ? price + s.vatMode.vatOn(price)
        : price;
    _amount.text = (incl / 100).toStringAsFixed(incl % 100 == 0 ? 0 : 2);
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final cents = Money.parseZar(_amount.text) ?? 0;
    Navigator.of(context).pop(
      QuoteItemDraft(
        id: widget.existing?.id ?? SparklingApi.newOpId(),
        label: _label.text.trim(),
        category: _category,
        amountCents: cents,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        serviceId: _serviceId,
        serviceName: _service?.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final service = _service;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _form,
          child: ListView(
            shrinkWrap: true,
            children: [
              SectionHeader(
                title: widget.existing == null ? 'Add item' : 'Edit item',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in QuoteCategories.all)
                    ChoiceChip(
                      key: ValueKey('quote-cat-$c'),
                      label: Text(c),
                      avatar: Icon(categoryIcon(c), size: 18),
                      selected: _category == c,
                      onSelected: (_) => _pickCategory(c),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('quote-item-label'),
                controller: _label,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Driver door dent',
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 2 ? 'Give the item a title' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('quote-item-description'),
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Where, how big, what is needed',
                ),
              ),
              const SizedBox(height: 12),
              ListTileCard(
                key: const ValueKey('quote-item-service'),
                onTap: widget.services.isEmpty ? null : _pickService,
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                leading: Icon(
                  service == null
                      ? Symbols.handyman_rounded
                      : serviceIcon(service.icon),
                  color: cs.primary,
                  fill: 1,
                ),
                title: Text(service?.name ?? 'Auto-body service (optional)'),
                subtitle: Text(
                  widget.services.isEmpty
                      ? 'No auto-body services at this outlet'
                      : service == null
                      ? 'Link a catalogue service for the work order'
                      : 'Linked · ${service.priceLabel(VehicleSize.small)} · tap to change',
                ),
                trailing: Icon(
                  Symbols.unfold_more_rounded,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('quote-item-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                style: SparklingTypography.headlineSmall.copyWith(
                  fontSize: 22,
                  color: cs.onSurface,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: 'R ',
                  hintText: '0.00',
                ),
                validator: (v) {
                  final cents = Money.parseZar(v ?? '');
                  if (cents == null || cents <= 0) return 'Enter the amount';
                  return null;
                },
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 18),
              PillButton(
                key: const ValueKey('quote-item-save'),
                label: widget.existing == null ? 'Add item' : 'Save item',
                icon: Symbols.check_rounded,
                expand: true,
                minHeight: 52,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Caption for a draft photo.
class _CaptionSheet extends StatefulWidget {
  const _CaptionSheet({required this.photo});
  final QuotePhotoDraft photo;

  @override
  State<_CaptionSheet> createState() => _CaptionSheetState();
}

class _CaptionSheetState extends State<_CaptionSheet> {
  late final _caption = TextEditingController(
    text: widget.photo.caption ?? '',
  );

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photo;
    Widget preview;
    if (p.bytes != null) {
      preview = Image.memory(p.bytes!, fit: BoxFit.cover);
    } else if (p.path != null) {
      preview = Image.file(File(p.path!), fit: BoxFit.cover);
    } else {
      preview = const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Photo caption'),
            ClipRRect(
              borderRadius: BorderRadius.circular(SparklingShapes.tile),
              child: SizedBox(height: 160, child: preview),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('quote-photo-caption'),
              controller: _caption,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              decoration: const InputDecoration(
                hintText: 'e.g. Rear bumper, left corner',
                counterText: '',
              ),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
            const SizedBox(height: 14),
            PillButton(
              label: 'Save caption',
              icon: Symbols.check_rounded,
              expand: true,
              minHeight: 52,
              onPressed: () => Navigator.of(context).pop(_caption.text),
            ),
          ],
        ),
      ),
    );
  }
}
