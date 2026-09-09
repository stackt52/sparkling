import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

/// One step of a `checklist_templates.steps` array.
class ChecklistStep extends Equatable {
  const ChecklistStep({
    required this.key,
    required this.title,
    this.type = StepType.confirm,
    this.required = true,
    this.hint,
    this.options = const [],
    this.unit,
    this.min,
    this.max,
    this.photoRequired = false,
  });

  final String key;
  final String title;
  final StepType type;
  final bool required;
  final String? hint;
  final List<String> options;
  final String? unit;
  final double? min;
  final double? max;
  final bool photoRequired;

  bool get isSupervisorVerify => type == StepType.supervisorVerify;
  bool get needsPhoto => photoRequired || type == StepType.photo;

  /// Client-side validation mirror of the API (numeric range / photo proof).
  String? validate({dynamic value, String? attachmentId}) {
    switch (type) {
      case StepType.numeric:
        final v = value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '');
        if (v == null) {
          return 'Enter a number${unit == null ? '' : ' in $unit'}';
        }
        if (min != null && v < min!) {
          return 'Must be at least $min${unit ?? ''}';
        }
        if (max != null && v > max!) return 'Must be at most $max${unit ?? ''}';
        return null;
      case StepType.photo:
        return attachmentId == null ? 'Photo proof is required' : null;
      case StepType.select:
        if (value == null || !options.contains(value.toString())) {
          return 'Choose one of ${options.join(', ')}';
        }
        return null;
      case StepType.text:
        return (value?.toString().trim().isEmpty ?? true)
            ? 'Enter a note'
            : null;
      case StepType.confirm:
      case StepType.ack:
      case StepType.supervisorVerify:
        return null;
    }
  }

  factory ChecklistStep.fromJson(Json json) => ChecklistStep(
    key: str(json['key']),
    title: str(json['title']),
    type: StepType.fromDb(strOrNull(json['type'])),
    required: boolOf(json['required'], true),
    hint: strOrNull(json['hint']),
    options: asStringList(json['options']),
    unit: strOrNull(json['unit']),
    min: dblOrNull(json['min']),
    max: dblOrNull(json['max']),
    photoRequired: boolOf(json['photo_required']),
  );

  Json toJson() => compact({
    'key': key,
    'title': title,
    'type': type.db,
    'required': required,
    'hint': hint,
    'options': options.isEmpty ? null : options,
    'unit': unit,
    'min': min,
    'max': max,
    'photo_required': photoRequired ? true : null,
  });

  @override
  List<Object?> get props => [
    key,
    title,
    type,
    required,
    hint,
    options,
    unit,
    min,
    max,
    photoRequired,
  ];
}

/// `checklist_templates` row.
class ChecklistTemplate extends Equatable {
  const ChecklistTemplate({
    required this.id,
    required this.name,
    required this.category,
    this.version = 1,
    this.status = ConfigStatus.published,
    this.steps = const [],
    this.outletId,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String name;
  final ServiceCategory category;
  final int version;
  final ConfigStatus status;
  final List<ChecklistStep> steps;
  final String? outletId;
  final String? createdBy;
  final DateTime? createdAt;

  int get stepCount => steps.length;
  List<ChecklistStep> get requiredSteps =>
      steps.where((s) => s.required && !s.isSupervisorVerify).toList();

  factory ChecklistTemplate.fromJson(Json json) => ChecklistTemplate(
    id: str(json['id']),
    name: str(json['name']),
    category: ServiceCategory.fromDb(strOrNull(json['category'])),
    version: intOf(json['version'], 1),
    status: ConfigStatus.fromDb(strOrNull(json['status'])),
    steps: asJsonList(json['steps']).map(ChecklistStep.fromJson).toList(),
    outletId: strOrNull(json['outlet_id']),
    createdBy: strOrNull(json['created_by']),
    createdAt: dtOrNull(json['created_at']),
  );

  Json toJson() => compact({
    'id': id,
    'name': name,
    'category': category.db,
    'version': version,
    'status': status.db,
    'steps': steps.map((s) => s.toJson()).toList(),
    'outlet_id': outletId,
    'created_by': createdBy,
    'created_at': iso(createdAt),
  });

  ChecklistTemplate copyWith({
    String? name,
    int? version,
    ConfigStatus? status,
    List<ChecklistStep>? steps,
  }) => ChecklistTemplate(
    id: id,
    name: name ?? this.name,
    category: category,
    version: version ?? this.version,
    status: status ?? this.status,
    steps: steps ?? this.steps,
    outletId: outletId,
    createdBy: createdBy,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [id, name, category, version, status, steps];
}

/// `checklist_step_results` row.
class StepResult extends Equatable {
  const StepResult({
    required this.workOrderId,
    required this.stepKey,
    this.id,
    this.status = StepStatus.pending,
    this.value,
    this.attachmentId,
    this.actorId,
    this.actorName,
    this.note,
    this.clientOpId,
    this.completedAt,
    this.updatedAt,
    this.pendingSync = false,
  });

  final String? id;
  final String workOrderId;
  final String stepKey;
  final StepStatus status;
  final dynamic value;
  final String? attachmentId;
  final String? actorId;
  final String? actorName;
  final String? note;
  final String? clientOpId;
  final DateTime? completedAt;
  final DateTime? updatedAt;

  /// `true` while the result sits in the offline queue (STF-034).
  final bool pendingSync;

  bool get isDone => status == StepStatus.done;
  bool get isBlocked => status == StepStatus.blocked;

  factory StepResult.fromJson(Json json) => StepResult(
    id: strOrNull(json['id']),
    workOrderId: str(json['work_order_id']),
    stepKey: str(json['step_key']),
    status: StepStatus.fromDb(strOrNull(json['status'])),
    value: json['value'],
    attachmentId: strOrNull(json['attachment_id']),
    actorId: strOrNull(json['actor_id']),
    actorName: strOrNull(json['actor_name']),
    note: strOrNull(json['note']),
    clientOpId: strOrNull(json['client_op_id']),
    completedAt: dtOrNull(json['completed_at']),
    updatedAt: dtOrNull(json['updated_at']),
    pendingSync: boolOf(json['pending_sync']),
  );

  Json toJson() => compact({
    'id': id,
    'work_order_id': workOrderId,
    'step_key': stepKey,
    'status': status.db,
    'value': value,
    'attachment_id': attachmentId,
    'actor_id': actorId,
    'actor_name': actorName,
    'note': note,
    'client_op_id': clientOpId,
    'completed_at': iso(completedAt),
    'updated_at': iso(updatedAt),
    'pending_sync': pendingSync ? true : null,
  });

  StepResult copyWith({
    StepStatus? status,
    dynamic value,
    String? attachmentId,
    String? actorId,
    String? actorName,
    String? note,
    String? clientOpId,
    DateTime? completedAt,
    DateTime? updatedAt,
    bool? pendingSync,
  }) => StepResult(
    id: id,
    workOrderId: workOrderId,
    stepKey: stepKey,
    status: status ?? this.status,
    value: value ?? this.value,
    attachmentId: attachmentId ?? this.attachmentId,
    actorId: actorId ?? this.actorId,
    actorName: actorName ?? this.actorName,
    note: note ?? this.note,
    clientOpId: clientOpId ?? this.clientOpId,
    completedAt: completedAt ?? this.completedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    pendingSync: pendingSync ?? this.pendingSync,
  );

  @override
  List<Object?> get props => [
    workOrderId,
    stepKey,
    status,
    value,
    attachmentId,
    actorId,
    note,
    completedAt,
    pendingSync,
  ];
}

/// Body for `POST /work-orders/:id/steps/:key`.
class StepResultInput {
  const StepResultInput({
    required this.status,
    required this.clientOpId,
    this.value,
    this.attachmentId,
    this.note,
  }) : assert(status != StepStatus.pending);

  final StepStatus status;
  final String clientOpId;
  final dynamic value;
  final String? attachmentId;
  final String? note;

  Json toJson() => compact({
    'status': status.db,
    'value': value,
    'attachment_id': attachmentId,
    'note': note,
    'client_op_id': clientOpId,
  });

  factory StepResultInput.fromJson(Json json) => StepResultInput(
    status: StepStatus.fromDb(strOrNull(json['status'])),
    clientOpId: str(json['client_op_id']),
    value: json['value'],
    attachmentId: strOrNull(json['attachment_id']),
    note: strOrNull(json['note']),
  );
}

/// `task_events` row (STF-024 audit trail).
class TaskEvent extends Equatable {
  const TaskEvent({
    required this.id,
    required this.event,
    this.taskId,
    this.workOrderId,
    this.actorId,
    this.actorName,
    this.fromStatus,
    this.toStatus,
    this.reason,
    this.metadata = const {},
    this.clientOpId,
    this.createdAt,
  });

  final String id;

  /// 'assigned' | 'transition' | 'step_done' | 'step_blocked' | 'override'
  final String event;
  final String? taskId;
  final String? workOrderId;
  final String? actorId;
  final String? actorName;
  final String? fromStatus;
  final String? toStatus;
  final String? reason;
  final Json metadata;
  final String? clientOpId;
  final DateTime? createdAt;

  factory TaskEvent.fromJson(Json json) => TaskEvent(
    id: str(json['id']),
    event: str(json['event']),
    taskId: strOrNull(json['task_id']),
    workOrderId: strOrNull(json['work_order_id']),
    actorId: strOrNull(json['actor_id']),
    actorName: strOrNull(json['actor_name']),
    fromStatus: strOrNull(json['from_status']),
    toStatus: strOrNull(json['to_status']),
    reason: strOrNull(json['reason']),
    metadata: asJson(json['metadata']),
    clientOpId: strOrNull(json['client_op_id']),
    createdAt: dtOrNull(json['created_at']),
  );

  Json toJson() => compact({
    'id': id,
    'event': event,
    'task_id': taskId,
    'work_order_id': workOrderId,
    'actor_id': actorId,
    'actor_name': actorName,
    'from_status': fromStatus,
    'to_status': toStatus,
    'reason': reason,
    'metadata': metadata.isEmpty ? null : metadata,
    'client_op_id': clientOpId,
    'created_at': iso(createdAt),
  });

  @override
  List<Object?> get props => [
    id,
    event,
    taskId,
    workOrderId,
    actorId,
    fromStatus,
    toStatus,
    reason,
    createdAt,
  ];
}

/// `work_orders` row.
class WorkOrder extends Equatable {
  const WorkOrder({
    required this.id,
    required this.ref,
    required this.outletId,
    required this.vehicleId,
    required this.customerId,
    required this.serviceId,
    required this.status,
    this.bookingId,
    this.quotationId,
    this.priority = 2,
    this.bay,
    this.checklistTemplateId,
    this.templateVersion,
    this.assigneeId,
    this.assigneeName,
    this.etaAt,
    this.startedAt,
    this.blockedReason,
    this.completedAt,
    this.verifiedAt,
    this.verifiedBy,
    this.dueAt,
    this.createdAt,
    this.updatedAt,
    this.serviceName,
    this.vehicleRegistration,
    this.vehicleName,
    this.customerName,
  });

  final String id;
  final String ref;
  final String outletId;
  final String? bookingId;
  final String? quotationId;
  final String vehicleId;
  final String customerId;
  final String serviceId;
  final WorkStatus status;

  /// 1 (P1) … 3
  final int priority;
  final String? bay;
  final String? checklistTemplateId;
  final int? templateVersion;
  final String? assigneeId;
  final String? assigneeName;
  final DateTime? etaAt;
  final DateTime? startedAt;
  final String? blockedReason;
  final DateTime? completedAt;
  final DateTime? verifiedAt;
  final String? verifiedBy;
  final DateTime? dueAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Common expansions
  final String? serviceName;
  final String? vehicleRegistration;
  final String? vehicleName;
  final String? customerName;

  bool get isOverdue =>
      dueAt != null && status.isOpen && dueAt!.isBefore(DateTime.now());

  factory WorkOrder.fromJson(Json json) {
    final vehicle = asJsonOrNull(json['vehicle']);
    final service = asJsonOrNull(json['service']);
    return WorkOrder(
      id: str(json['id']),
      ref: str(json['ref']),
      outletId: str(json['outlet_id']),
      bookingId: strOrNull(json['booking_id']),
      quotationId: strOrNull(json['quotation_id']),
      vehicleId: str(json['vehicle_id'], str(vehicle?['id'])),
      customerId: str(json['customer_id']),
      serviceId: str(json['service_id'], str(service?['id'])),
      status: WorkStatus.fromDb(strOrNull(json['status'])),
      priority: intOf(json['priority'], 2),
      bay: strOrNull(json['bay']),
      checklistTemplateId: strOrNull(json['checklist_template_id']),
      templateVersion: intOrNull(json['template_version']),
      assigneeId: strOrNull(json['assignee_id']),
      assigneeName: strOrNull(json['assignee_name']),
      etaAt: dtOrNull(json['eta_at']),
      startedAt: dtOrNull(json['started_at']),
      blockedReason: strOrNull(json['blocked_reason']),
      completedAt: dtOrNull(json['completed_at']),
      verifiedAt: dtOrNull(json['verified_at']),
      verifiedBy: strOrNull(json['verified_by']),
      dueAt: dtOrNull(json['due_at']),
      createdAt: dtOrNull(json['created_at']),
      updatedAt: dtOrNull(json['updated_at']),
      serviceName:
          strOrNull(json['service_name']) ?? strOrNull(service?['name']),
      vehicleRegistration:
          strOrNull(json['vehicle_registration']) ??
          strOrNull(vehicle?['registration_no']),
      vehicleName:
          strOrNull(json['vehicle_name']) ??
          (vehicle == null
              ? null
              : [
                  vehicle['make'],
                  vehicle['model'],
                ].whereType<String>().join(' ')),
      customerName: strOrNull(json['customer_name']),
    );
  }

  Json toJson() => compact({
    'id': id,
    'ref': ref,
    'outlet_id': outletId,
    'booking_id': bookingId,
    'quotation_id': quotationId,
    'vehicle_id': vehicleId,
    'customer_id': customerId,
    'service_id': serviceId,
    'status': status.db,
    'priority': priority,
    'bay': bay,
    'checklist_template_id': checklistTemplateId,
    'template_version': templateVersion,
    'assignee_id': assigneeId,
    'assignee_name': assigneeName,
    'eta_at': iso(etaAt),
    'started_at': iso(startedAt),
    'blocked_reason': blockedReason,
    'completed_at': iso(completedAt),
    'verified_at': iso(verifiedAt),
    'verified_by': verifiedBy,
    'due_at': iso(dueAt),
    'created_at': iso(createdAt),
    'updated_at': iso(updatedAt),
    'service_name': serviceName,
    'vehicle_registration': vehicleRegistration,
    'vehicle_name': vehicleName,
    'customer_name': customerName,
  });

  WorkOrder copyWith({
    WorkStatus? status,
    int? priority,
    String? bay,
    String? assigneeId,
    String? assigneeName,
    DateTime? etaAt,
    DateTime? startedAt,
    String? blockedReason,
    DateTime? completedAt,
    DateTime? verifiedAt,
    String? verifiedBy,
    DateTime? updatedAt,
    bool clearBlockedReason = false,
  }) => WorkOrder(
    id: id,
    ref: ref,
    outletId: outletId,
    bookingId: bookingId,
    quotationId: quotationId,
    vehicleId: vehicleId,
    customerId: customerId,
    serviceId: serviceId,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    bay: bay ?? this.bay,
    checklistTemplateId: checklistTemplateId,
    templateVersion: templateVersion,
    assigneeId: assigneeId ?? this.assigneeId,
    assigneeName: assigneeName ?? this.assigneeName,
    etaAt: etaAt ?? this.etaAt,
    startedAt: startedAt ?? this.startedAt,
    blockedReason: clearBlockedReason
        ? null
        : (blockedReason ?? this.blockedReason),
    completedAt: completedAt ?? this.completedAt,
    verifiedAt: verifiedAt ?? this.verifiedAt,
    verifiedBy: verifiedBy ?? this.verifiedBy,
    dueAt: dueAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    serviceName: serviceName,
    vehicleRegistration: vehicleRegistration,
    vehicleName: vehicleName,
    customerName: customerName,
  );

  @override
  List<Object?> get props => [
    id,
    ref,
    status,
    priority,
    bay,
    assigneeId,
    etaAt,
    blockedReason,
    completedAt,
    verifiedAt,
    updatedAt,
  ];
}
