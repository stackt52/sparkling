import 'dart:async';
import 'dart:math' as math;

import '../api/api_exception.dart';
import '../auth/auth_service.dart';
import '../models/models.dart';
import '../models/json.dart' as j;

/// Emitted by [DemoStore.changes] after every mutation.
class DemoChange {
  const DemoChange(this.table, {this.id});
  final String table;
  final String? id;
  @override
  String toString() => 'DemoChange($table${id == null ? '' : ' $id'})';
}

/// In-memory data mirroring `backend/supabase/seed.sql` (today-relative), with
/// the same server-side rules the API enforces (state machines, RBAC,
/// duplicate vehicles, stock never negative, idempotent loyalty awards).
///
/// Every mutation emits on [changes] so demo `watch*` streams update.
class DemoStore {
  DemoStore({AuthUser? currentUser, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      currentUser = currentUser ?? DemoAuthService.demoCustomer {
    _seed();
  }

  final DateTime Function() _clock;

  /// The signed-in persona (switch with [signInAs]).
  AuthUser currentUser;

  final StreamController<DemoChange> _changes = StreamController.broadcast();
  Stream<DemoChange> get changes => _changes.stream;

  DateTime get now => _clock();

  /// Today 10:00 local — the seed's anchor ("ten").
  DateTime get ten {
    final n = now;
    return DateTime(n.year, n.month, n.day, 10);
  }

  String get uid => currentUser.uid;
  UserRole get role => currentUser.role;

  void signInAs(AuthUser user) {
    currentUser = user;
    _notify('session');
  }

  void _notify(String table, [String? id]) {
    if (!_changes.isClosed) _changes.add(DemoChange(table, id: id));
  }

  void dispose() => _changes.close();

  // ---------------------------------------------------------------------------
  // Ids
  // ---------------------------------------------------------------------------

  static const String outletSandton = 'a0000000-0000-4000-8000-000000000001';
  static const String outletRosebank = 'a0000000-0000-4000-8000-000000000002';
  static const String outletCenturion = 'a0000000-0000-4000-8000-000000000003';

  static const String tplValet = 'c0000000-0000-4000-8000-000000000001';
  static const String tplExpress = 'c0000000-0000-4000-8000-000000000002';
  static const String tplBody = 'c0000000-0000-4000-8000-000000000003';

  static const String svcExpress = 'b0000000-0000-4000-8000-000000000001';
  static const String svcValet = 'b0000000-0000-4000-8000-000000000002';
  static const String svcDetail = 'b0000000-0000-4000-8000-000000000003';
  static const String svcInterior = 'b0000000-0000-4000-8000-000000000004';
  static const String svcDent = 'b0000000-0000-4000-8000-000000000011';
  static const String svcScratch = 'b0000000-0000-4000-8000-000000000012';
  static const String svcBumper = 'b0000000-0000-4000-8000-000000000013';
  static const String svcPanel = 'b0000000-0000-4000-8000-000000000014';

  static const String vehCorolla = 'd0000000-0000-4000-8000-000000000001';
  static const String vehPolo = 'd0000000-0000-4000-8000-000000000002';
  static const String vehSwift = 'd0000000-0000-4000-8000-000000000003';
  static const String vehHilux = 'd0000000-0000-4000-8000-000000000004';
  static const String vehBmw = 'd0000000-0000-4000-8000-000000000005';

  static const String bookingInService =
      '10000000-0000-4000-8000-000000000001'; // SPK-2026-0091
  static const String bookingNext =
      '10000000-0000-4000-8000-000000000002'; // SPK-2026-0094
  static const String woInService =
      '30000000-0000-4000-8000-000000000001'; // WO-2026-4821
  static const String taskInService = '40000000-0000-4000-8000-000000000001';
  static const String quotationQuoted =
      '20000000-0000-4000-8000-000000000001'; // QT-2026-0041

  int _bookingSeq = 97;
  int _quotationSeq = 43;
  int _workOrderSeq = 4825;
  int _receiptSeq = 70006;
  int _redemptionSeq = 1183;
  int _idSeq = 1;

  String _newId(String prefix) =>
      '${prefix}0000-0000-4000-8000-${(_idSeq++).toString().padLeft(12, '0')}';
  String _year() => now.year.toString();

  // ---------------------------------------------------------------------------
  // Tables
  // ---------------------------------------------------------------------------

  final List<Outlet> outlets = [];
  final List<Service> services = [];
  final Map<String, Map<String, ({int? priceCents, bool isAvailable})>>
  outletServiceOverrides = {};
  final List<ChecklistTemplate> templates = [];
  final Map<String, Profile> profiles = {};
  final Map<String, List<String>> staffOutlets = {};
  final Map<String, List<String>> staffSkills = {};
  final Map<String, ({AvailabilityStatus status, int capacity})>
  staffAvailability = {};
  final List<Vehicle> vehicles = [];
  final List<Booking> bookings = [];
  final List<Quotation> quotations = [];
  final List<WorkOrder> workOrders = [];
  final List<Task> tasks = [];
  final List<StepResult> stepResults = [];
  final List<TaskEvent> taskEvents = [];
  final List<PaymentMethod> paymentMethods = [];
  final List<Payment> payments = [];
  final List<LedgerEntry> loyaltyLedger = [];
  final Map<String, ({LoyaltyTier tier, DateTime tierSince})> loyaltyTiers = {};
  final List<Reward> rewards = [];
  final List<RewardRedemption> redemptions = [];
  final List<Badge> badges = [];
  final Map<String, Map<String, DateTime>> staffBadges = {};
  final List<InventoryItem> inventoryItems = [];
  final List<InventoryAlert> inventoryAlerts = [];
  final List<InventoryMovement> inventoryMovements = [];
  final List<
    ({
      String staffId,
      String outletId,
      int delta,
      String eventType,
      String key,
      DateTime at,
    })
  >
  staffPoints = [];
  final List<AppNotification> notifications = [];
  late LoyaltyConfig loyaltyConfig;
  late LoyaltyConfig loyaltyDraft;
  final Map<String, bool> featureFlags = {};
  final Set<String> _idempotencyKeys = {};

  // ---------------------------------------------------------------------------
  // Seed (mirrors seed.sql)
  // ---------------------------------------------------------------------------

  void _seed() {
    final t = ten;
    final n = now;

    outlets.addAll([
      Outlet(
        id: outletSandton,
        code: 'SAN',
        name: 'Sparkling Sandton',
        addressLine: '14 Rivonia Rd, Sandton',
        city: 'Johannesburg',
        province: 'Gauteng',
        latitude: -26.1076,
        longitude: 28.0567,
        phone: '+27 11 555 0101',
        email: 'sandton@sparkling.co.za',
        bayCount: 4,
        rating: 4.8,
        openingHours: _defaultHours,
        distanceKm: 2.1,
      ),
      Outlet(
        id: outletRosebank,
        code: 'ROS',
        name: 'Sparkling Rosebank',
        addressLine: 'Cradock Ave, Rosebank',
        city: 'Johannesburg',
        province: 'Gauteng',
        latitude: -26.1450,
        longitude: 28.0430,
        phone: '+27 11 555 0102',
        email: 'rosebank@sparkling.co.za',
        bayCount: 3,
        rating: 4.7,
        openingHours: _defaultHours,
        distanceKm: 5.4,
      ),
      Outlet(
        id: outletCenturion,
        code: 'CEN',
        name: 'Sparkling Centurion',
        addressLine: 'Lenchen Ave, Centurion',
        city: 'Centurion',
        province: 'Gauteng',
        latitude: -25.8600,
        longitude: 28.1890,
        phone: '+27 12 555 0103',
        email: 'centurion@sparkling.co.za',
        bayCount: 3,
        rating: 4.6,
        openingHours: _defaultHours,
        distanceKm: 31.0,
      ),
    ]);

    templates.addAll([
      ChecklistTemplate(
        id: tplValet,
        name: 'Full valet checklist',
        category: ServiceCategory.carWash,
        version: 3,
        steps: const [
          ChecklistStep(
            key: 'prewash',
            title: 'Pre-wash inspection',
            type: StepType.photo,
            required: true,
            hint: 'Photograph all four sides before starting',
            photoRequired: true,
          ),
          ChecklistStep(
            key: 'exterior',
            title: 'Exterior wash & rinse',
            type: StepType.confirm,
            required: true,
          ),
          ChecklistStep(
            key: 'wheels',
            title: 'Wheels, arches & tyre shine',
            type: StepType.confirm,
            required: true,
          ),
          ChecklistStep(
            key: 'interior',
            title: 'Interior vacuum & dash',
            type: StepType.confirm,
            required: true,
            hint: 'Include boot and door pockets',
          ),
          ChecklistStep(
            key: 'windows',
            title: 'Windows inside & out',
            type: StepType.confirm,
            required: true,
          ),
          ChecklistStep(
            key: 'tyre_pressure',
            title: 'Tyre pressure check',
            type: StepType.numeric,
            required: true,
            unit: 'bar',
            min: 1.5,
            max: 3.5,
            hint: 'Record front-left pressure',
          ),
          ChecklistStep(
            key: 'supervisor',
            title: 'Supervisor verification',
            type: StepType.supervisorVerify,
            required: true,
            hint: 'Locked until all required steps pass',
          ),
        ],
      ),
      ChecklistTemplate(
        id: tplExpress,
        name: 'Express wash checklist',
        category: ServiceCategory.carWash,
        version: 2,
        steps: const [
          ChecklistStep(
            key: 'exterior',
            title: 'Exterior wash & rinse',
            type: StepType.confirm,
            required: true,
          ),
          ChecklistStep(
            key: 'wheels',
            title: 'Wheels & tyres',
            type: StepType.confirm,
            required: true,
          ),
          ChecklistStep(
            key: 'dry',
            title: 'Hand dry & windows',
            type: StepType.confirm,
            required: true,
          ),
          ChecklistStep(
            key: 'supervisor',
            title: 'Supervisor verification',
            type: StepType.supervisorVerify,
            required: false,
          ),
        ],
      ),
      ChecklistTemplate(
        id: tplBody,
        name: 'Auto body repair checklist',
        category: ServiceCategory.autoBody,
        version: 1,
        steps: const [
          ChecklistStep(
            key: 'intake',
            title: 'Damage intake photos',
            type: StepType.photo,
            required: true,
            photoRequired: true,
          ),
          ChecklistStep(
            key: 'prep',
            title: 'Panel prep & masking',
            type: StepType.confirm,
            required: true,
          ),
          ChecklistStep(
            key: 'repair',
            title: 'Repair / filler / sanding',
            type: StepType.confirm,
            required: true,
          ),
          ChecklistStep(
            key: 'paint',
            title: 'Paint & clear coat',
            type: StepType.select,
            required: true,
            options: ['Spot', 'Panel', 'Blend'],
          ),
          ChecklistStep(
            key: 'cure',
            title: 'Cure time (hours)',
            type: StepType.numeric,
            required: true,
            unit: 'h',
            min: 1,
            max: 48,
          ),
          ChecklistStep(
            key: 'polish',
            title: 'Polish & final photos',
            type: StepType.photo,
            required: true,
            photoRequired: true,
          ),
          ChecklistStep(
            key: 'supervisor',
            title: 'Supervisor verification',
            type: StepType.supervisorVerify,
            required: true,
          ),
        ],
      ),
    ]);

    services.addAll([
      const Service(
        id: svcExpress,
        code: 'EXPRESS',
        name: 'Express Wash',
        description: 'Exterior wash, wheels and hand dry',
        category: ServiceCategory.carWash,
        durationMinutes: 20,
        basePriceCents: 12000,
        icon: 'water_drop',
        checklistTemplateId: tplExpress,
        sortOrder: 10,
      ),
      const Service(
        id: svcValet,
        code: 'VALET',
        name: 'Full Valet',
        description: 'Exterior + interior vacuum, dash and windows',
        category: ServiceCategory.carWash,
        durationMinutes: 60,
        basePriceCents: 22000,
        icon: 'local_car_wash',
        checklistTemplateId: tplValet,
        sortOrder: 20,
      ),
      const Service(
        id: svcDetail,
        code: 'DETAIL',
        name: 'Premium Detail',
        description: 'Clay bar, polish, wax and full interior detail',
        category: ServiceCategory.carWash,
        durationMinutes: 120,
        basePriceCents: 45000,
        icon: 'auto_awesome',
        checklistTemplateId: tplValet,
        sortOrder: 30,
      ),
      const Service(
        id: svcInterior,
        code: 'INTERIOR',
        name: 'Interior Deep Clean',
        description: 'Seats, carpets and upholstery shampoo',
        category: ServiceCategory.carWash,
        durationMinutes: 90,
        basePriceCents: 28000,
        icon: 'cleaning_services',
        checklistTemplateId: tplValet,
        sortOrder: 40,
      ),
      const Service(
        id: svcDent,
        code: 'DENT',
        name: 'Dent removal',
        description: 'Paintless dent removal',
        category: ServiceCategory.autoBody,
        durationMinutes: 240,
        isQuoteBased: true,
        icon: 'car_crash',
        checklistTemplateId: tplBody,
        sortOrder: 110,
      ),
      const Service(
        id: svcScratch,
        code: 'SCRATCH',
        name: 'Scratch repair',
        description: 'Scratch and scuff repair with blend',
        category: ServiceCategory.autoBody,
        durationMinutes: 240,
        isQuoteBased: true,
        icon: 'car_crash',
        checklistTemplateId: tplBody,
        sortOrder: 120,
      ),
      const Service(
        id: svcBumper,
        code: 'BUMPER',
        name: 'Bumper repair',
        description: 'Plastic bumper repair and respray',
        category: ServiceCategory.autoBody,
        durationMinutes: 480,
        isQuoteBased: true,
        icon: 'car_crash',
        checklistTemplateId: tplBody,
        sortOrder: 130,
      ),
      const Service(
        id: svcPanel,
        code: 'PANEL',
        name: 'Panel respray',
        description: 'Single panel respray',
        category: ServiceCategory.autoBody,
        durationMinutes: 960,
        isQuoteBased: true,
        icon: 'car_crash',
        checklistTemplateId: tplBody,
        sortOrder: 140,
      ),
    ]);
    outletServiceOverrides[outletSandton] = {
      svcValet: (priceCents: 24000, isAvailable: true),
    };
    outletServiceOverrides[outletCenturion] = {
      svcPanel: (priceCents: null, isAvailable: false),
    };

    void person(
      String id,
      UserRole role,
      String name,
      String email,
      String phone, {
      bool marketing = false,
    }) {
      profiles[id] = Profile(
        id: id,
        role: role,
        fullName: name,
        email: email,
        phone: phone,
        marketingOptIn: marketing,
        createdAt: n.subtract(const Duration(days: 200)),
      );
    }

    person(
      'seed_admin',
      UserRole.admin,
      'Sparkling Admin',
      'admin@sparkling.co.za',
      '+27 82 000 0001',
    );
    person(
      'seed_finance',
      UserRole.finance,
      'Nomvula Finance',
      'finance@sparkling.co.za',
      '+27 82 000 0002',
    );
    person(
      'seed_ayesha',
      UserRole.manager,
      'Ayesha Patel',
      'ayesha@sparkling.co.za',
      '+27 82 000 0010',
    );
    person(
      'seed_johan',
      UserRole.supervisor,
      'Johan Botha',
      'johan@sparkling.co.za',
      '+27 82 000 0011',
    );
    person(
      'seed_pieter',
      UserRole.technician,
      'Pieter van der Merwe',
      'pieter@sparkling.co.za',
      '+27 82 000 0012',
    );
    person(
      'seed_lerato',
      UserRole.technician,
      'Lerato Mahlangu',
      'lerato@sparkling.co.za',
      '+27 82 000 0013',
    );
    person(
      'seed_sipho_staff',
      UserRole.technician,
      'Sipho Ndlovu',
      'sipho.n@sparkling.co.za',
      '+27 82 000 0014',
    );
    person(
      'seed_thandi',
      UserRole.technician,
      'Thandi Khumalo',
      'thandi@sparkling.co.za',
      '+27 82 000 0015',
    );
    person(
      'seed_thabo',
      UserRole.customer,
      'Thabo Nkosi',
      'thabo@example.com',
      '+27 83 111 2222',
      marketing: true,
    );
    person(
      'seed_naledi',
      UserRole.customer,
      'Naledi Mokoena',
      'naledi@example.com',
      '+27 83 111 3333',
    );
    person(
      'seed_sipho',
      UserRole.customer,
      'Sipho Dlamini',
      'sipho@example.com',
      '+27 83 111 4444',
      marketing: true,
    );
    person(
      'seed_zanele',
      UserRole.customer,
      'Zanele Mthembu',
      'zanele@example.com',
      '+27 83 111 5555',
      marketing: true,
    );

    staffOutlets.addAll({
      'seed_ayesha': [outletSandton, outletRosebank],
      'seed_johan': [outletSandton],
      'seed_pieter': [outletSandton],
      'seed_lerato': [outletSandton],
      'seed_sipho_staff': [outletSandton],
      'seed_thandi': [outletRosebank],
      'seed_admin': [outletSandton, outletRosebank, outletCenturion],
      'seed_finance': [outletSandton, outletRosebank, outletCenturion],
    });
    staffSkills.addAll({
      'seed_pieter': ['wash', 'detail'],
      'seed_lerato': ['wash', 'interior'],
      'seed_sipho_staff': ['wash', 'paint', 'panel'],
      'seed_thandi': ['wash'],
      'seed_johan': ['wash', 'detail', 'paint'],
    });
    staffAvailability.addAll({
      'seed_pieter': (status: AvailabilityStatus.available, capacity: 3),
      'seed_lerato': (status: AvailabilityStatus.busy, capacity: 3),
      'seed_sipho_staff': (status: AvailabilityStatus.busy, capacity: 2),
      'seed_thandi': (status: AvailabilityStatus.available, capacity: 3),
      'seed_johan': (status: AvailabilityStatus.available, capacity: 5),
    });

    vehicles.addAll([
      Vehicle(
        id: vehCorolla,
        customerId: 'seed_thabo',
        registrationNo: 'KL 45 MN GP',
        vin: 'AHTFB3CB301234567',
        make: 'Toyota',
        model: 'Corolla Cross',
        colour: 'Celestite Grey',
        year: 2023,
        licenceNo: 'ABC123456',
        discExpiry: DateTime(2027, 3, 31),
        source: VehicleSource.scan,
        discVerified: true,
      ),
      Vehicle(
        id: vehPolo,
        customerId: 'seed_thabo',
        registrationNo: 'CJ 12 PZ GP',
        vin: 'WVWZZZ1KZ9W654321',
        make: 'Volkswagen',
        model: 'Polo Vivo',
        colour: 'Reflex Silver',
        year: 2019,
        discExpiry: DateTime(2026, 11, 30),
        source: VehicleSource.manual,
      ),
      Vehicle(
        id: vehSwift,
        customerId: 'seed_naledi',
        registrationNo: 'HR 88 TS GP',
        vin: 'MA3FB1B4200123456',
        make: 'Suzuki',
        model: 'Swift',
        colour: 'Pearl Arctic White',
        year: 2022,
        licenceNo: 'SW0091234',
        discExpiry: DateTime(2027, 1, 31),
        source: VehicleSource.scan,
        discVerified: true,
      ),
      Vehicle(
        id: vehHilux,
        customerId: 'seed_sipho',
        registrationNo: 'DN 07 KX GP',
        vin: 'SB1KZ3BE10E234567',
        make: 'Toyota',
        model: 'Hilux',
        colour: 'Glacier White',
        year: 2021,
        licenceNo: 'HX7711223',
        discExpiry: DateTime(2026, 10, 15),
        source: VehicleSource.scan,
        discVerified: true,
      ),
      Vehicle(
        id: vehBmw,
        customerId: 'seed_zanele',
        registrationNo: 'BW 33 RG GP',
        vin: 'WBA5R1C50KA112233',
        make: 'BMW',
        model: '330i',
        colour: 'Portimao Blue',
        year: 2020,
        licenceNo: 'BM4451122',
        discExpiry: DateTime(2027, 5, 31),
        source: VehicleSource.scan,
        discVerified: true,
      ),
    ]);

    const tiers = [
      LoyaltyTierConfig(
        tier: LoyaltyTier.silver,
        name: 'Silver',
        minPoints: 0,
        maxPoints: 499,
        earnMultiplier: 1.0,
        discountPct: 0,
      ),
      LoyaltyTierConfig(
        tier: LoyaltyTier.gold,
        name: 'Gold',
        minPoints: 500,
        maxPoints: 1999,
        earnMultiplier: 1.25,
        discountPct: 10,
      ),
      LoyaltyTierConfig(
        tier: LoyaltyTier.platinum,
        name: 'Platinum',
        minPoints: 2000,
        earnMultiplier: 1.5,
        discountPct: 15,
      ),
    ];
    loyaltyConfig = LoyaltyConfig(
      id: 'e0000000-0000-4000-8000-000000000014',
      version: 14,
      status: ConfigStatus.published,
      tiers: tiers,
      rules: const LoyaltyRules(
        pointsPerRand: 0.10,
        expiryMonths: 24,
        birthdayBonus: BonusRule(
          enabled: false,
          points: 100,
          reason: 'Pending consent review (ADM-042)',
        ),
        referralBonus: BonusRule(enabled: true, points: 150),
      ),
      changeNote: 'Baseline tiers and earn rules',
      createdBy: 'seed_admin',
      publishedBy: 'seed_admin',
      publishedAt: n.subtract(const Duration(days: 40)),
    );
    loyaltyDraft = loyaltyConfig.copyWith(
      version: 15,
      status: ConfigStatus.draft,
      rules: loyaltyConfig.rules.copyWith(
        pointsPerRand: 0.12,
        referralBonus: const BonusRule(enabled: true, points: 200),
      ),
      changeNote: 'Raise earn rate to 0.12/R and referral bonus to 200',
    );

    rewards.addAll(const [
      Reward(
        id: 'f0000000-0000-4000-8000-000000000001',
        name: 'Free Express Wash',
        description: 'One express wash at any outlet',
        icon: 'water_drop',
        pointsCost: 600,
        minTier: LoyaltyTier.silver,
        sortOrder: 10,
      ),
      Reward(
        id: 'f0000000-0000-4000-8000-000000000002',
        name: 'Interior refresh',
        description: 'Add-on interior vacuum and dash wipe',
        icon: 'cleaning_services',
        pointsCost: 350,
        minTier: LoyaltyTier.silver,
        sortOrder: 20,
      ),
      Reward(
        id: 'f0000000-0000-4000-8000-000000000003',
        name: 'Full Valet upgrade',
        description: 'Upgrade any Express to a Full Valet',
        icon: 'local_car_wash',
        pointsCost: 900,
        minTier: LoyaltyTier.gold,
        sortOrder: 30,
      ),
      Reward(
        id: 'f0000000-0000-4000-8000-000000000004',
        name: 'Premium Detail R150 off',
        description: 'Discount voucher for Premium Detail',
        icon: 'auto_awesome',
        pointsCost: 1200,
        minTier: LoyaltyTier.gold,
        sortOrder: 40,
      ),
      Reward(
        id: 'f0000000-0000-4000-8000-000000000005',
        name: 'Priority bay',
        description: 'Skip the queue on your next visit',
        icon: 'bolt',
        pointsCost: 400,
        minTier: LoyaltyTier.platinum,
        sortOrder: 50,
      ),
    ]);

    badges.addAll(const [
      Badge(
        id: '90000000-0000-4000-8000-000000000001',
        code: 'FIRST_50',
        name: 'Half century',
        description: 'Complete 50 tasks',
        icon: 'military_tech',
        colour: '#E2BA5F',
      ),
      Badge(
        id: '90000000-0000-4000-8000-000000000002',
        code: 'STREAK_5',
        name: 'On a roll',
        description: '5 verified tasks in a row',
        icon: 'local_fire_department',
        colour: '#FF7A59',
      ),
      Badge(
        id: '90000000-0000-4000-8000-000000000003',
        code: 'SPOTLESS',
        name: 'Spotless',
        description: '10 checklists with zero blocked steps',
        icon: 'verified',
        colour: '#1D8A4E',
      ),
      Badge(
        id: '90000000-0000-4000-8000-000000000004',
        code: 'SCANNER',
        name: 'Sharp eye',
        description: '25 disc scans verified',
        icon: 'qr_code_scanner',
        colour: '#00A0E0',
      ),
      Badge(
        id: '90000000-0000-4000-8000-000000000005',
        code: 'MENTOR',
        name: 'Mentor',
        description: 'Verify 20 colleague checklists',
        icon: 'groups',
        colour: '#8BD2FF',
      ),
      Badge(
        id: '90000000-0000-4000-8000-000000000006',
        code: 'TOP_MONTH',
        name: 'Top of the month',
        description: 'Finish #1 on a monthly leaderboard',
        icon: 'social_leaderboard',
        colour: '#F3DDA4',
      ),
    ]);
    staffBadges['seed_pieter'] = {
      '90000000-0000-4000-8000-000000000001': n.subtract(
        const Duration(days: 20),
      ),
      '90000000-0000-4000-8000-000000000002': n.subtract(
        const Duration(days: 3),
      ),
      '90000000-0000-4000-8000-000000000004': n.subtract(
        const Duration(days: 12),
      ),
    };
    staffBadges['seed_lerato'] = {
      '90000000-0000-4000-8000-000000000001': n.subtract(
        const Duration(days: 30),
      ),
      '90000000-0000-4000-8000-000000000003': n.subtract(
        const Duration(days: 6),
      ),
    };
    staffBadges['seed_sipho_staff'] = {
      '90000000-0000-4000-8000-000000000001': n.subtract(
        const Duration(days: 50),
      ),
    };

    featureFlags.addAll({
      'payments_sandbox': true,
      'whatsapp_enabled': false,
      'auto_assignment': true,
      'birthday_bonus': false,
    });

    // ---- Bookings --------------------------------------------------------------
    bookings.addAll([
      Booking(
        id: bookingInService,
        ref: 'SPK-$_yr-0091',
        customerId: 'seed_thabo',
        vehicleId: vehCorolla,
        outletId: outletSandton,
        serviceId: svcValet,
        slotStart: t,
        slotEnd: t.add(const Duration(minutes: 60)),
        status: BookingStatus.inService,
        priceCents: 22000,
        discountCents: 2200,
        totalCents: 19800,
        discountLabel: 'Gold −10%',
        pointsPending: 20,
        clientOpId: 'seed-op-0091',
        createdAt: n.subtract(const Duration(days: 2)),
      ),
      Booking(
        id: bookingNext,
        ref: 'SPK-$_yr-0094',
        customerId: 'seed_thabo',
        vehicleId: vehPolo,
        outletId: outletRosebank,
        serviceId: svcExpress,
        slotStart: t.add(const Duration(hours: 23)),
        slotEnd: t.add(const Duration(hours: 23, minutes: 20)),
        status: BookingStatus.confirmed,
        priceCents: 12000,
        discountCents: 1200,
        totalCents: 10800,
        discountLabel: 'Gold −10%',
        pointsPending: 11,
        clientOpId: 'seed-op-0094',
        createdAt: n.subtract(const Duration(hours: 3)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000003',
        ref: 'SPK-$_yr-0067',
        customerId: 'seed_thabo',
        vehicleId: vehCorolla,
        outletId: outletSandton,
        serviceId: svcDetail,
        slotStart: t.subtract(const Duration(days: 21)),
        slotEnd: t
            .subtract(const Duration(days: 21))
            .add(const Duration(minutes: 120)),
        status: BookingStatus.completed,
        priceCents: 45000,
        discountCents: 4500,
        totalCents: 40500,
        discountLabel: 'Gold −10%',
        clientOpId: 'seed-op-0067',
        createdAt: n.subtract(const Duration(days: 24)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000004',
        ref: 'SPK-$_yr-0052',
        customerId: 'seed_thabo',
        vehicleId: vehPolo,
        outletId: outletSandton,
        serviceId: svcExpress,
        slotStart: t.subtract(const Duration(days: 38)),
        slotEnd: t
            .subtract(const Duration(days: 38))
            .add(const Duration(minutes: 20)),
        status: BookingStatus.completed,
        priceCents: 12000,
        totalCents: 12000,
        clientOpId: 'seed-op-0052',
        createdAt: n.subtract(const Duration(days: 40)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000005',
        ref: 'SPK-$_yr-0092',
        customerId: 'seed_naledi',
        vehicleId: vehSwift,
        outletId: outletSandton,
        serviceId: svcExpress,
        slotStart: t.subtract(const Duration(minutes: 90)),
        slotEnd: t.subtract(const Duration(minutes: 70)),
        status: BookingStatus.completed,
        priceCents: 12000,
        totalCents: 12000,
        pointsPending: 12,
        clientOpId: 'seed-op-0092',
        createdAt: n.subtract(const Duration(hours: 5)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000006',
        ref: 'SPK-$_yr-0093',
        customerId: 'seed_sipho',
        vehicleId: vehHilux,
        outletId: outletSandton,
        serviceId: svcInterior,
        slotStart: t.add(const Duration(minutes: 30)),
        slotEnd: t.add(const Duration(minutes: 120)),
        status: BookingStatus.confirmed,
        priceCents: 28000,
        totalCents: 28000,
        pointsPending: 28,
        clientOpId: 'seed-op-0093',
        createdAt: n.subtract(const Duration(days: 1)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000007',
        ref: 'SPK-$_yr-0095',
        customerId: 'seed_zanele',
        vehicleId: vehBmw,
        outletId: outletSandton,
        serviceId: svcDetail,
        slotStart: t.add(const Duration(hours: 2)),
        slotEnd: t.add(const Duration(hours: 4)),
        status: BookingStatus.confirmed,
        priceCents: 45000,
        discountCents: 6750,
        totalCents: 38250,
        discountLabel: 'Platinum −15%',
        pointsPending: 68,
        clientOpId: 'seed-op-0095',
        createdAt: n.subtract(const Duration(hours: 1)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000008',
        ref: 'SPK-$_yr-0096',
        customerId: 'seed_naledi',
        vehicleId: vehSwift,
        outletId: outletRosebank,
        serviceId: svcValet,
        slotStart: t.add(const Duration(hours: 3)),
        slotEnd: t.add(const Duration(hours: 4)),
        status: BookingStatus.pending,
        priceCents: 22000,
        totalCents: 22000,
        pointsPending: 22,
        clientOpId: 'seed-op-0096',
        createdAt: n.subtract(const Duration(minutes: 20)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000009',
        ref: 'SPK-$_yr-0090',
        customerId: 'seed_sipho',
        vehicleId: vehHilux,
        outletId: outletSandton,
        serviceId: svcExpress,
        slotStart: t.subtract(const Duration(hours: 3)),
        slotEnd: t.subtract(const Duration(minutes: 160)),
        status: BookingStatus.cancelled,
        priceCents: 12000,
        totalCents: 12000,
        cancelReason: 'Customer request',
        clientOpId: 'seed-op-0090',
        createdAt: n.subtract(const Duration(days: 1)),
      ),
    ]);

    // ---- Quotations ------------------------------------------------------------
    quotations.addAll([
      Quotation(
        id: quotationQuoted,
        ref: 'QT-$_yr-0041',
        customerId: 'seed_thabo',
        vehicleId: vehCorolla,
        outletId: outletSandton,
        category: 'Bumper',
        description:
            'Rear bumper scuffed in parking lot, paint cracked on left corner.',
        status: QuotationStatus.quoted,
        amountCents: 385000,
        lineItems: const [
          LineItem(label: 'Bumper repair & respray', amountCents: 320000),
          LineItem(label: 'Blend to quarter panel', amountCents: 65000),
        ],
        assessorId: 'seed_sipho_staff',
        assessorName: 'Sipho Ndlovu',
        validUntil: n.add(const Duration(days: 14)),
        quotedAt: n.subtract(const Duration(days: 1)),
        clientOpId: 'seed-op-qt41',
        createdAt: n.subtract(const Duration(days: 3)),
        vehicleLabel: 'Corolla Cross · KL 45 MN GP',
        outletName: 'Sparkling Sandton',
      ),
      Quotation(
        id: '20000000-0000-4000-8000-000000000002',
        ref: 'QT-$_yr-0042',
        customerId: 'seed_zanele',
        vehicleId: vehBmw,
        outletId: outletSandton,
        category: 'Dent',
        description: 'Door ding on driver door, no paint damage.',
        status: QuotationStatus.requested,
        clientOpId: 'seed-op-qt42',
        createdAt: n.subtract(const Duration(hours: 6)),
        vehicleLabel: '330i · BW 33 RG GP',
        outletName: 'Sparkling Sandton',
      ),
      Quotation(
        id: '20000000-0000-4000-8000-000000000003',
        ref: 'QT-$_yr-0038',
        customerId: 'seed_sipho',
        vehicleId: vehHilux,
        outletId: outletSandton,
        category: 'Scratch',
        description: 'Key scratch along passenger side.',
        status: QuotationStatus.accepted,
        amountCents: 210000,
        lineItems: const [
          LineItem(label: 'Scratch repair & blend', amountCents: 210000),
        ],
        assessorId: 'seed_sipho_staff',
        assessorName: 'Sipho Ndlovu',
        validUntil: n.add(const Duration(days: 7)),
        quotedAt: n.subtract(const Duration(days: 4)),
        decidedAt: n.subtract(const Duration(days: 2)),
        decisionBy: 'seed_sipho',
        clientOpId: 'seed-op-qt38',
        createdAt: n.subtract(const Duration(days: 6)),
        vehicleLabel: 'Hilux · DN 07 KX GP',
        outletName: 'Sparkling Sandton',
      ),
    ]);

    // ---- Work orders / tasks ---------------------------------------------------
    workOrders.addAll([
      WorkOrder(
        id: woInService,
        ref: 'WO-$_yr-4821',
        outletId: outletSandton,
        bookingId: bookingInService,
        vehicleId: vehCorolla,
        customerId: 'seed_thabo',
        serviceId: svcValet,
        status: WorkStatus.inProgress,
        priority: 1,
        bay: 'Bay 2',
        checklistTemplateId: tplValet,
        templateVersion: 3,
        assigneeId: 'seed_pieter',
        assigneeName: 'Pieter van der Merwe',
        etaAt: t.add(const Duration(minutes: 55)),
        startedAt: t.add(const Duration(minutes: 5)),
        dueAt: t.add(const Duration(minutes: 60)),
        createdAt: t.subtract(const Duration(minutes: 20)),
      ),
      WorkOrder(
        id: '30000000-0000-4000-8000-000000000002',
        ref: 'WO-$_yr-4822',
        outletId: outletSandton,
        bookingId: '10000000-0000-4000-8000-000000000005',
        vehicleId: vehSwift,
        customerId: 'seed_naledi',
        serviceId: svcExpress,
        status: WorkStatus.verified,
        priority: 2,
        bay: 'Bay 1',
        checklistTemplateId: tplExpress,
        templateVersion: 2,
        assigneeId: 'seed_lerato',
        assigneeName: 'Lerato Mahlangu',
        etaAt: t.subtract(const Duration(minutes: 70)),
        startedAt: t.subtract(const Duration(minutes: 90)),
        completedAt: t.subtract(const Duration(minutes: 72)),
        verifiedAt: t.subtract(const Duration(minutes: 70)),
        verifiedBy: 'seed_johan',
        dueAt: t.subtract(const Duration(minutes: 70)),
        createdAt: t.subtract(const Duration(minutes: 95)),
      ),
      WorkOrder(
        id: '30000000-0000-4000-8000-000000000003',
        ref: 'WO-$_yr-4823',
        outletId: outletSandton,
        bookingId: '10000000-0000-4000-8000-000000000006',
        vehicleId: vehHilux,
        customerId: 'seed_sipho',
        serviceId: svcInterior,
        status: WorkStatus.blocked,
        priority: 1,
        bay: 'Bay 3',
        checklistTemplateId: tplValet,
        templateVersion: 3,
        assigneeId: 'seed_lerato',
        assigneeName: 'Lerato Mahlangu',
        etaAt: t.add(const Duration(minutes: 120)),
        startedAt: t.subtract(const Duration(minutes: 10)),
        blockedReason: 'Out of interior shampoo — substitute stock needed',
        dueAt: t.add(const Duration(minutes: 120)),
        createdAt: t.subtract(const Duration(minutes: 15)),
      ),
      WorkOrder(
        id: '30000000-0000-4000-8000-000000000004',
        ref: 'WO-$_yr-4824',
        outletId: outletSandton,
        bookingId: '10000000-0000-4000-8000-000000000007',
        vehicleId: vehBmw,
        customerId: 'seed_zanele',
        serviceId: svcDetail,
        status: WorkStatus.queued,
        priority: 2,
        checklistTemplateId: tplValet,
        templateVersion: 3,
        etaAt: t.add(const Duration(hours: 4)),
        dueAt: t.add(const Duration(hours: 4)),
        createdAt: t.subtract(const Duration(minutes: 5)),
      ),
      WorkOrder(
        id: '30000000-0000-4000-8000-000000000005',
        ref: 'WO-$_yr-4818',
        outletId: outletSandton,
        quotationId: '20000000-0000-4000-8000-000000000003',
        vehicleId: vehHilux,
        customerId: 'seed_sipho',
        serviceId: svcScratch,
        status: WorkStatus.assigned,
        priority: 2,
        bay: 'Body 1',
        checklistTemplateId: tplBody,
        templateVersion: 1,
        assigneeId: 'seed_sipho_staff',
        assigneeName: 'Sipho Ndlovu',
        etaAt: t.add(const Duration(days: 2)),
        dueAt: t.subtract(const Duration(minutes: 30)),
        createdAt: t.subtract(const Duration(days: 1)),
      ),
    ]);

    tasks.addAll([
      Task(
        id: taskInService,
        workOrderId: woInService,
        outletId: outletSandton,
        title: 'Full Valet · KL 45 MN GP',
        assigneeId: 'seed_pieter',
        assigneeName: 'Pieter van der Merwe',
        status: WorkStatus.inProgress,
        priority: 1,
        dueAt: t.add(const Duration(minutes: 60)),
        startedAt: t.add(const Duration(minutes: 5)),
        elapsedSeconds: 1740,
      ),
      Task(
        id: '40000000-0000-4000-8000-000000000002',
        workOrderId: '30000000-0000-4000-8000-000000000002',
        outletId: outletSandton,
        title: 'Express Wash · HR 88 TS GP',
        assigneeId: 'seed_lerato',
        assigneeName: 'Lerato Mahlangu',
        status: WorkStatus.verified,
        priority: 2,
        dueAt: t.subtract(const Duration(minutes: 70)),
        startedAt: t.subtract(const Duration(minutes: 90)),
        completedAt: t.subtract(const Duration(minutes: 72)),
        elapsedSeconds: 1080,
      ),
      Task(
        id: '40000000-0000-4000-8000-000000000003',
        workOrderId: '30000000-0000-4000-8000-000000000003',
        outletId: outletSandton,
        title: 'Interior Deep Clean · DN 07 KX GP',
        assigneeId: 'seed_lerato',
        assigneeName: 'Lerato Mahlangu',
        status: WorkStatus.blocked,
        priority: 1,
        blockedReason: 'Out of interior shampoo — substitute stock needed',
        dueAt: t.add(const Duration(minutes: 120)),
        startedAt: t.subtract(const Duration(minutes: 10)),
        elapsedSeconds: 600,
      ),
      Task(
        id: '40000000-0000-4000-8000-000000000004',
        workOrderId: '30000000-0000-4000-8000-000000000004',
        outletId: outletSandton,
        title: 'Premium Detail · BW 33 RG GP',
        status: WorkStatus.queued,
        priority: 2,
        dueAt: t.add(const Duration(hours: 4)),
      ),
      Task(
        id: '40000000-0000-4000-8000-000000000005',
        workOrderId: '30000000-0000-4000-8000-000000000005',
        outletId: outletSandton,
        title: 'Scratch repair · DN 07 KX GP',
        assigneeId: 'seed_sipho_staff',
        assigneeName: 'Sipho Ndlovu',
        status: WorkStatus.assigned,
        priority: 2,
        dueAt: t.subtract(const Duration(minutes: 30)),
      ),
    ]);

    // WO-4821: 4 of 7 done (mockup 2b)
    for (final (k, v, m) in [
      ('prewash', {'photos': 1}, 8),
      ('exterior', true, 18),
      ('wheels', true, 24),
      ('interior', true, 31),
    ]) {
      stepResults.add(
        StepResult(
          id: _newId('5'),
          workOrderId: woInService,
          stepKey: k,
          status: StepStatus.done,
          value: v,
          actorId: 'seed_pieter',
          actorName: 'Pieter van der Merwe',
          completedAt: t.add(Duration(minutes: m)),
        ),
      );
    }
    for (final k in ['windows', 'tyre_pressure', 'supervisor']) {
      stepResults.add(
        StepResult(id: _newId('5'), workOrderId: woInService, stepKey: k),
      );
    }
    for (final k in ['exterior', 'wheels', 'dry', 'supervisor']) {
      stepResults.add(
        StepResult(
          id: _newId('5'),
          workOrderId: '30000000-0000-4000-8000-000000000002',
          stepKey: k,
          status: StepStatus.done,
          value: true,
          actorId: k == 'supervisor' ? 'seed_johan' : 'seed_lerato',
          actorName: k == 'supervisor' ? 'Johan Botha' : 'Lerato Mahlangu',
          completedAt: t.subtract(const Duration(minutes: 75)),
        ),
      );
    }
    stepResults.addAll([
      StepResult(
        id: _newId('5'),
        workOrderId: '30000000-0000-4000-8000-000000000003',
        stepKey: 'prewash',
        status: StepStatus.done,
        value: const {'photos': 2},
        actorId: 'seed_lerato',
        actorName: 'Lerato Mahlangu',
        completedAt: t.subtract(const Duration(minutes: 8)),
      ),
      StepResult(
        id: _newId('5'),
        workOrderId: '30000000-0000-4000-8000-000000000003',
        stepKey: 'exterior',
        status: StepStatus.done,
        value: true,
        actorId: 'seed_lerato',
        actorName: 'Lerato Mahlangu',
        completedAt: t.subtract(const Duration(minutes: 2)),
      ),
      StepResult(
        id: _newId('5'),
        workOrderId: '30000000-0000-4000-8000-000000000003',
        stepKey: 'interior',
        status: StepStatus.blocked,
        actorId: 'seed_lerato',
        actorName: 'Lerato Mahlangu',
        note: 'Out of interior shampoo',
      ),
    ]);

    taskEvents.addAll([
      TaskEvent(
        id: _newId('8'),
        taskId: taskInService,
        workOrderId: woInService,
        actorId: 'seed_johan',
        actorName: 'Johan Botha',
        event: 'assigned',
        fromStatus: 'queued',
        toStatus: 'assigned',
        reason: 'Auto-assign: skill match, lowest load',
        createdAt: t.subtract(const Duration(minutes: 20)),
      ),
      TaskEvent(
        id: _newId('8'),
        taskId: taskInService,
        workOrderId: woInService,
        actorId: 'seed_pieter',
        actorName: 'Pieter van der Merwe',
        event: 'transition',
        fromStatus: 'assigned',
        toStatus: 'in_progress',
        createdAt: t.add(const Duration(minutes: 5)),
      ),
      TaskEvent(
        id: _newId('8'),
        taskId: '40000000-0000-4000-8000-000000000003',
        workOrderId: '30000000-0000-4000-8000-000000000003',
        actorId: 'seed_lerato',
        actorName: 'Lerato Mahlangu',
        event: 'transition',
        fromStatus: 'in_progress',
        toStatus: 'blocked',
        reason: 'Out of interior shampoo — substitute stock needed',
        createdAt: t.subtract(const Duration(minutes: 1)),
      ),
      TaskEvent(
        id: _newId('8'),
        taskId: '40000000-0000-4000-8000-000000000002',
        workOrderId: '30000000-0000-4000-8000-000000000002',
        actorId: 'seed_johan',
        actorName: 'Johan Botha',
        event: 'transition',
        fromStatus: 'completed',
        toStatus: 'verified',
        reason: 'Checklist compliant',
        createdAt: t.subtract(const Duration(minutes: 70)),
      ),
    ]);

    // ---- Payments --------------------------------------------------------------
    paymentMethods.addAll(const [
      PaymentMethod(
        id: '50000000-0000-4000-8000-000000000001',
        customerId: 'seed_thabo',
        brand: 'visa',
        last4: '4242',
        label: 'Visa •••• 4242',
        isDefault: true,
      ),
      PaymentMethod(
        id: '50000000-0000-4000-8000-000000000002',
        customerId: 'seed_thabo',
        brand: 'eft',
        label: 'Instant EFT',
      ),
    ]);
    payments.addAll([
      Payment(
        id: '60000000-0000-4000-8000-000000000001',
        bookingId: bookingInService,
        customerId: 'seed_thabo',
        providerRef: 'pi_sbx_0091',
        methodId: '50000000-0000-4000-8000-000000000001',
        amountCents: 19800,
        status: PaymentStatus.successful,
        receiptNo: 'RCP-70001',
        idempotencyKey: 'pay-seed-0091',
        verifiedAt: n.subtract(const Duration(days: 2)),
        createdAt: n.subtract(const Duration(days: 2)),
      ),
      Payment(
        id: '60000000-0000-4000-8000-000000000002',
        bookingId: '10000000-0000-4000-8000-000000000003',
        customerId: 'seed_thabo',
        providerRef: 'pi_sbx_0067',
        methodId: '50000000-0000-4000-8000-000000000001',
        amountCents: 40500,
        status: PaymentStatus.successful,
        receiptNo: 'RCP-70002',
        idempotencyKey: 'pay-seed-0067',
        verifiedAt: n.subtract(const Duration(days: 24)),
        createdAt: n.subtract(const Duration(days: 24)),
      ),
      Payment(
        id: '60000000-0000-4000-8000-000000000003',
        bookingId: '10000000-0000-4000-8000-000000000004',
        customerId: 'seed_thabo',
        providerRef: 'pi_sbx_0052',
        methodId: '50000000-0000-4000-8000-000000000001',
        amountCents: 12000,
        status: PaymentStatus.successful,
        receiptNo: 'RCP-70003',
        idempotencyKey: 'pay-seed-0052',
        verifiedAt: n.subtract(const Duration(days: 40)),
        createdAt: n.subtract(const Duration(days: 40)),
      ),
      Payment(
        id: '60000000-0000-4000-8000-000000000004',
        bookingId: '10000000-0000-4000-8000-000000000005',
        customerId: 'seed_naledi',
        providerRef: 'pi_sbx_0092',
        amountCents: 12000,
        status: PaymentStatus.successful,
        receiptNo: 'RCP-70004',
        idempotencyKey: 'pay-seed-0092',
        verifiedAt: n.subtract(const Duration(minutes: 80)),
        createdAt: n.subtract(const Duration(minutes: 85)),
      ),
      Payment(
        id: '60000000-0000-4000-8000-000000000005',
        bookingId: '10000000-0000-4000-8000-000000000007',
        customerId: 'seed_zanele',
        providerRef: 'pi_sbx_0095',
        amountCents: 38250,
        status: PaymentStatus.pending,
        idempotencyKey: 'pay-seed-0095',
        createdAt: n.subtract(const Duration(minutes: 30)),
      ),
      Payment(
        id: '60000000-0000-4000-8000-000000000006',
        bookingId: bookingNext,
        customerId: 'seed_thabo',
        providerRef: 'pi_sbx_0094',
        methodId: '50000000-0000-4000-8000-000000000001',
        amountCents: 10800,
        status: PaymentStatus.successful,
        receiptNo: 'RCP-70005',
        idempotencyKey: 'pay-seed-0094',
        verifiedAt: n.subtract(const Duration(hours: 3)),
        createdAt: n.subtract(const Duration(hours: 3)),
      ),
    ]);

    // ---- Loyalty ledger (Thabo = Gold, 1 450 pts) ------------------------------
    void ll(
      String cust,
      int delta,
      LedgerType type,
      String? sourceType,
      String? sourceId,
      String ref,
      String desc,
      String key,
      String by,
      int daysAgo, {
      int minutesAgo = 0,
    }) {
      loyaltyLedger.add(
        LedgerEntry(
          id: _newId('9'),
          customerId: cust,
          delta: delta,
          type: type,
          sourceType: sourceType,
          sourceId: sourceId,
          reference: ref,
          description: desc,
          idempotencyKey: key,
          createdBy: by,
          createdAt: n.subtract(Duration(days: daysAgo, minutes: minutesAgo)),
        ),
      );
    }

    ll(
      'seed_thabo',
      500,
      LedgerType.bonus,
      'admin',
      null,
      'WELCOME',
      'Welcome bonus',
      'll-thabo-welcome',
      'seed_admin',
      120,
    );
    ll(
      'seed_thabo',
      380,
      LedgerType.earn,
      'booking',
      '10000000-0000-4000-8000-000000000004',
      'SPK-$_yr-0031',
      'Premium Detail',
      'll-thabo-0031',
      'seed_admin',
      95,
    );
    ll(
      'seed_thabo',
      150,
      LedgerType.bonus,
      'referral',
      null,
      'REF-NALEDI',
      'Referral: Naledi M.',
      'll-thabo-ref1',
      'seed_admin',
      70,
    );
    ll(
      'seed_thabo',
      120,
      LedgerType.earn,
      'booking',
      '10000000-0000-4000-8000-000000000004',
      'SPK-$_yr-0052',
      'Express Wash',
      'll-thabo-0052',
      'seed_admin',
      40,
    );
    ll(
      'seed_thabo',
      -350,
      LedgerType.redeem,
      'reward',
      'f0000000-0000-4000-8000-000000000002',
      'RW-1182',
      'Interior refresh',
      'll-thabo-rw1182',
      'seed_thabo',
      30,
    );
    ll(
      'seed_thabo',
      450,
      LedgerType.earn,
      'booking',
      '10000000-0000-4000-8000-000000000003',
      'SPK-$_yr-0067',
      'Premium Detail',
      'll-thabo-0067',
      'seed_admin',
      21,
    );
    ll(
      'seed_thabo',
      200,
      LedgerType.earn,
      'booking',
      null,
      'SPK-$_yr-0078',
      'Full Valet',
      'll-thabo-0078',
      'seed_admin',
      9,
    );
    ll(
      'seed_naledi',
      500,
      LedgerType.bonus,
      'admin',
      null,
      'WELCOME',
      'Welcome bonus',
      'll-naledi-welcome',
      'seed_admin',
      60,
    );
    ll(
      'seed_naledi',
      120,
      LedgerType.earn,
      'booking',
      '10000000-0000-4000-8000-000000000005',
      'SPK-$_yr-0092',
      'Express Wash',
      'll-naledi-0092',
      'seed_admin',
      0,
      minutesAgo: 70,
    );
    ll(
      'seed_sipho',
      500,
      LedgerType.bonus,
      'admin',
      null,
      'WELCOME',
      'Welcome bonus',
      'll-sipho-welcome',
      'seed_admin',
      200,
    );
    ll(
      'seed_sipho',
      1650,
      LedgerType.earn,
      'booking',
      null,
      'SPK-${n.year - 1}-0410',
      'Panel respray',
      'll-sipho-0410',
      'seed_admin',
      150,
    );
    ll(
      'seed_zanele',
      500,
      LedgerType.bonus,
      'admin',
      null,
      'WELCOME',
      'Welcome bonus',
      'll-zanele-welcome',
      'seed_admin',
      10,
    );
    _idempotencyKeys.addAll(loyaltyLedger.map((e) => e.idempotencyKey!));
    loyaltyTiers.addAll({
      'seed_thabo': (
        tier: LoyaltyTier.gold,
        tierSince: n.subtract(const Duration(days: 95)),
      ),
      'seed_naledi': (
        tier: LoyaltyTier.gold,
        tierSince: n.subtract(const Duration(days: 60)),
      ),
      'seed_sipho': (
        tier: LoyaltyTier.platinum,
        tierSince: n.subtract(const Duration(days: 150)),
      ),
      'seed_zanele': (
        tier: LoyaltyTier.gold,
        tierSince: n.subtract(const Duration(days: 10)),
      ),
    });
    redemptions.add(
      RewardRedemption(
        id: _newId('a'),
        rewardId: 'f0000000-0000-4000-8000-000000000002',
        code: 'RW-1182',
        status: 'used',
        createdAt: n.subtract(const Duration(days: 30)),
      ),
    );

    // ---- Inventory -------------------------------------------------------------
    void inv(
      String id,
      String outlet,
      String sku,
      String name,
      String unit,
      double onHand,
      double threshold,
      double? pack,
    ) {
      inventoryItems.add(
        InventoryItem(
          id: id,
          outletId: outlet,
          sku: sku,
          name: name,
          unit: unit,
          onHand: onHand,
          reorderThreshold: threshold,
          packSize: pack,
          updatedAt: n.subtract(const Duration(minutes: 15)),
          outletName: outlets.firstWhere((o) => o.id == outlet).name,
        ),
      );
    }

    inv(
      '70000000-0000-4000-8000-000000000001',
      outletSandton,
      'SHP-INT',
      'Interior shampoo 5L',
      'bottle',
      0,
      4,
      5,
    ); // last bottle used → out
    inv(
      '70000000-0000-4000-8000-000000000002',
      outletSandton,
      'WAX-CRN',
      'Carnauba wax 500ml',
      'tin',
      3,
      6,
      1,
    );
    inv(
      '70000000-0000-4000-8000-000000000003',
      outletSandton,
      'TWL-MF',
      'Microfibre towels',
      'pack',
      18,
      10,
      20,
    );
    inv(
      '70000000-0000-4000-8000-000000000004',
      outletSandton,
      'TYR-SHN',
      'Tyre shine 1L',
      'bottle',
      9,
      4,
      1,
    );
    inv(
      '70000000-0000-4000-8000-000000000005',
      outletSandton,
      'SNW-FOAM',
      'Snow foam 5L',
      'bottle',
      12,
      5,
      5,
    );
    inv(
      '70000000-0000-4000-8000-000000000006',
      outletSandton,
      'GLS-CLN',
      'Glass cleaner 1L',
      'bottle',
      7,
      4,
      1,
    );
    inv(
      '70000000-0000-4000-8000-000000000007',
      outletSandton,
      'PNT-CLR',
      'Clear coat 1L',
      'tin',
      2,
      3,
      1,
    );
    inv(
      '70000000-0000-4000-8000-000000000011',
      outletRosebank,
      'SHP-INT',
      'Interior shampoo 5L',
      'bottle',
      6,
      4,
      5,
    );
    inv(
      '70000000-0000-4000-8000-000000000012',
      outletRosebank,
      'WAX-CRN',
      'Carnauba wax 500ml',
      'tin',
      8,
      6,
      1,
    );
    inv(
      '70000000-0000-4000-8000-000000000013',
      outletRosebank,
      'TWL-MF',
      'Microfibre towels',
      'pack',
      4,
      10,
      20,
    );
    inv(
      '70000000-0000-4000-8000-000000000021',
      outletCenturion,
      'SNW-FOAM',
      'Snow foam 5L',
      'bottle',
      15,
      5,
      5,
    );
    inv(
      '70000000-0000-4000-8000-000000000022',
      outletCenturion,
      'TYR-SHN',
      'Tyre shine 1L',
      'bottle',
      1,
      4,
      1,
    );
    inventoryMovements.add(
      InventoryMovement(
        id: _newId('b'),
        itemId: '70000000-0000-4000-8000-000000000001',
        delta: -1,
        reason: InventoryReason.usage,
        actorId: 'seed_lerato',
        workOrderId: '30000000-0000-4000-8000-000000000003',
        note: 'Last bottle used',
        createdAt: n.subtract(const Duration(minutes: 15)),
      ),
    );
    for (final item in inventoryItems) {
      _refreshAlert(item, notify: false);
    }
    for (var i = 0; i < inventoryAlerts.length; i++) {
      inventoryAlerts[i] = inventoryAlerts[i].copyWith(
        notifiedAt: n.subtract(const Duration(minutes: 14)),
      );
    }

    // ---- Staff points (STF-050) -------------------------------------------------
    for (final (staff, pts, count) in [
      ('seed_pieter', 25, 52),
      ('seed_lerato', 25, 44),
      ('seed_sipho_staff', 25, 38),
      ('seed_thandi', 25, 30),
    ]) {
      for (var g = 0; g <= 60; g += 2) {
        if (g > count) break;
        staffPoints.add((
          staffId: staff,
          outletId: outletSandton,
          delta: pts,
          eventType: 'task_completed',
          key: 'sp-$staff-$g',
          at: n.subtract(Duration(days: g)),
        ));
      }
    }
    staffPoints.addAll([
      (
        staffId: 'seed_pieter',
        outletId: outletSandton,
        delta: 50,
        eventType: 'streak_5_days',
        key: 'sp-pieter-streak-1',
        at: n.subtract(const Duration(days: 3)),
      ),
      (
        staffId: 'seed_lerato',
        outletId: outletSandton,
        delta: 20,
        eventType: 'p1_on_time',
        key: 'sp-lerato-p1-1',
        at: n.subtract(const Duration(days: 1)),
      ),
      (
        staffId: 'seed_pieter',
        outletId: outletSandton,
        delta: 15,
        eventType: 'verified_first_time',
        key: 'sp-pieter-vft-1',
        at: n.subtract(const Duration(hours: 2)),
      ),
    ]);

    // ---- Notifications ---------------------------------------------------------
    notifications.addAll([
      AppNotification(
        id: _newId('c'),
        recipientId: 'seed_thabo',
        channel: NotifyChannel.push,
        templateKey: 'service_started',
        title: 'Service started',
        body: 'Your Toyota Corolla Cross is now in Bay 2.',
        status: NotifyStatus.sent,
        payload: const {'type': 'booking', 'id': bookingInService},
        sentAt: n.subtract(const Duration(minutes: 25)),
        createdAt: n.subtract(const Duration(minutes: 25)),
      ),
      AppNotification(
        id: _newId('c'),
        recipientId: 'seed_thabo',
        channel: NotifyChannel.whatsapp,
        templateKey: 'booking_confirmed',
        body:
            'Hi Thabo, your Sparkling booking SPK-$_yr-0094 is confirmed for tomorrow 09:00 at Sparkling Rosebank.',
        status: NotifyStatus.delivered,
        payload: const {'type': 'booking', 'id': bookingNext},
        sentAt: n.subtract(const Duration(hours: 3)),
        createdAt: n.subtract(const Duration(hours: 3)),
        readAt: n.subtract(const Duration(hours: 2)),
      ),
      AppNotification(
        id: _newId('c'),
        recipientId: 'seed_thabo',
        channel: NotifyChannel.push,
        templateKey: 'quote_ready',
        title: 'Your quotation is ready',
        body: 'QT-$_yr-0041: R 3 850.00. Accept or decline in the app.',
        status: NotifyStatus.sent,
        payload: const {'type': 'quotation', 'id': quotationQuoted},
        sentAt: n.subtract(const Duration(days: 1)),
        createdAt: n.subtract(const Duration(days: 1)),
      ),
      AppNotification(
        id: _newId('c'),
        recipientId: 'seed_pieter',
        channel: NotifyChannel.push,
        templateKey: 'task_assigned',
        title: 'New task',
        body: 'WO-$_yr-4821 assigned to you · Full Valet · Bay 2.',
        status: NotifyStatus.sent,
        payload: const {'type': 'task', 'id': taskInService},
        sentAt: n.subtract(const Duration(minutes: 35)),
        createdAt: n.subtract(const Duration(minutes: 35)),
      ),
      AppNotification(
        id: _newId('c'),
        recipientId: 'seed_ayesha',
        channel: NotifyChannel.push,
        templateKey: 'low_stock',
        title: 'Low stock alert',
        body: 'Interior shampoo 5L at Sparkling Sandton is out of stock (0/4).',
        status: NotifyStatus.sent,
        payload: const {
          'type': 'inventory_item',
          'id': '70000000-0000-4000-8000-000000000001',
        },
        sentAt: n.subtract(const Duration(minutes: 14)),
        createdAt: n.subtract(const Duration(minutes: 14)),
      ),
    ]);
  }

  String get _yr => _year();

  static const Map<String, List<String>?> _defaultHours = {
    'mon': ['07:30', '17:30'],
    'tue': ['07:30', '17:30'],
    'wed': ['07:30', '17:30'],
    'thu': ['07:30', '17:30'],
    'fri': ['07:30', '17:30'],
    'sat': ['08:00', '14:00'],
    'sun': null,
  };

  // ---------------------------------------------------------------------------
  // Lookups
  // ---------------------------------------------------------------------------

  Outlet? outletById(String id) => outlets.where((o) => o.id == id).firstOrNull;
  Service? serviceById(String id) =>
      services.where((s) => s.id == id).firstOrNull;
  Vehicle? vehicleById(String id) =>
      vehicles.where((v) => v.id == id).firstOrNull;
  ChecklistTemplate? templateById(String? id) =>
      id == null ? null : templates.where((t) => t.id == id).firstOrNull;
  Profile? profileById(String? id) => id == null ? null : profiles[id];
  String? nameOf(String? id) => profileById(id)?.fullName;

  Profile requireProfile(String id) =>
      profiles[id] ??
      (throw ApiException(
        code: 'not_found',
        message: 'Profile not found',
        statusCode: 404,
      ));

  Booking _requireBooking(String id) =>
      bookings.where((b) => b.id == id).firstOrNull ??
      (throw ApiException(
        code: 'not_found',
        message: 'Booking not found',
        statusCode: 404,
      ));
  Task _requireTask(String id) =>
      tasks.where((t) => t.id == id).firstOrNull ??
      (throw ApiException(
        code: 'not_found',
        message: 'Task not found',
        statusCode: 404,
      ));
  WorkOrder _requireWorkOrder(String id) =>
      workOrders.where((w) => w.id == id).firstOrNull ??
      (throw ApiException(
        code: 'not_found',
        message: 'Work order not found',
        statusCode: 404,
      ));
  Quotation _requireQuotation(String id) =>
      quotations.where((q) => q.id == id).firstOrNull ??
      (throw ApiException(
        code: 'not_found',
        message: 'Quotation not found',
        statusCode: 404,
      ));
  InventoryItem _requireItem(String id) =>
      inventoryItems.where((i) => i.id == id).firstOrNull ??
      (throw ApiException(
        code: 'not_found',
        message: 'Inventory item not found',
        statusCode: 404,
      ));

  void _requireRole(
    bool ok, [
    String message = "You don't have permission to do that.",
  ]) {
    if (!ok) {
      throw ApiException(code: 'forbidden', message: message, statusCode: 403);
    }
  }

  OutletService outletService(String outletId, String serviceId) {
    final s =
        serviceById(serviceId) ??
        (throw ApiException(
          code: 'not_found',
          message: 'Service not found',
          statusCode: 404,
        ));
    final o = outletServiceOverrides[outletId]?[serviceId];
    final price = o?.priceCents ?? s.basePriceCents;
    return OutletService(
      outletId: outletId,
      service: s,
      priceCents: price,
      pointsEstimate: (price / 100 * loyaltyConfig.rules.pointsPerRand).round(),
      isAvailable: o?.isAvailable ?? true,
    );
  }

  List<OutletService> outletServices(String outletId) =>
      services
          .where((s) => s.isActive)
          .map((s) => outletService(outletId, s.id))
          .toList()
        ..sort((a, b) => a.service.sortOrder.compareTo(b.service.sortOrder));

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  Profile me() {
    final p = requireProfile(uid);
    return p.copyWith(outletIds: staffOutlets[uid] ?? const []);
  }

  Profile updateMe(ProfileUpdate u) {
    final p = requireProfile(uid).copyWith(
      fullName: u.fullName,
      phone: u.phone,
      avatarUrl: u.avatarUrl,
      marketingOptIn: u.marketingOptIn,
      whatsappOptIn: u.whatsappOptIn,
      pushOptIn: u.pushOptIn,
      locale: u.locale,
      reducedMotion: u.reducedMotion,
      haptics: u.haptics,
      updatedAt: now,
    );
    profiles[uid] = p;
    _notify('profiles', uid);
    return me();
  }

  // ---------------------------------------------------------------------------
  // Vehicles
  // ---------------------------------------------------------------------------

  List<Vehicle> myVehicles() =>
      vehicles.where((v) => v.customerId == uid && v.isActive).toList();

  Vehicle addVehicle(VehicleInput input) {
    final norm = Vehicle.normaliseRegistration(input.registrationNo);
    if (norm.length < 2) {
      throw ApiException(
        code: 'validation_error',
        message: 'Enter a valid registration number',
        statusCode: 400,
      );
    }
    final dup = vehicles
        .where(
          (v) =>
              v.customerId == uid &&
              v.isActive &&
              (v.normalisedRegistration == norm ||
                  (input.vin != null && v.vin == input.vin)),
        )
        .firstOrNull;
    if (dup != null && !input.force) {
      throw ApiException(
        code: 'conflict',
        message: 'You already have a vehicle with this registration or VIN.',
        statusCode: 409,
        data: {'existing_vehicle_id': dup.id},
      );
    }
    final v = Vehicle(
      id: _newId('d'),
      customerId: uid,
      registrationNo: input.registrationNo.toUpperCase(),
      vin: input.vin,
      engineNo: input.engineNo,
      make: input.make,
      model: input.model,
      colour: input.colour,
      year: input.year,
      licenceNo: input.licenceNo,
      discExpiry: input.discExpiry,
      source: input.source,
      discVerified:
          input.source == VehicleSource.scan && input.discHash != null,
      discHash: input.discHash,
      createdAt: now,
      updatedAt: now,
    );
    vehicles.add(v);
    _notify('vehicles', v.id);
    return v;
  }

  Vehicle updateVehicle(String id, VehicleInput input) {
    final i = vehicles.indexWhere((v) => v.id == id && v.customerId == uid);
    if (i < 0) {
      throw ApiException(
        code: 'not_found',
        message: 'Vehicle not found',
        statusCode: 404,
      );
    }
    final v = vehicles[i].copyWith(
      registrationNo: input.registrationNo,
      make: input.make,
      model: input.model,
      colour: input.colour,
      year: input.year,
      licenceNo: input.licenceNo,
      discExpiry: input.discExpiry,
      updatedAt: now,
    );
    vehicles[i] = v;
    _notify('vehicles', id);
    return v;
  }

  void deleteVehicle(String id) {
    final i = vehicles.indexWhere((v) => v.id == id && v.customerId == uid);
    if (i < 0) {
      throw ApiException(
        code: 'not_found',
        message: 'Vehicle not found',
        statusCode: 404,
      );
    }
    vehicles[i] = vehicles[i].copyWith(isActive: false, updatedAt: now);
    _notify('vehicles', id);
  }

  // ---------------------------------------------------------------------------
  // Availability & bookings
  // ---------------------------------------------------------------------------

  List<AvailabilitySlot> availability({
    required String outletId,
    required String serviceId,
    required DateTime date,
  }) {
    final outlet = outletById(outletId);
    if (outlet == null) return const [];
    final hours = outlet.hoursFor(date.weekday);
    if (hours == null) return const [];
    final duration =
        serviceById(serviceId)?.durationMinutes ?? outlet.slotMinutes;
    final open = _at(date, hours[0]);
    final close = _at(date, hours[1]);
    final slots = <AvailabilitySlot>[];
    var cursor = open;
    while (!cursor.add(Duration(minutes: duration)).isAfter(close)) {
      final end = cursor.add(Duration(minutes: duration));
      final booked = bookings
          .where(
            (b) =>
                b.outletId == outletId &&
                b.status.isActive &&
                b.slotStart.isBefore(end) &&
                b.slotEnd.isAfter(cursor),
          )
          .length;
      slots.add(
        AvailabilitySlot(
          slotStart: cursor,
          slotEnd: end,
          capacity: outlet.bayCount,
          booked: booked,
          available: booked < outlet.bayCount && cursor.isAfter(now),
        ),
      );
      cursor = cursor.add(Duration(minutes: outlet.slotMinutes));
    }
    return slots;
  }

  static DateTime _at(DateTime day, String hhmm) {
    final parts = hhmm.split(':');
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  Booking expandBooking(Booking b, {bool detail = false}) {
    final outlet = outletById(b.outletId ?? '');
    final service = serviceById(b.serviceId ?? '');
    final vehicle = vehicleById(b.vehicleId ?? '');
    final wo = workOrders.where((w) => w.bookingId == b.id).firstOrNull;
    WorkOrderSummary? woSummary;
    List<TimelineEntry> timeline = const [];
    if (wo != null) {
      final d = workOrderDetail(wo.id);
      final stepsDone = d.stepsDone;
      final count = d.stepCount;
      woSummary = WorkOrderSummary(
        id: wo.id,
        ref: wo.ref,
        status: wo.status,
        stage: math.min(stepsDone + 1, count),
        stageCount: count,
        progressPct: count == 0 ? 0 : (stepsDone / count * 100).round(),
        assigneeName: wo.assigneeName ?? nameOf(wo.assigneeId),
        bay: wo.bay,
        etaAt: wo.etaAt,
        updatedAt: wo.updatedAt ?? wo.startedAt,
        stageTitle: d.currentStep?.title,
      );
      if (detail) timeline = d.toTimeline();
    }
    final pay = payments.where((p) => p.bookingId == b.id).toList()
      ..sort((a, c) => (c.createdAt ?? now).compareTo(a.createdAt ?? now));
    return b.copyWith(
      outlet: outlet == null
          ? null
          : OutletSummary(
              id: outlet.id,
              name: outlet.name,
              rating: outlet.rating,
              code: outlet.code,
            ),
      service: service == null
          ? null
          : ServiceSummary(
              id: service.id,
              name: service.name,
              durationMinutes: service.durationMinutes,
              category: service.category,
              icon: service.icon,
            ),
      vehicle: vehicle == null
          ? null
          : VehicleSummary(
              id: vehicle.id,
              registrationNo: vehicle.registrationNo,
              make: vehicle.make,
              model: vehicle.model,
            ),
      workOrder: woSummary,
      timeline: timeline,
      payment: pay.isEmpty
          ? null
          : PaymentSummary(
              id: pay.first.id,
              status: pay.first.status,
              amountCents: pay.first.amountCents,
              receiptNo: pay.first.receiptNo,
            ),
    );
  }

  List<Booking> myBookings({BookingStatus? status}) {
    final list = bookings
        .where(
          (b) => b.customerId == uid && (status == null || b.status == status),
        )
        .map((b) => expandBooking(b))
        .toList();
    list.sort((a, b) => b.slotStart.compareTo(a.slotStart));
    return list;
  }

  List<Booking> outletBookings(String outletId, {BookingStatus? status}) {
    final list = bookings
        .where(
          (b) =>
              b.outletId == outletId && (status == null || b.status == status),
        )
        .map((b) => expandBooking(b))
        .toList();
    list.sort((a, b) => a.slotStart.compareTo(b.slotStart));
    return list;
  }

  Booking bookingDetail(String id) {
    final b = _requireBooking(id);
    if (b.customerId != uid && !role.isStaff) {
      throw ApiException(
        code: 'forbidden',
        message: 'Not your booking',
        statusCode: 403,
      );
    }
    return expandBooking(b, detail: true);
  }

  Booking createBooking(BookingInput input) {
    if (_idempotencyKeys.contains(input.clientOpId)) {
      final existing = bookings
          .where((b) => b.clientOpId == input.clientOpId)
          .firstOrNull;
      if (existing != null) return expandBooking(existing, detail: true);
    }
    final vehicle = vehicleById(input.vehicleId);
    if (vehicle == null || vehicle.customerId != uid) {
      throw ApiException(
        code: 'validation_error',
        message: 'Choose one of your vehicles',
        statusCode: 400,
      );
    }
    final outlet =
        outletById(input.outletId) ??
        (throw ApiException(
          code: 'validation_error',
          message: 'Outlet not found',
          statusCode: 400,
        ));
    final os = outletService(input.outletId, input.serviceId);
    if (!os.isAvailable) {
      throw ApiException(
        code: 'validation_error',
        message: '${os.name} is not available at ${outlet.name}',
        statusCode: 400,
      );
    }
    final end = input.slotStart.add(Duration(minutes: os.durationMinutes));
    final booked = bookings
        .where(
          (b) =>
              b.outletId == input.outletId &&
              b.status.isActive &&
              b.slotStart.isBefore(end) &&
              b.slotEnd.isAfter(input.slotStart),
        )
        .length;
    if (booked >= outlet.bayCount) {
      throw ApiException(
        code: 'conflict',
        message: 'Slot is no longer available',
        statusCode: 409,
      );
    }

    final tier = loyaltyTiers[uid]?.tier ?? LoyaltyTier.silver;
    final tierCfg = loyaltyConfig.tierConfig(tier);
    final discountPct = tierCfg?.discountPct ?? 0;
    final discount = (os.priceCents * discountPct / 100).round();
    final total = os.priceCents - discount;
    final b = Booking(
      id: _newId('1'),
      ref: 'SPK-$_yr-${(_bookingSeq++).toString().padLeft(4, '0')}',
      customerId: uid,
      status: BookingStatus.pending,
      slotStart: input.slotStart,
      slotEnd: end,
      vehicleId: input.vehicleId,
      outletId: input.outletId,
      serviceId: input.serviceId,
      priceCents: os.priceCents,
      discountCents: discount,
      totalCents: total,
      discountLabel: discountPct > 0 ? '${tier.label} −$discountPct%' : null,
      pointsPending: (total / 100 * loyaltyConfig.rules.pointsPerRand).round(),
      notes: input.notes,
      clientOpId: input.clientOpId,
      createdAt: now,
      updatedAt: now,
    );
    bookings.add(b);
    _idempotencyKeys.add(input.clientOpId);
    _notify('bookings', b.id);
    return expandBooking(b, detail: true);
  }

  Booking cancelBooking(String id, {String? reason}) {
    final i = bookings.indexWhere((b) => b.id == id);
    final b = _requireBooking(id);
    if (b.customerId != uid && !role.isStaff) {
      throw ApiException(
        code: 'forbidden',
        message: 'Not your booking',
        statusCode: 403,
      );
    }
    if (!b.status.canCancel) {
      throw ApiException(
        code: 'invalid_transition',
        message: 'This booking can no longer be cancelled — the service has started.',
        statusCode: 409,
      );
    }
    bookings[i] = b.copyWith(
      status: BookingStatus.cancelled,
      cancelReason: reason ?? 'Cancelled by customer',
      updatedAt: now,
    );
    _notify('bookings', id);
    return expandBooking(bookings[i], detail: true);
  }

  Booking rescheduleBooking(String id, DateTime slotStart) {
    final i = bookings.indexWhere((b) => b.id == id);
    final b = _requireBooking(id);
    if (b.customerId != uid) {
      throw ApiException(
        code: 'forbidden',
        message: 'Not your booking',
        statusCode: 403,
      );
    }
    if (!b.status.canCancel) {
      throw ApiException(
        code: 'invalid_transition',
        message: 'This booking can no longer be rescheduled.',
        statusCode: 409,
      );
    }
    final duration = b.slotEnd.difference(b.slotStart);
    final end = slotStart.add(duration);
    final outlet = outletById(b.outletId!)!;
    final booked = bookings
        .where(
          (o) =>
              o.id != id &&
              o.outletId == b.outletId &&
              o.status.isActive &&
              o.slotStart.isBefore(end) &&
              o.slotEnd.isAfter(slotStart),
        )
        .length;
    if (booked >= outlet.bayCount) {
      throw ApiException(
        code: 'conflict',
        message: 'Slot is no longer available',
        statusCode: 409,
      );
    }
    bookings[i] = b.copyWith(
      slotStart: slotStart,
      slotEnd: end,
      updatedAt: now,
    );
    _notify('bookings', id);
    return expandBooking(bookings[i], detail: true);
  }

  Booking checkinBooking(String id, {String? bay, int? priority}) {
    _requireRole(role.isStaff);
    final i = bookings.indexWhere((b) => b.id == id);
    final b = _requireBooking(id);
    if (!(b.status == BookingStatus.confirmed ||
        b.status == BookingStatus.pending)) {
      throw ApiException(
        code: 'invalid_transition',
        message: 'Only confirmed bookings can be checked in.',
        statusCode: 409,
      );
    }
    var wo = workOrders.where((w) => w.bookingId == id).firstOrNull;
    if (wo == null) {
      final service = serviceById(b.serviceId!)!;
      final vehicle = vehicleById(b.vehicleId!)!;
      final template = templateById(service.checklistTemplateId);
      wo = WorkOrder(
        id: _newId('3'),
        ref: 'WO-$_yr-${_workOrderSeq++}',
        outletId: b.outletId!,
        bookingId: id,
        vehicleId: b.vehicleId!,
        customerId: b.customerId,
        serviceId: b.serviceId!,
        status: WorkStatus.queued,
        priority: priority ?? 2,
        bay: bay,
        checklistTemplateId: template?.id,
        templateVersion: template?.version,
        etaAt: now.add(Duration(minutes: service.durationMinutes)),
        dueAt: now.add(Duration(minutes: service.durationMinutes)),
        createdAt: now,
        updatedAt: now,
      );
      workOrders.add(wo);
      for (final s in template?.steps ?? const <ChecklistStep>[]) {
        stepResults.add(
          StepResult(id: _newId('5'), workOrderId: wo.id, stepKey: s.key),
        );
      }
      tasks.add(
        Task(
          id: _newId('4'),
          workOrderId: wo.id,
          outletId: wo.outletId,
          title: '${service.name} · ${vehicle.registrationNo}',
          status: WorkStatus.queued,
          priority: wo.priority,
          dueAt: wo.dueAt,
          createdAt: now,
        ),
      );
      _notify('work_orders', wo.id);
      _notify('tasks');
    }
    bookings[i] = b.copyWith(status: BookingStatus.inService, updatedAt: now);
    _pushNotification(
      b.customerId,
      'service_started',
      'Service started',
      'Your ${vehicleById(b.vehicleId!)?.displayName ?? 'vehicle'} is now in ${bay ?? 'the bay'}.',
      {'type': 'booking', 'id': id},
    );
    _notify('bookings', id);
    return expandBooking(bookings[i], detail: true);
  }

  // ---------------------------------------------------------------------------
  // Quotations
  // ---------------------------------------------------------------------------

  List<Quotation> myQuotations() =>
      quotations.where((q) => q.customerId == uid).toList()
        ..sort((a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now));

  List<Quotation> outletQuotations(String? outletId) =>
      quotations
          .where((q) => outletId == null || q.outletId == outletId)
          .toList()
        ..sort((a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now));

  Quotation quotationDetail(String id) {
    final q = _requireQuotation(id);
    if (q.customerId != uid && !role.isStaff) {
      throw ApiException(
        code: 'forbidden',
        message: 'Not your quotation',
        statusCode: 403,
      );
    }
    return q;
  }

  Quotation createQuotation(QuotationInput input) {
    final existing = quotations
        .where((q) => q.clientOpId == input.clientOpId)
        .firstOrNull;
    if (existing != null) return existing;
    final vehicle = vehicleById(input.vehicleId);
    if (vehicle == null || vehicle.customerId != uid) {
      throw ApiException(
        code: 'validation_error',
        message: 'Choose one of your vehicles',
        statusCode: 400,
      );
    }
    if (input.description.trim().length < 10) {
      throw ApiException(
        code: 'validation_error',
        message: 'Describe the damage in a bit more detail (at least 10 characters).',
        statusCode: 400,
      );
    }
    final outlet =
        outletById(input.outletId) ??
        (throw ApiException(
          code: 'validation_error',
          message: 'Outlet not found',
          statusCode: 400,
        ));
    final q = Quotation(
      id: _newId('2'),
      ref: 'QT-$_yr-${(_quotationSeq++).toString().padLeft(4, '0')}',
      customerId: uid,
      vehicleId: input.vehicleId,
      outletId: input.outletId,
      category: input.category,
      description: input.description,
      status: QuotationStatus.requested,
      clientOpId: input.clientOpId,
      createdAt: now,
      updatedAt: now,
      vehicleLabel: '${vehicle.shortName} · ${vehicle.registrationNo}',
      outletName: outlet.name,
    );
    quotations.add(q);
    _notify('quotations', q.id);
    return q;
  }

  Quotation quoteQuotation(String id, QuoteInput input) {
    _requireRole(
      role.canSupervise,
      'Only supervisors and managers can issue quotations.',
    );
    final i = quotations.indexWhere((q) => q.id == id);
    final q = _requireQuotation(id);
    if (!(q.status == QuotationStatus.requested ||
        q.status == QuotationStatus.assessing)) {
      throw ApiException(
        code: 'invalid_transition',
        message: 'Quotation already ${q.status.label.toLowerCase()}.',
        statusCode: 409,
      );
    }
    quotations[i] = q.copyWith(
      status: QuotationStatus.quoted,
      amountCents: input.amountCents,
      lineItems: input.lineItems,
      validUntil: input.validUntil,
      quotedAt: now,
      assessorId: uid,
      assessorName: nameOf(uid),
      updatedAt: now,
    );
    _pushNotification(
      q.customerId,
      'quote_ready',
      'Your quotation is ready',
      '${q.ref}: ${Money.formatZar(input.amountCents)}. Accept or decline in the app.',
      {'type': 'quotation', 'id': id},
    );
    _notify('quotations', id);
    return quotations[i];
  }

  Quotation decideQuotation(String id, {required bool accept, String? note}) {
    final i = quotations.indexWhere((q) => q.id == id);
    final q = _requireQuotation(id);
    if (q.customerId != uid) {
      throw ApiException(
        code: 'forbidden',
        message: 'Not your quotation',
        statusCode: 403,
      );
    }
    if (q.status != QuotationStatus.quoted) {
      throw ApiException(
        code: 'invalid_transition',
        message: 'This quotation is not awaiting a decision.',
        statusCode: 409,
      );
    }
    quotations[i] = q.copyWith(
      status: accept ? QuotationStatus.accepted : QuotationStatus.declined,
      decidedAt: now,
      decisionBy: uid,
      decisionNote: note,
      updatedAt: now,
    );
    _notify('quotations', id);
    return quotations[i];
  }

  Quotation convertQuotation(String id) {
    _requireRole(
      role.canSupervise,
      'Only supervisors and managers can convert quotations.',
    );
    final i = quotations.indexWhere((q) => q.id == id);
    final q = _requireQuotation(id);
    if (q.status != QuotationStatus.accepted) {
      throw ApiException(
        code: 'invalid_transition',
        message: 'Only accepted quotations can be converted.',
        statusCode: 409,
      );
    }
    final service = services.firstWhere(
      (s) =>
          s.category == ServiceCategory.autoBody &&
          s.name.toLowerCase().startsWith(q.category.toLowerCase()),
      orElse: () => serviceById(svcScratch)!,
    );
    final template = templateById(service.checklistTemplateId);
    final vehicle = vehicleById(q.vehicleId)!;
    final wo = WorkOrder(
      id: _newId('3'),
      ref: 'WO-$_yr-${_workOrderSeq++}',
      outletId: q.outletId,
      quotationId: id,
      vehicleId: q.vehicleId,
      customerId: q.customerId,
      serviceId: service.id,
      status: WorkStatus.queued,
      priority: 2,
      checklistTemplateId: template?.id,
      templateVersion: template?.version,
      etaAt: now.add(Duration(minutes: service.durationMinutes)),
      dueAt: now.add(Duration(minutes: service.durationMinutes)),
      createdAt: now,
    );
    workOrders.add(wo);
    for (final s in template?.steps ?? const <ChecklistStep>[]) {
      stepResults.add(
        StepResult(id: _newId('5'), workOrderId: wo.id, stepKey: s.key),
      );
    }
    tasks.add(
      Task(
        id: _newId('4'),
        workOrderId: wo.id,
        outletId: wo.outletId,
        title: '${service.name} · ${vehicle.registrationNo}',
        status: WorkStatus.queued,
        priority: 2,
        dueAt: wo.dueAt,
        createdAt: now,
      ),
    );
    quotations[i] = q.copyWith(
      status: QuotationStatus.converted,
      updatedAt: now,
    );
    _notify('quotations', id);
    _notify('work_orders', wo.id);
    _notify('tasks');
    return quotations[i];
  }

  // ---------------------------------------------------------------------------
  // Payments
  // ---------------------------------------------------------------------------

  List<PaymentMethod> myPaymentMethods() =>
      paymentMethods.where((m) => m.customerId == uid).toList();

  PaymentIntentResult createPaymentIntent({
    required String bookingId,
    String? methodId,
    required String idempotencyKey,
  }) {
    final existing = payments
        .where((p) => p.idempotencyKey == idempotencyKey)
        .firstOrNull;
    if (existing != null) return PaymentIntentResult(payment: existing);
    final b = _requireBooking(bookingId);
    if (b.customerId != uid) {
      throw ApiException(
        code: 'forbidden',
        message: 'Not your booking',
        statusCode: 403,
      );
    }
    if (payments.any((p) => p.bookingId == bookingId && p.status.isVerified)) {
      throw ApiException(
        code: 'conflict',
        message: 'This booking is already paid.',
        statusCode: 409,
      );
    }
    final p = Payment(
      id: _newId('6'),
      bookingId: bookingId,
      customerId: uid,
      providerRef: 'pi_sbx_${b.ref.split('-').last}',
      methodId:
          methodId ??
          myPaymentMethods().where((m) => m.isDefault).firstOrNull?.id,
      amountCents: b.totalCents,
      status: PaymentStatus.pending,
      idempotencyKey: idempotencyKey,
      createdAt: now,
      updatedAt: now,
    );
    payments.add(p);
    _notify('payments', p.id);
    return PaymentIntentResult(
      payment: p,
      clientSecret: 'sbx_secret_${p.id.substring(p.id.length - 6)}',
    );
  }

  Payment sandboxConfirm(String paymentId) {
    if (featureFlags['payments_sandbox'] != true) {
      throw ApiException(
        code: 'forbidden',
        message: 'Sandbox payments are disabled',
        statusCode: 403,
      );
    }
    final i = payments.indexWhere((p) => p.id == paymentId);
    if (i < 0) {
      throw ApiException(
        code: 'not_found',
        message: 'Payment not found',
        statusCode: 404,
      );
    }
    var p = payments[i];
    if (p.status.isVerified) return p;
    p = p.copyWith(
      status: PaymentStatus.successful,
      receiptNo: 'RCP-${_receiptSeq++}',
      verifiedAt: now,
      updatedAt: now,
      receipt: {
        'receipt_no': 'RCP-${_receiptSeq - 1}',
        'amount_cents': p.amountCents,
        'paid_at': j.iso(now),
      },
    );
    payments[i] = p;
    final bi = bookings.indexWhere((b) => b.id == p.bookingId);
    if (bi >= 0 && bookings[bi].status == BookingStatus.pending) {
      bookings[bi] = bookings[bi].copyWith(
        status: BookingStatus.confirmed,
        updatedAt: now,
      );
      final b = bookings[bi];
      _pushNotification(
        b.customerId,
        'booking_confirmed',
        'Booking confirmed',
        '${serviceById(b.serviceId!)?.name} at ${outletById(b.outletId!)?.name} on ${SparklingDates.relativeSlot(b.slotStart, now: now)}. Ref ${b.ref}.',
        {'type': 'booking', 'id': b.id},
      );
      _notify('bookings', b.id);
    }
    _pushNotification(
      p.customerId,
      'payment_successful',
      'Payment received',
      '${Money.formatZar(p.amountCents)} received. Receipt ${p.receiptNo}.',
      {'type': 'payment', 'id': p.id},
    );
    _notify('payments', p.id);
    return p;
  }

  Payment paymentById(String id) {
    final p =
        payments.where((p) => p.id == id).firstOrNull ??
        (throw ApiException(
          code: 'not_found',
          message: 'Payment not found',
          statusCode: 404,
        ));
    if (p.customerId != uid && role == UserRole.customer) {
      throw ApiException(
        code: 'forbidden',
        message: 'Not your payment',
        statusCode: 403,
      );
    }
    return p;
  }

  // ---------------------------------------------------------------------------
  // Loyalty
  // ---------------------------------------------------------------------------

  int balanceOf(String customerId) => loyaltyLedger
      .where((e) => e.customerId == customerId)
      .fold(0, (s, e) => s + e.delta);
  int lifetimeOf(String customerId) => loyaltyLedger
      .where((e) => e.customerId == customerId && e.delta > 0)
      .fold(0, (s, e) => s + e.delta);

  LoyaltyAccount accountOf(String customerId) {
    final t = loyaltyTiers[customerId];
    return LoyaltyAccount(
      customerId: customerId,
      tier: t?.tier ?? LoyaltyTier.silver,
      balancePoints: balanceOf(customerId),
      lifetimePoints: lifetimeOf(customerId),
      tierSince: t?.tierSince,
      updatedAt: now,
    );
  }

  LoyaltyAccountSummary loyaltyAccount() {
    final acc = accountOf(uid);
    final next = acc.tier.next;
    NextTier? nextTier;
    if (next != null) {
      final cfg = loyaltyConfig.tierConfig(next)!;
      nextTier = NextTier(
        tier: next,
        name: cfg.name,
        pointsNeeded: math.max(0, cfg.minPoints - acc.lifetimePoints),
      );
    }
    return LoyaltyAccountSummary(
      account: acc,
      tierConfig: loyaltyConfig.tiers,
      nextTier: nextTier,
      publishedVersion: loyaltyConfig.version,
    );
  }

  List<LedgerEntry> myLedger() =>
      loyaltyLedger.where((e) => e.customerId == uid).toList()
        ..sort((a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now));

  List<Reward> eligibleRewards() {
    final tier = loyaltyTiers[uid]?.tier ?? LoyaltyTier.silver;
    return rewards.where((r) => r.isActive && r.eligibleFor(tier)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  RewardRedemption redeem(String rewardId, {required String idempotencyKey}) {
    final existing = loyaltyLedger
        .where((e) => e.idempotencyKey == idempotencyKey)
        .firstOrNull;
    if (existing != null) {
      return redemptions.firstWhere(
        (r) => r.ledger?.id == existing.id,
        orElse: () => RewardRedemption(
          id: existing.id,
          rewardId: rewardId,
          code: existing.reference ?? '',
          status: 'issued',
          ledger: existing,
          balanceAfter: balanceOf(uid),
        ),
      );
    }
    final reward =
        rewards.where((r) => r.id == rewardId).firstOrNull ??
        (throw ApiException(
          code: 'not_found',
          message: 'Reward not found',
          statusCode: 404,
        ));
    final acc = accountOf(uid);
    if (!reward.eligibleFor(acc.tier)) {
      throw ApiException(
        code: 'forbidden',
        message: '${reward.name} needs ${reward.minTier.label} tier.',
        statusCode: 403,
      );
    }
    if (acc.balancePoints < reward.pointsCost) {
      throw ApiException(
        code: 'validation_error',
        message:
            'You need ${Money.formatPoints(reward.pointsCost - acc.balancePoints)} more points for ${reward.name}.',
        statusCode: 400,
      );
    }
    final code = 'RW-${_redemptionSeq++}';
    final entry = LedgerEntry(
      id: _newId('9'),
      customerId: uid,
      delta: -reward.pointsCost,
      type: LedgerType.redeem,
      sourceType: 'reward',
      sourceId: reward.id,
      reference: code,
      description: reward.name,
      idempotencyKey: idempotencyKey,
      createdBy: uid,
      createdAt: now,
    );
    loyaltyLedger.add(entry);
    _idempotencyKeys.add(idempotencyKey);
    final redemption = RewardRedemption(
      id: _newId('a'),
      rewardId: reward.id,
      code: code,
      status: 'issued',
      ledger: entry,
      balanceAfter: balanceOf(uid),
      createdAt: now,
    );
    redemptions.add(redemption);
    _pushNotification(
      uid,
      'points_posted',
      'Reward redeemed',
      '${reward.name} · code $code. Balance ${Money.formatPoints(balanceOf(uid))}.',
      {'type': 'reward', 'id': reward.id},
    );
    _notify('loyalty_ledger', entry.id);
    return redemption;
  }

  /// Idempotent earn posting (CUS-063/064): key `booking:<id>:earn`.
  void _awardBookingPoints(Booking b) {
    final key = 'booking:${b.id}:earn';
    if (_idempotencyKeys.contains(key) || b.pointsPending <= 0) return;
    final service = serviceById(b.serviceId ?? '');
    loyaltyLedger.add(
      LedgerEntry(
        id: _newId('9'),
        customerId: b.customerId,
        delta: b.pointsPending,
        type: LedgerType.earn,
        sourceType: 'booking',
        sourceId: b.id,
        reference: b.ref,
        description: service?.name,
        idempotencyKey: key,
        createdBy: 'system',
        createdAt: now,
      ),
    );
    _idempotencyKeys.add(key);
    final lifetime = lifetimeOf(b.customerId);
    final newTier = loyaltyConfig.tierFor(lifetime);
    final current = loyaltyTiers[b.customerId];
    if (current == null || newTier.index > current.tier.index) {
      loyaltyTiers[b.customerId] = (tier: newTier, tierSince: now);
    }
    _pushNotification(
      b.customerId,
      'points_posted',
      'Points posted',
      '+${b.pointsPending} pts added. Balance ${Money.formatPoints(balanceOf(b.customerId))}.',
      {'type': 'loyalty', 'id': b.id},
    );
    _notify('loyalty_ledger');
  }

  // ---------------------------------------------------------------------------
  // Tasks & checklists
  // ---------------------------------------------------------------------------

  Task expandTask(Task t) {
    final wo = workOrders.where((w) => w.id == t.workOrderId).firstOrNull;
    if (wo == null) return t;
    final vehicle = vehicleById(wo.vehicleId);
    final service = serviceById(wo.serviceId);
    final template = templateById(wo.checklistTemplateId);
    final done = stepResults
        .where((r) => r.workOrderId == wo.id && r.isDone)
        .length;
    final booking = wo.bookingId == null
        ? null
        : bookings.where((b) => b.id == wo.bookingId).firstOrNull;
    return t.copyWith(
      assigneeName: t.assigneeName ?? nameOf(t.assigneeId),
      workOrder: WorkOrderCard(
        id: wo.id,
        ref: wo.ref,
        status: wo.status,
        vehicle: vehicle == null
            ? null
            : VehicleSummary(
                id: vehicle.id,
                registrationNo: vehicle.registrationNo,
                make: vehicle.make,
                model: vehicle.model,
              ),
        serviceName: service?.name,
        bay: wo.bay,
        priority: wo.priority,
        etaAt: wo.etaAt,
        progress: StepProgress(
          stepsDone: done,
          stepCount: template?.steps.length ?? 0,
        ),
        blockedReason: wo.blockedReason ?? t.blockedReason,
        bookingRef: booking?.ref,
        customerName: nameOf(wo.customerId),
        slotStart: booking?.slotStart,
      ),
    );
  }

  List<Task> taskList({required TaskScope scope, String? outletId}) {
    _requireRole(role.isStaff);
    final outlet = outletId ?? (staffOutlets[uid]?.firstOrNull);
    Iterable<Task> list = tasks.where(
      (t) => outlet == null || t.outletId == outlet,
    );
    list = switch (scope) {
      TaskScope.mine => list.where(
        (t) => t.assigneeId == uid && t.status.isOpen,
      ),
      TaskScope.queue => list.where(
        (t) =>
            t.status.isOpen &&
            (t.assigneeId == null ||
                t.status == WorkStatus.queued ||
                t.assigneeId != uid),
      ),
      TaskScope.done => list.where((t) => t.status.isDone),
    };
    final out = list.map(expandTask).toList();
    out.sort((a, b) {
      if (scope == TaskScope.done) {
        return (b.completedAt ?? now).compareTo(a.completedAt ?? now);
      }
      final p = a.priority.compareTo(b.priority);
      if (p != 0) return p;
      return (a.dueAt ?? now).compareTo(b.dueAt ?? now);
    });
    return out;
  }

  WorkOrderDetail workOrderDetail(String id) {
    final wo = _requireWorkOrder(id);
    final template = templateById(wo.checklistTemplateId);
    final results = stepResults
        .where((r) => r.workOrderId == id)
        .map((r) => r.copyWith(actorName: r.actorName ?? nameOf(r.actorId)))
        .toList();
    final events = taskEvents.where((e) => e.workOrderId == id).toList()
      ..sort((a, b) => (a.createdAt ?? now).compareTo(b.createdAt ?? now));
    final task = tasks.where((t) => t.workOrderId == id).firstOrNull;
    return WorkOrderDetail(
      workOrder: wo.copyWith(
        assigneeName: wo.assigneeName ?? nameOf(wo.assigneeId),
      ),
      template: template,
      results: results,
      events: events,
      task: task == null ? null : expandTask(task),
    );
  }

  Task transitionTask(String taskId, TaskTransitionInput input) {
    _requireRole(role.isStaff);
    final ti = tasks.indexWhere((t) => t.id == taskId);
    final task = _requireTask(taskId);
    final existing = taskEvents
        .where((e) => e.clientOpId == input.clientOpId)
        .firstOrNull;
    if (existing != null) return expandTask(task);
    final wi = workOrders.indexWhere((w) => w.id == task.workOrderId);
    final wo = workOrders[wi];
    if (!task.status.canTransitionTo(input.to)) {
      throw ApiException(
        code: 'invalid_transition',
        message:
            'Cannot move a task from ${task.status.label.toLowerCase()} to ${input.to.label.toLowerCase()}.',
        statusCode: 409,
      );
    }
    if (input.to == WorkStatus.blocked &&
        (input.reason == null || input.reason!.trim().isEmpty)) {
      throw ApiException(
        code: 'validation_error',
        message: 'Give a reason for blocking the task.',
        statusCode: 400,
      );
    }
    if (input.to == WorkStatus.verified) {
      _requireRole(
        role.canSupervise,
        'Only supervisors and managers can verify work.',
      );
      final detail = workOrderDetail(wo.id);
      if (!detail.requiredStepsPassed && input.overrideReason == null) {
        throw ApiException(
          code: 'invalid_transition',
          message: 'All required checklist steps must pass before verification (or record an override).',
          statusCode: 409,
        );
      }
    }
    final elapsed =
        task.status == WorkStatus.inProgress && task.startedAt != null
        ? task.elapsedSeconds + now.difference(task.startedAt!).inSeconds
        : task.elapsedSeconds;
    var updated = task.copyWith(
      status: input.to,
      blockedReason: input.to == WorkStatus.blocked ? input.reason : null,
      clearBlockedReason: input.to != WorkStatus.blocked,
      startedAt: input.to == WorkStatus.inProgress
          ? (task.startedAt ?? now)
          : null,
      completedAt: input.to == WorkStatus.completed ? now : null,
      elapsedSeconds: elapsed,
      updatedAt: now,
    );
    if (input.to == WorkStatus.inProgress && updated.assigneeId == null) {
      updated = updated.copyWith(assigneeId: uid, assigneeName: nameOf(uid));
    }
    tasks[ti] = updated;
    workOrders[wi] = wo.copyWith(
      status: input.to,
      blockedReason: input.to == WorkStatus.blocked ? input.reason : null,
      clearBlockedReason: input.to != WorkStatus.blocked,
      startedAt: input.to == WorkStatus.inProgress
          ? (wo.startedAt ?? now)
          : null,
      completedAt: input.to == WorkStatus.completed ? now : null,
      verifiedAt: input.to == WorkStatus.verified ? now : null,
      verifiedBy: input.to == WorkStatus.verified ? uid : null,
      assigneeId: updated.assigneeId,
      assigneeName: updated.assigneeName,
      updatedAt: now,
    );
    taskEvents.add(
      TaskEvent(
        id: _newId('8'),
        taskId: taskId,
        workOrderId: wo.id,
        actorId: uid,
        actorName: nameOf(uid),
        event: input.overrideReason != null ? 'override' : 'transition',
        fromStatus: task.status.db,
        toStatus: input.to.db,
        reason: input.overrideReason ?? input.reason,
        clientOpId: input.clientOpId,
        createdAt: now,
      ),
    );

    if (input.to == WorkStatus.verified) {
      // Side effects: booking → completed, loyalty earn, staff points, notification.
      final bi = bookings.indexWhere((b) => b.id == wo.bookingId);
      if (bi >= 0) {
        bookings[bi] = bookings[bi].copyWith(
          status: BookingStatus.completed,
          updatedAt: now,
        );
        _awardBookingPoints(bookings[bi]);
        _notify('bookings', bookings[bi].id);
      }
      final assignee = updated.assigneeId ?? wo.assigneeId;
      if (assignee != null) {
        final key = 'task:$taskId:completed';
        if (!_idempotencyKeys.contains(key)) {
          staffPoints.add((
            staffId: assignee,
            outletId: wo.outletId,
            delta: 25,
            eventType: 'task_completed',
            key: key,
            at: now,
          ));
          _idempotencyKeys.add(key);
          _notify('staff_points_ledger');
        }
      }
      final vehicle = vehicleById(wo.vehicleId);
      _pushNotification(
        wo.customerId,
        'service_ready',
        'Ready for collection',
        'Your ${vehicle?.displayName ?? 'vehicle'} is ready at ${outletById(wo.outletId)?.name}.',
        {'type': 'booking', 'id': wo.bookingId ?? wo.id},
      );
    } else if (input.to == WorkStatus.blocked) {
      for (final sup in profiles.values.where(
        (p) =>
            p.role.canSupervise &&
            (staffOutlets[p.id]?.contains(wo.outletId) ?? false),
      )) {
        _pushNotification(
          sup.id,
          'task_blocked',
          'Task blocked',
          '${wo.ref} blocked: ${input.reason}',
          {'type': 'task', 'id': taskId},
        );
      }
    }
    _notify('tasks', taskId);
    _notify('work_orders', wo.id);
    return expandTask(tasks[ti]);
  }

  Task assignTask(
    String taskId, {
    required String assigneeId,
    String? reason,
    String? clientOpId,
  }) {
    _requireRole(
      role.canSupervise,
      'Only supervisors and managers can assign tasks.',
    );
    final ti = tasks.indexWhere((t) => t.id == taskId);
    final task = _requireTask(taskId);
    final wi = workOrders.indexWhere((w) => w.id == task.workOrderId);
    final assignee = requireProfile(assigneeId);
    final avail = staffAvailability[assigneeId];
    final active = tasks
        .where(
          (t) =>
              t.assigneeId == assigneeId && t.status.isOpen && t.id != taskId,
        )
        .length;
    if (avail != null && active >= avail.capacity) {
      throw ApiException(
        code: 'conflict',
        message:
            '${assignee.firstName} is at capacity ($active/${avail.capacity}).',
        statusCode: 409,
      );
    }
    final newStatus = task.status == WorkStatus.queued
        ? WorkStatus.assigned
        : task.status;
    tasks[ti] = task.copyWith(
      assigneeId: assigneeId,
      assigneeName: assignee.fullName,
      status: newStatus,
      updatedAt: now,
    );
    workOrders[wi] = workOrders[wi].copyWith(
      assigneeId: assigneeId,
      assigneeName: assignee.fullName,
      status: newStatus,
      updatedAt: now,
    );
    taskEvents.add(
      TaskEvent(
        id: _newId('8'),
        taskId: taskId,
        workOrderId: task.workOrderId,
        actorId: uid,
        actorName: nameOf(uid),
        event: 'assigned',
        fromStatus: task.status.db,
        toStatus: newStatus.db,
        reason: reason,
        metadata: {'assignee_id': assigneeId},
        clientOpId: clientOpId,
        createdAt: now,
      ),
    );
    _pushNotification(
      assigneeId,
      'task_assigned',
      'New task',
      '${workOrders[wi].ref} assigned to you · ${serviceById(workOrders[wi].serviceId)?.name} · ${workOrders[wi].bay ?? 'bay TBC'}.',
      {'type': 'task', 'id': taskId},
    );
    _notify('tasks', taskId);
    _notify('work_orders', task.workOrderId);
    return expandTask(tasks[ti]);
  }

  StepResult submitStep(
    String workOrderId,
    String stepKey,
    StepResultInput input,
  ) {
    _requireRole(role.isStaff);
    final existing = stepResults
        .where((r) => r.clientOpId == input.clientOpId)
        .firstOrNull;
    if (existing != null) return existing;
    final wo = _requireWorkOrder(workOrderId);
    final template = templateById(wo.checklistTemplateId);
    final step = template?.steps.where((s) => s.key == stepKey).firstOrNull;
    if (step == null) {
      throw ApiException(
        code: 'not_found',
        message: 'Unknown checklist step "$stepKey"',
        statusCode: 404,
      );
    }
    // Steps may be recorded until the work is verified (the supervisor step
    // itself is recorded while the work order is `completed`).
    if (wo.status == WorkStatus.verified || wo.status == WorkStatus.cancelled) {
      throw ApiException(
        code: 'invalid_transition',
        message: 'This work order is ${wo.status.label.toLowerCase()}.',
        statusCode: 409,
      );
    }
    if (step.isSupervisorVerify) {
      _requireRole(
        role.canSupervise,
        'Only a supervisor can complete this step.',
      );
      if (!workOrderDetail(workOrderId).requiredStepsPassed) {
        throw ApiException(
          code: 'invalid_transition',
          message: 'Locked until all required steps pass.',
          statusCode: 409,
        );
      }
    }
    if (input.status == StepStatus.done) {
      final err = step.validate(
        value: input.value,
        attachmentId: input.attachmentId,
      );
      if (err != null) {
        throw ApiException(
          code: 'validation_error',
          message: err,
          statusCode: 400,
          details: [
            {'step': stepKey},
          ],
        );
      }
    }
    if (input.status == StepStatus.blocked &&
        (input.note == null || input.note!.trim().isEmpty)) {
      throw ApiException(
        code: 'validation_error',
        message: 'Add a note explaining why the step is blocked.',
        statusCode: 400,
      );
    }
    final i = stepResults.indexWhere(
      (r) => r.workOrderId == workOrderId && r.stepKey == stepKey,
    );
    final result = StepResult(
      id: i >= 0 ? stepResults[i].id : _newId('5'),
      workOrderId: workOrderId,
      stepKey: stepKey,
      status: input.status,
      value:
          input.value ??
          (step.type == StepType.confirm || step.type == StepType.ack
              ? true
              : null),
      attachmentId: input.attachmentId,
      actorId: uid,
      actorName: nameOf(uid),
      note: input.note,
      clientOpId: input.clientOpId,
      completedAt: input.status == StepStatus.done ? now : null,
      updatedAt: now,
    );
    if (i >= 0) {
      stepResults[i] = result;
    } else {
      stepResults.add(result);
    }
    taskEvents.add(
      TaskEvent(
        id: _newId('8'),
        taskId: tasks
            .where((t) => t.workOrderId == workOrderId)
            .firstOrNull
            ?.id,
        workOrderId: workOrderId,
        actorId: uid,
        actorName: nameOf(uid),
        event: input.status == StepStatus.blocked
            ? 'step_blocked'
            : 'step_done',
        reason: input.note,
        metadata: {'step_key': stepKey},
        clientOpId: input.clientOpId,
        createdAt: now,
      ),
    );
    // Customer progress notification on completed stages.
    if (input.status == StepStatus.done && !step.isSupervisorVerify) {
      _pushNotification(
        wo.customerId,
        'stage_changed',
        'Progress update',
        '${vehicleById(wo.vehicleId)?.displayName ?? 'Your vehicle'}: ${step.title} complete.',
        {'type': 'booking', 'id': wo.bookingId ?? wo.id},
      );
    }
    _notify('checklist_step_results', workOrderId);
    _notify('work_orders', workOrderId);
    _notify('tasks');
    return result;
  }

  // ---------------------------------------------------------------------------
  // Ops, team, leaderboard
  // ---------------------------------------------------------------------------

  OpsSummary opsSummary(String outletId) {
    _requireRole(
      role.canSupervise,
      'Ops overview is for supervisors and managers.',
    );
    final list = tasks.where((t) => t.outletId == outletId).toList();
    final counts = OpsCounts(
      inProgress: list.where((t) => t.status == WorkStatus.inProgress).length,
      queued: list
          .where(
            (t) =>
                t.status == WorkStatus.queued ||
                t.status == WorkStatus.assigned,
          )
          .length,
      blocked: list.where((t) => t.status == WorkStatus.blocked).length,
      done: list
          .where(
            (t) =>
                t.status.isDone &&
                (t.completedAt?.isAfter(
                      DateTime(now.year, now.month, now.day),
                    ) ??
                    true),
          )
          .length,
    );
    final attention = <AttentionItem>[];
    for (final t in list.where((t) => t.status == WorkStatus.blocked)) {
      final wo = workOrders.firstWhere((w) => w.id == t.workOrderId);
      attention.add(
        AttentionItem(
          kind: AttentionKind.blocked,
          title: '${wo.ref} blocked',
          detail: t.blockedReason ?? wo.blockedReason,
          ref: wo.ref,
          link: RecordLink(type: 'task', id: t.id),
          since: taskEvents
              .where((e) => e.taskId == t.id && e.toStatus == 'blocked')
              .lastOrNull
              ?.createdAt,
          outletId: outletId,
          severity: 'error',
          actions: const ['reassign', 'substitute_stock'],
        ),
      );
    }
    for (final t in list.where(
      (t) =>
          t.status.isOpen &&
          t.dueAt != null &&
          t.dueAt!.isBefore(now) &&
          t.status != WorkStatus.blocked,
    )) {
      final wo = workOrders.firstWhere((w) => w.id == t.workOrderId);
      attention.add(
        AttentionItem(
          kind: AttentionKind.overdueSla,
          title: '${wo.ref} overdue',
          detail:
              '${serviceById(wo.serviceId)?.name} · due ${SparklingDates.hhmm(t.dueAt!)} · ${nameOf(t.assigneeId) ?? 'unassigned'}',
          ref: wo.ref,
          link: RecordLink(type: 'task', id: t.id),
          since: t.dueAt,
          outletId: outletId,
          severity: 'warning',
          actions: const ['reassign'],
        ),
      );
    }
    for (final a in inventoryAlerts.where(
      (a) => a.outletId == outletId && a.isOpen,
    )) {
      final item = _requireItem(a.itemId);
      attention.add(
        AttentionItem(
          kind: a.level == AlertLevel.out
              ? AttentionKind.outOfStock
              : AttentionKind.lowStock,
          title:
              '${item.name} ${a.level == AlertLevel.out ? 'out of stock' : 'low'}',
          detail: item.levelLabel,
          link: RecordLink(type: 'inventory_item', id: item.id),
          since: a.createdAt,
          outletId: outletId,
          severity: a.level == AlertLevel.out ? 'error' : 'warning',
          actions: const ['reorder'],
        ),
      );
    }
    final team = teamMembers(outletId)
        .map(
          (m) => TeamLoadRow(
            staffId: m.id,
            name: m.fullName,
            activeTasks: m.activeTasks,
            capacity: m.capacity,
            availability: m.availability,
          ),
        )
        .toList();
    return OpsSummary(
      counts: counts,
      needsAttention: attention,
      teamLoad: team,
      generatedAt: now,
    );
  }

  List<StaffMember> teamMembers(String outletId) {
    final members = <StaffMember>[];
    for (final entry in staffOutlets.entries) {
      if (!entry.value.contains(outletId)) continue;
      final p = profiles[entry.key];
      if (p == null ||
          !p.role.isStaff ||
          p.role == UserRole.admin ||
          p.role == UserRole.finance ||
          p.role == UserRole.manager) {
        continue;
      }
      final avail = staffAvailability[p.id];
      members.add(
        StaffMember(
          id: p.id,
          fullName: p.fullName,
          role: p.role,
          availability: avail?.status ?? AvailabilityStatus.available,
          capacity: avail?.capacity ?? 3,
          skills: staffSkills[p.id] ?? const [],
          activeTasks: tasks
              .where((t) => t.assigneeId == p.id && t.status.isOpen)
              .length,
          outletIds: entry.value,
          email: p.email,
          phone: p.phone,
        ),
      );
    }
    members.sort((a, b) => a.fullName.compareTo(b.fullName));
    return members;
  }

  LeaderboardResult leaderboard(String outletId, LeaderboardPeriod period) {
    _requireRole(role.isStaff);
    final n = now;
    final weekStart = DateTime(
      n.year,
      n.month,
      n.day,
    ).subtract(Duration(days: n.weekday - 1));
    final monthStart = DateTime(n.year, n.month, 1);
    final start = period == LeaderboardPeriod.week ? weekStart : monthStart;
    final prevStart = period == LeaderboardPeriod.week
        ? weekStart.subtract(const Duration(days: 7))
        : DateTime(n.year, n.month - 1, 1);

    Map<String, int> sum(DateTime from, DateTime to) {
      final m = <String, int>{};
      for (final p in staffPoints.where(
        (p) =>
            p.outletId == outletId && !p.at.isBefore(from) && p.at.isBefore(to),
      )) {
        m[p.staffId] = (m[p.staffId] ?? 0) + p.delta;
      }
      return m;
    }

    final current = sum(start, n.add(const Duration(days: 1)));
    final previous = sum(prevStart, start);
    List<MapEntry<String, int>> ranked(Map<String, int> m) =>
        m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final prevRank = {
      for (final (i, e) in ranked(previous).indexed) e.key: i + 1,
    };
    // Ensure every outlet technician appears.
    for (final m in teamMembers(outletId)) {
      current.putIfAbsent(m.id, () => 0);
    }
    final rows = <LeaderboardRow>[];
    for (final (i, e) in ranked(current).indexed) {
      final rank = i + 1;
      final prev = prevRank[e.key];
      rows.add(
        LeaderboardRow(
          staffId: e.key,
          name: profiles[e.key]?.fullName ?? e.key,
          points: e.value,
          rank: rank,
          delta: prev == null ? 0 : prev - rank,
          isMe: e.key == uid,
        ),
      );
    }
    final earned = staffBadges[uid] ?? const {};
    return LeaderboardResult(
      rows: rows,
      me: rows.where((r) => r.isMe).firstOrNull,
      badges: badges
          .map((b) => EarnedBadge(badge: b, earnedAt: earned[b.id]))
          .toList(),
      period: period,
      resetsAt: period == LeaderboardPeriod.week
          ? weekStart.add(const Duration(days: 7))
          : DateTime(n.year, n.month + 1, 1),
    );
  }

  // ---------------------------------------------------------------------------
  // Inventory
  // ---------------------------------------------------------------------------

  List<InventoryItem> inventory(String outletId) {
    _requireRole(role.isStaff);
    final list = inventoryItems
        .where((i) => i.outletId == outletId && i.isActive)
        .map(_withAlert)
        .toList();
    list.sort((a, b) {
      final la = a.level.index, lb = b.level.index;
      if (la != lb) return lb.compareTo(la); // out, low first
      return a.name.compareTo(b.name);
    });
    return list;
  }

  InventoryItem _withAlert(InventoryItem i) => i.copyWith(
    alert: inventoryAlerts
        .where((a) => a.itemId == i.id && a.isOpen)
        .firstOrNull,
    clearAlert: !inventoryAlerts.any((a) => a.itemId == i.id && a.isOpen),
  );

  void _refreshAlert(InventoryItem item, {bool notify = true}) {
    final idx = inventoryAlerts.indexWhere(
      (a) => a.itemId == item.id && a.isOpen,
    );
    if (item.onHand <= 0 || item.onHand <= item.reorderThreshold) {
      final level = item.onHand <= 0 ? AlertLevel.out : AlertLevel.low;
      if (idx >= 0) {
        if (inventoryAlerts[idx].level != level) {
          inventoryAlerts[idx] = inventoryAlerts[idx].copyWith(level: level);
        }
      } else {
        inventoryAlerts.add(
          InventoryAlert(
            id: _newId('e'),
            itemId: item.id,
            outletId: item.outletId,
            level: level,
            createdAt: now,
            notifiedAt: notify ? now : null,
          ),
        );
        if (notify) {
          for (final mgr in profiles.values.where(
            (p) =>
                p.role.canSupervise &&
                (staffOutlets[p.id]?.contains(item.outletId) ?? false),
          )) {
            _pushNotification(
              mgr.id,
              'low_stock',
              'Low stock alert',
              '${item.name} at ${outletById(item.outletId)?.name} is ${level == AlertLevel.out ? 'out of stock' : 'below threshold'} (${_fmtNum(item.onHand)}/${_fmtNum(item.reorderThreshold)}).',
              {'type': 'inventory_item', 'id': item.id},
            );
          }
        }
      }
    } else if (idx >= 0) {
      inventoryAlerts[idx] = inventoryAlerts[idx].copyWith(
        status: AlertStatus.resolved,
        resolvedAt: now,
      );
    }
  }

  InventoryItem logMovement(String itemId, InventoryMovementInput input) {
    _requireRole(role.isStaff);
    if (!role.canSupervise && !input.reason.technicianAllowed) {
      throw ApiException(
        code: 'forbidden',
        message: 'Reorder and threshold edits are manager-only. Technicians can log usage or request a reorder.',
        statusCode: 403,
      );
    }
    final existing = inventoryMovements
        .where((m) => m.clientOpId == input.clientOpId)
        .firstOrNull;
    if (existing != null) return _withAlert(_requireItem(itemId));
    final i = inventoryItems.indexWhere((it) => it.id == itemId);
    final item = _requireItem(itemId);
    final delta = input.reason == InventoryReason.reorderRequest
        ? 0.0
        : input.delta;
    final newOnHand = item.onHand + delta;
    if (newOnHand < 0) {
      throw ApiException(
        code: 'validation_error',
        message:
            'Only ${_fmtNum(item.onHand)} ${item.unit}(s) on hand — stock cannot go negative.',
        statusCode: 400,
      );
    }
    inventoryItems[i] = item.copyWith(onHand: newOnHand, updatedAt: now);
    inventoryMovements.add(
      InventoryMovement(
        id: _newId('b'),
        itemId: itemId,
        delta: delta,
        reason: input.reason,
        actorId: uid,
        workOrderId: input.workOrderId,
        note: input.note,
        clientOpId: input.clientOpId,
        createdAt: now,
      ),
    );
    _refreshAlert(inventoryItems[i]);
    if (input.reason == InventoryReason.reorderRequest) {
      for (final mgr in profiles.values.where(
        (p) =>
            p.role.isManager &&
            (staffOutlets[p.id]?.contains(item.outletId) ?? false),
      )) {
        _pushNotification(
          mgr.id,
          'reorder_requested',
          'Reorder requested',
          '${nameOf(uid)} requested a reorder of ${item.name} at ${outletById(item.outletId)?.name}.',
          {'type': 'inventory_item', 'id': itemId},
        );
      }
    }
    _notify('inventory_items', itemId);
    _notify('inventory_alerts', itemId);
    return _withAlert(inventoryItems[i]);
  }

  InventoryItem updateInventoryItem(
    String itemId, {
    double? reorderThreshold,
    String? name,
    String? unit,
  }) {
    _requireRole(role.isManager, 'Threshold edits are manager-only.');
    final i = inventoryItems.indexWhere((it) => it.id == itemId);
    final item = _requireItem(itemId);
    inventoryItems[i] = item.copyWith(
      reorderThreshold: reorderThreshold,
      name: name,
      unit: unit,
      updatedAt: now,
    );
    _refreshAlert(inventoryItems[i]);
    _notify('inventory_items', itemId);
    return _withAlert(inventoryItems[i]);
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  void _pushNotification(
    String recipientId,
    String key,
    String? title,
    String body,
    Map<String, dynamic> payload,
  ) {
    notifications.add(
      AppNotification(
        id: _newId('c'),
        recipientId: recipientId,
        channel: NotifyChannel.push,
        templateKey: key,
        title: title,
        body: body,
        payload: payload,
        status: NotifyStatus.sent,
        sentAt: now,
        createdAt: now,
      ),
    );
    _notify('notifications', recipientId);
  }

  List<AppNotification> myNotifications() =>
      notifications.where((n) => n.recipientId == uid).toList()
        ..sort((a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now));

  void markRead(String id) {
    final i = notifications.indexWhere(
      (n) => n.id == id && n.recipientId == uid,
    );
    if (i < 0) {
      throw ApiException(
        code: 'not_found',
        message: 'Notification not found',
        statusCode: 404,
      );
    }
    if (notifications[i].readAt == null) {
      notifications[i] = notifications[i].copyWith(readAt: now);
      _notify('notifications', uid);
    }
  }

  Map<String, dynamic> _markReadResult(String id) {
    markRead(id);
    return {'ok': true};
  }

  // ---------------------------------------------------------------------------
  // Sync batch (ARC-004)
  // ---------------------------------------------------------------------------

  /// Applies queued operations in order, returning per-op results the way
  /// `POST /sync/batch` does.
  List<SyncOperationResult> applySyncBatch(
    List<Map<String, dynamic>> operations,
  ) {
    final results = <SyncOperationResult>[];
    for (final op in operations) {
      final id = op['client_op_id']?.toString() ?? '';
      final kind = op['kind']?.toString() ?? '';
      final payload = j.asJson(op['payload']);
      try {
        final result = switch (kind) {
          SyncKinds.taskTransition => transitionTask(
            j.str(payload['task_id']),
            TaskTransitionInput.fromJson({...payload, 'client_op_id': id}),
          ).toJson(),
          SyncKinds.stepResult => submitStep(
            j.str(payload['work_order_id']),
            j.str(payload['step_key']),
            StepResultInput.fromJson({...payload, 'client_op_id': id}),
          ).toJson(),
          SyncKinds.inventoryMovement => logMovement(
            j.str(payload['item_id']),
            InventoryMovementInput.fromJson({...payload, 'client_op_id': id}),
          ).toJson(),
          SyncKinds.bookingCreate => createBooking(
            BookingInput.fromJson({...payload, 'client_op_id': id}),
          ).toJson(),
          SyncKinds.bookingCancel => cancelBooking(
            j.str(payload['booking_id']),
            reason: j.strOrNull(payload['reason']),
          ).toJson(),
          SyncKinds.quotationCreate => createQuotation(
            QuotationInput.fromJson({...payload, 'client_op_id': id}),
          ).toJson(),
          SyncKinds.quotationDecision => decideQuotation(
            j.str(payload['quotation_id']),
            accept: payload['decision'] == 'accept',
            note: j.strOrNull(payload['note']),
          ).toJson(),
          SyncKinds.vehicleCreate => addVehicle(
            VehicleInput(
              registrationNo: j.str(payload['registration_no']),
              vin: j.strOrNull(payload['vin']),
              make: j.strOrNull(payload['make']),
              model: j.strOrNull(payload['model']),
              colour: j.strOrNull(payload['colour']),
              year: j.intOrNull(payload['year']),
              source: VehicleSource.fromDb(j.strOrNull(payload['source'])),
              discHash: j.strOrNull(payload['disc_hash']),
              force: j.boolOf(payload['force']),
            ),
          ).toJson(),
          SyncKinds.taskAssign => assignTask(
            j.str(payload['task_id']),
            assigneeId: j.str(payload['assignee_id']),
            reason: j.strOrNull(payload['reason']),
            clientOpId: id,
          ).toJson(),
          SyncKinds.notificationRead => _markReadResult(
            j.str(payload['notification_id']),
          ),
          _ => throw ApiException(
            code: 'validation_error',
            message: 'Unknown operation kind "$kind"',
            statusCode: 400,
          ),
        };
        results.add(
          SyncOperationResult(
            clientOpId: id,
            status: SyncStatus.applied,
            result: result,
          ),
        );
      } on ApiException catch (e) {
        results.add(
          SyncOperationResult(
            clientOpId: id,
            status: e.isConflict ? SyncStatus.conflict : SyncStatus.rejected,
            error: e.message,
            result: {'code': e.code},
          ),
        );
      }
    }
    return results;
  }
}

String _fmtNum(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
