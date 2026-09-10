import 'package:equatable/equatable.dart';

import 'booking.dart';
import 'enums.dart';
import 'json.dart';
import 'work_order.dart';

/// `progress{steps_done, step_count}` inside the task card.
class StepProgress extends Equatable {
  const StepProgress({required this.stepsDone, required this.stepCount});
  final int stepsDone;
  final int stepCount;

  double get fraction =>
      stepCount == 0 ? 0 : (stepsDone / stepCount).clamp(0, 1);

  /// "4/7 steps"
  String get label => '$stepsDone/$stepCount steps';

  factory StepProgress.fromJson(Json json) => StepProgress(
    stepsDone: intOf(json['steps_done']),
    stepCount: intOf(json['step_count']),
  );
  Json toJson() => {'steps_done': stepsDone, 'step_count': stepCount};

  StepProgress copyWith({int? stepsDone, int? stepCount}) => StepProgress(
    stepsDone: stepsDone ?? this.stepsDone,
    stepCount: stepCount ?? this.stepCount,
  );

  @override
  List<Object?> get props => [stepsDone, stepCount];
}

/// Expanded `work_order{...}` on `GET /tasks` — everything a task card needs.
class WorkOrderCard extends Equatable {
  const WorkOrderCard({
    required this.id,
    required this.ref,
    required this.status,
    this.vehicle,
    this.serviceName,
    this.bay,
    this.priority = 2,
    this.etaAt,
    this.progress = const StepProgress(stepsDone: 0, stepCount: 0),
    this.blockedReason,
    this.bookingRef,
    this.customerName,
    this.slotStart,
    this.collectedAt,
  });

  final String id;
  final String ref;
  final WorkStatus status;
  final VehicleSummary? vehicle;
  final String? serviceName;
  final String? bay;
  final int priority;
  final DateTime? etaAt;
  final StepProgress progress;
  final String? blockedReason;
  final String? bookingRef;
  final String? customerName;
  final DateTime? slotStart;

  /// Keys released to the customer (pickup OTP verified).
  final DateTime? collectedAt;

  bool get isCollected => collectedAt != null;

  /// Verified work waiting for the customer to collect the vehicle.
  bool get awaitingCollection =>
      status == WorkStatus.verified && collectedAt == null;

  /// "Wash & Wax — Toyota Corolla Cross"
  String get title => [
    serviceName,
    vehicle?.displayName,
  ].where((s) => s != null && s.isNotEmpty).join(' — ');

  factory WorkOrderCard.fromJson(Json json) => WorkOrderCard(
    id: str(json['id']),
    ref: str(json['ref']),
    status: WorkStatus.fromDb(strOrNull(json['status'])),
    vehicle: json['vehicle'] is Map
        ? VehicleSummary.fromJson(asJson(json['vehicle']))
        : null,
    serviceName:
        strOrNull(json['service_name']) ??
        strOrNull(asJsonOrNull(json['service'])?['name']),
    bay: strOrNull(json['bay']),
    priority: intOf(json['priority'], 2),
    etaAt: dtOrNull(json['eta_at']),
    progress: json['progress'] is Map
        ? StepProgress.fromJson(asJson(json['progress']))
        : const StepProgress(stepsDone: 0, stepCount: 0),
    blockedReason: strOrNull(json['blocked_reason']),
    bookingRef: strOrNull(json['booking_ref']),
    customerName: strOrNull(json['customer_name']),
    slotStart: dtOrNull(json['slot_start']),
    collectedAt: dtOrNull(json['collected_at']),
  );

  Json toJson() => compact({
    'id': id,
    'ref': ref,
    'status': status.db,
    'vehicle': vehicle?.toJson(),
    'service': serviceName == null ? null : {'name': serviceName},
    'bay': bay,
    'priority': priority,
    'eta_at': iso(etaAt),
    'progress': progress.toJson(),
    'blocked_reason': blockedReason,
    'booking_ref': bookingRef,
    'customer_name': customerName,
    'slot_start': iso(slotStart),
    'collected_at': iso(collectedAt),
  });

  WorkOrderCard copyWith({
    WorkStatus? status,
    String? bay,
    int? priority,
    DateTime? etaAt,
    StepProgress? progress,
    String? blockedReason,
    DateTime? collectedAt,
    bool clearBlockedReason = false,
  }) => WorkOrderCard(
    id: id,
    ref: ref,
    status: status ?? this.status,
    vehicle: vehicle,
    serviceName: serviceName,
    bay: bay ?? this.bay,
    priority: priority ?? this.priority,
    etaAt: etaAt ?? this.etaAt,
    progress: progress ?? this.progress,
    blockedReason: clearBlockedReason
        ? null
        : (blockedReason ?? this.blockedReason),
    bookingRef: bookingRef,
    customerName: customerName,
    slotStart: slotStart,
    collectedAt: collectedAt ?? this.collectedAt,
  );

  @override
  List<Object?> get props => [
    id,
    ref,
    status,
    vehicle,
    serviceName,
    bay,
    priority,
    etaAt,
    progress,
    blockedReason,
    collectedAt,
  ];
}

/// `tasks` row (+ expanded [workOrder] card from `GET /tasks`).
class Task extends Equatable {
  const Task({
    required this.id,
    required this.workOrderId,
    required this.outletId,
    required this.title,
    required this.status,
    this.seq = 1,
    this.assigneeId,
    this.assigneeName,
    this.priority = 2,
    this.blockedReason,
    this.dueAt,
    this.startedAt,
    this.completedAt,
    this.elapsedSeconds = 0,
    this.clientOpId,
    this.createdAt,
    this.updatedAt,
    this.workOrder,
  });

  final String id;
  final String workOrderId;
  final String outletId;
  final String title;
  final int seq;
  final String? assigneeId;
  final String? assigneeName;
  final WorkStatus status;
  final int priority;
  final String? blockedReason;
  final DateTime? dueAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int elapsedSeconds;
  final String? clientOpId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final WorkOrderCard? workOrder;

  bool get isBlocked => status == WorkStatus.blocked;
  bool get isOverdue =>
      dueAt != null && status.isOpen && dueAt!.isBefore(DateTime.now());
  String get ref => workOrder?.ref ?? id;

  /// Elapsed including the running segment since [startedAt] when in progress.
  Duration elapsed({DateTime? now}) {
    var secs = elapsedSeconds;
    if (status == WorkStatus.inProgress && startedAt != null) {
      secs += (now ?? DateTime.now())
          .difference(startedAt!)
          .inSeconds
          .clamp(0, 1 << 31);
    }
    return Duration(seconds: secs);
  }

  factory Task.fromJson(Json json) => Task(
    id: str(json['id']),
    workOrderId: str(
      json['work_order_id'],
      str(asJsonOrNull(json['work_order'])?['id']),
    ),
    outletId: str(json['outlet_id']),
    title: str(json['title']),
    seq: intOf(json['seq'], 1),
    assigneeId: strOrNull(json['assignee_id']),
    assigneeName: strOrNull(json['assignee_name']),
    status: WorkStatus.fromDb(strOrNull(json['status'])),
    priority: intOf(json['priority'], 2),
    blockedReason: strOrNull(json['blocked_reason']),
    dueAt: dtOrNull(json['due_at']),
    startedAt: dtOrNull(json['started_at']),
    completedAt: dtOrNull(json['completed_at']),
    elapsedSeconds: intOf(json['elapsed_seconds']),
    clientOpId: strOrNull(json['client_op_id']),
    createdAt: dtOrNull(json['created_at']),
    updatedAt: dtOrNull(json['updated_at']),
    workOrder: json['work_order'] is Map
        ? WorkOrderCard.fromJson(asJson(json['work_order']))
        : null,
  );

  Json toJson() => compact({
    'id': id,
    'work_order_id': workOrderId,
    'outlet_id': outletId,
    'title': title,
    'seq': seq,
    'assignee_id': assigneeId,
    'assignee_name': assigneeName,
    'status': status.db,
    'priority': priority,
    'blocked_reason': blockedReason,
    'due_at': iso(dueAt),
    'started_at': iso(startedAt),
    'completed_at': iso(completedAt),
    'elapsed_seconds': elapsedSeconds,
    'client_op_id': clientOpId,
    'created_at': iso(createdAt),
    'updated_at': iso(updatedAt),
    'work_order': workOrder?.toJson(),
  });

  Task copyWith({
    WorkStatus? status,
    String? assigneeId,
    String? assigneeName,
    int? priority,
    String? blockedReason,
    DateTime? startedAt,
    DateTime? completedAt,
    int? elapsedSeconds,
    DateTime? updatedAt,
    WorkOrderCard? workOrder,
    bool clearBlockedReason = false,
  }) => Task(
    id: id,
    workOrderId: workOrderId,
    outletId: outletId,
    title: title,
    seq: seq,
    assigneeId: assigneeId ?? this.assigneeId,
    assigneeName: assigneeName ?? this.assigneeName,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    blockedReason: clearBlockedReason
        ? null
        : (blockedReason ?? this.blockedReason),
    dueAt: dueAt,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt ?? this.completedAt,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    clientOpId: clientOpId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    workOrder: workOrder ?? this.workOrder,
  );

  @override
  List<Object?> get props => [
    id,
    workOrderId,
    status,
    assigneeId,
    priority,
    blockedReason,
    startedAt,
    completedAt,
    elapsedSeconds,
    workOrder,
    updatedAt,
  ];
}

/// Body for `POST /tasks/:id/transition`.
class TaskTransitionInput {
  const TaskTransitionInput({
    required this.to,
    required this.clientOpId,
    this.reason,
    this.overrideReason,
  });

  final WorkStatus to;
  final String clientOpId;
  final String? reason;

  /// Supervisor override when verifying with incomplete required steps (STF-033).
  final String? overrideReason;

  Json toJson() => compact({
    'to': to.db,
    'reason': reason,
    'client_op_id': clientOpId,
    'override': overrideReason == null ? null : {'reason': overrideReason},
  });

  factory TaskTransitionInput.fromJson(Json json) => TaskTransitionInput(
    to: WorkStatus.fromDb(strOrNull(json['to'])),
    clientOpId: str(json['client_op_id']),
    reason: strOrNull(json['reason']),
    overrideReason: strOrNull(asJsonOrNull(json['override'])?['reason']),
  );
}

/// `GET /work-orders/:id` → `{ work_order, template{steps[]}, results[], events[], task }`.
class WorkOrderDetail extends Equatable {
  const WorkOrderDetail({
    required this.workOrder,
    this.template,
    this.results = const [],
    this.events = const [],
    this.task,
  });

  final WorkOrder workOrder;
  final ChecklistTemplate? template;
  final List<StepResult> results;
  final List<TaskEvent> events;
  final Task? task;

  List<ChecklistStep> get steps => template?.steps ?? const [];

  StepResult? resultFor(String key) {
    for (final r in results) {
      if (r.stepKey == key) return r;
    }
    return null;
  }

  int get stepsDone => results.where((r) => r.isDone).length;
  int get stepCount => steps.length;
  StepProgress get progress =>
      StepProgress(stepsDone: stepsDone, stepCount: stepCount);

  /// First step that is not done (the "current" expanded card).
  ChecklistStep? get currentStep {
    for (final s in steps) {
      if (!(resultFor(s.key)?.isDone ?? false)) return s;
    }
    return null;
  }

  /// STF-033: supervisor verification unlocks only when required steps pass.
  bool get requiredStepsPassed => steps
      .where((s) => s.required && !s.isSupervisorVerify)
      .every((s) => resultFor(s.key)?.isDone ?? false);

  bool isStepLocked(ChecklistStep step) =>
      step.isSupervisorVerify && !requiredStepsPassed;

  factory WorkOrderDetail.fromJson(Json json) => WorkOrderDetail(
    workOrder: WorkOrder.fromJson(asJson(json['work_order'])),
    template: json['template'] is Map
        ? ChecklistTemplate.fromJson(asJson(json['template']))
        : null,
    results: asJsonList(json['results']).map(StepResult.fromJson).toList(),
    events: asJsonList(json['events']).map(TaskEvent.fromJson).toList(),
    task: json['task'] is Map ? Task.fromJson(asJson(json['task'])) : null,
  );

  Json toJson() => compact({
    'work_order': workOrder.toJson(),
    'template': template?.toJson(),
    'results': results.map((r) => r.toJson()).toList(),
    'events': events.map((e) => e.toJson()).toList(),
    'task': task?.toJson(),
  });

  WorkOrderDetail copyWith({
    WorkOrder? workOrder,
    ChecklistTemplate? template,
    List<StepResult>? results,
    List<TaskEvent>? events,
    Task? task,
  }) => WorkOrderDetail(
    workOrder: workOrder ?? this.workOrder,
    template: template ?? this.template,
    results: results ?? this.results,
    events: events ?? this.events,
    task: task ?? this.task,
  );

  /// Builds the customer-facing timeline (checked-in → stages → ready).
  List<TimelineEntry> toTimeline() {
    final entries = <TimelineEntry>[
      TimelineEntry(
        key: 'checked_in',
        title: 'Checked in',
        state: workOrder.startedAt == null
            ? TimelineEntryState.pending
            : TimelineEntryState.done,
        at: workOrder.startedAt,
      ),
    ];
    var currentAssigned = false;
    for (final s in steps) {
      final r = resultFor(s.key);
      TimelineEntryState state;
      if (r?.isDone ?? false) {
        state = TimelineEntryState.done;
      } else if (!currentAssigned && workOrder.status.isOpen) {
        state = TimelineEntryState.current;
        currentAssigned = true;
      } else {
        state = TimelineEntryState.pending;
      }
      entries.add(
        TimelineEntry(
          key: s.key,
          title: s.title,
          state: state,
          at: r?.completedAt,
          actorName: r?.actorName,
        ),
      );
    }
    entries.add(
      TimelineEntry(
        key: 'ready',
        title: 'Ready for collection',
        state: workOrder.status == WorkStatus.verified
            ? TimelineEntryState.done
            : TimelineEntryState.pending,
        at: workOrder.verifiedAt,
      ),
    );
    if (workOrder.collectedAt != null) {
      entries.add(
        TimelineEntry(
          key: 'collected',
          title: 'Keys released',
          state: TimelineEntryState.done,
          at: workOrder.collectedAt,
        ),
      );
    }
    return entries;
  }

  @override
  List<Object?> get props => [workOrder, template, results, events, task];
}
