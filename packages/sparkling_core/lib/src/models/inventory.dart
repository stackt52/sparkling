import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

/// `inventory_alerts` row.
class InventoryAlert extends Equatable {
  const InventoryAlert({
    required this.id,
    required this.itemId,
    required this.outletId,
    required this.level,
    this.status = AlertStatus.open,
    this.notifiedAt,
    this.resolvedAt,
    this.createdAt,
  });

  final String id;
  final String itemId;
  final String outletId;
  final AlertLevel level;
  final AlertStatus status;
  final DateTime? notifiedAt;
  final DateTime? resolvedAt;
  final DateTime? createdAt;

  bool get isOpen => status != AlertStatus.resolved;
  bool get managerNotified => notifiedAt != null;

  factory InventoryAlert.fromJson(Json json) => InventoryAlert(
    id: str(json['id']),
    itemId: str(json['item_id']),
    outletId: str(json['outlet_id']),
    level: AlertLevel.fromDb(strOrNull(json['level'])),
    status: AlertStatus.fromDb(strOrNull(json['status'])),
    notifiedAt: dtOrNull(json['notified_at']),
    resolvedAt: dtOrNull(json['resolved_at']),
    createdAt: dtOrNull(json['created_at']),
  );

  Json toJson() => compact({
    'id': id,
    'item_id': itemId,
    'outlet_id': outletId,
    'level': level.db,
    'status': status.db,
    'notified_at': iso(notifiedAt),
    'resolved_at': iso(resolvedAt),
    'created_at': iso(createdAt),
  });

  InventoryAlert copyWith({
    AlertLevel? level,
    AlertStatus? status,
    DateTime? notifiedAt,
    DateTime? resolvedAt,
  }) => InventoryAlert(
    id: id,
    itemId: itemId,
    outletId: outletId,
    level: level ?? this.level,
    status: status ?? this.status,
    notifiedAt: notifiedAt ?? this.notifiedAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    itemId,
    outletId,
    level,
    status,
    notifiedAt,
    resolvedAt,
  ];
}

/// Stock level classification used by the UI level bar.
enum StockLevel { ok, low, out }

/// `inventory_items` row + open alert (`GET /inventory`).
class InventoryItem extends Equatable {
  const InventoryItem({
    required this.id,
    required this.outletId,
    required this.sku,
    required this.name,
    this.unit = 'unit',
    this.onHand = 0,
    this.reorderThreshold = 0,
    this.packSize,
    this.isActive = true,
    this.updatedAt,
    this.alert,
    this.outletName,
  });

  final String id;
  final String outletId;
  final String sku;
  final String name;
  final String unit;
  final double onHand;
  final double reorderThreshold;
  final double? packSize;
  final bool isActive;
  final DateTime? updatedAt;

  /// Open alert, if any.
  final InventoryAlert? alert;
  final String? outletName;

  StockLevel get level {
    if (onHand <= 0) return StockLevel.out;
    if (onHand <= reorderThreshold) return StockLevel.low;
    return StockLevel.ok;
  }

  bool get isOut => level == StockLevel.out;
  bool get isLow => level == StockLevel.low;
  bool get needsAttention => level != StockLevel.ok;

  /// Bar fill relative to a "full" level (2× threshold, min pack size).
  double get fillFraction {
    final full = [
      reorderThreshold * 2,
      packSize ?? 0,
      onHand,
      1.0,
    ].reduce((a, b) => a > b ? a : b);
    return (onHand / full).clamp(0, 1);
  }

  /// "1 of 8 · min 4"
  String get levelLabel {
    final full = [
      reorderThreshold * 2,
      packSize ?? 0,
      onHand,
    ].reduce((a, b) => a > b ? a : b);
    return '${_num(onHand)} of ${_num(full)} · min ${_num(reorderThreshold)}';
  }

  static String _num(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  factory InventoryItem.fromJson(Json json) {
    final alertJson =
        asJsonOrNull(json['open_alert']) ?? asJsonOrNull(json['alert']);
    return InventoryItem(
      id: str(json['id']),
      outletId: str(json['outlet_id']),
      sku: str(json['sku']),
      name: str(json['name']),
      unit: str(json['unit'], 'unit'),
      onHand: dbl(json['on_hand']),
      reorderThreshold: dbl(json['reorder_threshold']),
      packSize: dblOrNull(json['pack_size']),
      isActive: boolOf(json['is_active'], true),
      updatedAt: dtOrNull(json['updated_at']),
      alert: alertJson == null ? null : InventoryAlert.fromJson(alertJson),
      outletName:
          strOrNull(json['outlet_name']) ??
          strOrNull(asJsonOrNull(json['outlet'])?['name']),
    );
  }

  Json toJson() => compact({
    'id': id,
    'outlet_id': outletId,
    'sku': sku,
    'name': name,
    'unit': unit,
    'on_hand': onHand,
    'reorder_threshold': reorderThreshold,
    'pack_size': packSize,
    'is_active': isActive,
    'updated_at': iso(updatedAt),
    'open_alert': alert?.toJson(),
    'outlet_name': outletName,
  });

  InventoryItem copyWith({
    String? name,
    String? unit,
    double? onHand,
    double? reorderThreshold,
    DateTime? updatedAt,
    InventoryAlert? alert,
    bool clearAlert = false,
  }) => InventoryItem(
    id: id,
    outletId: outletId,
    sku: sku,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    onHand: onHand ?? this.onHand,
    reorderThreshold: reorderThreshold ?? this.reorderThreshold,
    packSize: packSize,
    isActive: isActive,
    updatedAt: updatedAt ?? this.updatedAt,
    alert: clearAlert ? null : (alert ?? this.alert),
    outletName: outletName,
  );

  @override
  List<Object?> get props => [
    id,
    outletId,
    sku,
    name,
    unit,
    onHand,
    reorderThreshold,
    alert,
    updatedAt,
  ];
}

/// Body for `POST /inventory/:id/movements`.
class InventoryMovementInput {
  const InventoryMovementInput({
    required this.delta,
    required this.reason,
    required this.clientOpId,
    this.note,
    this.workOrderId,
  });

  final double delta;
  final InventoryReason reason;
  final String clientOpId;
  final String? note;
  final String? workOrderId;

  Json toJson() => compact({
    'delta': delta,
    'reason': reason.db,
    'note': note,
    'work_order_id': workOrderId,
    'client_op_id': clientOpId,
  });

  factory InventoryMovementInput.fromJson(Json json) => InventoryMovementInput(
    delta: dbl(json['delta']),
    reason: InventoryReason.fromDb(strOrNull(json['reason'])),
    clientOpId: str(json['client_op_id']),
    note: strOrNull(json['note']),
    workOrderId: strOrNull(json['work_order_id']),
  );
}

/// `inventory_movements` row.
class InventoryMovement extends Equatable {
  const InventoryMovement({
    required this.id,
    required this.itemId,
    required this.delta,
    required this.reason,
    this.actorId,
    this.workOrderId,
    this.note,
    this.clientOpId,
    this.createdAt,
  });

  final String id;
  final String itemId;
  final double delta;
  final InventoryReason reason;
  final String? actorId;
  final String? workOrderId;
  final String? note;
  final String? clientOpId;
  final DateTime? createdAt;

  factory InventoryMovement.fromJson(Json json) => InventoryMovement(
    id: str(json['id']),
    itemId: str(json['item_id']),
    delta: dbl(json['delta']),
    reason: InventoryReason.fromDb(strOrNull(json['reason'])),
    actorId: strOrNull(json['actor_id']),
    workOrderId: strOrNull(json['work_order_id']),
    note: strOrNull(json['note']),
    clientOpId: strOrNull(json['client_op_id']),
    createdAt: dtOrNull(json['created_at']),
  );

  Json toJson() => compact({
    'id': id,
    'item_id': itemId,
    'delta': delta,
    'reason': reason.db,
    'actor_id': actorId,
    'work_order_id': workOrderId,
    'note': note,
    'client_op_id': clientOpId,
    'created_at': iso(createdAt),
  });

  @override
  List<Object?> get props => [id, itemId, delta, reason, createdAt];
}
