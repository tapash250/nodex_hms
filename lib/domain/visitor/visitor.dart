/// Visitor & Pass Security Management entities (Module 37).
///
/// Specification scope: "Visitor registration, digital entry passes, ward visiting
/// hour restrictions, and security thermal badge printing."
///
/// This is the front door: who came in, on whose authority, where they were
/// allowed to go, and what the gate printed for them. It is distinct from the
/// clinical record (an encounter records the patient; a registration records the
/// person who came to see them) and from the workforce rosters (a shift is staff
/// on duty; a pass is a visitor allowed in).
///
/// Four records, one per clause of the scope: the [WardVisitingWindow] rule, the
/// [VisitorRegistration] at the gate, the [VisitorPass] issued against it and the
/// append-only [VisitorBadgePrint] log.
///
/// The facts a stored copy would let drift are derived instead. Expiry is
/// [isVisitorPassExpired] and usability is [isVisitorPassUsable], both from the
/// clock and the validity window, so a pass does not need a job to be updated
/// into an `expired` state. Whether an instant falls inside a ward's hours is
/// [isWithinVisitingWindow] over [visitingWindowFor], resolved from the day of
/// week rather than stored on the pass.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Sex as recorded for a visitor.
enum VisitorSex {
  /// Male.
  male('male'),

  /// Female.
  female('female'),

  /// Recorded otherwise, or not stated.
  other('other');

  const VisitorSex(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    VisitorSex.male => 'Male',
    VisitorSex.female => 'Female',
    VisitorSex.other => 'Other',
  };

  /// Parses a stored value.
  static VisitorSex? fromWire(String? value) => value == null
      ? null
      : VisitorSex.values.firstWhere(
          (VisitorSex value_) => value_.wireValue == value,
          orElse: () => VisitorSex.other,
        );
}

/// The identity document a visitor presented.
enum VisitorIdType {
  /// A national identity card.
  nationalId('national_id'),

  /// A passport.
  passport('passport'),

  /// A driving licence.
  drivingLicence('driving_licence'),

  /// A service or staff identity card.
  serviceId('service_id'),

  /// Anything else, described on the row.
  other('other');

  const VisitorIdType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    VisitorIdType.nationalId => 'National ID',
    VisitorIdType.passport => 'Passport',
    VisitorIdType.drivingLicence => 'Driving licence',
    VisitorIdType.serviceId => 'Service ID',
    VisitorIdType.other => 'Other',
  };

  /// Parses a stored value.
  static VisitorIdType? fromWire(String? value) => value == null
      ? null
      : VisitorIdType.values.firstWhere(
          (VisitorIdType value_) => value_.wireValue == value,
          orElse: () => VisitorIdType.other,
        );
}

/// Why a visitor came.
enum VisitorPurpose {
  /// Visiting an inpatient.
  patientVisit('patient_visit'),

  /// Staying with a patient as an attendant.
  attendant('attendant'),

  /// A supplier or contractor.
  vendor('vendor'),

  /// A maintenance or service call.
  service('service'),

  /// An official or regulatory visit.
  official('official'),

  /// Anything else, described on the row.
  other('other');

  const VisitorPurpose(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    VisitorPurpose.patientVisit => 'Patient visit',
    VisitorPurpose.attendant => 'Attendant',
    VisitorPurpose.vendor => 'Vendor',
    VisitorPurpose.service => 'Service call',
    VisitorPurpose.official => 'Official visit',
    VisitorPurpose.other => 'Other',
  };

  /// Parses a stored value.
  static VisitorPurpose fromWire(String value) =>
      VisitorPurpose.values.firstWhere(
        (VisitorPurpose value_) => value_.wireValue == value,
        orElse: () => VisitorPurpose.other,
      );
}

/// Lifecycle status of a visitor registration.
enum VisitorRegistrationStatus {
  /// Taken at the gate; the only stage whose recorded facts may be corrected.
  registered('registered'),

  /// Inside, or otherwise admitted.
  onSite('on_site'),

  /// Departed; terminal.
  left('left'),

  /// Turned away at the gate, with a reason; terminal.
  refused('refused'),

  /// Entered in error, with a reason; terminal.
  voided('voided');

  const VisitorRegistrationStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    VisitorRegistrationStatus.registered => 'Registered',
    VisitorRegistrationStatus.onSite => 'On site',
    VisitorRegistrationStatus.left => 'Left',
    VisitorRegistrationStatus.refused => 'Refused entry',
    VisitorRegistrationStatus.voided => 'Withdrawn',
  };

  /// Parses a stored value.
  static VisitorRegistrationStatus fromWire(String value) =>
      VisitorRegistrationStatus.values.firstWhere(
        (VisitorRegistrationStatus value_) => value_.wireValue == value,
        orElse: () => VisitorRegistrationStatus.registered,
      );

  /// Whether the registration is settled.
  bool get isTerminal => switch (this) {
    VisitorRegistrationStatus.left ||
    VisitorRegistrationStatus.refused ||
    VisitorRegistrationStatus.voided => true,
    VisitorRegistrationStatus.registered ||
    VisitorRegistrationStatus.onSite => false,
  };

  /// Whether the visitor is currently inside.
  bool get isOnSite => this == VisitorRegistrationStatus.onSite;

  /// Whether the registration still has to be worked.
  bool get isLive => !isTerminal;
}

/// Whether a registration may move from [from] to [to].
bool visitorRegistrationCanTransition(
  VisitorRegistrationStatus from,
  VisitorRegistrationStatus to,
) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    VisitorRegistrationStatus.registered =>
      to == VisitorRegistrationStatus.onSite ||
          to == VisitorRegistrationStatus.refused ||
          to == VisitorRegistrationStatus.voided,
    VisitorRegistrationStatus.onSite => to == VisitorRegistrationStatus.left,
    VisitorRegistrationStatus.left ||
    VisitorRegistrationStatus.refused ||
    VisitorRegistrationStatus.voided => false,
  };
}

/// Lifecycle status of a digital entry pass.
enum VisitorPassStatus {
  /// Printed or handed over, not yet used.
  issued('issued'),

  /// In use at the gate.
  active('active'),

  /// Handed back; terminal.
  returned('returned'),

  /// Withdrawn before its window closed, with a reason; terminal.
  revoked('revoked');

  const VisitorPassStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    VisitorPassStatus.issued => 'Issued',
    VisitorPassStatus.active => 'Active',
    VisitorPassStatus.returned => 'Returned',
    VisitorPassStatus.revoked => 'Revoked',
  };

  /// Parses a stored value.
  static VisitorPassStatus fromWire(String value) =>
      VisitorPassStatus.values.firstWhere(
        (VisitorPassStatus value_) => value_.wireValue == value,
        orElse: () => VisitorPassStatus.issued,
      );

  /// Whether the pass is settled.
  bool get isTerminal =>
      this == VisitorPassStatus.returned || this == VisitorPassStatus.revoked;

  /// Whether the pass still has to be worked.
  bool get isLive => !isTerminal;
}

/// Whether a pass may move from [from] to [to].
bool visitorPassCanTransition(VisitorPassStatus from, VisitorPassStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    VisitorPassStatus.issued =>
      to == VisitorPassStatus.active || to == VisitorPassStatus.revoked,
    VisitorPassStatus.active =>
      to == VisitorPassStatus.returned || to == VisitorPassStatus.revoked,
    VisitorPassStatus.returned || VisitorPassStatus.revoked => false,
  };
}

/// Where a pass lets its holder go.
enum VisitorAccessScope {
  /// The ward the visitor is registered against.
  ward('ward'),

  /// Outpatient areas.
  opd('opd'),

  /// Intensive care, where visiting is most restricted.
  icu('icu'),

  /// The whole facility.
  wholeFacility('whole_facility');

  const VisitorAccessScope(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    VisitorAccessScope.ward => 'The ward only',
    VisitorAccessScope.opd => 'Outpatient areas',
    VisitorAccessScope.icu => 'Intensive care',
    VisitorAccessScope.wholeFacility => 'The whole facility',
  };

  /// Parses a stored value.
  static VisitorAccessScope fromWire(String value) =>
      VisitorAccessScope.values.firstWhere(
        (VisitorAccessScope value_) => value_.wireValue == value,
        orElse: () => VisitorAccessScope.ward,
      );
}

/// Whether a ward's visiting window is in force.
enum VisitorWindowStatus {
  /// In force.
  active('active'),

  /// Retired; immutable, and kept so a past pass still resolves to its rule.
  archived('archived');

  const VisitorWindowStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    VisitorWindowStatus.active => 'In force',
    VisitorWindowStatus.archived => 'Retired',
  };

  /// Parses a stored value.
  static VisitorWindowStatus fromWire(String value) =>
      VisitorWindowStatus.values.firstWhere(
        (VisitorWindowStatus value_) => value_.wireValue == value,
        orElse: () => VisitorWindowStatus.active,
      );

  /// Whether the window is in force.
  bool get isActive => this == VisitorWindowStatus.active;
}

/// The day of week a wall clock instant falls on, as the database stores it.
///
/// Zero is Sunday. [at] is read as the caller's wall clock, not shifted to UTC:
/// visiting hours are a local rule, so escaping them by converting time zones
/// would be the bug rather than the fix.
int dayOfWeekFor(DateTime at) => at.weekday % 7;

/// The minute of day a wall clock instant falls on, from zero to 1439.
int minuteOfDayFor(DateTime at) => at.hour * 60 + at.minute;

/// The window in force for a ward on a day, or null when the ward has none.
///
/// Retired windows are skipped, and a ward with no window has no visiting hours
/// rather than unrestricted ones: an absent rule is not a rule that permits.
WardVisitingWindow? visitingWindowFor({
  required String wardId,
  required int dayOfWeek,
  required Iterable<WardVisitingWindow> windows,
}) {
  for (final WardVisitingWindow window in windows) {
    if (window.wardId == wardId &&
        window.dayOfWeek == dayOfWeek &&
        window.status.isActive) {
      return window;
    }
  }
  return null;
}

/// Whether a minute of the day falls inside a visiting window.
///
/// The end minute is exclusive, so a window that ends at 18:00 does not admit a
/// visitor at 18:00.
bool isWithinVisitingWindow({
  required WardVisitingWindow window,
  required int minuteOfDay,
}) => minuteOfDay >= window.startsMinute && minuteOfDay < window.endsMinute;

/// Whether a pass has run past its validity window.
///
/// The validity end is inclusive, because a pass is a permission rather than a
/// booking: the visitor holding it at the stated minute is still holding it.
bool isVisitorPassExpired({required VisitorPass pass, required DateTime now}) =>
    now.toUtc().isAfter(pass.validUntil.toUtc());

/// Whether a pass may be relied on at an instant: active, and not expired.
bool isVisitorPassUsable({required VisitorPass pass, required DateTime now}) =>
    pass.status == VisitorPassStatus.active &&
    !isVisitorPassExpired(pass: pass, now: now);

/// One ward's visiting window on one weekday.
@immutable
final class WardVisitingWindow {
  /// Creates a visiting window.
  const WardVisitingWindow({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.wardId,
    required this.dayOfWeek,
    required this.startsMinute,
    required this.endsMinute,
    required this.maxVisitors,
    required this.allowsChildren,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.createdAt,
  });

  /// Validates and builds a window row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String wardId,
    required int dayOfWeek,
    required int startsMinute,
    required int endsMinute,
    required String createdBy,
    int maxVisitors = 2,
    bool allowsChildren = false,
    String windowId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (wardId.isEmpty) {
      fieldErrors['ward_id'] = 'A ward is required.';
    }
    if (dayOfWeek < 0 || dayOfWeek > 6) {
      fieldErrors['day_of_week'] = 'A day of the week is required.';
    }
    if (startsMinute < 0 || startsMinute > 1439) {
      fieldErrors['starts_minute'] =
          'The opening minute must be a time of day.';
    }
    if (endsMinute <= startsMinute || endsMinute > 1440) {
      fieldErrors['ends_minute'] = 'The window must end after it opens.';
    }
    if (maxVisitors < 1 || maxVisitors > 50) {
      fieldErrors['max_visitors'] = 'A visitor limit is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Visiting window failed validation.',
        fieldErrors: fieldErrors,
        code: 'ward_visiting_window_invalid',
      );
    }
    final String stamp = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (windowId.isNotEmpty) 'id': windowId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'ward_id': wardId,
      'day_of_week': dayOfWeek,
      'starts_minute': startsMinute,
      'ends_minute': endsMinute,
      'max_visitors': maxVisitors,
      'allows_children': allowsChildren,
      'status': VisitorWindowStatus.active.wireValue,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a window from a local row.
  factory WardVisitingWindow.fromRow(Map<String, Object?> row) =>
      WardVisitingWindow(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        facilityId: row['facility_id']! as String,
        wardId: row['ward_id']! as String,
        dayOfWeek: _asInt(row['day_of_week']),
        startsMinute: _asInt(row['starts_minute']),
        endsMinute: _asInt(row['ends_minute']),
        maxVisitors: _asInt(row['max_visitors']),
        allowsChildren: _asBool(row['allows_children']),
        status: VisitorWindowStatus.fromWire(
          (row['status'] as String?) ?? VisitorWindowStatus.active.wireValue,
        ),
        createdBy: row['created_by']! as String,
        updatedAt: _parse(row['updated_at']),
        createdAt: _parseNullable(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility the ward belongs to.
  final String facilityId;

  /// The ward the window applies to.
  final String wardId;

  /// Zero is Sunday.
  final int dayOfWeek;

  /// Minutes from local midnight when visiting opens.
  final int startsMinute;

  /// Minutes from local midnight when visiting closes, exclusive.
  final int endsMinute;

  /// How many visitors the ward admits at once.
  final int maxVisitors;

  /// Whether children may visit.
  final bool allowsChildren;

  /// Whether the window is in force.
  final VisitorWindowStatus status;

  /// Who set it.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// How long the window is open.
  Duration get duration => Duration(minutes: endsMinute - startsMinute);

  /// Whether the window is in force.
  bool get isActive => status.isActive;
}

/// The change set that retires a visiting window.
Map<String, Object?> wardVisitingWindowArchiveChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': VisitorWindowStatus.archived.wireValue,
    'updated_at': now,
  };
}

/// One visitor taken at the gate.
@immutable
final class VisitorRegistration {
  /// Creates a visitor registration.
  const VisitorRegistration({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.registrationNumber,
    required this.fullName,
    required this.purpose,
    required this.registeredAt,
    required this.registeredBy,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.phone,
    this.sex,
    this.ageYears,
    this.idDocumentType,
    this.idDocumentNumber,
    this.relationship,
    this.patientId,
    this.wardId,
    this.checkedInAt,
    this.checkedOutAt,
    this.refusedAt,
    this.refuseReason,
    this.voidedAt,
    this.voidReason,
    this.createdAt,
  });

  /// Validates and builds a new registered visitor row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String registrationNumber,
    required String fullName,
    required String registeredBy,
    required String createdBy,
    VisitorPurpose purpose = VisitorPurpose.patientVisit,
    String? phone,
    VisitorSex? sex,
    int? ageYears,
    VisitorIdType? idDocumentType,
    String? idDocumentNumber,
    String? relationship,
    String? patientId,
    String? wardId,
    DateTime? registeredAt,
    String registrationId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (registrationNumber.trim().isEmpty) {
      fieldErrors['registration_number'] = 'A registration number is required.';
    }
    if (fullName.trim().isEmpty) {
      fieldErrors['full_name'] = 'The visitor name is required.';
    }
    if (ageYears != null && (ageYears < 0 || ageYears > 130)) {
      fieldErrors['age_years'] = 'A believable age is required.';
    }
    // A document type without a number, or a number without a type, is half a
    // check: the gate would have nothing to compare against on the way out.
    if ((idDocumentType == null) != (idDocumentNumber == null)) {
      fieldErrors['id_document_number'] =
          'A document needs both a type and a number.';
    }
    if (registeredBy.isEmpty) {
      fieldErrors['registered_by'] = 'Who registered them is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Visitor registration failed validation.',
        fieldErrors: fieldErrors,
        code: 'visitor_registration_invalid',
      );
    }
    final DateTime at = (registeredAt ?? DateTime.now()).toUtc();
    final String stamp = at.toIso8601String();
    return <String, Object?>{
      if (registrationId.isNotEmpty) 'id': registrationId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'registration_number': registrationNumber.trim(),
      'full_name': fullName.trim(),
      'phone': _trimmed(phone),
      'sex': sex?.wireValue,
      'age_years': ageYears,
      'id_document_type': idDocumentType?.wireValue,
      'id_document_number': _trimmed(idDocumentNumber),
      'relationship': _trimmed(relationship),
      'purpose': purpose.wireValue,
      'patient_id': _trimmed(patientId),
      'ward_id': _trimmed(wardId),
      'registered_at': stamp,
      'status': VisitorRegistrationStatus.registered.wireValue,
      'checked_in_at': null,
      'checked_out_at': null,
      'refused_at': null,
      'refuse_reason': null,
      'voided_at': null,
      'void_reason': null,
      'registered_by': registeredBy,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a registration from a local row.
  factory VisitorRegistration.fromRow(Map<String, Object?> row) =>
      VisitorRegistration(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        facilityId: row['facility_id']! as String,
        registrationNumber: row['registration_number']! as String,
        fullName: row['full_name']! as String,
        purpose: VisitorPurpose.fromWire(
          (row['purpose'] as String?) ?? VisitorPurpose.other.wireValue,
        ),
        registeredAt: _parse(row['registered_at']),
        registeredBy: row['registered_by']! as String,
        status: VisitorRegistrationStatus.fromWire(
          (row['status'] as String?) ??
              VisitorRegistrationStatus.registered.wireValue,
        ),
        createdBy: row['created_by']! as String,
        updatedAt: _parse(row['updated_at']),
        phone: row['phone'] as String?,
        sex: VisitorSex.fromWire(row['sex'] as String?),
        ageYears: row['age_years'] as int?,
        idDocumentType: VisitorIdType.fromWire(
          row['id_document_type'] as String?,
        ),
        idDocumentNumber: row['id_document_number'] as String?,
        relationship: row['relationship'] as String?,
        patientId: row['patient_id'] as String?,
        wardId: row['ward_id'] as String?,
        checkedInAt: _parseNullable(row['checked_in_at']),
        checkedOutAt: _parseNullable(row['checked_out_at']),
        refusedAt: _parseNullable(row['refused_at']),
        refuseReason: row['refuse_reason'] as String?,
        voidedAt: _parseNullable(row['voided_at']),
        voidReason: row['void_reason'] as String?,
        createdAt: _parseNullable(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility the gate belongs to.
  final String facilityId;

  /// The gate's registration number.
  final String registrationNumber;

  /// The visitor's name.
  final String fullName;

  /// Why they came.
  final VisitorPurpose purpose;

  /// When the gate took them, UTC.
  final DateTime registeredAt;

  /// Who took them.
  final String registeredBy;

  /// Lifecycle status.
  final VisitorRegistrationStatus status;

  /// Who raised the row.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// How to reach the visitor.
  final String? phone;

  /// Sex as recorded.
  final VisitorSex? sex;

  /// Age in years, when given.
  final int? ageYears;

  /// The document type presented.
  final VisitorIdType? idDocumentType;

  /// The document number presented.
  final String? idDocumentNumber;

  /// How the visitor relates to the patient.
  final String? relationship;

  /// The patient the visit is for.
  final String? patientId;

  /// The ward the visit is for.
  final String? wardId;

  /// When they came in, UTC.
  final DateTime? checkedInAt;

  /// When they went out, UTC.
  final DateTime? checkedOutAt;

  /// When they were turned away, UTC.
  final DateTime? refusedAt;

  /// Why they were turned away.
  final String? refuseReason;

  /// When the row was withdrawn, UTC.
  final DateTime? voidedAt;

  /// Why the row was withdrawn.
  final String? voidReason;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// Whether the visitor is inside.
  bool get isOnSite => status.isOnSite;

  /// Whether the registration is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the registration still has to be worked.
  bool get isLive => status.isLive;

  /// Whether an identity document was recorded.
  bool get hasIdentityDocument =>
      idDocumentType != null && idDocumentNumber != null;

  /// Whether the visitor is under eighteen, which a ward may refuse.
  bool get isMinor => (ageYears ?? 18) < 18;
}

/// The change set that admits a visitor.
Map<String, Object?> visitorRegistrationCheckInChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': VisitorRegistrationStatus.onSite.wireValue,
    'checked_in_at': now,
    'updated_at': now,
  };
}

/// The change set that records a visitor leaving.
Map<String, Object?> visitorRegistrationCheckOutChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': VisitorRegistrationStatus.left.wireValue,
    'checked_out_at': now,
    'updated_at': now,
  };
}

/// The change set that turns a visitor away.
Map<String, Object?> visitorRegistrationRefuseChanges({
  required String reason,
  DateTime? at,
}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Visitor registration failed validation.',
      fieldErrors: <String, String>{'refuse_reason': 'A reason is required.'},
      code: 'visitor_refuse_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': VisitorRegistrationStatus.refused.wireValue,
    'refused_at': now,
    'refuse_reason': reason.trim(),
    'updated_at': now,
  };
}

/// The change set that withdraws a registration entered in error.
Map<String, Object?> visitorRegistrationVoidChanges({
  required String reason,
  DateTime? at,
}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Visitor registration failed validation.',
      fieldErrors: <String, String>{'void_reason': 'A reason is required.'},
      code: 'visitor_registration_void_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': VisitorRegistrationStatus.voided.wireValue,
    'voided_at': now,
    'void_reason': reason.trim(),
    'updated_at': now,
  };
}

/// One digital entry pass.
@immutable
final class VisitorPass {
  /// Creates a pass.
  const VisitorPass({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.registrationId,
    required this.badgeNumber,
    required this.accessScope,
    required this.escortCount,
    required this.validFrom,
    required this.validUntil,
    required this.status,
    required this.issuedBy,
    required this.createdBy,
    required this.updatedAt,
    this.activatedAt,
    this.returnedAt,
    this.revokedAt,
    this.revokeReason,
    this.createdAt,
  });

  /// Validates and builds a new issued pass row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String registrationId,
    required String badgeNumber,
    required String issuedBy,
    required String createdBy,
    required DateTime validUntil,
    VisitorAccessScope accessScope = VisitorAccessScope.ward,
    int escortCount = 0,
    DateTime? validFrom,
    String passId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (registrationId.isEmpty) {
      fieldErrors['registration_id'] = 'A registration is required.';
    }
    if (badgeNumber.trim().isEmpty) {
      fieldErrors['badge_number'] = 'A badge number is required.';
    }
    if (escortCount < 0 || escortCount > 10) {
      fieldErrors['escort_count'] = 'An escort count is required.';
    }
    if (issuedBy.isEmpty) {
      fieldErrors['issued_by'] = 'Who issued it is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    final DateTime from = (validFrom ?? DateTime.now()).toUtc();
    if (!validUntil.toUtc().isAfter(from)) {
      fieldErrors['valid_until'] = 'The pass must end after it starts.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Visitor pass failed validation.',
        fieldErrors: fieldErrors,
        code: 'visitor_pass_invalid',
      );
    }
    final String stamp = from.toIso8601String();
    return <String, Object?>{
      if (passId.isNotEmpty) 'id': passId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'registration_id': registrationId,
      'badge_number': badgeNumber.trim(),
      'access_scope': accessScope.wireValue,
      'escort_count': escortCount,
      'valid_from': stamp,
      'valid_until': validUntil.toUtc().toIso8601String(),
      'status': VisitorPassStatus.issued.wireValue,
      'activated_at': null,
      'returned_at': null,
      'revoked_at': null,
      'revoke_reason': null,
      'issued_by': issuedBy,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a pass from a local row.
  factory VisitorPass.fromRow(Map<String, Object?> row) => VisitorPass(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    registrationId: row['registration_id']! as String,
    badgeNumber: row['badge_number']! as String,
    accessScope: VisitorAccessScope.fromWire(
      (row['access_scope'] as String?) ?? VisitorAccessScope.ward.wireValue,
    ),
    escortCount: _asInt(row['escort_count']),
    validFrom: _parse(row['valid_from']),
    validUntil: _parse(row['valid_until']),
    status: VisitorPassStatus.fromWire(
      (row['status'] as String?) ?? VisitorPassStatus.issued.wireValue,
    ),
    issuedBy: row['issued_by']! as String,
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    activatedAt: _parseNullable(row['activated_at']),
    returnedAt: _parseNullable(row['returned_at']),
    revokedAt: _parseNullable(row['revoked_at']),
    revokeReason: row['revoke_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility the pass was issued at.
  final String facilityId;

  /// The registration the pass was issued against.
  final String registrationId;

  /// The badge number on the pass.
  final String badgeNumber;

  /// Where the pass lets its holder go.
  final VisitorAccessScope accessScope;

  /// How many people the pass admits.
  final int escortCount;

  /// When the pass becomes valid, UTC.
  final DateTime validFrom;

  /// When the pass stops being valid, UTC, inclusive.
  final DateTime validUntil;

  /// Lifecycle status.
  final VisitorPassStatus status;

  /// Who issued it.
  final String issuedBy;

  /// Who raised the row.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// When the pass was activated, UTC.
  final DateTime? activatedAt;

  /// When the badge was handed back, UTC.
  final DateTime? returnedAt;

  /// When the pass was revoked, UTC.
  final DateTime? revokedAt;

  /// Why the pass was revoked.
  final String? revokeReason;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// How long the pass is valid for.
  Duration get validity => validUntil.difference(validFrom);

  /// Whether the pass has run past its window.
  bool get isExpired => DateTime.now().toUtc().isAfter(validUntil.toUtc());

  /// Whether the pass is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the pass still has to be worked.
  bool get isLive => status.isLive;

  /// Whether the pass admits anyone at all.
  bool get isActive => status == VisitorPassStatus.active;
}

/// The change set that activates a pass at the gate.
Map<String, Object?> visitorPassActivateChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': VisitorPassStatus.active.wireValue,
    'activated_at': now,
    'updated_at': now,
  };
}

/// The change set that records a badge handed back.
Map<String, Object?> visitorPassReturnChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': VisitorPassStatus.returned.wireValue,
    'returned_at': now,
    'updated_at': now,
  };
}

/// The change set that revokes a pass before its window closed.
Map<String, Object?> visitorPassRevokeChanges({
  required String reason,
  DateTime? at,
}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Visitor pass failed validation.',
      fieldErrors: <String, String>{'revoke_reason': 'A reason is required.'},
      code: 'visitor_pass_revoke_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': VisitorPassStatus.revoked.wireValue,
    'revoked_at': now,
    'revoke_reason': reason.trim(),
    'updated_at': now,
  };
}

/// One line of the badge print log.
@immutable
final class VisitorBadgePrint {
  /// Creates a badge print record.
  const VisitorBadgePrint({
    required this.id,
    required this.tenantId,
    required this.passId,
    required this.badgeNumber,
    required this.printOrdinal,
    required this.printerLabel,
    required this.printedAt,
    required this.printedBy,
    this.note,
    this.createdAt,
  });

  /// Validates and builds a badge print row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String passId,
    required String badgeNumber,
    required int printOrdinal,
    required String printerLabel,
    required String printedBy,
    String? note,
    DateTime? printedAt,
    String printId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (passId.isEmpty) {
      fieldErrors['pass_id'] = 'The pass is required.';
    }
    if (badgeNumber.trim().isEmpty) {
      fieldErrors['badge_number'] = 'A badge number is required.';
    }
    if (printOrdinal < 1 || printOrdinal > 20) {
      fieldErrors['print_ordinal'] = 'A print ordinal is required.';
    }
    if (printerLabel.trim().isEmpty) {
      fieldErrors['printer_label'] = 'The printer is required.';
    }
    if (printedBy.isEmpty) {
      fieldErrors['printed_by'] = 'Who printed it is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Badge print failed validation.',
        fieldErrors: fieldErrors,
        code: 'visitor_badge_print_invalid',
      );
    }
    final DateTime at = (printedAt ?? DateTime.now()).toUtc();
    return <String, Object?>{
      if (printId.isNotEmpty) 'id': printId,
      'tenant_id': tenantId,
      'pass_id': passId,
      'badge_number': badgeNumber.trim(),
      'print_ordinal': printOrdinal,
      'printer_label': printerLabel.trim(),
      'note': _trimmed(note),
      'printed_at': at.toIso8601String(),
      'printed_by': printedBy,
      'created_at': at.toIso8601String(),
    };
  }

  /// Materializes a print record from a local row.
  factory VisitorBadgePrint.fromRow(Map<String, Object?> row) =>
      VisitorBadgePrint(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        passId: row['pass_id']! as String,
        badgeNumber: row['badge_number']! as String,
        printOrdinal: _asInt(row['print_ordinal']),
        printerLabel: row['printer_label']! as String,
        printedAt: _parse(row['printed_at']),
        printedBy: row['printed_by']! as String,
        note: row['note'] as String?,
        createdAt: _parseNullable(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The pass that was printed.
  final String passId;

  /// The badge number written onto the badge.
  final String badgeNumber;

  /// Which print of this badge this is, from one.
  final int printOrdinal;

  /// The printer that made it.
  final String printerLabel;

  /// When it was printed, UTC.
  final DateTime printedAt;

  /// Who printed it.
  final String printedBy;

  /// Why it was printed again.
  final String? note;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// Whether the badge was made more than once.
  bool get isReprint => printOrdinal > 1;
}

String? _trimmed(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime _parse(Object? value) => value is String
    ? DateTime.parse(value).toUtc()
    : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _parseNullable(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.parse(value);
  }
  return 0;
}

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  return false;
}
