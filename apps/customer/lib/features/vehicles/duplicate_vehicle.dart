import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Saves a vehicle and handles the `409 conflict` duplicate response
/// (CUS-015): the customer chooses to update the existing record or keep
/// both. Returns the saved vehicle, or `null` if the user backed out.
Future<Vehicle?> saveVehicleHandlingDuplicates(
  BuildContext context,
  Repositories repos,
  VehicleInput input,
) async {
  try {
    return await repos.customer.addVehicle(input);
  } on ApiException catch (e) {
    final existingId = e.existingVehicleId;
    if (!e.isConflict || existingId == null) rethrow;
    if (!context.mounted) return null;
    final choice = await showModalBottomSheet<_DupChoice>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Already in your garage'),
              InfoBanner(tone: InfoTone.info, text: e.message),
              const SizedBox(height: 14),
              PillButton(
                label: 'Update existing vehicle',
                icon: Symbols.sync_rounded,
                expand: true,
                onPressed: () => Navigator.of(context).pop(_DupChoice.update),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'Add as a separate vehicle',
                variant: PillButtonVariant.tonal,
                expand: true,
                onPressed: () => Navigator.of(context).pop(_DupChoice.force),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'Cancel',
                variant: PillButtonVariant.outlined,
                expand: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
    switch (choice) {
      case _DupChoice.update:
        return repos.customer.updateVehicle(existingId, input);
      case _DupChoice.force:
        return repos.customer.addVehicle(input.copyWith(force: true));
      case null:
        return null;
    }
  }
}

enum _DupChoice { update, force }
