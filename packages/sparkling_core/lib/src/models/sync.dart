import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

/// Operation kinds accepted by `POST /sync/batch` (ARC-004).
///
/// The `payload` of each kind is the same body the direct route takes, plus
/// the routing ids (`task_id`, `work_order_id`, `step_key`, `item_id`, …).
abstract final class SyncKinds {
  static const String taskTransition = 'task.transition';
  static const String stepResult = 'step.result';
  static const String inventoryMovement = 'inventory.movement';
  static const String bookingCreate = 'booking.create';
  static const String bookingCancel = 'booking.cancel';
  static const String quotationCreate = 'quotation.create';
  static const String quotationDecision = 'quotation.decision';
  static const String vehicleCreate = 'vehicle.create';
  static const String taskAssign = 'task.assign';
  static const String notificationRead = 'notification.read';
}

/// Per-operation result of `POST /sync/batch`.
class SyncOperationResult extends Equatable {
  const SyncOperationResult({
    required this.clientOpId,
    required this.status,
    this.result,
    this.error,
  });

  final String clientOpId;
  final SyncStatus status;
  final Json? result;

  /// Error message when rejected/conflicted.
  final String? error;

  bool get applied => status == SyncStatus.applied;

  factory SyncOperationResult.fromJson(Json json) => SyncOperationResult(
    clientOpId: str(json['client_op_id']),
    status: SyncStatus.fromDb(strOrNull(json['status'])),
    result: asJsonOrNull(json['result']),
    error:
        strOrNull(json['error']) ??
        strOrNull(asJsonOrNull(json['result'])?['message']),
  );

  Json toJson() => compact({
    'client_op_id': clientOpId,
    'status': status.db,
    'result': result,
    'error': error,
  });

  @override
  List<Object?> get props => [clientOpId, status, result, error];
}
