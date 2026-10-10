/// Cross-module integration test for the core clinical flow
/// (Module 07 → 16 → 25 → 31): appointment → encounter →
/// prescription → billing.
///
/// The four real repositories are wired over one shared in-memory
/// projection of the local store, so a record written by one module
/// is the same record the next module reads back — the seam PowerSync
/// normally provides. This pins the linkage contracts that hold the
/// flow together: the encounter id threads the appointment to the
/// prescription and the invoice, and each lifecycle transition only
/// fires from its legal predecessor state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/appointments/appointment.dart';
import 'package:nodex_hms/domain/appointments/appointment_repository.dart';
import 'package:nodex_hms/domain/appointments/appointment_use_cases.dart';
import 'package:nodex_hms/domain/billing/billing_repository.dart';
import 'package:nodex_hms/domain/billing/billing_use_cases.dart';
import 'package:nodex_hms/domain/billing/invoice.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';
import 'package:nodex_hms/domain/encounters/encounter_use_cases.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/prescriptions/prescription.dart';
import 'package:nodex_hms/domain/prescriptions/prescription_repository.dart';
import 'package:nodex_hms/domain/prescriptions/prescription_use_cases.dart';

/// An in-memory [PatientLocalStore] that understands the small SQL
/// surface the repositories issue: `SELECT * FROM <table>` with an
/// optional `WHERE col ? [AND col ?]`, an optional `ORDER BY col
/// [ASC|DESC]` and an optional `LIMIT ?`, plus point reads, inserts
/// and column updates. Range operators compare ISO-8601 timestamps
/// lexicographically, which is correct for the UTC strings the
/// domain persists.
final class InMemoryLocalStore implements PatientLocalStore {
  final Map<String, Map<String, Map<String, Object?>>> _tables =
      <String, Map<String, Map<String, Object?>>>{};

  Map<String, Map<String, Object?>> _table(String name) =>
      _tables.putIfAbsent(name, () => <String, Map<String, Object?>>{});

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    final String table = RegExp(r'FROM\s+(\w+)').firstMatch(sql)!.group(1)!;
    var rows = _table(table).values
        .map((Map<String, Object?> row) => Map<String, Object?>.from(row))
        .toList();
    var paramIndex = 0;

    final RegExpMatch? where = RegExp(
      r'WHERE\s+(.+?)(?=\s+ORDER BY|\s+LIMIT|$)',
      caseSensitive: false,
    ).firstMatch(sql);
    if (where != null) {
      for (final String condition
          in where
              .group(1)!
              .split(RegExp(r'\s+AND\s+', caseSensitive: false))) {
        final RegExpMatch? match = RegExp(r'(\w+)\s*(>=|<=|>|<|=)\s*\?')
            .firstMatch(condition);
        if (match == null) {
          continue;
        }
        final String column = match.group(1)!;
        final String operator = match.group(2)!;
        final Object? value = parameters[paramIndex++];
        rows = rows
            .where(
              (Map<String, Object?> row) =>
                  _matches(row[column], operator, value),
            )
            .toList();
      }
    }

    final RegExpMatch? order = RegExp(
      r'ORDER BY\s+(\w+)(?:\s+(ASC|DESC))?',
      caseSensitive: false,
    ).firstMatch(sql);
    if (order != null) {
      final String column = order.group(1)!;
      final bool descending = (order.group(2) ?? 'ASC').toUpperCase() == 'DESC';
      rows.sort((Map<String, Object?> a, Map<String, Object?> b) {
        final int comparison = _compare(a[column], b[column]);
        return descending ? -comparison : comparison;
      });
    }

    final RegExpMatch? limit = RegExp(
      r'LIMIT\s+\?',
      caseSensitive: false,
    ).firstMatch(sql);
    if (limit != null) {
      final int count = parameters[paramIndex++] as int;
      rows = rows.take(count).toList();
    }

    return rows;
  }

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async {
    final Map<String, Object?>? row = _table(table)[id];
    return row == null ? null : Map<String, Object?>.from(row);
  }

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {
    final Object? id = row['id'];
    if (id is String) {
      _table(table)[id] = Map<String, Object?>.from(row);
    }
  }

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> changes,
  ) async {
    _table(table)[id]?.addAll(changes);
  }

  bool _matches(Object? value, String operator, Object? parameter) {
    final int comparison = _compare(value, parameter);
    return switch (operator) {
      '=' => comparison == 0,
      '>=' => comparison >= 0,
      '<=' => comparison <= 0,
      '>' => comparison > 0,
      '<' => comparison < 0,
      _ => false,
    };
  }

  int _compare(Object? a, Object? b) {
    if (a is num && b is num) {
      return a.compareTo(b);
    }
    return a.toString().compareTo(b.toString());
  }
}

/// A no-op logger: the repositories log on writes, but the sink list
/// is empty so nothing is emitted.
NodexLogger get _silentLogger => NodexLogger(sinks: const <NodexLogSink>[]);

/// Builds a policy holding every permission the clinical flow needs.
AuthorizationPolicy policyWith({
  required String userId,
  required Set<String> permissions,
}) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: userId,
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.medicalOfficer},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

const Set<String> _clinicalPermissions = <String>{
  NodexPermissions.appointmentWrite,
  NodexPermissions.encounterWrite,
  NodexPermissions.prescriptionDraft,
  NodexPermissions.prescriptionFinalize,
  NodexPermissions.pharmacyDispense,
  NodexPermissions.medicationAdminister,
  NodexPermissions.billingSettle,
};

void main() {
  const String tenantId = 'tenant-1';
  const String patientId = 'patient-1';
  const String physicianId = 'dr-1';
  const String clerkId = 'clerk-1';

  late InMemoryLocalStore store;
  late DefaultAppointmentRepository appointmentRepo;
  late DefaultEncounterRepository encounterRepo;
  late DefaultPrescriptionRepository prescriptionRepo;
  late DefaultBillingRepository billingRepo;

  late BookAppointmentUseCase bookAppointment;
  late LinkEncounterAppointmentUseCase linkEncounter;
  late StartEncounterUseCase startEncounter;
  late SaveEncounterDraftUseCase saveDraft;
  late SignEncounterUseCase signEncounter;
  late DraftPrescriptionUseCase draftPrescription;
  late AddPrescriptionItemUseCase addPrescriptionItem;
  late FinalizePrescriptionUseCase finalizePrescription;
  late RecordDispenseUseCase recordDispense;
  late RecordAdministrationUseCase recordAdministration;
  late DraftInvoiceUseCase draftInvoice;
  late AddInvoiceLineUseCase addInvoiceLine;
  late IssueInvoiceUseCase issueInvoice;
  late RecordPaymentUseCase recordPayment;
  late SettleInvoiceUseCase settleInvoice;

  late AuthorizationPolicy clinician;

  setUp(() {
    store = InMemoryLocalStore();
    appointmentRepo = DefaultAppointmentRepository(
      store: store,
      logger: _silentLogger,
    );
    encounterRepo = DefaultEncounterRepository(
      store: store,
      logger: _silentLogger,
    );
    prescriptionRepo = DefaultPrescriptionRepository(
      store: store,
      logger: _silentLogger,
    );
    billingRepo = DefaultBillingRepository(store: store, logger: _silentLogger);

    bookAppointment = BookAppointmentUseCase(repository: appointmentRepo);
    linkEncounter = LinkEncounterAppointmentUseCase(
      repository: appointmentRepo,
    );
    startEncounter = StartEncounterUseCase(repository: encounterRepo);
    saveDraft = SaveEncounterDraftUseCase(repository: encounterRepo);
    signEncounter = SignEncounterUseCase(repository: encounterRepo);
    draftPrescription = DraftPrescriptionUseCase(repository: prescriptionRepo);
    addPrescriptionItem = AddPrescriptionItemUseCase(
      repository: prescriptionRepo,
    );
    finalizePrescription = FinalizePrescriptionUseCase(
      repository: prescriptionRepo,
    );
    recordDispense = RecordDispenseUseCase(repository: prescriptionRepo);
    recordAdministration = RecordAdministrationUseCase(
      repository: prescriptionRepo,
    );
    draftInvoice = DraftInvoiceUseCase(repository: billingRepo);
    addInvoiceLine = AddInvoiceLineUseCase(repository: billingRepo);
    issueInvoice = IssueInvoiceUseCase(repository: billingRepo);
    recordPayment = RecordPaymentUseCase(repository: billingRepo);
    settleInvoice = SettleInvoiceUseCase(repository: billingRepo);

    clinician = policyWith(
      userId: physicianId,
      permissions: _clinicalPermissions,
    );
  });

  test('a visit threads through encounter, prescription and billing', () async {
    // 1. Book the visit.
    final String appointmentId = await bookAppointment.call(
      policy: clinician,
      tenantId: tenantId,
      patientId: patientId,
      providerId: physicianId,
      bookedBy: clerkId,
      appointmentCode: 'APT-001',
      visitType: VisitType.outpatient,
      priority: AppointmentPriority.routine,
      scheduledStart: DateTime.utc(2026, 10, 1, 9),
      scheduledEnd: DateTime.utc(2026, 10, 1, 9, 30),
    );
    Appointment appointment = (await appointmentRepo.getAppointment(
      appointmentId,
    ))!;
    expect(appointment.status, AppointmentStatus.booked);
    expect(appointment.encounterId, isNull);

    // 2. Open the encounter the visit produces.
    final String encounterId = await startEncounter.call(
      policy: clinician,
      tenantId: tenantId,
      patientId: patientId,
      attendingPhysicianId: physicianId,
      encounterType: EncounterType.outpatient,
      createdBy: physicianId,
    );
    ClinicalEncounter encounter = (await encounterRepo.getEncounter(
      encounterId,
    ))!;
    expect(encounter.status, EncounterStatus.inProgress);
    expect(encounter.isEditable, isTrue);

    // 3. Link the encounter back to the appointment.
    await linkEncounter.call(
      policy: clinician,
      appointment: appointment,
      encounterId: encounterId,
    );
    appointment = (await appointmentRepo.getAppointment(appointmentId))!;
    expect(appointment.encounterId, encounterId);

    // 4. Record SOAP, then the attending signs and freezes it.
    await saveDraft.call(
      policy: clinician,
      encounter: encounter,
      subjectiveNote: 'S: fever and cough',
      objectiveFindings: 'O: 38.2°C',
      assessment: 'A: viral URI',
      planDescription: 'P: rest, fluids',
    );
    await signEncounter.call(
      policy: clinician,
      encounterId: encounterId,
      signerUserId: physicianId,
    );
    encounter = (await encounterRepo.getEncounter(encounterId))!;
    expect(encounter.isSigned, isTrue);
    expect(encounter.isEditable, isFalse);

    // 5. Prescribe against the signed encounter.
    final String prescriptionId = await draftPrescription.call(
      policy: clinician,
      tenantId: tenantId,
      patientId: patientId,
      prescribedBy: physicianId,
      prescriptionCode: 'RX-001',
      priority: PrescriptionPriority.routine,
      encounterId: encounterId,
    );
    Prescription prescription = (await prescriptionRepo.getPrescription(
      prescriptionId,
    ))!;
    expect(prescription.status, PrescriptionStatus.draft);
    expect(prescription.version, 1);
    expect(prescription.encounterId, encounterId);

    final String itemId = await addPrescriptionItem.call(
      policy: clinician,
      prescription: prescription,
      lineNumber: 1,
      drugCode: 'PAR-500',
      drugName: 'Paracetamol 500mg',
      dosageText: '1 tablet q8h',
      quantityPrescribed: 10,
    );
    final PrescriptionItem item = (await prescriptionRepo.getItem(itemId))!;
    expect(item.drugCode, 'PAR-500');
    expect(item.quantityPrescribed, 10);

    await finalizePrescription.call(
      policy: clinician,
      prescription: prescription,
      finalizerId: physicianId,
    );
    prescription = (await prescriptionRepo.getPrescription(prescriptionId))!;
    expect(prescription.status, PrescriptionStatus.finalized);

    // 6. Bill the encounter.
    final String invoiceId = await draftInvoice.call(
      policy: clinician,
      tenantId: tenantId,
      patientId: patientId,
      createdBy: clerkId,
      invoiceCode: 'INV-001',
      encounterId: encounterId,
    );
    Invoice invoice = (await billingRepo.getInvoice(invoiceId))!;
    expect(invoice.status, InvoiceStatus.draft);
    expect(invoice.encounterId, encounterId);

    await addInvoiceLine.call(
      policy: clinician,
      invoice: invoice,
      lineNumber: 1,
      description: 'Outpatient consultation',
      quantity: 1,
      unitPriceMinor: 50000,
      lineTotalMinor: 50000,
    );
    await issueInvoice.call(policy: clinician, invoice: invoice);
    invoice = (await billingRepo.getInvoice(invoiceId))!;
    expect(invoice.status, InvoiceStatus.issued);

    final String paymentId = await recordPayment.call(
      policy: clinician,
      invoice: invoice,
      recordedBy: clerkId,
      amountMinor: 50000,
      method: PaymentMethod.cash,
    );
    await settleInvoice.call(policy: clinician, invoice: invoice);
    invoice = (await billingRepo.getInvoice(invoiceId))!;
    expect(invoice.status, InvoiceStatus.settled);

    // 7. The payment landed against the settled invoice.
    final List<Payment> payments = await billingRepo.listPayments(invoiceId);
    expect(payments, hasLength(1));
    expect(payments.single.id, paymentId);
    expect(payments.single.amountMinor, 50000);
    expect(payments.single.method, PaymentMethod.cash);
  });

  test('each module reads the visit back for the patient', () async {
    final String appointmentId = await bookAppointment.call(
      policy: clinician,
      tenantId: tenantId,
      patientId: patientId,
      providerId: physicianId,
      bookedBy: clerkId,
      appointmentCode: 'APT-002',
      visitType: VisitType.followUp,
      priority: AppointmentPriority.urgent,
      scheduledStart: DateTime.utc(2026, 10, 2, 10),
      scheduledEnd: DateTime.utc(2026, 10, 2, 10, 30),
    );
    final String encounterId = await startEncounter.call(
      policy: clinician,
      tenantId: tenantId,
      patientId: patientId,
      attendingPhysicianId: physicianId,
      encounterType: EncounterType.outpatient,
      createdBy: physicianId,
    );
    await linkEncounter.call(
      policy: clinician,
      appointment: (await appointmentRepo.getAppointment(appointmentId))!,
      encounterId: encounterId,
    );
    final String prescriptionId = await draftPrescription.call(
      policy: clinician,
      tenantId: tenantId,
      patientId: patientId,
      prescribedBy: physicianId,
      prescriptionCode: 'RX-002',
      priority: PrescriptionPriority.routine,
      encounterId: encounterId,
    );
    final String invoiceId = await draftInvoice.call(
      policy: clinician,
      tenantId: tenantId,
      patientId: patientId,
      createdBy: clerkId,
      invoiceCode: 'INV-002',
      encounterId: encounterId,
    );

    // Every module lists exactly this patient's record, and each
    // record points at the shared encounter.
    final List<Appointment> appointments = await appointmentRepo.listForPatient(
      patientId,
    );
    expect(appointments, hasLength(1));
    expect(appointments.single.encounterId, encounterId);

    final List<ClinicalEncounter> encounters = await encounterRepo
        .listForPatient(patientId, limit: 10);
    expect(encounters, hasLength(1));
    expect(encounters.single.id, encounterId);

    final List<Prescription> prescriptions = await prescriptionRepo
        .listPrescriptionsForPatient(patientId);
    expect(prescriptions, hasLength(1));
    expect(prescriptions.single.id, prescriptionId);
    expect(prescriptions.single.encounterId, encounterId);

    final List<Invoice> invoices = await billingRepo.listForPatient(patientId);
    expect(invoices, hasLength(1));
    expect(invoices.single.id, invoiceId);
    expect(invoices.single.encounterId, encounterId);
  });

  test('a policy without billing rights cannot open an invoice', () async {
    final AuthorizationPolicy prescriberOnly = policyWith(
      userId: physicianId,
      permissions: const <String>{
        NodexPermissions.appointmentWrite,
        NodexPermissions.encounterWrite,
        NodexPermissions.prescriptionDraft,
        NodexPermissions.prescriptionFinalize,
      },
    );

    expect(
      draftInvoice.call(
        policy: prescriberOnly,
        tenantId: tenantId,
        patientId: patientId,
        createdBy: clerkId,
        invoiceCode: 'INV-003',
      ),
      throwsA(isA<AuthorizationError>()),
    );
    // Nothing was written: the gate fired before the repository.
    expect(await billingRepo.listForPatient(patientId), isEmpty);
  });

  test(
    'the pharmacy hop carries a dispensed medication into billing',
    () async {
      const String pharmacistId = 'pharm-1';
      const String nurseId = 'nurse-1';

      // Clinical front half: visit, signed encounter, finalized order.
      final String appointmentId = await bookAppointment.call(
        policy: clinician,
        tenantId: tenantId,
        patientId: patientId,
        providerId: physicianId,
        bookedBy: clerkId,
        appointmentCode: 'APT-HOP',
        visitType: VisitType.outpatient,
        priority: AppointmentPriority.routine,
        scheduledStart: DateTime.utc(2026, 10, 3, 9),
        scheduledEnd: DateTime.utc(2026, 10, 3, 9, 30),
      );
      final String encounterId = await startEncounter.call(
        policy: clinician,
        tenantId: tenantId,
        patientId: patientId,
        attendingPhysicianId: physicianId,
        encounterType: EncounterType.outpatient,
        createdBy: physicianId,
      );
      await linkEncounter.call(
        policy: clinician,
        appointment: (await appointmentRepo.getAppointment(appointmentId))!,
        encounterId: encounterId,
      );
      final String prescriptionId = await draftPrescription.call(
        policy: clinician,
        tenantId: tenantId,
        patientId: patientId,
        prescribedBy: physicianId,
        prescriptionCode: 'RX-HOP',
        priority: PrescriptionPriority.routine,
        encounterId: encounterId,
      );
      final String itemId = await addPrescriptionItem.call(
        policy: clinician,
        prescription: (await prescriptionRepo.getPrescription(prescriptionId))!,
        lineNumber: 1,
        drugCode: 'PAR-500',
        drugName: 'Paracetamol 500mg',
        dosageText: '1 tablet q8h',
        quantityPrescribed: 10,
      );
      await finalizePrescription.call(
        policy: clinician,
        prescription: (await prescriptionRepo.getPrescription(prescriptionId))!,
        finalizerId: physicianId,
      );

      // The no-trigger store needs the release cascade the server performs on
      // finalize before a line is dispensable, exactly as the unit test does.
      await prescriptionRepo.updateItem(
        itemId,
        PrescriptionItem.progressChanges(
          status: PrescriptionItemStatus.ordered,
        ),
      );

      // The pharmacy hop: hand over the medication.
      final String dispenseId = await recordDispense.call(
        policy: clinician,
        item: (await prescriptionRepo.getItem(itemId))!,
        dispensedBy: pharmacistId,
        quantityDispensed: 10,
      );
      final PrescriptionItem dispensedItem = (await prescriptionRepo.getItem(
        itemId,
      ))!;
      expect(dispensedItem.status, PrescriptionItemStatus.dispensed);

      final List<PharmacyDispense> dispenses = await prescriptionRepo
          .listDispenses(itemId);
      expect(dispenses, hasLength(1));
      expect(dispenses.single.id, dispenseId);
      expect(dispenses.single.itemId, itemId);
      expect(dispenses.single.prescriptionId, prescriptionId);
      expect(dispenses.single.quantityDispensed, 10);
      expect(dispenses.single.dispensedBy, pharmacistId);

      // The bedside hop rides on the dispense event.
      final String adminId = await recordAdministration.call(
        policy: clinician,
        item: dispensedItem,
        patientId: patientId,
        administeredBy: nurseId,
        doseText: '1 tablet',
        dispenseId: dispenseId,
      );
      final List<MedicationAdministration> administrations =
          await prescriptionRepo.listAdministrations(itemId);
      expect(administrations, hasLength(1));
      expect(administrations.single.id, adminId);
      expect(administrations.single.dispenseId, dispenseId);
      expect(administrations.single.prescriptionId, prescriptionId);
      expect(administrations.single.administeredBy, nurseId);

      // Billing picks up the encounter the medication was ordered against.
      final String invoiceId = await draftInvoice.call(
        policy: clinician,
        tenantId: tenantId,
        patientId: patientId,
        createdBy: clerkId,
        invoiceCode: 'INV-HOP',
        encounterId: encounterId,
      );
      Invoice invoice = (await billingRepo.getInvoice(invoiceId))!;
      expect(invoice.encounterId, encounterId);

      await addInvoiceLine.call(
        policy: clinician,
        invoice: invoice,
        lineNumber: 1,
        description: 'Paracetamol 500mg x10',
        quantity: 10,
        unitPriceMinor: 300,
        lineTotalMinor: 3000,
      );
      await issueInvoice.call(policy: clinician, invoice: invoice);
      invoice = (await billingRepo.getInvoice(invoiceId))!;
      await recordPayment.call(
        policy: clinician,
        invoice: invoice,
        recordedBy: clerkId,
        amountMinor: 3000,
        method: PaymentMethod.cash,
      );
      await settleInvoice.call(policy: clinician, invoice: invoice);
      invoice = (await billingRepo.getInvoice(invoiceId))!;
      expect(invoice.status, InvoiceStatus.settled);

      // The whole chain still threads through the one encounter.
      final Prescription endToEnd = (await prescriptionRepo.getPrescription(
        prescriptionId,
      ))!;
      expect(endToEnd.encounterId, encounterId);
      final Appointment endAppointment = (await appointmentRepo.getAppointment(
        appointmentId,
      ))!;
      expect(endAppointment.encounterId, encounterId);
    },
  );
}
