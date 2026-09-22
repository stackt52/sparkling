import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../api/api_exception.dart';
import '../auth/auth_service.dart';
import '../models/models.dart';
import '../models/json.dart' as j;
import 'demo_catalogue.dart';

export 'demo_catalogue.dart';

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

  /// `PUT /staff/me/availability` — the signed-in persona's availability.
  void setAvailability(AvailabilityStatus status) {
    final prev = staffAvailability[uid];
    staffAvailability[uid] = (status: status, capacity: prev?.capacity ?? 3);
    _changes.add(const DemoChange('staff_availability'));
  }
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

  // Real outlets (backend/supabase/seed_catalogue.sql).
  static const String outletMenlyn = DemoCatalogueIds.outletMen;
  static const String outletGlenVillage = DemoCatalogueIds.outletGlv;
  static const String outletPotch = DemoCatalogueIds.outletPot;
  static const String outletToti = DemoCatalogueIds.outletTot;
  static const String outletRustenburg = DemoCatalogueIds.outletRus;

  static const String tplValet = 'c0000000-0000-4000-8000-000000000001';
  static const String tplExpress = 'c0000000-0000-4000-8000-000000000002';
  static const String tplBody = 'c0000000-0000-4000-8000-000000000003';

  // Canonical services used by the seeded bookings / quotes.
  static const String svcExtWash = DemoCatalogueIds.extWash;
  static const String svcExtWashTyreBumper = DemoCatalogueIds.extWashTyreBumper;
  static const String svcSparklingWash = DemoCatalogueIds.sparklingWash;
  static const String svcExecWash = DemoCatalogueIds.execWash;
  static const String svcEngineChassisCombo =
      DemoCatalogueIds.engineChassisCombo;
  static const String svcAutoDetailInterior =
      DemoCatalogueIds.autoDetailInterior;
  static const String svcAutoDetailComplete =
      DemoCatalogueIds.autoDetailComplete;
  static const String svcFullMonty = DemoCatalogueIds.fullMonty;
  static const String svcAddonOdour = DemoCatalogueIds.addonOdour;
  static const String svcHeadlight = DemoCatalogueIds.headlightRenewal;
  static const String svcSpotRepair = DemoCatalogueIds.spotRepair;
  static const String svcBumperScuff = DemoCatalogueIds.bumperScuff;
  static const String svcPdr = DemoCatalogueIds.pdr;
  static const String svcCeramic = DemoCatalogueIds.ceramicCoating;
  static const String svcTarRemoval = DemoCatalogueIds.tarRemoval;

  /// Where the demo customer "is" for outlet distances (Lynnwood, Pretoria).
  static const double demoLatitude = -25.7650;
  static const double demoLongitude = 28.2650;

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

  /// Thabo's exterior wash from earlier today: verified, keys not yet released
  /// (collection OTP `73104`).
  static const String bookingReady =
      '10000000-0000-4000-8000-000000000010'; // SPK-2026-0098
  static const String woReady =
      '30000000-0000-4000-8000-000000000006'; // WO-2026-4820
  static const String taskReady = '40000000-0000-4000-8000-000000000006';

  /// Naledi's verified exterior wash (WO-2026-4822) — hand-over OTP.
  static const String woVerified = '30000000-0000-4000-8000-000000000002';

  /// Wrong-OTP attempts allowed before `rate_limited` (mirrors the API).
  static const int maxOtpAttempts = 5;

  /// Minimum gap between OTP re-sends per work order.
  static const Duration otpResendCooldown = Duration(seconds: 60);
  static const String quotationQuoted =
      '20000000-0000-4000-8000-000000000001'; // QT-2026-0041

  /// Minimum gap between `POST /quotations/:id/share` calls per quotation.
  static const Duration shareCooldown = Duration(seconds: 60);

  /// Damage photos per quotation (mirrors the API limit).
  static const int maxQuotationPhotos = 10;

  // Membership plans (migration 0010) and demo memberships (seed_memberships.sql).
  static const String planGold = 'c1000000-0000-4000-8000-000000000001';
  static const String planPlatinum = 'c1000000-0000-4000-8000-000000000002';
  static const String planBlack = 'c1000000-0000-4000-8000-000000000003';
  static const String membershipThabo = 'c4000000-0000-4000-8000-000000000001';
  static const String membershipNaledi = 'c4000000-0000-4000-8000-000000000002';
  static const String membershipSipho = 'c4000000-0000-4000-8000-000000000003';
  static const String membershipZanele = 'c4000000-0000-4000-8000-000000000004';

  /// Zanele's pending renewal invoice (due in 3 days).
  static const String invoiceZaneleRenewal =
      'c5000000-0000-4000-8000-000000000105';

  /// Public quote pages live under this origin in demo mode.
  static const String publicWebBaseUrl = 'https://demo.sparkling.local';

  int _bookingSeq = 97;
  int _quotationSeq = 43;
  int _workOrderSeq = 4825;
  int _receiptSeq = 70006;
  int _redemptionSeq = 1183;
  int _membershipSeq = 5;
  int _membershipInvoiceSeq = 106;
  int _idSeq = 1;

  String _newId(String prefix) =>
      '${prefix}0000-0000-4000-8000-${(_idSeq++).toString().padLeft(12, '0')}';
  String _year() => now.year.toString();

  // ---------------------------------------------------------------------------
  // Tables
  // ---------------------------------------------------------------------------

  final List<Outlet> outlets = [];
  final List<Service> services = [];

  /// `outlet_services` rows by outlet → service (the outlet's wording, prices
  /// and overrides).
  final Map<String, Map<String, DemoOfferRow>> outletOffers = {};

  /// `service_components` rows (outlet-specific sets override global ones).
  final List<DemoComponentRow> serviceComponents = [];
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

  /// Damage photo bytes by attachment id (`demo://photo/<id>`).
  final Map<String, Uint8List> photoBytes = {};
  final Map<String, DateTime> _shareSentAt = {};
  late LoyaltyConfig loyaltyConfig;
  late LoyaltyConfig loyaltyDraft;

  // ---- Memberships (docs/MEMBERSHIPS.md) ------------------------------------
  final List<MembershipPlan> membershipPlans = [];
  final List<Membership> memberships = [];

  /// `membership_selections`: membership id → { group code: entitlement code }.
  final Map<String, Map<String, String>> membershipSelections = {};

  /// Selections stored for a pending downgrade (`next_plan_id`).
  final Map<String, Map<String, String>> membershipNextSelections = {};

  /// Append-only usage rows (`+1` redeem / `−1` release).
  final List<MembershipUsage> membershipUsage = [];
  final List<MembershipInvoice> membershipInvoices = [];

  /// Upgrade invoices awaiting payment: invoice id → target plan + options.
  final Map<String, ({String planId, Map<String, String> selections})>
  _pendingUpgrades = {};
  final Map<String, bool> featureFlags = {};
  final Set<String> _idempotencyKeys = {};

  /// Active collection OTP per work order (never exposed to staff payloads).
  final Map<String, String> pickupOtps = {};
  final Map<String, int> _otpAttempts = {};
  final Map<String, DateTime> _otpResentAt = {};
  int _otpSeq = 0;

  // ---------------------------------------------------------------------------
  // Seed (mirrors seed.sql)
  // ---------------------------------------------------------------------------

  void _seed() {
    final t = ten;
    final n = now;

    const ratings = {'MEN': 4.8, 'GLV': 4.9, 'POT': 4.7, 'TOT': 4.6, 'RUS': 4.7};
    for (final r in demoOutletRows) {
      outlets.add(
        Outlet(
          id: r.id,
          code: r.code,
          name: r.name,
          addressLine: r.addressLine,
          city: r.city,
          province: r.province,
          latitude: r.latitude,
          longitude: r.longitude,
          phone: r.phone,
          email: r.email,
          bayCount: r.bayCount,
          rating: ratings[r.code] ?? 4.7,
          openingHours: _defaultHours,
          distanceKm: _distanceKm(
            demoLatitude,
            demoLongitude,
            r.latitude,
            r.longitude,
          ),
        ),
      );
    }

    templates.addAll([
      ChecklistTemplate(
        id: tplValet,
        name: 'Sparkling wash checklist',
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
        name: 'Exterior wash checklist',
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

    for (final r in demoServiceRows) {
      final isCombo =
          r.groupName == ServiceGroups.combinations ||
          r.code == 'SPARKLING_WASH' ||
          r.code == 'EXEC_WASH';
      services.add(
        Service(
          id: r.id,
          code: r.code,
          name: r.name,
          description: r.description,
          category: ServiceCategory.fromDb(r.category),
          groupName: r.groupName,
          durationMinutes: r.durationMinutes,
          isQuoteBased: r.pricingMode == 'by_quote',
          pricingMode: PricingMode.fromDb(r.pricingMode),
          vatMode: VatMode.fromDb(r.vatMode),
          isAddon: r.isAddon,
          addonGroupName: r.addonGroupName,
          icon: r.icon,
          checklistTemplateId: r.category == 'auto_body'
              ? tplBody
              : isCombo
              ? tplValet
              : tplExpress,
          sortOrder: r.sortOrder,
        ),
      );
    }
    for (final o in demoOfferRows) {
      outletOffers.putIfAbsent(o.outletId, () => {})[o.serviceId] = o;
    }
    serviceComponents.addAll(demoComponentRows);

    void person(
      String id,
      UserRole role,
      String name,
      String email,
      String phone, {
      bool marketing = false,
      bool mustChangePassword = false,
      DateTime? createdAt,
    }) {
      profiles[id] = Profile(
        id: id,
        role: role,
        fullName: name,
        email: email,
        phone: phone,
        marketingOptIn: marketing,
        mustChangePassword: mustChangePassword,
        createdAt: createdAt ?? n.subtract(const Duration(days: 200)),
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
    // Created from the admin dashboard yesterday with a temporary password
    // (ADM-010) — her first sign-in must set a new one.
    person(
      'seed_nomsa',
      UserRole.technician,
      'Nomsa Dube',
      'nomsa@sparkling.co.za',
      '+27 82 000 0016',
      mustChangePassword: true,
      createdAt: n.subtract(const Duration(days: 1)),
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
    // Visiting from the UK — shows international formatting (+44 7911 123456).
    person(
      'seed_priya',
      UserRole.customer,
      'Priya Naidoo',
      'priya@example.com',
      '+447911123456',
    );

    const allOutlets = [
      outletMenlyn,
      outletGlenVillage,
      outletPotch,
      outletToti,
      outletRustenburg,
    ];
    staffOutlets.addAll({
      'seed_ayesha': [outletMenlyn, outletGlenVillage],
      'seed_johan': [outletMenlyn],
      'seed_pieter': [outletMenlyn],
      'seed_lerato': [outletMenlyn],
      'seed_sipho_staff': [outletMenlyn],
      'seed_thandi': [outletGlenVillage],
      'seed_nomsa': [outletMenlyn],
      'seed_admin': allOutlets,
      'seed_finance': allOutlets,
    });
    staffSkills.addAll({
      'seed_pieter': ['wash', 'detail'],
      'seed_lerato': ['wash', 'interior'],
      'seed_sipho_staff': ['wash', 'paint', 'panel'],
      'seed_thandi': ['wash'],
      'seed_nomsa': ['wash'],
      'seed_johan': ['wash', 'detail', 'paint'],
    });
    staffAvailability.addAll({
      'seed_pieter': (status: AvailabilityStatus.available, capacity: 3),
      'seed_lerato': (status: AvailabilityStatus.busy, capacity: 3),
      'seed_sipho_staff': (status: AvailabilityStatus.busy, capacity: 2),
      'seed_thandi': (status: AvailabilityStatus.available, capacity: 3),
      'seed_nomsa': (status: AvailabilityStatus.off, capacity: 3),
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
        sizeClass: VehicleSize.large,
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
        sizeClass: VehicleSize.large,
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
      // Tier = membership plan: discounts live on the plan (docs/MEMBERSHIPS.md),
      // min/max points are informational only.
      LoyaltyTierConfig(
        tier: LoyaltyTier.gold,
        name: 'Gold',
        minPoints: 500,
        maxPoints: 1999,
        earnMultiplier: 1.25,
        discountPct: 0,
      ),
      LoyaltyTierConfig(
        tier: LoyaltyTier.platinum,
        name: 'Platinum',
        minPoints: 2000,
        maxPoints: 4999,
        earnMultiplier: 1.5,
        discountPct: 0,
      ),
      LoyaltyTierConfig(
        tier: LoyaltyTier.black,
        name: 'Black',
        minPoints: 5000,
        earnMultiplier: 1.75,
        discountPct: 0,
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
        name: 'Free Sparkling Wash',
        description: 'One Sparkling Wash at any outlet',
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
        name: 'Executive wash upgrade',
        description: 'Upgrade any Sparkling Wash to an Executive wash',
        icon: 'local_car_wash',
        pointsCost: 900,
        minTier: LoyaltyTier.gold,
        sortOrder: 30,
      ),
      Reward(
        id: 'f0000000-0000-4000-8000-000000000004',
        name: 'Auto detailing R150 off',
        description: 'Discount voucher for Auto detailing complete & polish',
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
        outletId: outletMenlyn,
        serviceId: svcSparklingWash,
        slotStart: t,
        slotEnd: t.add(const Duration(minutes: 60)),
        status: BookingStatus.inService,
        priceCents: 15000,
        discountCents: 1500,
        totalCents: 13500,
        discountLabel: 'Gold −10%',
        vehicleSize: VehicleSize.large,
        pricingMode: PricingMode.from,
        vatMode: VatMode.incl,
        pointsPending: 14,
        clientOpId: 'seed-op-0091',
        createdAt: n.subtract(const Duration(days: 2)),
      ),
      Booking(
        id: bookingNext,
        ref: 'SPK-$_yr-0094',
        customerId: 'seed_thabo',
        vehicleId: vehPolo,
        outletId: outletGlenVillage,
        serviceId: svcExecWash,
        slotStart: t.add(const Duration(hours: 23)),
        slotEnd: t.add(const Duration(hours: 23, minutes: 30)),
        status: BookingStatus.confirmed,
        priceCents: 25000,
        discountCents: 2500,
        totalCents: 22500,
        discountLabel: 'Gold −10%',
        vehicleSize: VehicleSize.small,
        pricingMode: PricingMode.from,
        vatMode: VatMode.incl,
        pointsPending: 23,
        clientOpId: 'seed-op-0094',
        createdAt: n.subtract(const Duration(hours: 3)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000003',
        ref: 'SPK-$_yr-0067',
        customerId: 'seed_thabo',
        vehicleId: vehCorolla,
        outletId: outletMenlyn,
        serviceId: svcAutoDetailComplete,
        slotStart: t.subtract(const Duration(days: 21)),
        slotEnd: t
            .subtract(const Duration(days: 21))
            .add(const Duration(minutes: 120)),
        status: BookingStatus.completed,
        priceCents: 90000,
        discountCents: 9000,
        totalCents: 81000,
        discountLabel: 'Gold −10%',
        vehicleSize: VehicleSize.large,
        pricingMode: PricingMode.from,
        vatMode: VatMode.incl,
        clientOpId: 'seed-op-0067',
        createdAt: n.subtract(const Duration(days: 24)),
      ),
      Booking(
        id: bookingReady,
        ref: 'SPK-$_yr-0098',
        customerId: 'seed_thabo',
        vehicleId: vehPolo,
        outletId: outletMenlyn,
        serviceId: svcExtWashTyreBumper,
        slotStart: t.subtract(const Duration(hours: 2)),
        slotEnd: t
            .subtract(const Duration(hours: 2))
            .add(const Duration(minutes: 20)),
        status: BookingStatus.completed,
        priceCents: 9000,
        discountCents: 900,
        totalCents: 8100,
        discountLabel: 'Gold −10%',
        vehicleSize: VehicleSize.small,
        pricingMode: PricingMode.from,
        vatMode: VatMode.incl,
        pointsPending: 8,
        clientOpId: 'seed-op-0098',
        createdAt: n.subtract(const Duration(days: 1)),
        updatedAt: t.subtract(const Duration(minutes: 100)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000004',
        ref: 'SPK-$_yr-0052',
        customerId: 'seed_thabo',
        vehicleId: vehPolo,
        outletId: outletMenlyn,
        serviceId: svcExtWash,
        slotStart: t.subtract(const Duration(days: 38)),
        slotEnd: t
            .subtract(const Duration(days: 38))
            .add(const Duration(minutes: 20)),
        status: BookingStatus.completed,
        priceCents: 8000,
        totalCents: 8000,
        vehicleSize: VehicleSize.small,
        pricingMode: PricingMode.from,
        vatMode: VatMode.incl,
        clientOpId: 'seed-op-0052',
        createdAt: n.subtract(const Duration(days: 40)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000005',
        ref: 'SPK-$_yr-0092',
        customerId: 'seed_naledi',
        vehicleId: vehSwift,
        outletId: outletMenlyn,
        serviceId: svcExtWash,
        slotStart: t.subtract(const Duration(minutes: 90)),
        slotEnd: t.subtract(const Duration(minutes: 70)),
        status: BookingStatus.completed,
        priceCents: 8000,
        totalCents: 8000,
        vehicleSize: VehicleSize.small,
        pricingMode: PricingMode.from,
        vatMode: VatMode.incl,
        pointsPending: 8,
        clientOpId: 'seed-op-0092',
        createdAt: n.subtract(const Duration(hours: 5)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000006',
        ref: 'SPK-$_yr-0093',
        customerId: 'seed_sipho',
        vehicleId: vehHilux,
        outletId: outletMenlyn,
        serviceId: svcAutoDetailInterior,
        slotStart: t.add(const Duration(minutes: 30)),
        slotEnd: t.add(const Duration(minutes: 120)),
        status: BookingStatus.confirmed,
        priceCents: 70000,
        totalCents: 70000,
        vehicleSize: VehicleSize.large,
        pricingMode: PricingMode.from,
        vatMode: VatMode.incl,
        pointsPending: 70,
        clientOpId: 'seed-op-0093',
        createdAt: n.subtract(const Duration(days: 1)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000007',
        ref: 'SPK-$_yr-0095',
        customerId: 'seed_zanele',
        vehicleId: vehBmw,
        outletId: outletMenlyn,
        serviceId: svcAutoDetailComplete,
        slotStart: t.add(const Duration(hours: 2)),
        slotEnd: t.add(const Duration(hours: 4)),
        status: BookingStatus.confirmed,
        priceCents: 85000,
        discountCents: 12750,
        totalCents: 72250,
        discountLabel: 'Platinum −15%',
        vehicleSize: VehicleSize.small,
        pricingMode: PricingMode.from,
        vatMode: VatMode.incl,
        pointsPending: 72,
        clientOpId: 'seed-op-0095',
        createdAt: n.subtract(const Duration(hours: 1)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000008',
        ref: 'SPK-$_yr-0096',
        customerId: 'seed_naledi',
        vehicleId: vehSwift,
        outletId: outletGlenVillage,
        serviceId: svcSparklingWash,
        slotStart: t.add(const Duration(hours: 3)),
        slotEnd: t.add(const Duration(hours: 4)),
        status: BookingStatus.pending,
        priceCents: 16000,
        totalCents: 16000,
        vehicleSize: VehicleSize.small,
        pricingMode: PricingMode.from,
        vatMode: VatMode.incl,
        pointsPending: 16,
        clientOpId: 'seed-op-0096',
        createdAt: n.subtract(const Duration(minutes: 20)),
      ),
      Booking(
        id: '10000000-0000-4000-8000-000000000009',
        ref: 'SPK-$_yr-0090',
        customerId: 'seed_sipho',
        vehicleId: vehHilux,
        outletId: outletMenlyn,
        serviceId: svcExtWash,
        slotStart: t.subtract(const Duration(hours: 3)),
        slotEnd: t.subtract(const Duration(minutes: 160)),
        status: BookingStatus.cancelled,
        priceCents: 9000,
        totalCents: 9000,
        vehicleSize: VehicleSize.large,
        pricingMode: PricingMode.from,
        vatMode: VatMode.incl,
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
        outletId: outletMenlyn,
        category: 'Bumper',
        description:
            'Rear bumper scuffed in parking lot, paint cracked on left corner.',
        status: QuotationStatus.quoted,
        amountCents: 385000,
        lineItems: const [
          LineItem(
            label: 'Bumper scuff repair & respray',
            amountCents: 320000,
            category: 'Bumper',
            description: 'Rear bumper, left corner — fill, sand and respray.',
            serviceId: svcBumperScuff,
          ),
          LineItem(
            label: 'Blend to quarter panel',
            amountCents: 65000,
            category: 'Paint',
            description: 'Colour blend into the rear quarter so the join is invisible.',
            serviceId: svcSpotRepair,
          ),
        ],
        itemsNote: 'Parts on hand · 2 working days once the car is in.',
        assessorId: 'seed_sipho_staff',
        assessorName: 'Sipho Ndlovu',
        validUntil: n.add(const Duration(days: 14)),
        quotedAt: n.subtract(const Duration(days: 1)),
        clientOpId: 'seed-op-qt41',
        createdAt: n.subtract(const Duration(days: 3)),
        vehicleLabel: 'Corolla Cross · KL 45 MN GP',
        outletName: 'Sparkling Auto Care Centre Menlyn',
        customerName: 'Thabo Nkosi',
        publicUrl: '$publicWebBaseUrl/q/seed-token-qt41',
        pdfUrl: '/v1/quotations/$quotationQuoted/pdf',
        attachments: [
          _seedPhoto(
            '20000000-0000-4000-8000-0000000000a1',
            quotationQuoted,
            'Rear bumper',
            n.subtract(const Duration(days: 3)),
          ),
          _seedPhoto(
            '20000000-0000-4000-8000-0000000000a2',
            quotationQuoted,
            'Paint crack close-up',
            n.subtract(const Duration(days: 3)),
          ),
        ],
      ),
      Quotation(
        id: '20000000-0000-4000-8000-000000000002',
        ref: 'QT-$_yr-0042',
        customerId: 'seed_zanele',
        vehicleId: vehBmw,
        outletId: outletMenlyn,
        category: 'Dent',
        description: 'Door ding on driver door, no paint damage.',
        status: QuotationStatus.requested,
        clientOpId: 'seed-op-qt42',
        createdAt: n.subtract(const Duration(hours: 6)),
        vehicleLabel: '330i · BW 33 RG GP',
        outletName: 'Sparkling Auto Care Centre Menlyn',
        customerName: 'Zanele Mthembu',
      ),
      Quotation(
        id: '20000000-0000-4000-8000-000000000003',
        ref: 'QT-$_yr-0038',
        customerId: 'seed_sipho',
        vehicleId: vehHilux,
        outletId: outletMenlyn,
        category: 'Scratch',
        description: 'Key scratch along passenger side.',
        status: QuotationStatus.accepted,
        amountCents: 210000,
        lineItems: const [
          LineItem(
            label: 'Scratch repair & blend',
            amountCents: 210000,
            category: 'Scratch',
            serviceId: svcSpotRepair,
          ),
        ],
        assessorId: 'seed_sipho_staff',
        assessorName: 'Sipho Ndlovu',
        validUntil: n.add(const Duration(days: 7)),
        quotedAt: n.subtract(const Duration(days: 4)),
        decidedAt: n.subtract(const Duration(days: 2)),
        decisionBy: 'seed_sipho',
        decisionSource: QuoteDecisionSource.publicLink,
        decisionByName: 'Sipho Dlamini',
        customerName: 'Sipho Dlamini',
        publicUrl: '$publicWebBaseUrl/q/seed-token-qt38',
        pdfUrl: '/v1/quotations/20000000-0000-4000-8000-000000000003/pdf',
        clientOpId: 'seed-op-qt38',
        createdAt: n.subtract(const Duration(days: 6)),
        vehicleLabel: 'Hilux · DN 07 KX GP',
        outletName: 'Sparkling Auto Care Centre Menlyn',
      ),
    ]);

    // ---- Work orders / tasks ---------------------------------------------------
    workOrders.addAll([
      WorkOrder(
        id: woInService,
        ref: 'WO-$_yr-4821',
        outletId: outletMenlyn,
        bookingId: bookingInService,
        vehicleId: vehCorolla,
        customerId: 'seed_thabo',
        serviceId: svcSparklingWash,
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
        id: woReady,
        ref: 'WO-$_yr-4820',
        outletId: outletMenlyn,
        bookingId: bookingReady,
        vehicleId: vehPolo,
        customerId: 'seed_thabo',
        serviceId: svcExtWashTyreBumper,
        status: WorkStatus.verified,
        priority: 2,
        bay: 'Bay 1',
        checklistTemplateId: tplExpress,
        templateVersion: 2,
        assigneeId: 'seed_lerato',
        assigneeName: 'Lerato Mahlangu',
        etaAt: t.subtract(const Duration(minutes: 100)),
        startedAt: t.subtract(const Duration(minutes: 118)),
        completedAt: t.subtract(const Duration(minutes: 102)),
        verifiedAt: t.subtract(const Duration(minutes: 100)),
        verifiedBy: 'seed_johan',
        dueAt: t.subtract(const Duration(minutes: 100)),
        createdAt: t.subtract(const Duration(minutes: 125)),
      ),
      WorkOrder(
        id: woVerified,
        ref: 'WO-$_yr-4822',
        outletId: outletMenlyn,
        bookingId: '10000000-0000-4000-8000-000000000005',
        vehicleId: vehSwift,
        customerId: 'seed_naledi',
        serviceId: svcExtWash,
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
        outletId: outletMenlyn,
        bookingId: '10000000-0000-4000-8000-000000000006',
        vehicleId: vehHilux,
        customerId: 'seed_sipho',
        serviceId: svcAutoDetailInterior,
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
        outletId: outletMenlyn,
        bookingId: '10000000-0000-4000-8000-000000000007',
        vehicleId: vehBmw,
        customerId: 'seed_zanele',
        serviceId: svcAutoDetailComplete,
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
        outletId: outletMenlyn,
        quotationId: '20000000-0000-4000-8000-000000000003',
        vehicleId: vehHilux,
        customerId: 'seed_sipho',
        serviceId: svcSpotRepair,
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

    // Collection OTPs for verified, not-yet-collected work (5 digits).
    pickupOtps[woReady] = '73104';
    pickupOtps[woVerified] = '48213';

    tasks.addAll([
      Task(
        id: taskReady,
        workOrderId: woReady,
        outletId: outletMenlyn,
        title: 'Exterior wash, tyre shine & bumper polish · CJ 12 PZ GP',
        assigneeId: 'seed_lerato',
        assigneeName: 'Lerato Mahlangu',
        status: WorkStatus.verified,
        priority: 2,
        dueAt: t.subtract(const Duration(minutes: 100)),
        startedAt: t.subtract(const Duration(minutes: 118)),
        completedAt: t.subtract(const Duration(minutes: 102)),
        elapsedSeconds: 960,
      ),
      Task(
        id: taskInService,
        workOrderId: woInService,
        outletId: outletMenlyn,
        title: 'Sparkling Wash · KL 45 MN GP',
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
        outletId: outletMenlyn,
        title: 'Exterior wash · HR 88 TS GP',
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
        outletId: outletMenlyn,
        title: 'Auto detailing interior · DN 07 KX GP',
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
        outletId: outletMenlyn,
        title: 'Auto detailing complete & polish · BW 33 RG GP',
        status: WorkStatus.queued,
        priority: 2,
        dueAt: t.add(const Duration(hours: 4)),
      ),
      Task(
        id: '40000000-0000-4000-8000-000000000005',
        workOrderId: '30000000-0000-4000-8000-000000000005',
        outletId: outletMenlyn,
        title: 'Spot repair & blending · DN 07 KX GP',
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
    for (final (wo, minutesAgo) in [(woVerified, 75), (woReady, 104)]) {
      for (final k in ['exterior', 'wheels', 'dry', 'supervisor']) {
        stepResults.add(
          StepResult(
            id: _newId('5'),
            workOrderId: wo,
            stepKey: k,
            status: StepStatus.done,
            value: true,
            actorId: k == 'supervisor' ? 'seed_johan' : 'seed_lerato',
            actorName: k == 'supervisor' ? 'Johan Botha' : 'Lerato Mahlangu',
            completedAt: t.subtract(Duration(minutes: minutesAgo)),
          ),
        );
      }
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
        workOrderId: woVerified,
        actorId: 'seed_johan',
        actorName: 'Johan Botha',
        event: 'transition',
        fromStatus: 'completed',
        toStatus: 'verified',
        reason: 'Checklist compliant',
        createdAt: t.subtract(const Duration(minutes: 70)),
      ),
      TaskEvent(
        id: _newId('8'),
        taskId: taskReady,
        workOrderId: woReady,
        actorId: 'seed_johan',
        actorName: 'Johan Botha',
        event: 'transition',
        fromStatus: 'completed',
        toStatus: 'verified',
        reason: 'Checklist compliant',
        createdAt: t.subtract(const Duration(minutes: 100)),
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
        amountCents: 13500,
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
        amountCents: 81000,
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
        amountCents: 8000,
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
        amountCents: 8000,
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
        amountCents: 72250,
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
        amountCents: 22500,
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
      'Auto detailing complete & polish',
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
      'Exterior wash',
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
      'Auto detailing complete & polish',
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
      'Sparkling Wash',
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
      'Exterior wash',
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
      'Spot repair & blending',
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
    // Loyalty tiers derive from the memberships seeded below (tier = plan).
    _seedMemberships(n);
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
      outletMenlyn,
      'SHP-INT',
      'Interior shampoo 5L',
      'bottle',
      0,
      4,
      5,
    ); // last bottle used → out
    inv(
      '70000000-0000-4000-8000-000000000002',
      outletMenlyn,
      'WAX-CRN',
      'Carnauba wax 500ml',
      'tin',
      3,
      6,
      1,
    );
    inv(
      '70000000-0000-4000-8000-000000000003',
      outletMenlyn,
      'TWL-MF',
      'Microfibre towels',
      'pack',
      18,
      10,
      20,
    );
    inv(
      '70000000-0000-4000-8000-000000000004',
      outletMenlyn,
      'TYR-SHN',
      'Tyre shine 1L',
      'bottle',
      9,
      4,
      1,
    );
    inv(
      '70000000-0000-4000-8000-000000000005',
      outletMenlyn,
      'SNW-FOAM',
      'Snow foam 5L',
      'bottle',
      12,
      5,
      5,
    );
    inv(
      '70000000-0000-4000-8000-000000000006',
      outletMenlyn,
      'GLS-CLN',
      'Glass cleaner 1L',
      'bottle',
      7,
      4,
      1,
    );
    inv(
      '70000000-0000-4000-8000-000000000007',
      outletMenlyn,
      'PNT-CLR',
      'Clear coat 1L',
      'tin',
      2,
      3,
      1,
    );
    inv(
      '70000000-0000-4000-8000-000000000011',
      outletGlenVillage,
      'SHP-INT',
      'Interior shampoo 5L',
      'bottle',
      6,
      4,
      5,
    );
    inv(
      '70000000-0000-4000-8000-000000000012',
      outletGlenVillage,
      'WAX-CRN',
      'Carnauba wax 500ml',
      'tin',
      8,
      6,
      1,
    );
    inv(
      '70000000-0000-4000-8000-000000000013',
      outletGlenVillage,
      'TWL-MF',
      'Microfibre towels',
      'pack',
      4,
      10,
      20,
    );
    inv(
      '70000000-0000-4000-8000-000000000021',
      outletPotch,
      'SNW-FOAM',
      'Snow foam 5L',
      'bottle',
      15,
      5,
      5,
    );
    inv(
      '70000000-0000-4000-8000-000000000022',
      outletPotch,
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
          outletId: outletMenlyn,
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
        outletId: outletMenlyn,
        delta: 50,
        eventType: 'streak_5_days',
        key: 'sp-pieter-streak-1',
        at: n.subtract(const Duration(days: 3)),
      ),
      (
        staffId: 'seed_lerato',
        outletId: outletMenlyn,
        delta: 20,
        eventType: 'p1_on_time',
        key: 'sp-lerato-p1-1',
        at: n.subtract(const Duration(days: 1)),
      ),
      (
        staffId: 'seed_pieter',
        outletId: outletMenlyn,
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
            'Hi Thabo, your Sparkling booking SPK-$_yr-0094 is confirmed for tomorrow 09:00 at Sparkling Elite Centre Glen Village.',
        status: NotifyStatus.delivered,
        payload: const {'type': 'booking', 'id': bookingNext},
        sentAt: n.subtract(const Duration(hours: 3)),
        createdAt: n.subtract(const Duration(hours: 3)),
        readAt: n.subtract(const Duration(hours: 2)),
      ),
      AppNotification(
        id: _newId('c'),
        recipientId: 'seed_thabo',
        channel: NotifyChannel.whatsapp,
        templateKey: 'pickup_otp',
        title: 'Ready for collection',
        body: 'Your Volkswagen Polo Vivo is ready at Sparkling Auto Care Centre Menlyn. Collection OTP: 73104 — show it at the counter to collect your keys.',
        status: NotifyStatus.delivered,
        providerRef: 'SM7f3c0d9e4a1b4c8d9e0f1a2b3c4d5e6f',
        providerStatus: 'delivered',
        payload: const {'type': 'booking', 'id': bookingReady},
        sentAt: t.subtract(const Duration(minutes: 100)),
        deliveredAt: t.subtract(const Duration(minutes: 99)),
        readAt: t.subtract(const Duration(minutes: 95)),
        createdAt: t.subtract(const Duration(minutes: 100)),
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
        body: 'WO-$_yr-4821 assigned to you · Sparkling Wash · Bay 2.',
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
        body: 'Interior shampoo 5L at Sparkling Auto Care Centre Menlyn is out of stock (0/4).',
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

  /// Registers a small striped PNG as a demo damage photo.
  Attachment _seedPhoto(
    String id,
    String quotationId,
    String caption,
    DateTime at,
  ) {
    final bytes = base64Decode(
      photoBytes.length.isEven ? _demoPngGrey : _demoPngBlue,
    );
    photoBytes[id] = bytes;
    return Attachment(
      id: id,
      entityId: quotationId,
      mimeType: 'image/png',
      sizeBytes: bytes.length,
      width: 96,
      height: 72,
      caption: caption,
      uploadedBy: 'seed_sipho_staff',
      createdAt: at,
      url: 'demo://photo/$id',
    );
  }

  static const String _demoPngGrey = 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABICAIAAACGBWc0AAAAxklEQVR42u3YoRGEQBREwRc3AZzF4EjgwiSDMUi66tsxT+12x+8ad97/cV/Yps7eps7eps7eps7eps7eps7eps7eps7eps7eps7eps7eps7eps7eps7eps7eps7eps7eps7eps7epg6TZtJMmkkzaSbNpJm0OkyaSTNpJs2kmTSTZtLqMGkmzaSZNJNm0kyaSXtnM2kmzaSZNJNm0kyaSTNpdZg0k2bSTJpJM2kmzaTVYdJMmkkzaSbNpJk0k/YLYdJM+uX2AVN/5sraXG0wAAAAAElFTkSuQmCC';
  static const String _demoPngBlue = 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABICAIAAACGBWc0AAAAx0lEQVR42u3YMRGEQBREwSeG/KzgABtoONU4mISQrvrpJC/a7Y7zHve7/uO+sE2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU2dvU0dJs2kmTSTZtJMmkkzaXWYNJNm0kyaSTNpJs2k1WHSTJpJM2kmzaSZNJP2zmbSTJpJM2kmzaSZNJNm0uowaSbNpJk0k2bSTJpJq8OkmTSTZtJMmkkzaSbtF8KkmfTL7QNFnjnSFnTnPAAAAABJRU5ErkJggg==';

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

  // ---- Catalogue pricing engine (mirrors backend services/pricing.ts) ------

  /// Components of [parentId] at [outletId]: the outlet's own rows when it
  /// has any, otherwise the global default set.
  List<DemoComponentRow> _componentsFor(String outletId, String parentId) {
    final rows = serviceComponents.where((c) => c.parentServiceId == parentId);
    final own = rows.where((c) => c.outletId == outletId).toList();
    final set = own.isNotEmpty
        ? own
        : rows.where((c) => c.outletId == null).toList();
    return set..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// The outlet's wording for [serviceId] (falls back to the canonical name).
  String _offerName(String outletId, String serviceId) =>
      outletOffers[outletId]?[serviceId]?.displayName ??
      serviceById(serviceId)?.name ??
      serviceId;

  /// Builds the documented offer for a service the outlet carries, or null
  /// when the outlet does not offer it.
  OutletService? _offer(
    String outletId,
    String serviceId, {
    VehicleSize? size,
  }) {
    final svc = serviceById(serviceId);
    final row = outletOffers[outletId]?[serviceId];
    if (svc == null || row == null || !svc.isActive) return null;
    final mode = row.pricingMode == null
        ? svc.pricingMode
        : PricingMode.fromDb(row.pricingMode);
    final vat = row.vatMode == null ? svc.vatMode : VatMode.fromDb(row.vatMode);
    final includes = [
      for (final c in _componentsFor(outletId, serviceId))
        if (serviceById(c.childServiceId) case final child?)
          ServiceRef(
            serviceId: child.id,
            code: child.code,
            name: _offerName(outletId, child.id),
          ),
    ];
    final includedIn = [
      for (final parent in outletOffers[outletId]!.keys)
        if (parent != serviceId &&
            _componentsFor(
              outletId,
              parent,
            ).any((c) => c.childServiceId == serviceId))
          parent,
    ];
    final offer = OutletService(
      outletId: outletId,
      serviceId: svc.id,
      code: svc.code,
      name: row.displayName,
      category: svc.category,
      description: svc.description,
      groupName: svc.groupName,
      durationMinutes: svc.durationMinutes,
      icon: svc.icon,
      pricingMode: mode,
      vatMode: vat,
      priceSmallCents: mode == PricingMode.byQuote
          ? null
          : row.priceSmallCents ?? svc.priceSmallCents,
      priceLargeCents: mode == PricingMode.byQuote
          ? null
          : row.priceLargeCents ?? svc.priceLargeCents,
      priceGeneralCents: mode == PricingMode.byQuote
          ? null
          : row.priceGeneralCents ?? svc.priceGeneralCents,
      pricedFor: size,
      isAddon: svc.isAddon,
      addonGroupName: svc.addonGroupName,
      includes: includes,
      includedIn: includedIn,
      isAvailable: row.isAvailable,
      sortOrder: row.sortOrder,
      notes: row.notes,
      pointsPerRand: loyaltyConfig.rules.pointsPerRand,
      checklistTemplateId: svc.checklistTemplateId,
    );
    final resolved = offer.priceFor(size ?? VehicleSize.small);
    return offer.copyWith(
      priceCents: resolved,
      clearPrice: resolved == null,
      pointsEstimate: offer.pointsFor(size ?? VehicleSize.small),
    );
  }

  /// One offer of the outlet (404 when the outlet does not carry it).
  OutletService outletService(
    String outletId,
    String serviceId, {
    VehicleSize? size,
  }) =>
      _offer(outletId, serviceId, size: size) ??
      (throw ApiException(
        code: 'not_found',
        message: 'Service not offered at this outlet',
        statusCode: 404,
      ));

  /// `GET /outlets/:id/services` — all offers of the outlet in sort order.
  List<OutletService> outletServices(String outletId, {VehicleSize? size}) =>
      (outletOffers[outletId]?.keys ?? const <String>[])
          .map((id) => _offer(outletId, id, size: size))
          .whereType<OutletService>()
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// The catalogue envelope with the group list in display order.
  OutletCatalogue outletCatalogue(String outletId, {VehicleSize? vehicleSize}) {
    final offers = outletServices(outletId, size: vehicleSize);
    final groups = offers.map((o) => o.groupName).toSet().toList()
      ..sort((a, b) => ServiceGroups.order(a).compareTo(ServiceGroups.order(b)));
    return OutletCatalogue(
      outletId: outletId,
      offers: offers,
      groups: groups,
      vehicleSize: vehicleSize,
    );
  }

  /// Server-side pricing of a booking: size resolution (request → vehicle
  /// → small), by-quote refusal (409 `validation_error` `{reason:'by_quote'}`),
  /// add-on group validation, the membership benefit (covered service →
  /// base waived, else the plan discount by scope — docs/MEMBERSHIPS.md) and
  /// 15 % VAT on `excl` offers. [discountPct] is a legacy flat discount used
  /// only when the plan gives nothing (0 for every tier now).
  ({
    OutletService offer,
    VehicleSize size,
    int base,
    List<BookingAddon> addons,
    int addonsCents,
    int discount,
    String? discountLabel,
    int vat,
    int total,
    BookingMembership? membership,
    String? membershipId,
    String? entitlementId,
  })
  priceBooking({
    required String outletId,
    required String serviceId,
    required Vehicle vehicle,
    VehicleSize? vehicleSize,
    List<String> addonServiceIds = const [],
    String? customerId,
    int discountPct = 0,
  }) {
    final outlet = outletById(outletId);
    final offer = outletService(outletId, serviceId);
    if (!offer.isAvailable) {
      throw ApiException(
        code: 'validation_error',
        message: '${offer.name} is not available at ${outlet?.name ?? 'this outlet'}',
        statusCode: 400,
      );
    }
    if (offer.isAddon) {
      throw ApiException(
        code: 'validation_error',
        message: '${offer.name} is an add-on — choose a main service first.',
        statusCode: 400,
      );
    }
    if (offer.isByQuote) {
      throw ApiException(
        code: 'validation_error',
        message: '${offer.name} is priced by quote — request a quotation instead.',
        statusCode: 409,
        details: const [
          {'reason': 'by_quote'},
        ],
        data: {'reason': 'by_quote', 'service_id': serviceId},
      );
    }
    final size = vehicleSize ?? vehicle.sizeClass;
    final base = offer.priceFor(size)!;
    final addons = <BookingAddon>[];
    for (final id in addonServiceIds.toSet()) {
      final a = _offer(outletId, id, size: size);
      if (a == null || !a.isAvailable) {
        throw ApiException(
          code: 'validation_error',
          message: 'Add-on not offered at ${outlet?.name ?? 'this outlet'}',
          statusCode: 400,
        );
      }
      final price = a.priceFor(size);
      if (!a.isAddon ||
          (a.addonGroupName ?? a.groupName) != offer.groupName ||
          price == null) {
        throw ApiException(
          code: 'validation_error',
          message: '${a.name} cannot be added to ${offer.name}',
          statusCode: 400,
        );
      }
      addons.add(BookingAddon(serviceId: a.serviceId, name: a.name, priceCents: price));
    }
    final addonsCents = addons.fold(0, (sum, a) => sum + a.priceCents);
    final mp = customerId == null
        ? null
        : _membershipPricing(
            customerId: customerId,
            offer: offer,
            base: base,
            addonsCents: addonsCents,
          );
    var discount = mp?.discount ?? 0;
    var label = mp?.label;
    if (discount == 0 && discountPct > 0) {
      discount = ((base + addonsCents) * discountPct / 100).round();
      label = null;
    }
    final vat = offer.vatMode.vatOn(base + addonsCents - discount);
    return (
      offer: offer,
      size: size,
      base: base,
      addons: addons,
      addonsCents: addonsCents,
      discount: discount,
      discountLabel: label,
      vat: vat,
      total: base + addonsCents - discount + vat,
      membership: mp?.block,
      membershipId: mp?.membership?.id,
      entitlementId: mp?.entitlement?.id,
    );
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  Profile me() {
    final p = requireProfile(uid);
    return p.copyWith(outletIds: staffOutlets[uid] ?? const []);
  }

  /// `POST /auth/session` — the demo has no claims to mint; returns the
  /// persona's profile (with `mustChangePassword` for new staff accounts).
  Profile bootstrapSession() => me();

  /// `POST /auth/password-changed` — clears the temporary-password flag.
  Profile passwordChanged() {
    final p = requireProfile(uid);
    profiles[uid] = p.copyWith(
      mustChangePassword: false,
      passwordChangedAt: now,
      updatedAt: now,
    );
    _notify('profiles', uid);
    return me();
  }

  Profile updateMe(ProfileUpdate u) {
    String? phone;
    if (u.phone != null && u.phone!.trim().isNotEmpty) {
      phone = Phone.normalise(u.phone);
      if (phone == null) throw _invalidPhone();
    }
    final p = requireProfile(uid).copyWith(
      fullName: u.fullName,
      phone: phone,
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

  Vehicle addVehicle(VehicleInput input) => _addVehicleFor(uid, input);

  /// Staff route `POST /staff/customers/:id/vehicles` (STF-012).
  Vehicle createCustomerVehicle(String customerId, VehicleInput input) {
    _requireRole(role.isStaff);
    final p = requireProfile(customerId);
    if (p.role != UserRole.customer) {
      throw ApiException(
        code: 'validation_error',
        message: 'Not a customer profile',
        statusCode: 400,
      );
    }
    return _addVehicleFor(customerId, input, staff: true);
  }

  Vehicle _addVehicleFor(
    String customerId,
    VehicleInput input, {
    bool staff = false,
  }) {
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
              v.customerId == customerId &&
              v.isActive &&
              (v.normalisedRegistration == norm ||
                  (input.vin != null && v.vin == input.vin)),
        )
        .firstOrNull;
    if (dup != null && !input.force) {
      throw ApiException(
        code: 'conflict',
        message: staff
            ? 'This customer already has a vehicle with this registration or VIN.'
            : 'You already have a vehicle with this registration or VIN.',
        statusCode: 409,
        data: {'existing_vehicle_id': dup.id},
      );
    }
    final v = Vehicle(
      id: _newId('d'),
      customerId: customerId,
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
      sizeClass: input.sizeClass ?? VehicleSize.small,
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
      sizeClass: input.sizeClass,
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
  // Walk-in customers (STF-010/012) — `GET/POST /staff/customers`
  // ---------------------------------------------------------------------------

  /// `GET /staff/customers` row for [customerId].
  CustomerSummary customerSummary(String customerId) {
    final p = requireProfile(customerId);
    final brief = membershipBriefOf(customerId);
    final acc = loyaltyTiers.containsKey(customerId) ||
            brief != null ||
            loyaltyLedger.any((e) => e.customerId == customerId)
        ? accountOf(customerId)
        : null;
    return CustomerSummary(
      id: p.id,
      fullName: p.fullName,
      email: p.email,
      phone: p.phone,
      marketingOptIn: p.marketingOptIn,
      whatsappOptIn: p.whatsappOptIn,
      loyalty: acc == null
          ? null
          : CustomerLoyaltySummary(
              tier: acc.tier,
              balancePoints: acc.balancePoints,
              discountPct: loyaltyConfig.tierConfig(acc.tier)?.discountPct ?? 0,
              planCode: brief?.planCode,
              planName: brief?.planName,
              includedRemaining: brief?.includedRemaining,
            ),
      vehicles: vehicles
          .where((v) => v.customerId == customerId && v.isActive)
          .map(CustomerVehicleSummary.fromVehicle)
          .toList(),
    );
  }

  /// Name / phone / e-mail / plate search over customer profiles (min 2
  /// chars; phone digits and plates are compared normalised).
  List<CustomerSummary> searchCustomers(String query, {int limit = 20}) {
    _requireRole(role.isStaff);
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    // A pasted `+44 7400…` / `072 555…` compares against the E.164 key.
    final digits = Phone.normalise(q)?.replaceAll('+', '') ??
        q.replaceAll(RegExp(r'[^0-9]'), '');
    final plate = q.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    // Only an all-numeric query (`072 555…`, `+44 7400…`) is a phone search;
    // plates and names carry letters.
    final phoneQuery =
        digits.length >= 3 && RegExp(r'^[+0-9\s().-]+$').hasMatch(q);
    final matches = <CustomerSummary>[];
    for (final p in profiles.values) {
      if (p.role != UserRole.customer || !p.isActive) continue;
      final byName = p.fullName.toLowerCase().contains(q);
      final byEmail = (p.email ?? '').toLowerCase().contains(q);
      final phoneKey = CustomerInput.phoneKey(p.phone);
      final byPhone =
          phoneQuery && digits.isNotEmpty && phoneKey.contains(digits) ||
          phoneQuery &&
              digits.startsWith('0') &&
              phoneKey.contains(digits.substring(1));
      final byPlate =
          plate.length >= 2 &&
          vehicles.any(
            (v) =>
                v.customerId == p.id &&
                v.isActive &&
                v.normalisedRegistration.contains(plate),
          );
      if (byName || byEmail || byPhone || byPlate) {
        matches.add(customerSummary(p.id));
      }
    }
    matches.sort((a, b) => a.fullName.compareTo(b.fullName));
    return matches.take(limit).toList();
  }

  /// `POST /staff/customers` — registers a walk-in profile (`walkin_<id>`).
  /// Duplicate phone / e-mail → 409 with `existing_customer`.
  CustomerSummary createCustomer(CustomerInput input) {
    _requireRole(role.isStaff);
    if (_idempotencyKeys.contains(input.clientOpId)) {
      final existing = _walkInOps[input.clientOpId];
      if (existing != null) return customerSummary(existing);
    }
    final name = input.fullName.trim();
    if (name.length < 2) {
      throw ApiException(
        code: 'validation_error',
        message: 'Enter the customer\'s full name',
        statusCode: 400,
      );
    }
    final phone = Phone.normalise(input.phone);
    if (phone == null) throw _invalidPhone();
    final email = input.email?.trim().toLowerCase();
    final phoneKey = CustomerInput.phoneKey(phone);
    final dup = profiles.values
        .where(
          (p) =>
              p.role == UserRole.customer &&
              (CustomerInput.phoneKey(p.phone) == phoneKey ||
                  (email != null &&
                      email.isNotEmpty &&
                      p.email?.toLowerCase() == email)),
        )
        .firstOrNull;
    if (dup != null) {
      final existing = customerSummary(dup.id).toJson();
      throw ApiException(
        code: 'conflict',
        message:
            '${dup.fullName} is already registered with this ${CustomerInput.phoneKey(dup.phone) == phoneKey ? 'phone number' : 'e-mail address'}.',
        statusCode: 409,
        details: [
          {'existing_customer': existing},
        ],
        data: {
          'existing_customer': existing,
          'details': {'existing_customer': existing},
        },
      );
    }
    final id = 'walkin_${_newId('w')}';
    profiles[id] = Profile(
      id: id,
      role: UserRole.customer,
      fullName: name,
      email: email?.isEmpty ?? true ? null : email,
      phone: phone,
      marketingOptIn: input.marketingOptIn,
      whatsappOptIn: input.whatsappOptIn,
      createdAt: now,
      updatedAt: now,
    );
    _idempotencyKeys.add(input.clientOpId);
    _walkInOps[input.clientOpId] = id;
    _notify('profiles', id);
    return customerSummary(id);
  }

  /// client_op_id → created walk-in profile id (idempotent replays).
  final Map<String, String> _walkInOps = {};

  /// 400 `validation_error` the API returns for a phone that is not a valid
  /// mobile number in its country (`POST /staff/customers`, `PATCH /me`).
  static ApiException _invalidPhone() => const ApiException(
    code: 'validation_error',
    message: Phone.invalidMessage,
    statusCode: 400,
  );

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
      // The OTP is only exposed to the owning customer while the booking is
      // completed and the keys have not been released (API contract).
      final exposeOtp =
          b.customerId == uid &&
          !role.isStaff &&
          b.status == BookingStatus.completed &&
          wo.collectedAt == null;
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
        pickupOtp: exposeOtp ? pickupOtps[wo.id] : null,
        pickupOtpVerifiedAt: wo.pickupOtpVerifiedAt,
        collectedAt: wo.collectedAt,
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
              name: _offerName(b.outletId ?? '', service.id),
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
    final quote = priceBooking(
      outletId: input.outletId,
      serviceId: input.serviceId,
      vehicle: vehicle,
      vehicleSize: input.vehicleSize,
      addonServiceIds: input.addonServiceIds,
      customerId: uid,
    );
    final os = quote.offer;
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

    final total = quote.total;
    final b = Booking(
      id: _newId('1'),
      ref: 'SPK-$_yr-${(_bookingSeq++).toString().padLeft(4, '0')}',
      customerId: uid,
      // Nothing to pay (service included in the plan) → confirmed at once.
      status: total == 0 ? BookingStatus.confirmed : BookingStatus.pending,
      slotStart: input.slotStart,
      slotEnd: end,
      vehicleId: input.vehicleId,
      outletId: input.outletId,
      serviceId: input.serviceId,
      priceCents: quote.base,
      discountCents: quote.discount,
      totalCents: total,
      discountLabel: quote.discountLabel,
      vehicleSize: quote.size,
      pricingMode: os.pricingMode,
      vatMode: os.vatMode,
      addons: quote.addons,
      addonsCents: quote.addonsCents,
      vatCents: quote.vat,
      pointsPending: (total / 100 * loyaltyConfig.rules.pointsPerRand).round(),
      notes: input.notes,
      clientOpId: input.clientOpId,
      createdAt: now,
      updatedAt: now,
      membershipId: quote.membershipId,
      entitlementId: quote.entitlementId,
      membershipBenefit: quote.membership?.benefit,
      membership: quote.membership,
    );
    bookings.add(b);
    _idempotencyKeys.add(input.clientOpId);
    _redeemMembershipUsage(b);
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
    _releaseMembershipUsage(bookings[i]);
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
    return _checkin(id, bay: bay, priority: priority);
  }

  /// `POST /bookings` from the staff app with `walk_in: true` (STF-010/012):
  /// slot defaults to now on the outlet grid, capacity is enforced per bay,
  /// status starts `confirmed`, and `checkin` creates the work order + task.
  Booking createWalkInBooking(WalkInBookingInput input) {
    _requireRole(role.isStaff);
    if (_idempotencyKeys.contains(input.clientOpId)) {
      final existing = bookings
          .where((b) => b.clientOpId == input.clientOpId)
          .firstOrNull;
      if (existing != null) return expandBooking(existing, detail: true);
    }
    final myOutlets = staffOutlets[uid] ?? const <String>[];
    if (!myOutlets.contains(input.outletId) && !role.isManager) {
      throw ApiException(
        code: 'forbidden',
        message: 'You can only book walk-ins at your own outlet.',
        statusCode: 403,
      );
    }
    final customer = requireProfile(input.customerId);
    if (customer.role != UserRole.customer) {
      throw ApiException(
        code: 'validation_error',
        message: 'Not a customer profile',
        statusCode: 400,
      );
    }
    final vehicle = vehicleById(input.vehicleId);
    if (vehicle == null || vehicle.customerId != customer.id || !vehicle.isActive) {
      throw ApiException(
        code: 'validation_error',
        message: 'Choose one of the customer\'s vehicles',
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
    final quote = priceBooking(
      outletId: input.outletId,
      serviceId: input.serviceId,
      vehicle: vehicle,
      vehicleSize: input.vehicleSize,
      addonServiceIds: input.addonServiceIds,
      customerId: customer.id,
    );
    final os = quote.offer;
    final start = input.slotStart == null
        ? _roundToGrid(now, outlet.slotMinutes)
        : input.slotStart!.toLocal();
    final end = start.add(Duration(minutes: os.durationMinutes));
    final booked = bookings
        .where(
          (b) =>
              b.outletId == input.outletId &&
              b.status.isActive &&
              b.slotStart.isBefore(end) &&
              b.slotEnd.isAfter(start),
        )
        .length;
    if (booked >= outlet.bayCount) {
      throw ApiException(
        code: 'conflict',
        message: input.slotStart == null
            ? 'All ${outlet.bayCount} bays are busy right now — pick a later slot.'
            : 'Slot is no longer available',
        statusCode: 409,
      );
    }

    final total = quote.total;
    final b = Booking(
      id: _newId('1'),
      ref: 'SPK-$_yr-${(_bookingSeq++).toString().padLeft(4, '0')}',
      customerId: customer.id,
      status: BookingStatus.confirmed,
      slotStart: start,
      slotEnd: end,
      vehicleId: input.vehicleId,
      outletId: input.outletId,
      serviceId: input.serviceId,
      priceCents: quote.base,
      discountCents: quote.discount,
      totalCents: total,
      discountLabel: quote.discountLabel,
      vehicleSize: quote.size,
      pricingMode: os.pricingMode,
      vatMode: os.vatMode,
      addons: quote.addons,
      addonsCents: quote.addonsCents,
      vatCents: quote.vat,
      pointsPending: (total / 100 * loyaltyConfig.rules.pointsPerRand).round(),
      notes: input.notes ?? 'Walk-in',
      clientOpId: input.clientOpId,
      createdAt: now,
      updatedAt: now,
      membershipId: quote.membershipId,
      entitlementId: quote.entitlementId,
      membershipBenefit: quote.membership?.benefit,
      membership: quote.membership,
    );
    bookings.add(b);
    _idempotencyKeys.add(input.clientOpId);
    _redeemMembershipUsage(b);
    _notify('bookings', b.id);
    final checkin = input.checkin;
    if (checkin == null) return expandBooking(b, detail: true);
    return _checkin(b.id, bay: checkin.bay, priority: checkin.priority);
  }

  /// `POST /payments/record` — staff-attested cash / card-terminal payment.
  Payment recordPayment(RecordPaymentInput input) {
    _requireRole(role.isStaff);
    final existing = payments
        .where((p) => p.idempotencyKey == input.idempotencyKey)
        .firstOrNull;
    if (existing != null) return existing;
    // Queued behind an offline walk-in: resolve the booking by its op id.
    final byOp = input.bookingClientOpId == null
        ? null
        : bookings
              .where((b) => b.clientOpId == input.bookingClientOpId)
              .firstOrNull;
    final b = byOp ?? _requireBooking(input.bookingId);
    final myOutlets = staffOutlets[uid] ?? const <String>[];
    if (!myOutlets.contains(b.outletId) && !role.isManager) {
      throw ApiException(
        code: 'forbidden',
        message: 'This booking belongs to another outlet.',
        statusCode: 403,
      );
    }
    if (input.amountCents != b.totalCents) {
      throw ApiException(
        code: 'validation_error',
        message:
            'Amount must equal the booking total (${Money.formatZar(b.totalCents)}).',
        statusCode: 400,
      );
    }
    if (payments.any((p) => p.bookingId == b.id && p.status.isVerified)) {
      throw ApiException(
        code: 'conflict',
        message: 'This booking is already paid.',
        statusCode: 409,
      );
    }
    final receiptNo = 'RCP-${_receiptSeq++}';
    final p = Payment(
      id: _newId('6'),
      bookingId: b.id,
      customerId: b.customerId,
      provider: 'pos',
      providerRef: input.reference,
      amountCents: b.totalCents,
      status: PaymentStatus.successful,
      receiptNo: receiptNo,
      idempotencyKey: input.idempotencyKey,
      verifiedAt: now,
      createdAt: now,
      updatedAt: now,
      receipt: {
        'receipt_no': receiptNo,
        'amount_cents': b.totalCents,
        'method': input.method.db,
        'reference': input.reference,
        'recorded_by': nameOf(uid),
        'paid_at': j.iso(now),
      },
    );
    payments.add(p);
    final bi = bookings.indexWhere((x) => x.id == b.id);
    if (bi >= 0 && bookings[bi].status == BookingStatus.pending) {
      bookings[bi] = bookings[bi].copyWith(
        status: BookingStatus.confirmed,
        updatedAt: now,
      );
      _notify('bookings', b.id);
    }
    _pushNotification(
      b.customerId,
      'payment_successful',
      'Payment received',
      '${Money.formatZar(p.amountCents)} received (${input.method.label.toLowerCase()}). Receipt $receiptNo.',
      {'type': 'payment', 'id': p.id},
    );
    _notify('payments', p.id);
    return p;
  }

  /// Floors [t] to the outlet slot grid (e.g. 10:13 → 10:00 on a 30-min grid).
  static DateTime _roundToGrid(DateTime t, int slotMinutes) {
    final m = slotMinutes <= 0 ? 30 : slotMinutes;
    final minute = (t.minute ~/ m) * m;
    return DateTime(t.year, t.month, t.day, t.hour, minute);
  }

  Booking _checkin(String id, {String? bay, int? priority}) {
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
      quotations
          .where((q) => q.customerId == uid)
          .map(_expandQuotation)
          .toList()
        ..sort((a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now));

  List<Quotation> outletQuotations(String? outletId) =>
      quotations
          .where((q) => outletId == null || q.outletId == outletId)
          .map(_expandQuotation)
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
    return _expandQuotation(q);
  }

  /// `public_url` is a staff-only field; every response carries `pdf_url`.
  Quotation _expandQuotation(Quotation q) => q.copyWith(
    clearPublicUrl: !role.isStaff,
    pdfUrl: q.pdfUrl ?? '/v1/quotations/${q.id}/pdf',
  );

  int _publicTokenSeq = 0;
  String _newPublicToken() =>
      'demo-${(_publicTokenSeq++).toString().padLeft(4, '0')}-${_newId('t').substring(24)}';

  // ---- Staff-raised quotations (STF-010/012, CUS-030..034) -----------------

  /// Staff `POST /quotations` — one step to a `quoted` quotation with the
  /// items sum as amount, a fresh public link and (optionally) the
  /// `quote_ready` push + WhatsApp.
  Quotation raiseQuotation(StaffQuotationInput input) {
    _requireRole(role.isStaff, 'Only staff can raise quotations.');
    final existing = quotations
        .where((q) => q.clientOpId == input.clientOpId)
        .firstOrNull;
    if (existing != null) return _expandQuotation(existing);
    final myOutlets = staffOutlets[uid] ?? const <String>[];
    if (!myOutlets.contains(input.outletId) && !role.isManager) {
      throw ApiException(
        code: 'forbidden',
        message: 'You can only raise quotes at your own outlet.',
        statusCode: 403,
      );
    }
    final customer = requireProfile(input.customerId);
    if (customer.role != UserRole.customer) {
      throw ApiException(
        code: 'validation_error',
        message: 'Not a customer profile',
        statusCode: 400,
      );
    }
    final vehicle = vehicleById(input.vehicleId);
    if (vehicle == null ||
        vehicle.customerId != customer.id ||
        !vehicle.isActive) {
      throw ApiException(
        code: 'validation_error',
        message: 'Choose one of the customer\'s vehicles',
        statusCode: 400,
      );
    }
    if (input.items.isEmpty) {
      throw ApiException(
        code: 'validation_error',
        message: 'Add at least one item',
        statusCode: 400,
      );
    }
    for (final item in input.items) {
      if (item.label.trim().isEmpty || item.amountCents <= 0) {
        throw ApiException(
          code: 'validation_error',
          message: 'Every item needs a title and an amount',
          statusCode: 400,
        );
      }
      final sid = item.serviceId;
      if (sid != null && serviceById(sid) == null) {
        throw ApiException(
          code: 'validation_error',
          message: 'Unknown service',
          statusCode: 400,
        );
      }
    }
    final today = DateTime(now.year, now.month, now.day);
    final vu = input.validUntil;
    if (DateTime(vu.year, vu.month, vu.day).isBefore(today)) {
      throw ApiException(
        code: 'validation_error',
        message: 'valid_until must be today or later',
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
    final id = _newId('2');
    final token = _newPublicToken();
    final q = Quotation(
      id: id,
      ref: 'QT-$_yr-${(_quotationSeq++).toString().padLeft(4, '0')}',
      customerId: customer.id,
      vehicleId: vehicle.id,
      outletId: outlet.id,
      category: input.category,
      description: input.description.trim(),
      status: QuotationStatus.quoted,
      amountCents: input.totalCents,
      lineItems: input.items.map((i) => i.toLineItem()).toList(),
      itemsNote: input.itemsNote,
      assessorId: uid,
      assessorName: nameOf(uid),
      validUntil: DateTime(vu.year, vu.month, vu.day, 23, 59, 59),
      quotedAt: now,
      clientOpId: input.clientOpId,
      createdAt: now,
      updatedAt: now,
      vehicleLabel: '${vehicle.shortName} · ${vehicle.registrationNo}',
      outletName: outlet.name,
      customerName: customer.fullName,
      publicUrl: '$publicWebBaseUrl/q/$token',
      pdfUrl: '/v1/quotations/$id/pdf',
    );
    quotations.add(q);
    _idempotencyKeys.add(input.clientOpId);
    if (input.sendToCustomer) _sendQuoteReady(q);
    _notify('quotations', q.id);
    return q;
  }

  void _sendQuoteReady(Quotation q) {
    final body =
        '${q.ref}: ${Money.formatZar(q.amountCents ?? 0)}. Accept or decline in the app.';
    _pushNotification(
      q.customerId,
      'quote_ready',
      'Your quotation is ready',
      body,
      {'type': 'quotation', 'id': q.id},
    );
    final customer = profileById(q.customerId);
    if (customer?.whatsappOptIn ?? false) {
      _pushNotification(
        q.customerId,
        'quote_ready',
        null,
        'Hi ${customer!.fullName.split(' ').first}, your Sparkling quote ${q.ref} '
            '(${Money.formatZar(q.amountCents ?? 0)}) is ready: ${q.publicUrl}',
        {'type': 'quotation', 'id': q.id},
        channel: NotifyChannel.whatsapp,
      );
    }
  }

  /// `POST /quotations/:id/photos` — bytes are kept in memory and served at
  /// `demo://photo/<attachmentId>`.
  Attachment uploadQuotationPhoto(
    String quotationId,
    Uint8List bytes, {
    String? caption,
    String? mimeType,
    String? filename,
  }) {
    final i = quotations.indexWhere((q) => q.id == quotationId);
    final q = _requireQuotation(quotationId);
    if (q.customerId != uid && !role.isStaff) {
      throw ApiException(
        code: 'forbidden',
        message: 'Not your quotation',
        statusCode: 403,
      );
    }
    if (bytes.isEmpty) {
      throw ApiException(
        code: 'validation_error',
        message: 'Empty photo',
        statusCode: 400,
      );
    }
    if (bytes.length > 10 * 1024 * 1024) {
      throw ApiException(
        code: 'validation_error',
        message: 'Photo is larger than 10 MB',
        statusCode: 400,
      );
    }
    if (q.attachments.length >= maxQuotationPhotos) {
      throw ApiException(
        code: 'validation_error',
        message: 'Up to $maxQuotationPhotos photos per quotation',
        statusCode: 400,
      );
    }
    final id = _newId('e');
    photoBytes[id] = bytes;
    final a = Attachment(
      id: id,
      entityId: quotationId,
      mimeType: mimeType ?? _sniffMime(bytes, filename),
      sizeBytes: bytes.length,
      caption: (caption?.trim().isEmpty ?? true) ? null : caption!.trim(),
      uploadedBy: uid,
      createdAt: now,
      url: 'demo://photo/$id',
    );
    quotations[i] = q.copyWith(
      attachments: [...q.attachments, a],
      updatedAt: now,
    );
    _notify('quotations', quotationId);
    return a;
  }

  static String _sniffMime(Uint8List bytes, String? filename) {
    if (bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if ((filename ?? '').toLowerCase().endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  /// `DELETE /quotations/:id/photos/:attachmentId` (staff, before decision).
  void deleteQuotationPhoto(String quotationId, String attachmentId) {
    _requireRole(role.isStaff);
    final i = quotations.indexWhere((q) => q.id == quotationId);
    final q = _requireQuotation(quotationId);
    if (q.isDecided) {
      throw ApiException(
        code: 'conflict',
        message: 'Photos are locked once the quote is decided.',
        statusCode: 409,
      );
    }
    if (!q.attachments.any((a) => a.id == attachmentId)) {
      throw ApiException(
        code: 'not_found',
        message: 'Photo not found',
        statusCode: 404,
      );
    }
    photoBytes.remove(attachmentId);
    quotations[i] = q.copyWith(
      attachments: q.attachments.where((a) => a.id != attachmentId).toList(),
      updatedAt: now,
    );
    _notify('quotations', quotationId);
  }

  /// `GET /quotations/:id/photos/:attachmentId` (`demo://photo/<id>`).
  Uint8List quotationPhotoBytes(String url) {
    final id = url.startsWith('demo://photo/')
        ? url.substring('demo://photo/'.length)
        : url.split('/').last;
    final bytes = photoBytes[id];
    if (bytes == null) {
      throw ApiException(
        code: 'not_found',
        message: 'Photo not found',
        statusCode: 404,
      );
    }
    final owner = quotations
        .where((q) => q.attachments.any((a) => a.id == id))
        .firstOrNull;
    if (owner != null && owner.customerId != uid && !role.isStaff) {
      throw ApiException(
        code: 'forbidden',
        message: 'Not your quotation',
        statusCode: 403,
      );
    }
    return bytes;
  }

  /// `POST /quotations/:id/share` — rotates the token, re-sends
  /// `quote_ready`; 429 within [shareCooldown].
  SharedQuoteLink shareQuotation(String quotationId) {
    _requireRole(role.isStaff);
    final i = quotations.indexWhere((q) => q.id == quotationId);
    final q = _requireQuotation(quotationId);
    final last = _shareSentAt[quotationId];
    if (last != null && now.difference(last) < shareCooldown) {
      final wait = shareCooldown - now.difference(last);
      throw ApiException(
        code: 'rate_limited',
        message: 'Link already sent — try again in ${wait.inSeconds} s.',
        statusCode: 429,
        data: {'retry_after_seconds': wait.inSeconds},
      );
    }
    final token = _newPublicToken();
    final expires = now.add(const Duration(days: 30));
    quotations[i] = q.copyWith(
      publicUrl: '$publicWebBaseUrl/q/$token',
      updatedAt: now,
    );
    _shareSentAt[quotationId] = now;
    _sendQuoteReady(quotations[i]);
    _notify('quotations', quotationId);
    return SharedQuoteLink(publicUrl: quotations[i].publicUrl!, expiresAt: expires);
  }

  /// `GET /quotations/:id/pdf` — a small but valid single-page PDF.
  Uint8List quotationPdf(String quotationId) {
    final q = quotationDetail(quotationId);
    final lines = <String>[
      'Sparkling quotation ${q.ref}',
      '${q.outletName ?? ''}  -  ${q.vehicleLabel ?? ''}',
      for (final li in q.lineItems)
        '${li.label}  ${Money.formatZar(li.totalCents)}',
      'Total ${Money.formatZar(q.amountCents ?? 0)}',
      if (q.validUntil != null) 'Valid until ${j.isoDate(q.validUntil)}',
      'Status ${q.status.label}',
    ];
    return buildPlaceholderPdf(lines);
  }

  /// Minimal PDF 1.4 writer (Helvetica text lines, A4) with a correct xref
  /// table so viewers open it without repair.
  static Uint8List buildPlaceholderPdf(List<String> lines) {
    String esc(String s) => s
        .replaceAll('\\', '\\\\')
        .replaceAll('(', '\\(')
        .replaceAll(')', '\\)')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
    final content = StringBuffer('BT /F1 14 Tf 60 780 Td 18 TL\n');
    for (final l in lines) {
      content.write('(${esc(l)}) Tj T*\n');
    }
    content.write('ET');
    final objects = <String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R '
          '/Resources << /Font << /F1 5 0 R >> >> >>',
      '<< /Length ${content.length} >>\nstream\n$content\nendstream',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ];
    final out = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(out.length);
      out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xref = out.length;
    out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
    for (final o in offsets) {
      out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    out.write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
    );
    return Uint8List.fromList(latin1.encode(out.toString()));
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
    if (q.isDecided) {
      throw ApiException(
        code: 'conflict',
        message:
            'This quotation was already ${q.status == QuotationStatus.declined ? 'declined' : 'accepted'} ${q.decisionSource?.label ?? 'in app'}.',
        statusCode: 409,
        data: {'decided_at': j.iso(q.decidedAt), 'status': q.status.db},
      );
    }
    final expired =
        q.status == QuotationStatus.expired ||
        (q.validUntil != null && q.validUntil!.isBefore(now));
    if (expired) {
      throw ApiException(
        code: 'gone',
        message: 'This quotation has expired — ask the outlet for a new one.',
        statusCode: 410,
        data: {'ref': q.ref, 'status': QuotationStatus.expired.db},
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
      decisionSource: QuoteDecisionSource.app,
      decisionByName: nameOf(uid),
      updatedAt: now,
    );
    _pushNotification(
      q.assessorId ?? 'seed_johan',
      'quote_decided',
      'Quote ${accept ? 'accepted' : 'declined'}',
      '${q.ref} ${accept ? 'accepted' : 'declined'} in app by ${nameOf(uid) ?? 'the customer'}.',
      {'type': 'quotation', 'id': id},
    );
    _notify('quotations', id);
    return _expandQuotation(quotations[i]);
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
    final linked = q.lineItems
        .map((i) => i.serviceId)
        .whereType<String>()
        .map(serviceById)
        .whereType<Service>()
        .firstOrNull;
    final code = QuoteCategories.serviceCodeFor(q.category.split(',').first.trim());
    final service =
        linked ??
        services.where((s) => s.code == code).firstOrNull ??
        serviceById(svcSpotRepair)!;
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
    if (b.totalCents <= 0) {
      throw ApiException(
        code: 'validation_error',
        message: 'Nothing to pay — this service is included in your plan.',
        statusCode: 400,
        data: {'reason': 'nothing_to_pay'},
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
    if (p.membershipInvoiceId != null) {
      _applyMembershipInvoicePaid(p.membershipInvoiceId!, p.id);
    }
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
      membership: membershipBriefOf(uid),
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
    // Tier = plan (docs/MEMBERSHIPS.md): points no longer promote tiers.
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
        collectedAt: wo.collectedAt,
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
      _issuePickupOtp(workOrders[wi]);
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
  // Vehicle hand-over (collection OTP)
  // ---------------------------------------------------------------------------

  /// Generates a fresh 5-digit OTP for [wo], resets the attempt counter and
  /// sends it to the customer by WhatsApp (mirrored in the inbox).
  void _issuePickupOtp(WorkOrder wo, {bool resend = false}) {
    _otpSeq++;
    final code = ((wo.ref.hashCode.abs() + _otpSeq * 7919) % 90000 + 10000)
        .toString();
    pickupOtps[wo.id] = code;
    _otpAttempts.remove(wo.id);
    final vehicle = vehicleById(wo.vehicleId);
    _pushNotification(
      wo.customerId,
      'pickup_otp',
      'Ready for collection',
      'Your ${vehicle?.displayName ?? 'vehicle'} is ready at ${outletById(wo.outletId)?.name}. Collection OTP: $code — show it at the counter to collect your keys.',
      {'type': 'booking', 'id': wo.bookingId ?? wo.id},
      channel: NotifyChannel.whatsapp,
      providerStatus: resend ? 'queued' : 'sent',
    );
  }

  /// `POST /work-orders/:id/pickup/verify` — staff only.
  PickupVerifyResult verifyPickupOtp(String workOrderId, String otp) {
    _requireRole(role.isStaff);
    final wi = workOrders.indexWhere((w) => w.id == workOrderId);
    final wo = _requireWorkOrder(workOrderId);
    if (wo.collectedAt != null) {
      throw ApiException(
        code: 'invalid_transition',
        message:
            'Keys were already released at ${SparklingDates.hhmm(wo.collectedAt!)}.',
        statusCode: 409,
      );
    }
    if (wo.status != WorkStatus.verified) {
      throw ApiException(
        code: 'invalid_transition',
        message: 'The work must be verified before the vehicle is handed over.',
        statusCode: 409,
      );
    }
    final attempts = _otpAttempts[workOrderId] ?? 0;
    if (attempts >= maxOtpAttempts) {
      throw ApiException(
        code: 'rate_limited',
        message: 'Too many incorrect codes. Re-send a new OTP to the customer and try again.',
        statusCode: 429,
      );
    }
    final expected = pickupOtps[workOrderId];
    if (expected == null || otp.trim() != expected) {
      final used = attempts + 1;
      _otpAttempts[workOrderId] = used;
      final left = maxOtpAttempts - used;
      if (left <= 0) {
        throw ApiException(
          code: 'rate_limited',
          message: 'Too many incorrect codes. Re-send a new OTP to the customer and try again.',
          statusCode: 429,
          data: const {
            'code': 'rate_limited',
            'details': {'attempts_left': 0},
          },
        );
      }
      throw ApiException(
        code: 'invalid_otp',
        message: 'That code is not correct.',
        statusCode: 409,
        data: {
          'code': 'invalid_otp',
          'details': {'attempts_left': left},
        },
      );
    }
    final at = now;
    workOrders[wi] = wo.copyWith(
      pickupOtpVerifiedAt: at,
      collectedAt: at,
      updatedAt: at,
    );
    _otpAttempts.remove(workOrderId);
    final task = tasks.where((t) => t.workOrderId == workOrderId).firstOrNull;
    taskEvents.add(
      TaskEvent(
        id: _newId('8'),
        taskId: task?.id,
        workOrderId: workOrderId,
        actorId: uid,
        actorName: nameOf(uid),
        event: 'pickup_verified',
        fromStatus: wo.status.db,
        toStatus: wo.status.db,
        reason: 'Collection OTP verified · keys released',
        createdAt: at,
      ),
    );
    _notify('work_orders', workOrderId);
    if (task != null) _notify('tasks', task.id);
    if (wo.bookingId != null) _notify('bookings', wo.bookingId);
    return PickupVerifyResult(verified: true, collectedAt: at);
  }

  /// `POST /work-orders/:id/pickup/resend` — staff only, 60 s cooldown.
  void resendPickupOtp(String workOrderId) {
    _requireRole(role.isStaff);
    final wi = workOrders.indexWhere((w) => w.id == workOrderId);
    final wo = _requireWorkOrder(workOrderId);
    if (wo.collectedAt != null || wo.status != WorkStatus.verified) {
      throw ApiException(
        code: 'invalid_transition',
        message: wo.collectedAt != null
            ? 'The vehicle has already been collected.'
            : 'The work must be verified before an OTP can be sent.',
        statusCode: 409,
      );
    }
    final last = _otpResentAt[workOrderId];
    if (last != null && now.difference(last) < otpResendCooldown) {
      final wait = otpResendCooldown - now.difference(last);
      throw ApiException(
        code: 'rate_limited',
        message: 'An OTP was just sent. Try again in ${wait.inSeconds} s.',
        statusCode: 429,
      );
    }
    _otpResentAt[workOrderId] = now;
    _issuePickupOtp(workOrders[wi], resend: true);
    _notify('work_orders', workOrderId);
    if (wo.bookingId != null) _notify('bookings', wo.bookingId);
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
    Map<String, dynamic> payload, {
    NotifyChannel channel = NotifyChannel.push,
    String? providerStatus,
  }) {
    notifications.add(
      AppNotification(
        id: _newId('c'),
        recipientId: recipientId,
        channel: channel,
        templateKey: key,
        title: title,
        body: body,
        payload: payload,
        status: NotifyStatus.sent,
        attempts: 1,
        providerStatus:
            providerStatus ??
            (channel == NotifyChannel.whatsapp ? 'sent' : null),
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
  // Memberships (docs/MEMBERSHIPS.md) — plans, allowances, pricing, lifecycle
  // ---------------------------------------------------------------------------

  /// Adds calendar months, clamping to the last day of the target month.
  static DateTime addMonths(DateTime d, int months) {
    final y = d.year + ((d.month - 1 + months) ~/ 12);
    final m = (d.month - 1 + months) % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    final day = math.min(d.day, lastDay);
    return d.isUtc
        ? DateTime.utc(y, m, day, d.hour, d.minute, d.second, d.millisecond)
        : DateTime(y, m, day, d.hour, d.minute, d.second, d.millisecond);
  }

  static DateTime _addYears(DateTime d, int years) => addMonths(d, 12 * years);

  MembershipPlan? planById(String id) =>
      membershipPlans.where((p) => p.id == id).firstOrNull;
  MembershipPlan? planByCode(String code) =>
      membershipPlans.where((p) => p.code == code).firstOrNull;

  MembershipPlan _requirePlan(String code) =>
      planByCode(code) ??
      (throw ApiException(
        code: 'not_found',
        message: 'Plan "$code" not found',
        statusCode: 404,
      ));

  /// The customer's one live (pending / active / past_due) membership.
  Membership? liveMembership(String customerId) => memberships
      .where((m) => m.customerId == customerId && m.isLive)
      .firstOrNull;

  Membership _requireLiveMembership(String customerId) =>
      liveMembership(customerId) ??
      (throw ApiException(
        code: 'not_found',
        message: 'No active membership',
        statusCode: 404,
      ));

  /// Tier = plan: the live active / past-due membership's plan tier, else
  /// silver (`memberships_sync_tier`).
  LoyaltyTier tierOf(String customerId) {
    final m = liveMembership(customerId);
    if (m == null || m.isPending) return LoyaltyTier.silver;
    return planById(m.planId)?.tier ?? LoyaltyTier.silver;
  }

  void _syncTier(String customerId) {
    final tier = tierOf(customerId);
    final current = loyaltyTiers[customerId];
    if (current?.tier == tier) return;
    if (tier == LoyaltyTier.silver) {
      loyaltyTiers.remove(customerId);
    } else {
      loyaltyTiers[customerId] = (
        tier: tier,
        tierSince: liveMembership(customerId)?.startedAt ?? now,
      );
    }
    _notify('loyalty_accounts', customerId);
  }

  void _validateSelections(MembershipPlan plan, Map<String, String> selections) {
    for (final g in plan.chooseOneGroups) {
      final code = selections[g.code];
      if (code == null || g.entitlement(code) == null) {
        throw ApiException(
          code: 'validation_error',
          message:
              'Choose one option for "${g.name}" (${g.entitlements.map((e) => e.code).join(' / ')}).',
          statusCode: 400,
          data: {'group_code': g.code},
        );
      }
    }
  }

  /// `[anniversary, anniversary + 1 year)` covering now.
  (DateTime, DateTime) _membershipYear(Membership m) {
    var start = m.startedAt ?? m.currentPeriodStart ?? now;
    while (!_addYears(start, 1).isAfter(now)) {
      start = _addYears(start, 1);
    }
    return (start, _addYears(start, 1));
  }

  (DateTime, DateTime) _entitlementPeriod(
    Membership m,
    MembershipEntitlement e,
  ) => e.period == EntitlementPeriod.year
      ? _membershipYear(m)
      : (
          m.currentPeriodStart ?? now,
          m.currentPeriodEnd ?? addMonths(m.currentPeriodStart ?? now, 1),
        );

  Allowance _allowanceOf(
    Membership m,
    MembershipPlan plan,
    MembershipEntitlement e,
  ) {
    final (start, end) = _entitlementPeriod(m, e);
    final used = membershipUsage
        .where(
          (u) =>
              u.membershipId == m.id &&
              u.entitlementId == e.id &&
              u.periodStart.isAtSameMomentAs(start),
        )
        .fold(0, (s, u) => s + u.quantity);
    return Allowance(
      entitlementId: e.id,
      entitlementCode: e.code,
      groupCode: plan.groupOf(e)?.code ?? '',
      label: e.label,
      quantity: e.quantity,
      used: used,
      remaining: math.max(0, e.quantity - used),
      period: e.period,
      periodStart: start,
      periodEnd: end,
      itemName: e.itemName,
    );
  }

  /// Remaining quantity per selected entitlement for the current period(s).
  List<Allowance> allowancesFor(Membership m) {
    final plan = planById(m.planId);
    if (plan == null) return const [];
    final sel = membershipSelections[m.id] ?? const <String, String>{};
    return [
      for (final e in plan.selectedEntitlements(sel)) _allowanceOf(m, plan, e),
    ];
  }

  /// `GET /memberships/me` for [customerId] ([MembershipSummary.none] when
  /// the customer has no live membership).
  MembershipSummary membershipSummary(String customerId) {
    final m = liveMembership(customerId);
    if (m == null) return MembershipSummary.none;
    final plan = planById(m.planId);
    final sel = membershipSelections[m.id] ?? const <String, String>{};
    final invoices =
        membershipInvoices.where((i) => i.membershipId == m.id).toList()
          ..sort(
            (a, b) => (b.periodStart ?? b.createdAt ?? now).compareTo(
              a.periodStart ?? a.createdAt ?? now,
            ),
          );
    final open =
        invoices.where((i) => i.isPending).toList()
          ..sort((a, b) => (a.dueAt ?? now).compareTo(b.dueAt ?? now));
    return MembershipSummary(
      membership: m.copyWith(planCode: plan?.code),
      plan: plan,
      selections: Map.unmodifiable(sel),
      allowances: allowancesFor(m),
      openInvoice: open.firstOrNull,
      invoices: invoices.take(12).toList(),
      nextRenewalAt: m.cancelAtPeriodEnd ? null : m.currentPeriodEnd,
      benefitsSummary: plan?.benefitsSummary(sel),
    );
  }

  /// The `membership` block of `GET /loyalty/account` / `GET /me`.
  MembershipBrief? membershipBriefOf(String customerId) {
    final m = liveMembership(customerId);
    final plan = m == null ? null : planById(m.planId);
    if (m == null || plan == null) return null;
    return MembershipBrief(
      planCode: plan.code,
      planName: plan.name,
      status: m.status,
      periodEnd: m.currentPeriodEnd,
      allowances: allowancesFor(m),
    );
  }

  /// `GET /memberships/plans`.
  MembershipPlanList membershipPlanList() {
    final live = liveMembership(uid);
    return MembershipPlanList(
      plans: membershipPlans.where((p) => p.isActive).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      currentPlanCode: live == null ? null : planById(live.planId)?.code,
    );
  }

  /// Plan benefit on a priced service (docs/MEMBERSHIPS.md "Pricing rules"
  /// 2–3): covered with allowance → base waived; otherwise the plan discount
  /// by scope. `past_due` / `pending` → no benefits.
  ({
    int discount,
    String? label,
    BookingMembership? block,
    Membership? membership,
    MembershipEntitlement? entitlement,
  })
  _membershipPricing({
    required String customerId,
    required OutletService offer,
    required int base,
    required int addonsCents,
  }) {
    const none = (
      discount: 0,
      label: null,
      block: null,
      membership: null,
      entitlement: null,
    );
    final m = liveMembership(customerId);
    if (m == null || !m.benefitsActive) return none;
    final plan = planById(m.planId);
    if (plan == null) return none;
    final summary = membershipSummary(customerId);
    final covering = summary.coveringAllowance(offer.code);
    if (covering != null) {
      final e = plan.entitlementById(covering.entitlementId)!;
      final after = covering.remaining - 1;
      return (
        discount: base,
        label: 'Included in ${plan.name} · $after of ${covering.quantity} left',
        block: BookingMembership(
          planCode: plan.code,
          planName: plan.name,
          benefit: MembershipBenefit.included,
          entitlementCode: e.code,
          remainingAfter: after,
          periodEnd: covering.periodEnd,
        ),
        membership: m,
        entitlement: e,
      );
    }
    final pct = summary.discountPctFor(offer.code);
    if (pct > 0) {
      return (
        discount: ((base + addonsCents) * pct / 100).round(),
        label: '${plan.name} −$pct%',
        block: BookingMembership(
          planCode: plan.code,
          planName: plan.name,
          benefit: MembershipBenefit.discount,
          periodEnd: m.currentPeriodEnd,
        ),
        membership: m,
        entitlement: null,
      );
    }
    return (
      discount: 0,
      label: null,
      block: BookingMembership(
        planCode: plan.code,
        planName: plan.name,
        periodEnd: m.currentPeriodEnd,
      ),
      membership: m,
      entitlement: null,
    );
  }

  /// `priceService` as a [PriceQuote] (what `POST /bookings` would record).
  PriceQuote quoteBooking({
    required String outletId,
    required String serviceId,
    required Vehicle vehicle,
    VehicleSize? vehicleSize,
    List<String> addonServiceIds = const [],
    String? customerId,
  }) {
    final q = priceBooking(
      outletId: outletId,
      serviceId: serviceId,
      vehicle: vehicle,
      vehicleSize: vehicleSize,
      addonServiceIds: addonServiceIds,
      customerId: customerId ?? vehicle.customerId,
    );
    return PriceQuote(
      priceCents: q.base,
      addons: q.addons,
      addonsCents: q.addonsCents,
      discountCents: q.discount,
      discountLabel: q.discountLabel,
      vatCents: q.vat,
      totalCents: q.total,
      pointsPending: (q.total / 100 * loyaltyConfig.rules.pointsPerRand).round(),
      vehicleSize: q.size,
      pricingMode: q.offer.pricingMode,
      vatMode: q.offer.vatMode,
      membership: q.membership,
    );
  }

  /// `+1` usage row when a booking redeemed an entitlement
  /// (key `booking:<id>:membership`, idempotent).
  void _redeemMembershipUsage(Booking b) {
    if (!b.isIncluded || b.membershipId == null || b.entitlementId == null) {
      return;
    }
    final key = 'booking:${b.id}:membership';
    if (_idempotencyKeys.contains(key)) return;
    final m = memberships.where((m) => m.id == b.membershipId).firstOrNull;
    final plan = m == null ? null : planById(m.planId);
    final e = plan?.entitlementById(b.entitlementId!);
    if (m == null || e == null) return;
    final (start, end) = _entitlementPeriod(m, e);
    membershipUsage.add(
      MembershipUsage(
        id: _newId('u'),
        membershipId: m.id,
        entitlementId: e.id,
        bookingId: b.id,
        quantity: 1,
        periodStart: start,
        periodEnd: end,
        idempotencyKey: key,
        createdBy: uid,
        createdAt: now,
      ),
    );
    _idempotencyKeys.add(key);
    _notify('membership_usage', b.id);
  }

  /// `−1` release row when an included booking is cancelled
  /// (key `booking:<id>:membership_release`, idempotent).
  void _releaseMembershipUsage(Booking b) {
    if (!b.isIncluded || b.membershipId == null) return;
    final key = 'booking:${b.id}:membership_release';
    if (_idempotencyKeys.contains(key)) return;
    final redeemed = membershipUsage
        .where((u) => u.bookingId == b.id && u.quantity > 0)
        .firstOrNull;
    if (redeemed == null) return;
    membershipUsage.add(
      MembershipUsage(
        id: _newId('u'),
        membershipId: redeemed.membershipId,
        entitlementId: redeemed.entitlementId,
        bookingId: b.id,
        quantity: -1,
        periodStart: redeemed.periodStart,
        periodEnd: redeemed.periodEnd,
        idempotencyKey: key,
        createdBy: uid,
        createdAt: now,
      ),
    );
    _idempotencyKeys.add(key);
    _notify('membership_usage', b.id);
  }

  MembershipInvoice _newInvoice(
    Membership m,
    MembershipPlan plan, {
    required DateTime periodStart,
    required DateTime periodEnd,
    required String idempotencyKey,
    DateTime? dueAt,
  }) => MembershipInvoice(
    id: _newId('5'),
    ref: 'MINV-$_yr-${(_membershipInvoiceSeq++).toString().padLeft(4, '0')}',
    membershipId: m.id,
    customerId: m.customerId,
    periodStart: periodStart,
    periodEnd: periodEnd,
    amountCents: plan.monthlyFeeCents,
    status: MembershipInvoiceStatus.pending,
    dueAt: dueAt ?? periodStart,
    idempotencyKey: idempotencyKey,
    createdAt: now,
  );

  PaymentIntentResult _membershipPaymentIntent(
    MembershipInvoice inv, {
    required String idempotencyKey,
  }) {
    final existing = payments
        .where(
          (p) =>
              p.membershipInvoiceId == inv.id &&
              (p.idempotencyKey == idempotencyKey ||
                  p.status == PaymentStatus.pending),
        )
        .firstOrNull;
    if (existing != null) {
      return PaymentIntentResult(
        payment: existing,
        clientSecret:
            'sbx_secret_${existing.id.substring(existing.id.length - 6)}',
      );
    }
    final p = Payment(
      id: _newId('6'),
      membershipInvoiceId: inv.id,
      customerId: inv.customerId,
      providerRef: 'pi_sbx_${inv.ref.split('-').last}',
      methodId: paymentMethods
          .where((m) => m.customerId == inv.customerId && m.isDefault)
          .firstOrNull
          ?.id,
      amountCents: inv.amountCents,
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

  String _benefitsLine(Membership m) {
    final plan = planById(m.planId);
    if (plan == null) return '';
    return plan.benefitsSummary(membershipSelections[m.id] ?? const {});
  }

  /// Marks the invoice paid and activates / renews / upgrades the
  /// membership (webhook + counter payments share this path).
  void _applyMembershipInvoicePaid(String invoiceId, String paymentId) {
    final ii = membershipInvoices.indexWhere((i) => i.id == invoiceId);
    if (ii < 0) return;
    var inv = membershipInvoices[ii];
    if (inv.isPaid) return;
    inv = inv.copyWith(
      status: MembershipInvoiceStatus.paid,
      paidAt: now,
      paymentId: paymentId,
    );
    membershipInvoices[ii] = inv;
    final mi = memberships.indexWhere((m) => m.id == inv.membershipId);
    if (mi < 0) return;
    var m = memberships[mi];
    final upgrade = _pendingUpgrades.remove(inv.id);
    String key;
    if (upgrade != null) {
      m = m.copyWith(
        planId: upgrade.planId,
        planCode: planById(upgrade.planId)?.code,
        status: MembershipStatus.active,
        currentPeriodStart: now,
        currentPeriodEnd: addMonths(now, 1),
        clearNextPlan: true,
        updatedAt: now,
      );
      membershipSelections[m.id] = Map.of(upgrade.selections);
      key = 'membership_activated';
    } else if (m.isPending) {
      m = m.copyWith(
        status: MembershipStatus.active,
        startedAt: now,
        currentPeriodStart: now,
        currentPeriodEnd: addMonths(now, 1),
        updatedAt: now,
      );
      key = 'membership_activated';
    } else {
      // Renewal: roll the period (applying a pending downgrade).
      final start = inv.periodStart ?? m.currentPeriodEnd ?? now;
      var planId = m.planId;
      Map<String, String>? sel;
      if (m.nextPlanId != null) {
        planId = m.nextPlanId!;
        sel =
            membershipNextSelections.remove(m.id) ??
            planById(planId)?.defaultSelections();
      }
      m = m.copyWith(
        planId: planId,
        planCode: planById(planId)?.code,
        status: MembershipStatus.active,
        currentPeriodStart: start,
        currentPeriodEnd: inv.periodEnd ?? addMonths(start, 1),
        clearNextPlan: true,
        updatedAt: now,
      );
      if (sel != null) membershipSelections[m.id] = sel;
      key = 'membership_renewed';
    }
    memberships[mi] = m;
    _syncTier(m.customerId);
    final plan = planById(m.planId);
    _pushNotification(
      m.customerId,
      key,
      key == 'membership_renewed'
          ? '${plan?.name} membership renewed'
          : 'Welcome to Sparkling ${plan?.name}',
      key == 'membership_renewed'
          ? 'Paid ${Money.formatZar(inv.amountCents)}. Your washes have been reset for the month.'
          : 'Your ${plan?.name} membership is active until ${SparklingDates.dayMonth(m.currentPeriodEnd!)}. ${_benefitsLine(m)}',
      {'type': 'membership', 'id': m.id},
    );
    _notify('membership_invoices', inv.id);
    _notify('memberships', m.id);
  }

  /// `POST /memberships` — pending membership + first invoice + sandbox
  /// payment intent; activation happens when the payment is confirmed.
  SubscribeResult subscribeMembership({
    required String planCode,
    required Map<String, String> selections,
    required String clientOpId,
    MembershipPaymentMethod paymentMethod = MembershipPaymentMethod.card,
  }) {
    _requireRole(role == UserRole.customer, 'Only customers can subscribe.');
    final existing = memberships
        .where((m) => m.clientOpId == clientOpId)
        .firstOrNull;
    if (existing != null) return _subscribeResultFor(existing);
    final plan = _requirePlan(planCode);
    final live = liveMembership(uid);
    if (live != null) {
      throw ApiException(
        code: 'conflict',
        message:
            'You already have a ${planById(live.planId)?.name ?? ''} membership (${live.status.label.toLowerCase()}).',
        statusCode: 409,
        data: {'membership_id': live.id, 'status': live.status.db},
      );
    }
    _validateSelections(plan, selections);
    final m = Membership(
      id: _newId('7'),
      ref: 'MEM-$_yr-${(_membershipSeq++).toString().padLeft(4, '0')}',
      customerId: uid,
      planId: plan.id,
      planCode: plan.code,
      status: MembershipStatus.pending,
      paymentMethod: paymentMethod,
      clientOpId: clientOpId,
      createdBy: uid,
      createdAt: now,
      updatedAt: now,
    );
    memberships.add(m);
    membershipSelections[m.id] = Map.of(selections);
    final inv = _newInvoice(
      m,
      plan,
      periodStart: now,
      periodEnd: addMonths(now, 1),
      idempotencyKey: 'subscribe:${m.id}',
    );
    membershipInvoices.add(inv);
    _idempotencyKeys.add(clientOpId);
    _notify('memberships', m.id);
    _notify('membership_invoices', inv.id);
    return SubscribeResult(
      membership: m,
      invoice: inv,
      payment: _membershipPaymentIntent(
        inv,
        idempotencyKey: 'membership:${m.id}:first',
      ),
    );
  }

  SubscribeResult _subscribeResultFor(Membership m) {
    final inv = membershipInvoices
        .where((i) => i.membershipId == m.id)
        .firstOrNull;
    final pay = inv == null
        ? null
        : payments.where((p) => p.membershipInvoiceId == inv.id).firstOrNull;
    return SubscribeResult(
      membership: m,
      invoice: inv,
      payment: pay == null || !inv!.isPending
          ? null
          : PaymentIntentResult(
              payment: pay,
              clientSecret: 'sbx_secret_${pay.id.substring(pay.id.length - 6)}',
            ),
    );
  }

  /// `POST /memberships/me/invoices/:id/pay`.
  PaymentIntentResult payMembershipInvoice(
    String invoiceId, {
    required String idempotencyKey,
  }) {
    final inv =
        membershipInvoices.where((i) => i.id == invoiceId).firstOrNull ??
        (throw ApiException(
          code: 'not_found',
          message: 'Invoice not found',
          statusCode: 404,
        ));
    if (inv.customerId != uid && role == UserRole.customer) {
      throw ApiException(
        code: 'forbidden',
        message: 'Not your invoice',
        statusCode: 403,
      );
    }
    if (!inv.isPending) {
      throw ApiException(
        code: 'conflict',
        message: 'Invoice ${inv.ref} is already ${inv.status.label.toLowerCase()}.',
        statusCode: 409,
      );
    }
    return _membershipPaymentIntent(inv, idempotencyKey: idempotencyKey);
  }

  /// `PUT /memberships/me/selections` — 409 once anything was used.
  MembershipSummary changeMembershipSelections(Map<String, String> selections) {
    final m = _requireLiveMembership(uid);
    final plan = planById(m.planId)!;
    _validateSelections(plan, selections);
    final used = allowancesFor(m).where((a) => a.used > 0).toList();
    if (used.isNotEmpty) {
      throw ApiException(
        code: 'conflict',
        message:
            'You have already used ${used.first.used} of your ${used.first.noun.toLowerCase()} allowance this month — options can change from ${SparklingDates.dayMonth(m.currentPeriodEnd ?? now)}.',
        statusCode: 409,
        data: {'period_end': j.iso(m.currentPeriodEnd)},
      );
    }
    membershipSelections[m.id] = Map.of(selections);
    _notify('memberships', m.id);
    return membershipSummary(uid);
  }

  /// `POST /memberships/me/change-plan` — upgrade now (new invoice +
  /// payment), downgrade at renewal (`next_plan_id`).
  SubscribeResult changeMembershipPlan({
    required String planCode,
    required Map<String, String> selections,
    required String clientOpId,
  }) {
    var m = _requireLiveMembership(uid);
    final current = planById(m.planId)!;
    final target = _requirePlan(planCode);
    if (target.id == current.id) {
      throw ApiException(
        code: 'validation_error',
        message: 'You are already on ${current.name}.',
        statusCode: 400,
      );
    }
    _validateSelections(target, selections);
    final mi = memberships.indexWhere((x) => x.id == m.id);
    if (target.monthlyFeeCents > current.monthlyFeeCents) {
      final inv = _newInvoice(
        m,
        target,
        periodStart: now,
        periodEnd: addMonths(now, 1),
        idempotencyKey: 'upgrade:${m.id}:$clientOpId',
      );
      membershipInvoices.add(inv);
      _pendingUpgrades[inv.id] = (
        planId: target.id,
        selections: Map.of(selections),
      );
      _notify('membership_invoices', inv.id);
      return SubscribeResult(
        membership: m,
        invoice: inv,
        payment: _membershipPaymentIntent(inv, idempotencyKey: clientOpId),
      );
    }
    m = m.copyWith(nextPlanId: target.id, updatedAt: now);
    memberships[mi] = m;
    membershipNextSelections[m.id] = Map.of(selections);
    _notify('memberships', m.id);
    return SubscribeResult(membership: m);
  }

  /// `POST /memberships/me/cancel`.
  MembershipSummary cancelMembership({bool atPeriodEnd = true}) {
    var m = _requireLiveMembership(uid);
    final mi = memberships.indexWhere((x) => x.id == m.id);
    final plan = planById(m.planId);
    if (atPeriodEnd && m.isActive) {
      m = m.copyWith(
        cancelAtPeriodEnd: true,
        cancelledAt: now,
        clearNextPlan: true,
        updatedAt: now,
      );
    } else {
      m = m.copyWith(
        status: MembershipStatus.cancelled,
        cancelledAt: now,
        endedAt: now,
        clearNextPlan: true,
        updatedAt: now,
      );
    }
    memberships[mi] = m;
    for (var i = 0; i < membershipInvoices.length; i++) {
      final inv = membershipInvoices[i];
      if (inv.membershipId == m.id && inv.isPending) {
        membershipInvoices[i] = inv.copyWith(
          status: MembershipInvoiceStatus.voided,
        );
      }
    }
    _pendingUpgrades.removeWhere((_, u) => false);
    _syncTier(m.customerId);
    _pushNotification(
      m.customerId,
      'membership_cancelled',
      'Membership cancelled',
      m.isLive
          ? 'Your ${plan?.name} membership ends on ${SparklingDates.dayMonth(m.currentPeriodEnd ?? now)}. You can rejoin any time.'
          : 'Your ${plan?.name} membership has ended. You can rejoin any time.',
      {'type': 'membership', 'id': m.id},
    );
    _notify('memberships', m.id);
    return membershipSummary(uid);
  }

  /// `GET /staff/customers/:id/membership`.
  MembershipSummary customerMembershipSummary(String customerId) {
    _requireRole(role.isStaff);
    requireProfile(customerId);
    return membershipSummary(customerId);
  }

  /// `POST /staff/customers/:id/membership` — enrol at the counter: active
  /// immediately, invoice paid, POS payment recorded.
  MembershipSummary enrolMembership(EnrolMembershipInput input) {
    _requireRole(role.isStaff);
    if (_idempotencyKeys.contains(input.clientOpId)) {
      return membershipSummary(input.customerId);
    }
    final customer = requireProfile(input.customerId);
    if (customer.role != UserRole.customer) {
      throw ApiException(
        code: 'validation_error',
        message: 'Not a customer profile',
        statusCode: 400,
      );
    }
    final plan = _requirePlan(input.planCode);
    final live = liveMembership(customer.id);
    if (live != null) {
      throw ApiException(
        code: 'conflict',
        message:
            '${customer.fullName.split(' ').first} already has a ${planById(live.planId)?.name ?? ''} membership (${live.status.label.toLowerCase()}).',
        statusCode: 409,
        data: {'membership_id': live.id, 'status': live.status.db},
      );
    }
    _validateSelections(plan, input.selections);
    final m = Membership(
      id: _newId('7'),
      ref: 'MEM-$_yr-${(_membershipSeq++).toString().padLeft(4, '0')}',
      customerId: customer.id,
      planId: plan.id,
      planCode: plan.code,
      status: MembershipStatus.active,
      startedAt: now,
      currentPeriodStart: now,
      currentPeriodEnd: addMonths(now, 1),
      paymentMethod: input.paymentMethod.stored,
      clientOpId: input.clientOpId,
      createdBy: uid,
      createdAt: now,
      updatedAt: now,
    );
    memberships.add(m);
    membershipSelections[m.id] = Map.of(input.selections);
    final receiptNo = 'RCP-${_receiptSeq++}';
    final p = Payment(
      id: _newId('6'),
      customerId: customer.id,
      provider: 'pos',
      providerRef: 'pos_${m.ref.split('-').last}',
      amountCents: plan.monthlyFeeCents,
      status: PaymentStatus.successful,
      receiptNo: receiptNo,
      idempotencyKey: input.clientOpId,
      verifiedAt: now,
      createdAt: now,
      updatedAt: now,
      receipt: {
        'receipt_no': receiptNo,
        'amount_cents': plan.monthlyFeeCents,
        'method': input.paymentMethod.db,
        'recorded_by': nameOf(uid),
        'paid_at': j.iso(now),
      },
    );
    final inv = _newInvoice(
      m,
      plan,
      periodStart: m.currentPeriodStart!,
      periodEnd: m.currentPeriodEnd!,
      idempotencyKey: 'enrol:${m.id}',
    ).copyWith(
      status: MembershipInvoiceStatus.paid,
      paidAt: now,
      paymentId: p.id,
    );
    payments.add(p.copyWith(status: PaymentStatus.successful));
    // The payment row needs the invoice id — rebuild with it.
    payments[payments.length - 1] = Payment(
      id: p.id,
      membershipInvoiceId: inv.id,
      customerId: p.customerId,
      provider: p.provider,
      providerRef: p.providerRef,
      amountCents: p.amountCents,
      status: p.status,
      receiptNo: p.receiptNo,
      idempotencyKey: p.idempotencyKey,
      verifiedAt: p.verifiedAt,
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
      receipt: p.receipt,
    );
    membershipInvoices.add(inv);
    _idempotencyKeys.add(input.clientOpId);
    _syncTier(customer.id);
    _pushNotification(
      customer.id,
      'membership_activated',
      'Welcome to Sparkling ${plan.name}',
      'Your ${plan.name} membership is active until ${SparklingDates.dayMonth(m.currentPeriodEnd!)}. ${_benefitsLine(m)}',
      {'type': 'membership', 'id': m.id},
    );
    _notify('memberships', m.id);
    _notify('membership_invoices', inv.id);
    _notify('payments', p.id);
    return membershipSummary(customer.id);
  }

  /// `POST /staff/memberships/:id/invoices/:invoiceId/record-payment`.
  MembershipSummary recordMembershipInvoicePayment({
    required String membershipId,
    required String invoiceId,
    required CounterPaymentMethod method,
    required String clientOpId,
  }) {
    _requireRole(role.isStaff);
    final m =
        memberships.where((x) => x.id == membershipId).firstOrNull ??
        (throw ApiException(
          code: 'not_found',
          message: 'Membership not found',
          statusCode: 404,
        ));
    if (_idempotencyKeys.contains(clientOpId)) {
      return membershipSummary(m.customerId);
    }
    final inv =
        membershipInvoices
            .where((i) => i.id == invoiceId && i.membershipId == m.id)
            .firstOrNull ??
        (throw ApiException(
          code: 'not_found',
          message: 'Invoice not found',
          statusCode: 404,
        ));
    if (!inv.isPending) {
      throw ApiException(
        code: 'conflict',
        message: 'Invoice ${inv.ref} is already ${inv.status.label.toLowerCase()}.',
        statusCode: 409,
      );
    }
    final receiptNo = 'RCP-${_receiptSeq++}';
    final p = Payment(
      id: _newId('6'),
      membershipInvoiceId: inv.id,
      customerId: m.customerId,
      provider: 'pos',
      providerRef: 'pos_${inv.ref.split('-').last}',
      amountCents: inv.amountCents,
      status: PaymentStatus.successful,
      receiptNo: receiptNo,
      idempotencyKey: clientOpId,
      verifiedAt: now,
      createdAt: now,
      updatedAt: now,
      receipt: {
        'receipt_no': receiptNo,
        'amount_cents': inv.amountCents,
        'method': method.db,
        'recorded_by': nameOf(uid),
        'paid_at': j.iso(now),
      },
    );
    payments.add(p);
    _idempotencyKeys.add(clientOpId);
    _applyMembershipInvoicePaid(inv.id, p.id);
    _notify('payments', p.id);
    return membershipSummary(m.customerId);
  }

  /// The daily `membershipRenewals` job (docs/MEMBERSHIPS.md): ends
  /// memberships cancelled at period end, raises the next invoice 3 days
  /// before renewal and marks unpaid periods `past_due`. The sandbox card
  /// auto-charge (step 4) is intentionally not simulated so a past-due
  /// member can be demonstrated.
  void runMembershipRenewals() {
    for (var i = 0; i < memberships.length; i++) {
      var m = memberships[i];
      if (!m.isLive || m.isPending) continue;
      final end = m.currentPeriodEnd;
      if (end == null) continue;
      if (m.cancelAtPeriodEnd && !end.isAfter(now)) {
        m = m.copyWith(
          status: MembershipStatus.expired,
          endedAt: now,
          updatedAt: now,
        );
        memberships[i] = m;
        _syncTier(m.customerId);
        _notify('memberships', m.id);
        continue;
      }
      final key = 'renewal:${m.id}:${j.isoDate(end)}';
      final hasNext = membershipInvoices.any((x) => x.idempotencyKey == key);
      if (!m.cancelAtPeriodEnd &&
          !hasNext &&
          !end.isAfter(now.add(const Duration(days: 3)))) {
        final plan = planById(m.nextPlanId ?? m.planId)!;
        final inv = _newInvoice(
          m,
          plan,
          periodStart: end,
          periodEnd: addMonths(end, 1),
          idempotencyKey: key,
          dueAt: end,
        );
        membershipInvoices.add(inv);
        _pushNotification(
          m.customerId,
          'membership_renewal_due',
          '${plan.name} membership renewal',
          'Your ${plan.name} membership renews on ${SparklingDates.dayMonth(end)} (${Money.formatZar(inv.amountCents)}).',
          {'type': 'membership', 'id': m.id},
        );
        _notify('membership_invoices', inv.id);
      }
      if (m.isActive && !end.isAfter(now)) {
        final unpaid = membershipInvoices.any(
          (x) => x.membershipId == m.id && x.isPending,
        );
        if (unpaid) {
          m = m.copyWith(status: MembershipStatus.pastDue, updatedAt: now);
          memberships[i] = m;
          final plan = planById(m.planId);
          _pushNotification(
            m.customerId,
            'membership_past_due',
            'Membership payment due',
            'Your ${plan?.name} benefits are paused until ${Money.formatZar(plan?.monthlyFeeCents ?? 0)} is paid.',
            {'type': 'membership', 'id': m.id},
          );
          _notify('memberships', m.id);
        }
      }
    }
  }

  // ---- Seed (mirrors backend/supabase/seed_memberships.sql) ----------------

  void _seedMemberships(DateTime n) {
    EntitlementService es(String id, {bool primary = false}) {
      final s = serviceById(id)!;
      return EntitlementService(
        id: s.id,
        code: s.code,
        name: s.name,
        isPrimary: primary,
      );
    }

    final sparkling = [es(DemoCatalogueIds.sparklingWash, primary: true)];
    final exterior = [
      es(DemoCatalogueIds.extWash, primary: true),
      es(DemoCatalogueIds.extWashTyre),
      es(DemoCatalogueIds.washGo),
    ];
    MembershipEntitlement ent(
      int n,
      String code,
      String label,
      int qty,
      List<EntitlementService> services, {
      EntitlementPeriod period = EntitlementPeriod.month,
      int sort = 10,
    }) => MembershipEntitlement(
      id: 'c3000000-0000-4000-8000-00000000000$n',
      code: code,
      label: label,
      quantity: qty,
      period: period,
      sortOrder: sort,
      services: services,
    );
    MembershipPlanGroup grp(
      int n,
      String code,
      String name,
      GroupSelection sel,
      int sort,
      List<MembershipEntitlement> ents,
    ) => MembershipPlanGroup(
      id: 'c2000000-0000-4000-8000-00000000000$n',
      code: code,
      name: name,
      selection: sel,
      sortOrder: sort,
      entitlements: ents,
    );

    membershipPlans.addAll([
      MembershipPlan(
        id: planGold,
        code: 'gold',
        tier: LoyaltyTier.gold,
        name: 'Gold',
        tagline: '4 Sparkling Washes or 8 Exterior Washes a month',
        monthlyFeeCents: 29500,
        discountPct: 10,
        discountScope: DiscountScope.otherServices,
        discountNote: '10% discount on any other Sparkling service',
        color: 'gold',
        sortOrder: 10,
        groups: [
          grp(1, 'washes', 'Monthly washes', GroupSelection.chooseOne, 10, [
            ent(1, 'G1', '4 × Sparkling Wash', 4, sparkling),
            ent(2, 'G2', '8 × Exterior Wash', 8, exterior, sort: 20),
          ]),
        ],
      ),
      MembershipPlan(
        id: planPlatinum,
        code: 'platinum',
        tier: LoyaltyTier.platinum,
        name: 'Platinum',
        tagline: '8 Sparkling Washes or 16 Exterior Washes a month',
        monthlyFeeCents: 47500,
        discountPct: 10,
        discountScope: DiscountScope.planServices,
        discountNote: '10% discount on the above selected services',
        color: 'platinum',
        sortOrder: 20,
        groups: [
          grp(2, 'washes', 'Monthly washes', GroupSelection.chooseOne, 10, [
            ent(3, 'P1', '8 × Sparkling Wash', 8, sparkling),
            ent(4, 'P2', '16 × Exterior Wash', 16, exterior, sort: 20),
          ]),
        ],
      ),
      MembershipPlan(
        id: planBlack,
        code: 'black',
        tier: LoyaltyTier.black,
        name: 'Black',
        tagline:
            'Washes, a monthly detail or steam clean and an annual ceramic coating',
        monthlyFeeCents: 85000,
        discountPct: 10,
        discountScope: DiscountScope.planServices,
        discountNote: '10% discount on the above selected services',
        color: 'black',
        sortOrder: 30,
        groups: [
          grp(3, 'washes', 'Monthly washes', GroupSelection.chooseOne, 10, [
            ent(5, 'B1', '10 × Sparkling Wash per month', 10, sparkling),
            ent(6, 'B2', '20 × Exterior Wash', 20, exterior, sort: 20),
          ]),
          grp(4, 'detail', 'Monthly detail', GroupSelection.chooseOne, 20, [
            ent(7, 'B3', '1 × Auto Detail Complete per month', 1, [
              es(DemoCatalogueIds.autoDetailComplete, primary: true),
            ]),
            ent(8, 'B4', '1 × Engine Steam Clean per month', 1, [
              es(DemoCatalogueIds.engineSteam, primary: true),
            ], sort: 20),
          ]),
          grp(5, 'coating', 'Annual ceramic coating', GroupSelection.all, 30, [
            ent(9, 'B5', '1 × Ceramic coating per annum', 1, [
              es(DemoCatalogueIds.ceramicCoating, primary: true),
            ], period: EntitlementPeriod.year),
          ]),
        ],
      ),
    ]);

    Membership mem(
      String id,
      int seq,
      String customer,
      String plan, {
      required int startedDaysAgo,
      required int periodStartDaysAgo,
      DateTime? periodEnd,
      MembershipPaymentMethod method = MembershipPaymentMethod.card,
      String? createdBy,
    }) {
      final ps = n.subtract(Duration(days: periodStartDaysAgo));
      return Membership(
        id: id,
        ref: 'MEM-$_yr-${seq.toString().padLeft(4, '0')}',
        customerId: customer,
        planId: plan,
        planCode: planById(plan)?.code,
        status: MembershipStatus.active,
        startedAt: n.subtract(Duration(days: startedDaysAgo)),
        currentPeriodStart: ps,
        currentPeriodEnd: periodEnd ?? addMonths(ps, 1),
        paymentMethod: method,
        clientOpId: 'seed-mem-${customer.replaceFirst('seed_', '')}',
        createdBy: createdBy ?? customer,
        createdAt: n.subtract(Duration(days: startedDaysAgo)),
      );
    }

    memberships.addAll([
      mem(
        membershipThabo,
        1,
        'seed_thabo',
        planGold,
        startedDaysAgo: 95,
        periodStartDaysAgo: 5,
      ),
      mem(
        membershipNaledi,
        2,
        'seed_naledi',
        planGold,
        startedDaysAgo: 60,
        periodStartDaysAgo: 12,
        method: MembershipPaymentMethod.cash,
        createdBy: 'seed_johan',
      ),
      mem(
        membershipSipho,
        3,
        'seed_sipho',
        planPlatinum,
        startedDaysAgo: 150,
        periodStartDaysAgo: 20,
      ),
      mem(
        membershipZanele,
        4,
        'seed_zanele',
        planBlack,
        startedDaysAgo: 27,
        periodStartDaysAgo: 27,
        periodEnd: n.add(const Duration(days: 3)),
      ),
    ]);
    membershipSelections.addAll({
      membershipThabo: {'washes': 'G1'},
      membershipNaledi: {'washes': 'G2'},
      membershipSipho: {'washes': 'P1'},
      membershipZanele: {'washes': 'B1', 'detail': 'B3'},
    });

    void use(String mid, int entN, String key, int offsetDays) {
      final m = memberships.firstWhere((x) => x.id == mid);
      membershipUsage.add(
        MembershipUsage(
          id: _newId('u'),
          membershipId: mid,
          entitlementId: 'c3000000-0000-4000-8000-00000000000$entN',
          quantity: 1,
          periodStart: m.currentPeriodStart!,
          periodEnd: m.currentPeriodEnd!,
          idempotencyKey: key,
          createdBy: m.customerId,
          createdAt: m.currentPeriodStart!.add(Duration(days: offsetDays)),
        ),
      );
      _idempotencyKeys.add(key);
    }

    use(membershipThabo, 1, 'seed-use-thabo-1', 2);
    use(membershipNaledi, 2, 'seed-use-naledi-1', 3);
    use(membershipNaledi, 2, 'seed-use-naledi-2', 9);
    use(membershipSipho, 3, 'seed-use-sipho-1', 4);
    use(membershipSipho, 3, 'seed-use-sipho-2', 11);
    use(membershipSipho, 3, 'seed-use-sipho-3', 17);
    use(membershipZanele, 5, 'seed-use-zanele-1', 6);
    use(membershipZanele, 5, 'seed-use-zanele-2', 20);
    use(membershipZanele, 7, 'seed-use-zanele-3', 14);

    // Current-period invoices (paid) + their payments.
    var seq = 101;
    for (final m in memberships) {
      final plan = planById(m.planId)!;
      final invId = 'c5000000-0000-4000-8000-0000000000${seq.toString().padLeft(2, '0')}';
      final payId = '60000000-0000-4000-8000-0000000000${seq.toString().padLeft(2, '0')}';
      final card = m.paymentMethod == MembershipPaymentMethod.card;
      membershipInvoices.add(
        MembershipInvoice(
          id: invId,
          ref: 'MINV-$_yr-0$seq',
          membershipId: m.id,
          customerId: m.customerId,
          periodStart: m.currentPeriodStart,
          periodEnd: m.currentPeriodEnd,
          amountCents: plan.monthlyFeeCents,
          status: MembershipInvoiceStatus.paid,
          dueAt: m.currentPeriodStart,
          paidAt: m.currentPeriodStart,
          paymentId: payId,
          idempotencyKey: 'seed-minv-${m.customerId.replaceFirst('seed_', '')}-cur',
          createdAt: m.currentPeriodStart,
        ),
      );
      payments.add(
        Payment(
          id: payId,
          membershipInvoiceId: invId,
          customerId: m.customerId,
          provider: card ? 'sandbox' : 'pos',
          providerRef: card ? 'pi_sbx_mem_0$seq' : 'pos_mem_0$seq',
          amountCents: plan.monthlyFeeCents,
          status: PaymentStatus.successful,
          receiptNo: 'RCP-70$seq',
          idempotencyKey: 'pay-seed-mem-0$seq',
          verifiedAt: m.currentPeriodStart,
          createdAt: m.currentPeriodStart,
          updatedAt: m.currentPeriodStart,
          receipt: {
            'receipt_no': 'RCP-70$seq',
            'amount_cents': plan.monthlyFeeCents,
            'method': card ? 'card' : 'cash',
            if (!card) 'recorded_by': 'Johan Botha',
            'paid_at': j.iso(m.currentPeriodStart),
          },
        ),
      );
      seq++;
    }
    // Zanele's renewal is due in 3 days: the renewal job has already raised
    // the next invoice (pending).
    final zanele = memberships.firstWhere((m) => m.id == membershipZanele);
    membershipInvoices.add(
      MembershipInvoice(
        id: invoiceZaneleRenewal,
        ref: 'MINV-$_yr-0105',
        membershipId: zanele.id,
        customerId: zanele.customerId,
        periodStart: zanele.currentPeriodEnd,
        periodEnd: addMonths(zanele.currentPeriodEnd!, 1),
        amountCents: planById(planBlack)!.monthlyFeeCents,
        status: MembershipInvoiceStatus.pending,
        dueAt: zanele.currentPeriodEnd,
        idempotencyKey: 'renewal:${zanele.id}:${j.isoDate(zanele.currentPeriodEnd)}',
        createdAt: n,
      ),
    );
    _membershipInvoiceSeq = 106;

    for (final m in memberships) {
      loyaltyTiers[m.customerId] = (
        tier: planById(m.planId)!.tier,
        tierSince: m.startedAt!,
      );
    }
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
              sizeClass: payload['size_class'] == null
                  ? null
                  : VehicleSize.fromDb(j.strOrNull(payload['size_class'])),
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
          SyncKinds.bookingCreateWalkIn => createWalkInBooking(
            WalkInBookingInput.fromJson({...payload, 'client_op_id': id}),
          ).toJson(),
          SyncKinds.quotationRaise => raiseQuotation(
            StaffQuotationInput.fromJson({...payload, 'client_op_id': id}),
          ).toJson(),
          SyncKinds.paymentRecord => recordPayment(
            RecordPaymentInput.fromJson({
              ...payload,
              'idempotency_key': payload['idempotency_key'] ?? id,
            }),
          ).toJson(),
          SyncKinds.membershipEnrol => enrolMembership(
            EnrolMembershipInput.fromJson({...payload, 'client_op_id': id}),
          ).toJson(),
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

/// Great-circle distance in km (haversine), rounded to 0.1.
double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return (r * c * 10).round() / 10;
}

String _fmtNum(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
