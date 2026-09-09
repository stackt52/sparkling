import 'package:equatable/equatable.dart';

import 'json.dart';

/// Row from `GET /availability` (wraps `get_available_slots`).
class AvailabilitySlot extends Equatable {
  const AvailabilitySlot({
    required this.slotStart,
    required this.slotEnd,
    required this.capacity,
    required this.booked,
    required this.available,
  });

  final DateTime slotStart;
  final DateTime slotEnd;
  final int capacity;
  final int booked;
  final bool available;

  int get remaining => (capacity - booked).clamp(0, capacity);

  factory AvailabilitySlot.fromJson(Json json) => AvailabilitySlot(
    slotStart: dt(json['slot_start']),
    slotEnd: dt(json['slot_end']),
    capacity: intOf(json['capacity']),
    booked: intOf(json['booked']),
    available: boolOf(json['available']),
  );

  Json toJson() => {
    'slot_start': iso(slotStart),
    'slot_end': iso(slotEnd),
    'capacity': capacity,
    'booked': booked,
    'available': available,
  };

  AvailabilitySlot copyWith({int? booked, bool? available}) => AvailabilitySlot(
    slotStart: slotStart,
    slotEnd: slotEnd,
    capacity: capacity,
    booked: booked ?? this.booked,
    available: available ?? this.available,
  );

  @override
  List<Object?> get props => [slotStart, slotEnd, capacity, booked, available];
}
