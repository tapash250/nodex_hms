/// Human resources & payroll entities (Module 13).
///
/// Specification scope: "Employee lifecycle, attendance, leave, payroll,
/// payslips, holidays, badges."
///
/// Attendance is deliberately absent: Module 09 already owns
/// `attendance_logs`, and HR reads those facts rather than keeping a second
/// copy. What lives here is the employment record, the leave *workflow* (the
/// roster block an approval produces is a Module 09 duty allocation), the
/// holiday calendar, and the payroll run.
///
/// Money is integer minor units, matching the billing engine's refusal of
/// floating-point currency. A payslip's net is derived from gross less
/// deductions and cannot disagree with them.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// ISO-8601 calendar date, as stored in `date` columns.
final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// How someone is employed.
enum EmploymentType {
  /// Salaried, ongoing.
  permanent('permanent'),

  /// Fixed-term.
  contract('contract'),

  /// Less than full-time hours.
  partTime('part_time'),

  /// Training placement.
  intern('intern'),

  /// Temporary cover.
  locum('locum');

  const EmploymentType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    EmploymentType.permanent => 'Permanent',
    EmploymentType.contract => 'Contract',
    EmploymentType.partTime => 'Part-time',
    EmploymentType.intern => 'Intern',
    EmploymentType.locum => 'Locum',
  };

  /// Parses a stored value.
  static EmploymentType fromWire(String value) =>
      EmploymentType.values.firstWhere(
        (EmploymentType type) => type.wireValue == value,
        orElse: () => EmploymentType.permanent,
      );
}

/// Where someone is in the employment lifecycle.
enum EmploymentStatus {
  /// Joined, not yet confirmed.
  probation('probation'),

  /// Confirmed and working.
  active('active'),

  /// On an approved leave of absence.
  onLeave('on_leave'),

  /// Under suspension pending a decision.
  suspended('suspended'),

  /// Left the organisation; the record is retained.
  separated('separated');

  const EmploymentStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    EmploymentStatus.probation => 'Probation',
    EmploymentStatus.active => 'Active',
    EmploymentStatus.onLeave => 'On leave',
    EmploymentStatus.suspended => 'Suspended',
    EmploymentStatus.separated => 'Separated',
  };

  /// Parses a stored value.
  static EmploymentStatus fromWire(String value) =>
      EmploymentStatus.values.firstWhere(
        (EmploymentStatus status) => status.wireValue == value,
        orElse: () => EmploymentStatus.probation,
      );

  /// Whether the employee is expected to work.
  bool get isWorking =>
      this == EmploymentStatus.probation ||
      this == EmploymentStatus.active ||
      this == EmploymentStatus.onLeave;
}

/// The kind of leave applied for.
enum LeaveType {
  /// Paid annual leave.
  annual('annual'),

  /// Paid sick leave.
  sick('sick'),

  /// Maternity leave.
  maternity('maternity'),

  /// Paternity leave.
  paternity('paternity'),

  /// Unpaid leave.
  unpaid('unpaid'),

  /// Study or examination leave.
  study('study'),

  /// Casual leave.
  casual('casual'),

  /// Bereavement leave.
  bereavement('bereavement'),

  /// Anything not covered above.
  other('other');

  const LeaveType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    LeaveType.annual => 'Annual',
    LeaveType.sick => 'Sick',
    LeaveType.maternity => 'Maternity',
    LeaveType.paternity => 'Paternity',
    LeaveType.unpaid => 'Unpaid',
    LeaveType.study => 'Study',
    LeaveType.casual => 'Casual',
    LeaveType.bereavement => 'Bereavement',
    LeaveType.other => 'Other',
  };

  /// Parses a stored value.
  static LeaveType fromWire(String value) => LeaveType.values.firstWhere(
    (LeaveType type) => type.wireValue == value,
    orElse: () => LeaveType.other,
  );
}

/// Where a leave application stands.
enum LeaveStatus {
  /// Awaiting a decision.
  requested('requested'),

  /// Granted.
  approved('approved'),

  /// Refused.
  rejected('rejected'),

  /// Withdrawn before or after a decision.
  cancelled('cancelled');

  const LeaveStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    LeaveStatus.requested => 'Requested',
    LeaveStatus.approved => 'Approved',
    LeaveStatus.rejected => 'Rejected',
    LeaveStatus.cancelled => 'Cancelled',
  };

  /// Parses a stored value.
  static LeaveStatus fromWire(String value) => LeaveStatus.values.firstWhere(
    (LeaveStatus status) => status.wireValue == value,
    orElse: () => LeaveStatus.requested,
  );

  /// Whether the application still occupies its window.
  bool get isLive =>
      this == LeaveStatus.requested || this == LeaveStatus.approved;

  /// Whether a decision has been made.
  bool get isDecided => this != LeaveStatus.requested;
}

/// The kind of holiday.
enum HolidayType {
  /// Government public holiday.
  public('public'),

  /// Religious observance.
  religious('religious'),

  /// National day.
  national('national'),

  /// Institution-specific closure.
  institutional('institutional'),

  /// Optional / restricted holiday.
  optional('optional');

  const HolidayType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    HolidayType.public => 'Public',
    HolidayType.religious => 'Religious',
    HolidayType.national => 'National',
    HolidayType.institutional => 'Institutional',
    HolidayType.optional => 'Optional',
  };

  /// Parses a stored value.
  static HolidayType fromWire(String value) => HolidayType.values.firstWhere(
    (HolidayType type) => type.wireValue == value,
    orElse: () => HolidayType.public,
  );
}

/// Where a payroll run or payslip stands.
enum PayrollStatus {
  /// Being prepared; editable.
  draft('draft'),

  /// Frozen and approved for payment.
  finalized('finalized'),

  /// Paid out.
  paid('paid');

  const PayrollStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    PayrollStatus.draft => 'Draft',
    PayrollStatus.finalized => 'Finalized',
    PayrollStatus.paid => 'Paid',
  };

  /// Parses a stored value.
  static PayrollStatus fromWire(String value) =>
      PayrollStatus.values.firstWhere(
        (PayrollStatus status) => status.wireValue == value,
        orElse: () => PayrollStatus.draft,
      );

  /// Whether the financial fields may still change.
  bool get isEditable => this == PayrollStatus.draft;
}

/// The employment record layered on an `app_users` identity.
@immutable
final class HrEmployee {
  /// Creates an employment record.
  const HrEmployee({
    required this.id,
    required this.tenantId,
    required this.userId,
    required this.employeeCode,
    required this.joinedOn,
    required this.employmentType,
    required this.employmentStatus,
    this.departmentId,
    this.designation,
    this.grade,
    this.reportsTo,
    this.confirmationOn,
    this.separatedOn,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  /// Validates and builds a new employee row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String userId,
    required String employeeCode,
    required String joinedOn,
    EmploymentType employmentType = EmploymentType.permanent,
    EmploymentStatus employmentStatus = EmploymentStatus.probation,
    String? departmentId,
    String? designation,
    String? grade,
    String? reportsTo,
    String? notes,
    String employeeId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (userId.isEmpty) {
      fieldErrors['user_id'] = 'User is required.';
    }
    if (employeeCode.trim().isEmpty) {
      fieldErrors['employee_code'] = 'Employee code is required.';
    }
    if (!_isoDate.hasMatch(joinedOn)) {
      fieldErrors['joined_on'] = 'Expected an ISO-8601 date.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Employee record failed validation.',
        fieldErrors: fieldErrors,
        code: 'hr_employee_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (employeeId.isNotEmpty) 'id': employeeId,
      'tenant_id': tenantId,
      'user_id': userId,
      'employee_code': employeeCode.trim(),
      'department_id': departmentId,
      'designation': _trimmed(designation),
      'employment_type': employmentType.wireValue,
      'employment_status': employmentStatus.wireValue,
      'grade': _trimmed(grade),
      'reports_to': reportsTo,
      'joined_on': joinedOn,
      'confirmation_on': null,
      'separated_on': null,
      'notes': _trimmed(notes),
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes an employee from a local row.
  factory HrEmployee.fromRow(Map<String, Object?> row) => HrEmployee(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    userId: row['user_id']! as String,
    employeeCode: row['employee_code']! as String,
    joinedOn: row['joined_on']! as String,
    employmentType: EmploymentType.fromWire(row['employment_type']! as String),
    employmentStatus: EmploymentStatus.fromWire(
      row['employment_status']! as String,
    ),
    departmentId: row['department_id'] as String?,
    designation: row['designation'] as String?,
    grade: row['grade'] as String?,
    reportsTo: row['reports_to'] as String?,
    confirmationOn: row['confirmation_on'] as String?,
    separatedOn: row['separated_on'] as String?,
    notes: row['notes'] as String?,
    createdAt: _parse(row['created_at']),
    updatedAt: _parse(row['updated_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The `app_users` identity this record belongs to.
  final String userId;

  /// Employer-issued staff number, unique within the tenant.
  final String employeeCode;

  /// Owning department, when known.
  final String? departmentId;

  /// Job title held.
  final String? designation;

  /// Employment type.
  final EmploymentType employmentType;

  /// Lifecycle status.
  final EmploymentStatus employmentStatus;

  /// Pay/grade band.
  final String? grade;

  /// The `app_users` id this person reports to.
  final String? reportsTo;

  /// Date of joining, `YYYY-MM-DD`.
  final String joinedOn;

  /// Date confirmed in post, if confirmed.
  final String? confirmationOn;

  /// Date separated, if separated.
  final String? separatedOn;

  /// Free-text notes.
  final String? notes;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether the person is still employed.
  bool get isEmployed => employmentStatus != EmploymentStatus.separated;

  /// Whether a confirmation date has been recorded.
  bool get isConfirmed => confirmationOn != null;
}

/// Column changes for an employee edit.
Map<String, Object?> hrEmployeeChanges({
  String? departmentId,
  String? designation,
  String? grade,
  String? reportsTo,
  String? notes,
  EmploymentType? employmentType,
  EmploymentStatus? employmentStatus,
}) => <String, Object?>{
  'department_id': departmentId,
  'designation': _trimmed(designation),
  'grade': ?_trimmed(grade),
  'reports_to': reportsTo,
  'notes': _trimmed(notes),
  'employment_type': ?employmentType?.wireValue,
  'employment_status': ?employmentStatus?.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The change set for confirming an employee in post.
Map<String, Object?> hrEmployeeConfirmationChanges({
  required String confirmedOn,
}) => <String, Object?>{
  'confirmation_on': confirmedOn,
  'employment_status': EmploymentStatus.active.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The change set for separating an employee.
Map<String, Object?> hrEmployeeSeparationChanges({
  required String separatedOn,
}) => <String, Object?>{
  'separated_on': separatedOn,
  'employment_status': EmploymentStatus.separated.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// A leave application and its decision.
@immutable
final class HrLeaveRequest {
  /// Creates a leave application.
  const HrLeaveRequest({
    required this.id,
    required this.tenantId,
    required this.employeeId,
    required this.leaveType,
    required this.startsOn,
    required this.endsOn,
    required this.status,
    required this.requestedBy,
    this.reason,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
    this.createdAt,
    this.updatedAt,
  });

  /// Validates and builds a new leave-request row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String employeeId,
    required String startsOn,
    required String endsOn,
    required String requestedBy,
    LeaveType leaveType = LeaveType.annual,
    String? reason,
    String requestId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (employeeId.isEmpty) {
      fieldErrors['employee_id'] = 'Employee is required.';
    }
    if (requestedBy.isEmpty) {
      fieldErrors['requested_by'] = 'Requester is required.';
    }
    if (!_isoDate.hasMatch(startsOn)) {
      fieldErrors['starts_on'] = 'Expected an ISO-8601 date.';
    }
    if (!_isoDate.hasMatch(endsOn)) {
      fieldErrors['ends_on'] = 'Expected an ISO-8601 date.';
    }
    if (_isoDate.hasMatch(startsOn) &&
        _isoDate.hasMatch(endsOn) &&
        endsOn.compareTo(startsOn) < 0) {
      fieldErrors['ends_on'] = 'Must not end before it starts.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Leave request failed validation.',
        fieldErrors: fieldErrors,
        code: 'hr_leave_request_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (requestId.isNotEmpty) 'id': requestId,
      'tenant_id': tenantId,
      'employee_id': employeeId,
      'leave_type': leaveType.wireValue,
      'starts_on': startsOn,
      'ends_on': endsOn,
      'reason': _trimmed(reason),
      'status': LeaveStatus.requested.wireValue,
      'requested_by': requestedBy,
      'decided_by': null,
      'decided_at': null,
      'decision_note': null,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a leave application from a local row.
  factory HrLeaveRequest.fromRow(Map<String, Object?> row) => HrLeaveRequest(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    employeeId: row['employee_id']! as String,
    leaveType: LeaveType.fromWire(row['leave_type']! as String),
    startsOn: row['starts_on']! as String,
    endsOn: row['ends_on']! as String,
    status: LeaveStatus.fromWire(row['status']! as String),
    requestedBy: row['requested_by']! as String,
    reason: row['reason'] as String?,
    decidedBy: row['decided_by'] as String?,
    decidedAt: _parse(row['decided_at']),
    decisionNote: row['decision_note'] as String?,
    createdAt: _parse(row['created_at']),
    updatedAt: _parse(row['updated_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The employee applying.
  final String employeeId;

  /// Kind of leave.
  final LeaveType leaveType;

  /// First day of leave, `YYYY-MM-DD`.
  final String startsOn;

  /// Last day of leave, `YYYY-MM-DD`.
  final String endsOn;

  /// Lifecycle status.
  final LeaveStatus status;

  /// Who raised the application.
  final String requestedBy;

  /// Who decided it, once decided.
  final String? decidedBy;

  /// When it was decided.
  final DateTime? decidedAt;

  /// The decision note.
  final String? decisionNote;

  /// The reason given.
  final String? reason;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether the application still occupies its window.
  bool get occupiesWindow => status.isLive;

  /// Whether a decision is still possible.
  bool get isPending => status == LeaveStatus.requested;
}

/// The change set for deciding a leave application.
Map<String, Object?> hrLeaveDecisionChanges({
  required LeaveStatus status,
  required String decidedBy,
  String? note,
}) => <String, Object?>{
  'status': status.wireValue,
  'decided_by': decidedBy,
  'decided_at': DateTime.now().toUtc().toIso8601String(),
  'decision_note': _trimmed(note),
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The change set for cancelling a leave application.
Map<String, Object?> hrLeaveCancellationChanges({
  required String cancelledBy,
  String? note,
}) => <String, Object?>{
  'status': LeaveStatus.cancelled.wireValue,
  'decided_by': cancelledBy,
  'decided_at': DateTime.now().toUtc().toIso8601String(),
  'decision_note': _trimmed(note),
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// A calendar holiday.
@immutable
final class HrHoliday {
  /// Creates a holiday.
  const HrHoliday({
    required this.id,
    required this.tenantId,
    required this.holidayDate,
    required this.displayName,
    required this.holidayType,
    required this.isPaid,
    this.facilityId,
    this.createdAt,
    this.updatedAt,
  });

  /// Validates and builds a new holiday row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String holidayDate,
    required String displayName,
    HolidayType holidayType = HolidayType.public,
    bool isPaid = true,
    String? facilityId,
    String holidayId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (!_isoDate.hasMatch(holidayDate)) {
      fieldErrors['holiday_date'] = 'Expected an ISO-8601 date.';
    }
    if (displayName.trim().isEmpty) {
      fieldErrors['display_name'] = 'Holiday name is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Holiday failed validation.',
        fieldErrors: fieldErrors,
        code: 'hr_holiday_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (holidayId.isNotEmpty) 'id': holidayId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'holiday_date': holidayDate,
      'display_name': displayName.trim(),
      'holiday_type': holidayType.wireValue,
      'is_paid': isPaid,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a holiday from a local row.
  factory HrHoliday.fromRow(Map<String, Object?> row) => HrHoliday(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    holidayDate: row['holiday_date']! as String,
    displayName: row['display_name']! as String,
    holidayType: HolidayType.fromWire(row['holiday_type']! as String),
    isPaid: _asBool(row['is_paid']),
    facilityId: row['facility_id'] as String?,
    createdAt: _parse(row['created_at']),
    updatedAt: _parse(row['updated_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Facility scope, or null for a tenant-wide holiday.
  final String? facilityId;

  /// Calendar date, `YYYY-MM-DD`.
  final String holidayDate;

  /// Human-readable name.
  final String displayName;

  /// Kind of holiday.
  final HolidayType holidayType;

  /// Whether it is a paid holiday.
  final bool isPaid;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether the holiday applies to the whole tenant.
  bool get isTenantWide => facilityId == null;
}

/// A monthly payroll run.
@immutable
final class HrPayrollPeriod {
  /// Creates a payroll period.
  const HrPayrollPeriod({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.periodStart,
    required this.periodEnd,
    required this.payDate,
    required this.currency,
    required this.status,
    this.finalizedBy,
    this.finalizedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Validates and builds a new payroll-period row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String periodStart,
    required String periodEnd,
    required String payDate,
    String currency = 'BDT',
    String periodId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'Facility is required.';
    }
    if (!_isoDate.hasMatch(periodStart)) {
      fieldErrors['period_start'] = 'Expected an ISO-8601 date.';
    }
    if (!_isoDate.hasMatch(periodEnd)) {
      fieldErrors['period_end'] = 'Expected an ISO-8601 date.';
    }
    if (!_isoDate.hasMatch(payDate)) {
      fieldErrors['pay_date'] = 'Expected an ISO-8601 date.';
    }
    if (_isoDate.hasMatch(periodStart) &&
        _isoDate.hasMatch(periodEnd) &&
        periodEnd.compareTo(periodStart) < 0) {
      fieldErrors['period_end'] = 'Must not end before it starts.';
    }
    if (_isoDate.hasMatch(periodEnd) &&
        _isoDate.hasMatch(payDate) &&
        payDate.compareTo(periodEnd) < 0) {
      fieldErrors['pay_date'] = 'Must not precede the period end.';
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      fieldErrors['currency'] = 'Expected an ISO-4217 code.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Payroll period failed validation.',
        fieldErrors: fieldErrors,
        code: 'hr_payroll_period_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (periodId.isNotEmpty) 'id': periodId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'period_start': periodStart,
      'period_end': periodEnd,
      'pay_date': payDate,
      'currency': currency,
      'status': PayrollStatus.draft.wireValue,
      'finalized_by': null,
      'finalized_at': null,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a payroll period from a local row.
  factory HrPayrollPeriod.fromRow(Map<String, Object?> row) => HrPayrollPeriod(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    periodStart: row['period_start']! as String,
    periodEnd: row['period_end']! as String,
    payDate: row['pay_date']! as String,
    currency: row['currency']! as String,
    status: PayrollStatus.fromWire(row['status']! as String),
    finalizedBy: row['finalized_by'] as String?,
    finalizedAt: _parse(row['finalized_at']),
    createdAt: _parse(row['created_at']),
    updatedAt: _parse(row['updated_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Facility the run pays.
  final String facilityId;

  /// First day of the pay window, `YYYY-MM-DD`.
  final String periodStart;

  /// Last day of the pay window, `YYYY-MM-DD`.
  final String periodEnd;

  /// The date staff are paid.
  final String payDate;

  /// ISO-4217 code.
  final String currency;

  /// Lifecycle status.
  final PayrollStatus status;

  /// Who finalized the run.
  final String? finalizedBy;

  /// When it was finalized.
  final DateTime? finalizedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether the run may still be edited.
  bool get isEditable => status.isEditable;
}

/// The change set for finalizing a payroll run.
Map<String, Object?> hrPayrollFinalizationChanges({
  required String finalizedBy,
}) => <String, Object?>{
  'status': PayrollStatus.finalized.wireValue,
  'finalized_by': finalizedBy,
  'finalized_at': DateTime.now().toUtc().toIso8601String(),
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The change set for marking a finalized run as paid.
Map<String, Object?> hrPayrollPaidChanges() => <String, Object?>{
  'status': PayrollStatus.paid.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// A payslip under a payroll run.
@immutable
final class HrPayslip {
  /// Creates a payslip.
  const HrPayslip({
    required this.id,
    required this.tenantId,
    required this.periodId,
    required this.employeeId,
    required this.grossMinor,
    required this.deductionsMinor,
    required this.netMinor,
    required this.status,
    this.paidOn,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  /// Validates and builds a new payslip row. Net is derived, never supplied.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String periodId,
    required String employeeId,
    required int grossMinor,
    int deductionsMinor = 0,
    String? note,
    String payslipId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (periodId.isEmpty) {
      fieldErrors['period_id'] = 'Payroll period is required.';
    }
    if (employeeId.isEmpty) {
      fieldErrors['employee_id'] = 'Employee is required.';
    }
    if (grossMinor < 0) {
      fieldErrors['gross_minor'] = 'Gross pay cannot be negative.';
    }
    if (deductionsMinor < 0) {
      fieldErrors['deductions_minor'] = 'Deductions cannot be negative.';
    }
    if (deductionsMinor > grossMinor) {
      fieldErrors['deductions_minor'] = 'Deductions exceed gross pay.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Payslip failed validation.',
        fieldErrors: fieldErrors,
        code: 'hr_payslip_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (payslipId.isNotEmpty) 'id': payslipId,
      'tenant_id': tenantId,
      'period_id': periodId,
      'employee_id': employeeId,
      'gross_minor': grossMinor,
      'deductions_minor': deductionsMinor,
      'net_minor': grossMinor - deductionsMinor,
      'status': PayrollStatus.draft.wireValue,
      'paid_on': null,
      'note': _trimmed(note),
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a payslip from a local row.
  factory HrPayslip.fromRow(Map<String, Object?> row) => HrPayslip(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    periodId: row['period_id']! as String,
    employeeId: row['employee_id']! as String,
    grossMinor: _asInt(row['gross_minor']),
    deductionsMinor: _asInt(row['deductions_minor']),
    netMinor: _asInt(row['net_minor']),
    status: PayrollStatus.fromWire(row['status']! as String),
    paidOn: row['paid_on'] as String?,
    note: row['note'] as String?,
    createdAt: _parse(row['created_at']),
    updatedAt: _parse(row['updated_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Owning payroll run.
  final String periodId;

  /// The employee paid.
  final String employeeId;

  /// Gross pay in minor units.
  final int grossMinor;

  /// Total deductions in minor units.
  final int deductionsMinor;

  /// Net pay in minor units; always gross less deductions.
  final int netMinor;

  /// Lifecycle status.
  final PayrollStatus status;

  /// Date paid, if paid.
  final String? paidOn;

  /// Optional note.
  final String? note;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether the payslip may still be edited.
  bool get isEditable => status.isEditable;
}

/// The change set for marking a payslip paid.
Map<String, Object?> hrPayslipPaidChanges({required String paidOn}) =>
    <String, Object?>{
      'status': PayrollStatus.paid.wireValue,
      'paid_on': paidOn,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

String? _trimmed(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

DateTime? _parse(Object? value) =>
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
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return false;
}
