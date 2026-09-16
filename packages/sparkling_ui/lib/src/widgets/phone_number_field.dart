import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:sparkling_core/sparkling_core.dart' show Country, Phone, countries, defaultCountryIso;

import '../theme/colors_ext.dart';
import '../tokens/shapes.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Country + national digits behind a [PhoneNumberField]; [value] is the
/// E.164 number (`+27821234567`) or `''` while empty / invalid.
class PhoneNumberController extends ChangeNotifier {
  PhoneNumberController({
    String? initialValue,
    String defaultIso = defaultCountryIso,
  }) : _country = Phone.countryByIso(defaultIso) ?? countries.first {
    if (initialValue != null && initialValue.trim().isNotEmpty) {
      _apply(initialValue);
    }
  }

  Country _country;
  String _digits = '';

  Country get country => _country;

  /// National digits without the trunk prefix (`821234567`).
  String get nationalDigits => _digits;

  /// National digits grouped for display (`82 123 4567`).
  String get formatted => Phone.formatNational(_country.iso, _digits);

  bool get isEmpty => _digits.isEmpty;

  /// E.164 or `''` when empty or not a valid mobile number.
  String get value =>
      _digits.isEmpty ? '' : (Phone.normalise('+${_country.dial}$_digits') ?? '');

  bool get isValid => value.isNotEmpty;

  set country(Country c) {
    if (c.iso == _country.iso) return;
    _country = c;
    notifyListeners();
  }

  set nationalDigits(String digits) {
    final d = digits.replaceAll(RegExp(r'[^0-9]'), '');
    if (d == _digits) return;
    _digits = d;
    notifyListeners();
  }

  /// Replaces the whole number from E.164 (`null` / `''` clears the digits
  /// and keeps the country).
  set value(String? e164) {
    final changed = _apply(e164);
    if (changed) notifyListeners();
  }

  bool _apply(String? e164) {
    if (e164 == null || e164.trim().isEmpty) {
      if (_digits.isEmpty) return false;
      _digits = '';
      return true;
    }
    final split = Phone.split(e164);
    if (split == null) {
      final d = e164.replaceAll(RegExp(r'[^0-9]'), '');
      if (d == _digits) return false;
      _digits = d;
      return true;
    }
    final (c, nsn) = split;
    if (c.iso == _country.iso && nsn == _digits) return false;
    _country = c;
    _digits = nsn;
    return true;
  }
}

/// M3 mobile-number field: a tappable country chip (flag + `+dial`) that
/// opens a searchable country sheet, and a national-number input that groups
/// digits live (`82 123 4567`). Emits E.164 (`+27821234567`) or `''` via
/// [onChanged]; pasting a full `+44 …` number switches the country.
///
/// Registers with an enclosing [Form]: `Form.validate()` reports
/// "Enter a mobile number" (when [required]) or "Enter a valid `<Country>`
/// mobile number"; the same error shows inline after the field loses focus.
class PhoneNumberField extends StatefulWidget {
  const PhoneNumberField({
    super.key,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.label = 'Mobile number',
    this.helperText,
    this.required = false,
    this.validator,
    this.defaultIso = defaultCountryIso,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction,
    this.onSubmitted,
    this.onCountryChanged,
  });

  /// Optional external controller; otherwise one is created from
  /// [initialValue] / [defaultIso].
  final PhoneNumberController? controller;

  /// E.164 to prefill (ignored when [controller] is given).
  final String? initialValue;

  /// E.164 or `''` after every edit.
  final ValueChanged<String>? onChanged;
  final String? label;
  final String? helperText;

  /// Empty is an error when `true`.
  final bool required;

  /// Extra validation on top of the built-in checks (receives E.164 or `''`).
  final FormFieldValidator<String>? validator;

  /// Country preselected while the field is empty.
  final String defaultIso;
  final bool autofocus;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<Country>? onCountryChanged;

  /// Countries picked from the sheet most recently (newest first, max 4) —
  /// shown at the top of the sheet for the rest of the session.
  static final List<Country> recentCountries = [];

  static void _remember(Country c) {
    recentCountries.removeWhere((r) => r.iso == c.iso);
    recentCountries.insert(0, c);
    if (recentCountries.length > 4) recentCountries.removeLast();
  }

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  late PhoneNumberController _controller;
  bool _ownsController = false;
  late final TextEditingController _text;
  final _focus = FocusNode();
  final _field = GlobalKey<FormFieldState<String>>();

  /// Country resolved from a pasted `+…` number, applied on the next change.
  Country? _switchTo;

  /// Once the field has been validated (blur / form submit) it re-validates
  /// on every change so the error clears as soon as the number is right.
  bool _validated = false;

  @override
  void initState() {
    super.initState();
    _attach();
    _text = TextEditingController(text: _controller.formatted);
    _focus.addListener(_onFocus);
  }

  void _attach() {
    final external = widget.controller;
    _ownsController = external == null;
    _controller = external ??
        PhoneNumberController(
          initialValue: widget.initialValue,
          defaultIso: widget.defaultIso,
        );
    _controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(covariant PhoneNumberField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _controller.removeListener(_onController);
      if (_ownsController) _controller.dispose();
      _attach();
      _syncText();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    if (_ownsController) _controller.dispose();
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  /// External `controller.value = …` / `country = …`: mirror into the text.
  void _onController() {
    if (!mounted) return;
    _syncText();
    setState(() {});
    _field.currentState?.didChange(_controller.value);
    if (_validated) _field.currentState?.validate();
  }

  void _syncText() {
    final formatted = _controller.formatted;
    if (_text.text != formatted) {
      _text.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  void _onFocus() {
    if (_focus.hasFocus) return;
    if (_controller.isEmpty && !widget.required) return;
    _validated = true;
    _field.currentState?.validate();
  }

  void _onTextChanged(String text) {
    final switchTo = _switchTo;
    _switchTo = null;
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    _controller.removeListener(_onController);
    final countryChanged =
        switchTo != null && switchTo.iso != _controller.country.iso;
    if (countryChanged) _controller.country = switchTo;
    _controller.nationalDigits = digits;
    _controller.addListener(_onController);
    _field.currentState?.didChange(_controller.value);
    if (_validated) _field.currentState?.validate();
    if (countryChanged) widget.onCountryChanged?.call(switchTo);
    setState(() {});
    widget.onChanged?.call(_controller.value);
  }

  Future<void> _pickCountry() async {
    final picked = await showCountryPicker(
      context,
      selected: _controller.country,
      recent: PhoneNumberField.recentCountries,
    );
    if (picked == null || !mounted) return;
    PhoneNumberField._remember(picked);
    if (picked.iso == _controller.country.iso) return;
    _controller.removeListener(_onController);
    _controller.country = picked;
    _controller.addListener(_onController);
    _syncText();
    _field.currentState?.didChange(_controller.value);
    if (_validated) _field.currentState?.validate();
    setState(() {});
    widget.onCountryChanged?.call(picked);
    widget.onChanged?.call(_controller.value);
    if (widget.enabled) _focus.requestFocus();
  }

  String? _validate(String? _) {
    _validated = true;
    final value = _controller.value;
    if (_controller.isEmpty) {
      if (widget.required) return 'Enter a mobile number';
      return widget.validator?.call('');
    }
    if (!_controller.isValid) {
      return 'Enter a valid ${_controller.country.name} mobile number';
    }
    return widget.validator?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final country = _controller.country;
    return FormField<String>(
      key: _field,
      initialValue: _controller.value,
      validator: _validate,
      autovalidateMode: AutovalidateMode.disabled,
      enabled: widget.enabled,
      builder: (field) => TextField(
        controller: _text,
        focusNode: _focus,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        keyboardType: TextInputType.phone,
        textInputAction: widget.textInputAction,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.telephoneNumberNational],
        inputFormatters: [_NationalNumberFormatter(this)],
        onChanged: _onTextChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: Phone.exampleFor(country.iso),
          helperText: widget.helperText,
          errorText: field.errorText,
          prefixIcon: _CountryChip(
            country: country,
            enabled: widget.enabled,
            onTap: _pickCountry,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: SparklingSpacing.touchTargetStaff,
            minHeight: SparklingSpacing.touchTargetStaff,
          ),
        ),
      ),
    );
  }
}

/// Keeps the input to grouped national digits. A pasted international number
/// (`+44 7400 123456`, `0044 …`) is resolved with [Phone.normalise] and
/// re-targets the country; a leading trunk `0` is dropped.
class _NationalNumberFormatter extends TextInputFormatter {
  _NationalNumberFormatter(this.state);
  final _PhoneNumberFieldState state;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var country = state._controller.country;
    final raw = newValue.text;
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final international =
        raw.contains('+') || (digits.startsWith('00') && digits.length > 6);
    if (international) {
      final split = Phone.split(Phone.normalise(raw, defaultIso: country.iso));
      if (split != null) {
        country = split.$1;
        digits = split.$2;
        state._switchTo = country;
      }
    }
    if (!international || state._switchTo == null) {
      final trunk = Phone.nationalPrefixOf(country.iso);
      if (trunk == '0' && digits.length >= 2 && digits.startsWith('0')) {
        digits = digits.substring(1);
      }
    }
    final max = Phone.maxNationalLength(country.iso);
    if (digits.length > max) digits = digits.substring(0, max);
    final formatted = Phone.formatNational(country.iso, digits);

    // Keep the caret after the same number of digits it followed before.
    final caret = newValue.selection.baseOffset < 0
        ? raw.length
        : newValue.selection.baseOffset.clamp(0, raw.length);
    var digitsBefore = raw
        .substring(0, caret)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;
    if (international && state._switchTo != null) digitsBefore = digits.length;
    var offset = formatted.length;
    if (digitsBefore < digits.length) {
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (RegExp(r'[0-9]').hasMatch(formatted[i])) {
          if (seen == digitsBefore) {
            offset = i;
            break;
          }
          seen++;
        }
      }
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class _CountryChip extends StatelessWidget {
  const _CountryChip({
    required this.country,
    required this.enabled,
    required this.onTap,
  });

  final Country country;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Semantics(
      button: true,
      label: 'Country ${country.name}, +${country.dial}. Change country',
      child: Padding(
        padding: const EdgeInsets.only(left: SparklingSpacing.sm),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('phone-country-chip'),
            onTap: enabled ? onTap : null,
            borderRadius: SparklingShapes.pillRadius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: SparklingSpacing.touchTargetStaff,
                minWidth: SparklingSpacing.touchTargetStaff,
              ),
              child: Align(
                widthFactor: 1,
                heightFactor: 1,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: SparklingShapes.pillRadius,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          country.flag,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '+${country.dial}',
                        style: SparklingTypography.labelLarge.copyWith(
                          color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        Symbols.arrow_drop_down_rounded,
                        size: 22,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Searchable country sheet (name / dial code / ISO). Resolves with the
/// chosen [Country] or `null` when dismissed.
Future<Country?> showCountryPicker(
  BuildContext context, {
  Country? selected,
  List<Country> recent = const [],
}) {
  return showModalBottomSheet<Country>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: SparklingShapes.sheetShape,
    builder: (ctx) {
      final h = MediaQuery.sizeOf(ctx).height;
      final inset = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SizedBox(
          height: (h * 0.85 - inset).clamp(280.0, h),
          child: _CountrySheet(selected: selected, recent: recent),
        ),
      );
    },
  );
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet({this.selected, this.recent = const []});
  final Country? selected;
  final List<Country> recent;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Country> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return countries;
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    final numeric = digits.isNotEmpty && RegExp(r'^[+0-9 ]+$').hasMatch(q);
    return [
      for (final c in countries)
        if (numeric
            ? c.dial.startsWith(digits)
            : c.name.toLowerCase().contains(q) || c.iso.toLowerCase() == q)
          c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final matches = _matches;
    final showRecent = _query.trim().isEmpty && widget.recent.isNotEmpty;
    final defaultCountry = Phone.countryByIso(defaultCountryIso);
    final pinned = <Country>[
      if (showRecent) ...widget.recent,
      if (_query.trim().isEmpty &&
          defaultCountry != null &&
          !widget.recent.any((c) => c.iso == defaultCountry.iso))
        defaultCountry,
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SparklingSpacing.gutter,
            0,
            SparklingSpacing.gutter,
            SparklingSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose country',
                style: SparklingTypography.titleLarge.copyWith(
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: SparklingSpacing.md),
              TextField(
                key: const ValueKey('phone-country-search'),
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search by country or code',
                  prefixIcon: const Icon(Symbols.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Symbols.close_rounded),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: matches.isEmpty
              ? Center(
                  child: Text(
                    'No country matches “${_query.trim()}”',
                    style: SparklingTypography.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: SparklingSpacing.xxl),
                  itemCount: matches.length + (pinned.isEmpty ? 0 : pinned.length + 2),
                  itemBuilder: (context, i) {
                    if (pinned.isNotEmpty) {
                      if (i == 0) {
                        return _header(context, showRecent ? 'Recent' : 'Default');
                      }
                      if (i <= pinned.length) {
                        return _tile(context, pinned[i - 1]);
                      }
                      if (i == pinned.length + 1) {
                        return _header(context, 'All countries');
                      }
                      i -= pinned.length + 2;
                    }
                    return _tile(context, matches[i]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SparklingSpacing.gutter,
      SparklingSpacing.sm,
      SparklingSpacing.gutter,
      SparklingSpacing.xs,
    ),
    child: Text(
      text.toUpperCase(),
      style: SparklingTypography.overline.copyWith(
        color: context.colors.onSurfaceVariant,
      ),
    ),
  );

  Widget _tile(BuildContext context, Country c) {
    final cs = context.colors;
    final selected = c.iso == widget.selected?.iso;
    return ListTile(
      minTileHeight: SparklingSpacing.touchTargetStaff,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: SparklingSpacing.gutter,
      ),
      selected: selected,
      selectedTileColor: cs.primaryContainer.withValues(alpha: 0.35),
      leading: ExcludeSemantics(
        child: Text(c.flag, style: const TextStyle(fontSize: 22)),
      ),
      title: Text(
        c.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: SparklingTypography.bodyMedium.copyWith(
          color: cs.onSurface,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: Text(
        '+${c.dial}',
        style: SparklingTypography.labelLarge.copyWith(
          color: selected ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
      onTap: () => Navigator.of(context).pop(c),
    );
  }
}
