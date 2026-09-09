import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import '../booking/booking_widgets.dart';

/// Repair quote request (1j, CUS-030..033).
class QuoteRequestScreen extends StatefulWidget {
  const QuoteRequestScreen({super.key});

  static const int maxPhotos = 6;

  @override
  State<QuoteRequestScreen> createState() => _QuoteRequestScreenState();
}

class _QuoteRequestScreenState extends State<QuoteRequestScreen> {
  static const _draftKey = 'quote_draft';

  final _description = TextEditingController();
  final _picker = ImagePicker();
  final Set<String> _categories = {};
  final List<XFile> _photos = [];
  List<Vehicle>? _vehicles;
  List<Outlet>? _outlets;
  Vehicle? _vehicle;
  Outlet? _outlet;
  Object? _error;
  bool _busy = false;
  late String _clientOpId;

  @override
  void initState() {
    super.initState();
    _clientOpId = SparklingApi.newOpId();
    _description.addListener(_persist);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vehicles == null && _error == null) _load();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final repos = context.repos;
    try {
      final results = await Future.wait([
        repos.customer.vehicles(),
        repos.catalogue.outlets(),
      ]);
      if (!mounted) return;
      final vehicles = results[0] as List<Vehicle>;
      final outlets = results[1] as List<Outlet>;
      final draft = repos.drafts.load(_draftKey);
      setState(() {
        _vehicles = vehicles;
        _outlets = outlets;
        _vehicle =
            vehicles.where((v) => v.id == draft?['vehicle_id']).firstOrNull ??
            vehicles.firstOrNull;
        _outlet =
            outlets.where((o) => o.id == draft?['outlet_id']).firstOrNull ??
            context.bookingFlow.outlet ??
            outlets.firstOrNull;
        if (draft != null) {
          _description.text = draft['description']?.toString() ?? '';
          _categories.addAll(
            (draft['categories'] as List?)?.map((e) => e.toString()) ??
                const <String>[],
          );
          _clientOpId = draft['client_op_id']?.toString() ?? _clientOpId;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _persist() {
    context.repos.drafts.save(_draftKey, {
      'vehicle_id': _vehicle?.id,
      'outlet_id': _outlet?.id,
      'categories': _categories.toList(),
      'description': _description.text,
      'client_op_id': _clientOpId,
    });
  }

  Future<void> _pickVehicle() async {
    final v = await showVehiclePicker(
      context,
      vehicles: _vehicles ?? const [],
      selectedId: _vehicle?.id,
    );
    if (v != null) {
      setState(() => _vehicle = v);
      _persist();
    }
  }

  Future<void> _pickOutlet() async {
    final o = await showOutletPicker(
      context,
      outlets: _outlets ?? const [],
      selectedId: _outlet?.id,
    );
    if (o != null) {
      setState(() => _outlet = o);
      _persist();
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= QuoteRequestScreen.maxPhotos) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.photo_camera_rounded),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Symbols.photo_library_rounded),
              title: const Text('Choose from library'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (file != null && mounted) setState(() => _photos.add(file));
    } catch (e) {
      if (mounted) {
        showSnack(
          context,
          'Could not open the ${source.name}. Check permissions.',
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_vehicle == null || _outlet == null) {
      showSnack(context, 'Choose a vehicle and outlet first.');
      return;
    }
    if (_categories.isEmpty) {
      showSnack(context, 'Tell us what needs attention.');
      return;
    }
    if (_description.text.trim().length < 10) {
      showSnack(context, 'Describe the damage in a sentence or two.');
      return;
    }
    setState(() => _busy = true);
    final repos = context.repos;
    try {
      final q = await repos.customer.createQuotation(
        QuotationInput(
          vehicleId: _vehicle!.id,
          outletId: _outlet!.id,
          category: (_categories.toList()..sort()).join(', '),
          description: _description.text.trim(),
          clientOpId: _clientOpId,
        ),
      );
      await repos.drafts.delete(_draftKey);
      if (!mounted) return;
      AppHaptics.success(context);
      showSnack(
        context,
        _photos.isEmpty
            ? 'Quote ${q.ref} requested.'
            : 'Quote ${q.ref} requested. Photos are attached when upload is enabled.',
      );
      context.pushReplacement(Routes.quote(q.id));
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ScreenHeader(
              title: 'Repair quote',
              subtitle: 'Auto body · an estimator replies within 24 h',
              trailing: IconTileButton(
                icon: Symbols.request_quote_rounded,
                tooltip: 'My quotes',
                onPressed: () => context.push(Routes.quotes),
              ),
            ),
            Expanded(
              child: _error != null
                  ? ErrorView(error: _error, onRetry: _load)
                  : _vehicles == null
                  ? const LoadingView()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      children: [
                        ListTileCard(
                          onTap: _pickVehicle,
                          leading: Icon(
                            Symbols.directions_car_rounded,
                            color: cs.primary,
                            fill: 1,
                            size: 26,
                          ),
                          title: Text(
                            _vehicle == null
                                ? 'Choose a vehicle'
                                : '${_vehicle!.shortName} · ${_vehicle!.registrationNo}',
                          ),
                          subtitle: InkWell(
                            onTap: _pickOutlet,
                            child: Text(_outlet?.name ?? 'Choose an outlet'),
                          ),
                          trailing: Icon(
                            Symbols.unfold_more_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 22),
                        const SectionHeader(title: 'What needs attention?'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final c in QuoteCategories.all)
                              FilterChip(
                                label: Text(c),
                                selected: _categories.contains(c),
                                labelStyle: SparklingTypography.titleMedium
                                    .copyWith(
                                      color: _categories.contains(c)
                                          ? (context.isDark
                                                ? cs.onPrimaryContainer
                                                : Colors.white)
                                          : cs.onSurfaceVariant,
                                    ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                onSelected: (v) {
                                  AppHaptics.selection(context);
                                  setState(() {
                                    v
                                        ? _categories.add(c)
                                        : _categories.remove(c);
                                  });
                                  _persist();
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const SectionHeader(title: 'Describe the damage'),
                        TextField(
                          controller: _description,
                          minLines: 4,
                          maxLines: 8,
                          maxLength: 600,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Deep scratch and small dent on the left rear door, about 20 cm.',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 22),
                        SectionHeader(
                          title: 'Damage photos',
                          trailing: Text(
                            '${_photos.length} of ${QuoteRequestScreen.maxPhotos}',
                            style: SparklingTypography.bodyLarge.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          child: Row(
                            children: [
                              for (var i = 0; i < _photos.length; i++) ...[
                                PhotoPlaceholder(
                                  onRemove: () =>
                                      setState(() => _photos.removeAt(i)),
                                  child: Image.file(
                                    File(_photos[i].path),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Center(
                                      child: Text(
                                        _photos[i].name,
                                        textAlign: TextAlign.center,
                                        style: SparklingTypography.mono(
                                          fontSize: 10,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              if (_photos.length < QuoteRequestScreen.maxPhotos)
                                PhotoPlaceholder.add(onTap: _addPhoto),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        const InfoBanner(
                          tone: InfoTone.info,
                          icon: Symbols.schedule_rounded,
                          text: "You'll get the quote in-app and on WhatsApp. Accept or decline — nothing is booked until you approve.",
                        ),
                      ],
                    ),
            ),
            if (_vehicles != null)
              Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: BottomActionBar(
                  child: PillButton(
                    label: 'Request quote',
                    expand: true,
                    minHeight: 56,
                    loading: _busy,
                    onPressed: _submit,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
