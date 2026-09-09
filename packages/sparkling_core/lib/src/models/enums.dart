/// Enums mirroring `backend/supabase/migrations/0001_schema.sql` §1.
/// Each exposes `db` (the SQL literal) and `fromDb`.
library;

T _find<T extends SparklingEnum>(List<T> values, String? v, T fallback) {
  if (v == null) return fallback;
  for (final e in values) {
    if (e.db == v) return e;
  }
  return fallback;
}

/// Marker for enums that serialise to a Postgres enum literal.
abstract interface class SparklingEnum {
  String get db;
}

enum UserRole implements SparklingEnum {
  customer('customer'),
  technician('technician'),
  supervisor('supervisor'),
  manager('manager'),
  admin('admin'),
  finance('finance');

  const UserRole(this.db);
  @override
  final String db;
  static UserRole fromDb(String? v) => _find(values, v, customer);

  bool get isStaff => this != customer;
  bool get isManager => this == manager || this == admin;
  bool get canSupervise => this == supervisor || isManager;
}

enum ServiceCategory implements SparklingEnum {
  carWash('car_wash'),
  autoBody('auto_body');

  const ServiceCategory(this.db);
  @override
  final String db;
  static ServiceCategory fromDb(String? v) => _find(values, v, carWash);

  String get label => this == carWash ? 'Car wash' : 'Auto body';
}

enum VehicleSource implements SparklingEnum {
  manual('manual'),
  scan('scan');

  const VehicleSource(this.db);
  @override
  final String db;
  static VehicleSource fromDb(String? v) => _find(values, v, manual);
}

enum BookingStatus implements SparklingEnum {
  draft('draft'),
  pending('pending'),
  confirmed('confirmed'),
  inService('in_service'),
  completed('completed'),
  cancelled('cancelled');

  const BookingStatus(this.db);
  @override
  final String db;
  static BookingStatus fromDb(String? v) => _find(values, v, pending);

  String get label => switch (this) {
    draft => 'Draft',
    pending => 'Pending',
    confirmed => 'Confirmed',
    inService => 'In service',
    completed => 'Completed',
    cancelled => 'Cancelled',
  };

  bool get isActive =>
      this == pending || this == confirmed || this == inService;

  /// CUS-025: cancellable until in_service.
  bool get canCancel => this == draft || this == pending || this == confirmed;
}

enum QuotationStatus implements SparklingEnum {
  requested('requested'),
  assessing('assessing'),
  quoted('quoted'),
  accepted('accepted'),
  declined('declined'),
  expired('expired'),
  converted('converted');

  const QuotationStatus(this.db);
  @override
  final String db;
  static QuotationStatus fromDb(String? v) => _find(values, v, requested);

  String get label => switch (this) {
    requested => 'Requested',
    assessing => 'Assessing',
    quoted => 'Quoted',
    accepted => 'Accepted',
    declined => 'Declined',
    expired => 'Expired',
    converted => 'Converted',
  };

  bool get awaitingDecision => this == quoted;
}

enum WorkStatus implements SparklingEnum {
  queued('queued'),
  assigned('assigned'),
  inProgress('in_progress'),
  blocked('blocked'),
  completed('completed'),
  verified('verified'),
  cancelled('cancelled');

  const WorkStatus(this.db);
  @override
  final String db;
  static WorkStatus fromDb(String? v) => _find(values, v, queued);

  String get label => switch (this) {
    queued => 'Queued',
    assigned => 'Assigned',
    inProgress => 'In progress',
    blocked => 'Blocked',
    completed => 'Completed',
    verified => 'Verified',
    cancelled => 'Cancelled',
  };

  bool get isDone => this == completed || this == verified;
  bool get isOpen => !isDone && this != cancelled;

  /// Server-validated state machine (ARCHITECTURE.md): `queued → assigned →
  /// in_progress ⇄ blocked → completed → verified`.
  bool canTransitionTo(WorkStatus to) => switch (this) {
    queued => to == assigned || to == inProgress || to == cancelled,
    assigned => to == inProgress || to == blocked || to == cancelled,
    inProgress => to == blocked || to == completed || to == cancelled,
    blocked => to == inProgress || to == cancelled,
    completed => to == verified || to == inProgress,
    verified => false,
    cancelled => false,
  };
}

enum StepStatus implements SparklingEnum {
  pending('pending'),
  done('done'),
  blocked('blocked'),
  skipped('skipped');

  const StepStatus(this.db);
  @override
  final String db;
  static StepStatus fromDb(String? v) => _find(values, v, pending);
}

enum StepType implements SparklingEnum {
  confirm('confirm'),
  text('text'),
  numeric('numeric'),
  select('select'),
  photo('photo'),
  ack('ack'),
  supervisorVerify('supervisor_verify');

  const StepType(this.db);
  @override
  final String db;
  static StepType fromDb(String? v) => _find(values, v, confirm);
}

enum PaymentStatus implements SparklingEnum {
  initiated('initiated'),
  pending('pending'),
  successful('successful'),
  failed('failed'),
  cancelled('cancelled'),
  refunded('refunded');

  const PaymentStatus(this.db);
  @override
  final String db;
  static PaymentStatus fromDb(String? v) => _find(values, v, initiated);

  String get label => switch (this) {
    initiated => 'Initiated',
    pending => 'Pending',
    successful => 'Paid',
    failed => 'Failed',
    cancelled => 'Cancelled',
    refunded => 'Refunded',
  };

  /// CUS-041: only webhook-confirmed payments count as paid.
  bool get isVerified => this == successful;
}

enum LoyaltyTier implements SparklingEnum {
  silver('silver'),
  gold('gold'),
  platinum('platinum');

  const LoyaltyTier(this.db);
  @override
  final String db;
  static LoyaltyTier fromDb(String? v) => _find(values, v, silver);

  String get label => switch (this) {
    silver => 'Silver',
    gold => 'Gold',
    platinum => 'Platinum',
  };

  LoyaltyTier? get next => switch (this) {
    silver => gold,
    gold => platinum,
    platinum => null,
  };
}

enum LedgerType implements SparklingEnum {
  earn('earn'),
  redeem('redeem'),
  adjust('adjust'),
  expire('expire'),
  bonus('bonus');

  const LedgerType(this.db);
  @override
  final String db;
  static LedgerType fromDb(String? v) => _find(values, v, earn);

  String get label => switch (this) {
    earn => 'earn',
    redeem => 'redemption',
    adjust => 'adjustment',
    expire => 'expiry',
    bonus => 'bonus',
  };
}

enum InventoryReason implements SparklingEnum {
  usage('usage'),
  receive('receive'),
  adjust('adjust'),
  reorderRequest('reorder_request'),
  count('count');

  const InventoryReason(this.db);
  @override
  final String db;
  static InventoryReason fromDb(String? v) => _find(values, v, usage);

  /// STF-042: technicians may only log usage / request reorders.
  bool get technicianAllowed => this == usage || this == reorderRequest;
}

enum AlertLevel implements SparklingEnum {
  low('low'),
  out('out');

  const AlertLevel(this.db);
  @override
  final String db;
  static AlertLevel fromDb(String? v) => _find(values, v, low);
}

enum AlertStatus implements SparklingEnum {
  open('open'),
  acknowledged('acknowledged'),
  resolved('resolved');

  const AlertStatus(this.db);
  @override
  final String db;
  static AlertStatus fromDb(String? v) => _find(values, v, open);
}

enum NotifyChannel implements SparklingEnum {
  push('push'),
  whatsapp('whatsapp'),
  sms('sms'),
  email('email');

  const NotifyChannel(this.db);
  @override
  final String db;
  static NotifyChannel fromDb(String? v) => _find(values, v, push);
}

enum NotifyStatus implements SparklingEnum {
  queued('queued'),
  sent('sent'),
  delivered('delivered'),
  failed('failed'),
  suppressed('suppressed');

  const NotifyStatus(this.db);
  @override
  final String db;
  static NotifyStatus fromDb(String? v) => _find(values, v, queued);
}

enum ConfigStatus implements SparklingEnum {
  draft('draft'),
  published('published'),
  archived('archived');

  const ConfigStatus(this.db);
  @override
  final String db;
  static ConfigStatus fromDb(String? v) => _find(values, v, draft);
}

enum SyncStatus implements SparklingEnum {
  pending('pending'),
  applied('applied'),
  conflict('conflict'),
  rejected('rejected');

  const SyncStatus(this.db);
  @override
  final String db;
  static SyncStatus fromDb(String? v) => _find(values, v, pending);
}

/// `staff_availability.status`
enum AvailabilityStatus implements SparklingEnum {
  available('available'),
  busy('busy'),
  onBreak('break'),
  off('off');

  const AvailabilityStatus(this.db);
  @override
  final String db;
  static AvailabilityStatus fromDb(String? v) => _find(values, v, available);

  String get label => switch (this) {
    available => 'Available',
    busy => 'Busy',
    onBreak => 'On break',
    off => 'Off',
  };
}

/// `GET /tasks?scope=`
enum TaskScope { mine, queue, done }

/// `GET /staff/leaderboard?period=`
enum LeaderboardPeriod { week, month }
