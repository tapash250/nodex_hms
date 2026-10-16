/// Human resources & payroll use cases (Module 13).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/hr/hr.dart';
import 'package:nodex_hms/domain/hr/hr_repository.dart';

/// Registers an employment record.
final class RegisterEmployeeUseCase {
  /// Creates the use case.
  RegisterEmployeeUseCase({required this._repository});

  final HrRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String userId,
    required String employeeCode,
    required String joinedOn,
    EmploymentType employmentType = EmploymentType.permanent,
    String? departmentId,
    String? designation,
    String? grade,
    String? reportsTo,
    String? notes,
    String employeeId = '',
  }) async {
    policy.require(NodexPermissions.hrManage);
    return _repository.registerEmployee(
      HrEmployee.registerRow(
        tenantId: tenantId,
        userId: userId,
        employeeCode: employeeCode,
        joinedOn: joinedOn,
        employmentType: employmentType,
        departmentId: departmentId,
        designation: designation,
        grade: grade,
        reportsTo: reportsTo,
        notes: notes,
        employeeId: employeeId,
      ),
    );
  }
}

/// Edits a non-lifecycle employment attribute.
final class UpdateEmployeeUseCase {
  /// Creates the use case.
  UpdateEmployeeUseCase({required this._repository});

  final HrRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required HrEmployee employee,
    String? departmentId,
    String? designation,
    String? grade,
    String? reportsTo,
    String? notes,
    EmploymentType? employmentType,
  }) async {
    policy.require(NodexPermissions.hrManage);
    if (!employee.isEmployed) {
      throw const AuthorizationError(
        message: 'A separated employee record is retained, not edited.',
        code: 'hr_employee_separated',
      );
    }
    await _repository.updateEmployee(
      employee.id,
      hrEmployeeChanges(
        departmentId: departmentId,
        designation: designation,
        grade: grade,
        reportsTo: reportsTo,
        notes: notes,
        employmentType: employmentType,
      ),
    );
  }
}

/// Confirms an employee in post.
final class ConfirmEmployeeUseCase {
  /// Creates the use case.
  ConfirmEmployeeUseCase({required this._repository});

  final HrRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required HrEmployee employee,
    required String confirmedOn,
  }) async {
    policy.require(NodexPermissions.hrManage);
    if (!employee.isEmployed) {
      throw const AuthorizationError(
        message: 'A separated employee cannot be confirmed.',
        code: 'hr_employee_separated',
      );
    }
    if (employee.isConfirmed) {
      throw const AuthorizationError(
        message: 'This employee is already confirmed.',
        code: 'hr_employee_already_confirmed',
      );
    }
    await _repository.updateEmployee(
      employee.id,
      hrEmployeeConfirmationChanges(confirmedOn: confirmedOn),
    );
  }
}

/// Separates an employee, retaining the record.
final class SeparateEmployeeUseCase {
  /// Creates the use case.
  SeparateEmployeeUseCase({required this._repository});

  final HrRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required HrEmployee employee,
    required String separatedOn,
  }) async {
    policy.require(NodexPermissions.hrManage);
    if (!employee.isEmployed) {
      throw const AuthorizationError(
        message: 'This employee has already been separated.',
        code: 'hr_employee_already_separated',
      );
    }
    if (separatedOn.compareTo(employee.joinedOn) < 0) {
      throw const ValidationError(
        message: 'Separation cannot precede joining.',
        code: 'hr_employee_separation_before_joining',
        fieldErrors: <String, String>{
          'separated_on': 'Must be on or after the joining date.',
        },
      );
    }
    await _repository.updateEmployee(
      employee.id,
      hrEmployeeSeparationChanges(separatedOn: separatedOn),
    );
  }
}

/// Raises a leave application, refusing an overlap with a live one.
final class RequestLeaveUseCase {
  /// Creates the use case.
  RequestLeaveUseCase({required this._repository});

  final HrRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String employeeId,
    required String startsOn,
    required String endsOn,
    required String requestedBy,
    LeaveType leaveType = LeaveType.annual,
    String? reason,
    String requestId = '',
  }) async {
    policy.require(NodexPermissions.hrManage);
    final List<HrLeaveRequest> existing = await _repository.listLeaveRequests(
      tenantId,
      employeeId: employeeId,
    );
    for (final HrLeaveRequest other in existing) {
      if (other.occupiesWindow &&
          other.startsOn.compareTo(endsOn) <= 0 &&
          startsOn.compareTo(other.endsOn) <= 0) {
        throw ValidationError(
          message: 'A live leave application already covers that window.',
          code: 'hr_leave_overlap',
          fieldErrors: <String, String>{
            'starts_on':
                'Overlaps ${other.leaveType.label} leave from '
                '${other.startsOn} to ${other.endsOn}.',
          },
        );
      }
    }
    return _repository.registerLeaveRequest(
      HrLeaveRequest.registerRow(
        tenantId: tenantId,
        employeeId: employeeId,
        startsOn: startsOn,
        endsOn: endsOn,
        requestedBy: requestedBy,
        leaveType: leaveType,
        reason: reason,
        requestId: requestId,
      ),
    );
  }
}

/// Approves or rejects a pending leave application.
final class DecideLeaveUseCase {
  /// Creates the use case.
  DecideLeaveUseCase({required this._repository});

  final HrRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required HrLeaveRequest request,
    required LeaveStatus decision,
    required String decidedBy,
    String? note,
  }) async {
    policy.require(NodexPermissions.hrManage);
    if (decision != LeaveStatus.approved && decision != LeaveStatus.rejected) {
      throw const ValidationError(
        message: 'A decision is either approval or rejection.',
        code: 'hr_leave_decision_invalid',
      );
    }
    if (!request.isPending) {
      throw const AuthorizationError(
        message: 'This leave application has already been decided.',
        code: 'hr_leave_already_decided',
      );
    }
    await _repository.updateLeaveRequest(
      request.id,
      hrLeaveDecisionChanges(
        status: decision,
        decidedBy: decidedBy,
        note: note,
      ),
    );
  }
}

/// Cancels a leave application, before or after approval.
final class CancelLeaveUseCase {
  /// Creates the use case.
  CancelLeaveUseCase({required this._repository});

  final HrRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required HrLeaveRequest request,
    required String cancelledBy,
    String? note,
  }) async {
    policy.require(NodexPermissions.hrManage);
    if (request.status == LeaveStatus.cancelled) {
      throw const AuthorizationError(
        message: 'This leave application is already cancelled.',
        code: 'hr_leave_already_cancelled',
      );
    }
    if (request.status == LeaveStatus.rejected) {
      throw const AuthorizationError(
        message: 'A rejected leave application cannot be cancelled.',
        code: 'hr_leave_rejected_immutable',
      );
    }
    await _repository.updateLeaveRequest(
      request.id,
      hrLeaveCancellationChanges(cancelledBy: cancelledBy, note: note),
    );
  }
}

/// Adds a holiday to the calendar.
final class SetHolidayUseCase {
  /// Creates the use case.
  SetHolidayUseCase({required this._repository});

  final HrRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String holidayDate,
    required String displayName,
    HolidayType holidayType = HolidayType.public,
    bool isPaid = true,
    String? facilityId,
    String holidayId = '',
  }) async {
    policy.require(NodexPermissions.hrManage);
    return _repository.registerHoliday(
      HrHoliday.registerRow(
        tenantId: tenantId,
        holidayDate: holidayDate,
        displayName: displayName,
        holidayType: holidayType,
        isPaid: isPaid,
        facilityId: facilityId,
        holidayId: holidayId,
      ),
    );
  }
}

/// Opens a draft payroll run.
final class OpenPayrollPeriodUseCase {
  /// Creates the use case.
  OpenPayrollPeriodUseCase({required this._repository});

  final HrRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String periodStart,
    required String periodEnd,
    required String payDate,
    String currency = 'BDT',
    String periodId = '',
  }) async {
    policy.require(NodexPermissions.payrollManage);
    return _repository.registerPayrollPeriod(
      HrPayrollPeriod.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        periodStart: periodStart,
        periodEnd: periodEnd,
        payDate: payDate,
        currency: currency,
        periodId: periodId,
      ),
    );
  }
}

/// Adds a payslip to a draft payroll run.
final class CreatePayslipUseCase {
  /// Creates the use case.
  CreatePayslipUseCase({required this._repository});

  final HrRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required HrPayrollPeriod period,
    required HrEmployee employee,
    required int grossMinor,
    int deductionsMinor = 0,
    String? note,
    String payslipId = '',
  }) async {
    policy.require(NodexPermissions.payrollManage);
    if (!period.isEditable) {
      throw const AuthorizationError(
        message: 'Payslips may only be added to a draft payroll run.',
        code: 'hr_payroll_period_frozen',
      );
    }
    if (!employee.isEmployed) {
      throw const AuthorizationError(
        message: 'A separated employee cannot be paid.',
        code: 'hr_employee_separated',
      );
    }
    return _repository.registerPayslip(
      HrPayslip.registerRow(
        tenantId: period.tenantId,
        periodId: period.id,
        employeeId: employee.id,
        grossMinor: grossMinor,
        deductionsMinor: deductionsMinor,
        note: note,
        payslipId: payslipId,
      ),
    );
  }
}

/// Finalizes a payroll run, freezing it and its payslips.
///
/// A run with no payslips is refused: finalizing an empty period would freeze a
/// number nobody has checked.
final class FinalizePayrollPeriodUseCase {
  /// Creates the use case.
  FinalizePayrollPeriodUseCase({required this._repository});

  final HrRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required HrPayrollPeriod period,
    required String finalizedBy,
  }) async {
    policy.require(NodexPermissions.payrollManage);
    if (!period.isEditable) {
      throw const AuthorizationError(
        message: 'This payroll run is already finalized.',
        code: 'hr_payroll_period_frozen',
      );
    }
    final List<HrPayslip> payslips = await _repository.listPayslips(
      period.tenantId,
      periodId: period.id,
    );
    if (payslips.isEmpty) {
      throw const ValidationError(
        message: 'A payroll run needs at least one payslip before finalizing.',
        code: 'hr_payroll_period_empty',
        fieldErrors: <String, String>{'period_id': 'No payslips recorded.'},
      );
    }
    for (final HrPayslip payslip in payslips) {
      if (payslip.status == PayrollStatus.draft) {
        await _repository.updatePayslip(payslip.id, <String, Object?>{
          'status': PayrollStatus.finalized.wireValue,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    }
    await _repository.updatePayrollPeriod(
      period.id,
      hrPayrollFinalizationChanges(finalizedBy: finalizedBy),
    );
  }
}

/// Marks a finalized payroll run, and its payslips, paid.
final class MarkPayrollPaidUseCase {
  /// Creates the use case.
  MarkPayrollPaidUseCase({required this._repository});

  final HrRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required HrPayrollPeriod period,
  }) async {
    policy.require(NodexPermissions.payrollManage);
    if (period.status != PayrollStatus.finalized) {
      throw const AuthorizationError(
        message: 'A payroll run must be finalized before it is paid.',
        code: 'hr_payroll_not_finalized',
      );
    }
    final List<HrPayslip> payslips = await _repository.listPayslips(
      period.tenantId,
      periodId: period.id,
    );
    for (final HrPayslip payslip in payslips) {
      if (payslip.status != PayrollStatus.paid) {
        await _repository.updatePayslip(
          payslip.id,
          hrPayslipPaidChanges(paidOn: period.payDate),
        );
      }
    }
    await _repository.updatePayrollPeriod(period.id, hrPayrollPaidChanges());
  }
}

/// Reads HR records. Gated on the read permission rather than manage.
final class ReadHrUseCase {
  /// Creates the use case.
  ReadHrUseCase({required this._repository});

  final HrRepository _repository;

  Future<List<HrEmployee>> employees({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? departmentId,
    EmploymentStatus? status,
  }) async {
    policy.require(NodexPermissions.hrRead);
    return _repository.listEmployees(
      tenantId,
      departmentId: departmentId,
      status: status,
    );
  }

  Future<List<HrLeaveRequest>> leaveRequests({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? employeeId,
    LeaveStatus? status,
  }) async {
    policy.require(NodexPermissions.hrRead);
    return _repository.listLeaveRequests(
      tenantId,
      employeeId: employeeId,
      status: status,
    );
  }

  Future<List<HrHoliday>> holidays({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? fromDate,
  }) async {
    policy.require(NodexPermissions.hrRead);
    return _repository.listHolidays(tenantId, fromDate: fromDate);
  }
}

/// Reads payroll. Gated on the payroll read permission instead of HR read.
final class ReadPayrollUseCase {
  /// Creates the use case.
  ReadPayrollUseCase({required this._repository});

  final HrRepository _repository;

  Future<List<HrPayrollPeriod>> periods({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? facilityId,
    PayrollStatus? status,
  }) async {
    policy.require(NodexPermissions.payrollRead);
    return _repository.listPayrollPeriods(
      tenantId,
      facilityId: facilityId,
      status: status,
    );
  }

  Future<List<HrPayslip>> payslips({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? periodId,
    String? employeeId,
  }) async {
    policy.require(NodexPermissions.payrollRead);
    return _repository.listPayslips(
      tenantId,
      periodId: periodId,
      employeeId: employeeId,
    );
  }
}
