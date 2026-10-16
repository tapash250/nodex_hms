/// Human resources & payroll repository contract and local implementation
/// (Module 13).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/hr/hr.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class HrRepository {
  Future<List<HrEmployee>> listEmployees(
    String tenantId, {
    String? departmentId,
    EmploymentStatus? status,
    int limit = 200,
  });
  Future<HrEmployee?> employeeById(String id);
  Future<HrEmployee?> employeeForUser(String tenantId, String userId);
  Future<String> registerEmployee(Map<String, Object?> row);
  Future<void> updateEmployee(String id, Map<String, Object?> changes);

  Future<List<HrLeaveRequest>> listLeaveRequests(
    String tenantId, {
    String? employeeId,
    LeaveStatus? status,
    int limit = 200,
  });
  Future<HrLeaveRequest?> leaveRequestById(String id);
  Future<String> registerLeaveRequest(Map<String, Object?> row);
  Future<void> updateLeaveRequest(String id, Map<String, Object?> changes);

  Future<List<HrHoliday>> listHolidays(
    String tenantId, {
    String? fromDate,
    int limit = 200,
  });
  Future<String> registerHoliday(Map<String, Object?> row);
  Future<void> updateHoliday(String id, Map<String, Object?> changes);

  Future<List<HrPayrollPeriod>> listPayrollPeriods(
    String tenantId, {
    String? facilityId,
    PayrollStatus? status,
    int limit = 100,
  });
  Future<HrPayrollPeriod?> payrollPeriodById(String id);
  Future<String> registerPayrollPeriod(Map<String, Object?> row);
  Future<void> updatePayrollPeriod(String id, Map<String, Object?> changes);

  Future<List<HrPayslip>> listPayslips(
    String tenantId, {
    String? periodId,
    String? employeeId,
    int limit = 500,
  });
  Future<HrPayslip?> payslipById(String id);
  Future<String> registerPayslip(Map<String, Object?> row);
  Future<void> updatePayslip(String id, Map<String, Object?> changes);
}

final class DefaultHrRepository implements HrRepository {
  DefaultHrRepository({required this._store, required this._logger});

  static const String _module = 'domain.hr';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<HrEmployee>> listEmployees(
    String tenantId, {
    String? departmentId,
    EmploymentStatus? status,
    int limit = 200,
  }) => _list<HrEmployee>(
    table: LocalTables.hrEmployees,
    tenantId: tenantId,
    filters: <String, Object?>{
      'department_id': departmentId,
      'employment_status': status?.wireValue,
    },
    orderBy: 'employee_code',
    limit: limit,
    map: HrEmployee.fromRow,
    operation: 'hr.listEmployees',
  );

  @override
  Future<HrEmployee?> employeeById(String id) => _byId(
    table: LocalTables.hrEmployees,
    id: id,
    map: HrEmployee.fromRow,
    operation: 'hr.employeeById',
  );

  @override
  Future<HrEmployee?> employeeForUser(String tenantId, String userId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.hrEmployees} where tenant_id = ? and user_id = ? limit 1',
        <Object?>[tenantId, userId],
      );
      return rows.isEmpty ? null : HrEmployee.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'hr.employeeForUser');
    }
  }

  @override
  Future<String> registerEmployee(Map<String, Object?> row) =>
      _insert(LocalTables.hrEmployees, row, 'hr.registerEmployee');

  @override
  Future<void> updateEmployee(String id, Map<String, Object?> changes) =>
      _update(LocalTables.hrEmployees, id, changes, 'hr.updateEmployee');

  @override
  Future<List<HrLeaveRequest>> listLeaveRequests(
    String tenantId, {
    String? employeeId,
    LeaveStatus? status,
    int limit = 200,
  }) => _list<HrLeaveRequest>(
    table: LocalTables.hrLeaveRequests,
    tenantId: tenantId,
    filters: <String, Object?>{
      'employee_id': employeeId,
      'status': status?.wireValue,
    },
    orderBy: 'starts_on',
    limit: limit,
    map: HrLeaveRequest.fromRow,
    operation: 'hr.listLeaveRequests',
  );

  @override
  Future<HrLeaveRequest?> leaveRequestById(String id) => _byId(
    table: LocalTables.hrLeaveRequests,
    id: id,
    map: HrLeaveRequest.fromRow,
    operation: 'hr.leaveRequestById',
  );

  @override
  Future<String> registerLeaveRequest(Map<String, Object?> row) =>
      _insert(LocalTables.hrLeaveRequests, row, 'hr.registerLeaveRequest');

  @override
  Future<void> updateLeaveRequest(String id, Map<String, Object?> changes) =>
      _update(
        LocalTables.hrLeaveRequests,
        id,
        changes,
        'hr.updateLeaveRequest',
      );

  @override
  Future<List<HrHoliday>> listHolidays(
    String tenantId, {
    String? fromDate,
    int limit = 200,
  }) async {
    try {
      final StringBuffer sql = StringBuffer(
        'select * from ${LocalTables.hrHolidays} where tenant_id = ?',
      );
      final List<Object?> params = <Object?>[tenantId];
      if (fromDate != null) {
        sql.write(' and holiday_date >= ?');
        params.add(fromDate);
      }
      sql.write(' order by holiday_date limit ?');
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(
        sql.toString(),
        params,
      );
      return rows.map(HrHoliday.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'hr.listHolidays');
    }
  }

  @override
  Future<String> registerHoliday(Map<String, Object?> row) =>
      _insert(LocalTables.hrHolidays, row, 'hr.registerHoliday');

  @override
  Future<void> updateHoliday(String id, Map<String, Object?> changes) =>
      _update(LocalTables.hrHolidays, id, changes, 'hr.updateHoliday');

  @override
  Future<List<HrPayrollPeriod>> listPayrollPeriods(
    String tenantId, {
    String? facilityId,
    PayrollStatus? status,
    int limit = 100,
  }) => _list<HrPayrollPeriod>(
    table: LocalTables.hrPayrollPeriods,
    tenantId: tenantId,
    filters: <String, Object?>{
      'facility_id': facilityId,
      'status': status?.wireValue,
    },
    orderBy: 'period_start',
    limit: limit,
    map: HrPayrollPeriod.fromRow,
    operation: 'hr.listPayrollPeriods',
  );

  @override
  Future<HrPayrollPeriod?> payrollPeriodById(String id) => _byId(
    table: LocalTables.hrPayrollPeriods,
    id: id,
    map: HrPayrollPeriod.fromRow,
    operation: 'hr.payrollPeriodById',
  );

  @override
  Future<String> registerPayrollPeriod(Map<String, Object?> row) =>
      _insert(LocalTables.hrPayrollPeriods, row, 'hr.registerPayrollPeriod');

  @override
  Future<void> updatePayrollPeriod(String id, Map<String, Object?> changes) =>
      _update(
        LocalTables.hrPayrollPeriods,
        id,
        changes,
        'hr.updatePayrollPeriod',
      );

  @override
  Future<List<HrPayslip>> listPayslips(
    String tenantId, {
    String? periodId,
    String? employeeId,
    int limit = 500,
  }) => _list<HrPayslip>(
    table: LocalTables.hrPayslips,
    tenantId: tenantId,
    filters: <String, Object?>{
      'period_id': periodId,
      'employee_id': employeeId,
    },
    orderBy: 'created_at',
    limit: limit,
    map: HrPayslip.fromRow,
    operation: 'hr.listPayslips',
  );

  @override
  Future<HrPayslip?> payslipById(String id) => _byId(
    table: LocalTables.hrPayslips,
    id: id,
    map: HrPayslip.fromRow,
    operation: 'hr.payslipById',
  );

  @override
  Future<String> registerPayslip(Map<String, Object?> row) =>
      _insert(LocalTables.hrPayslips, row, 'hr.registerPayslip');

  @override
  Future<void> updatePayslip(String id, Map<String, Object?> changes) =>
      _update(LocalTables.hrPayslips, id, changes, 'hr.updatePayslip');

  Future<List<T>> _list<T>({
    required String table,
    required String tenantId,
    required Map<String, Object?> filters,
    required String orderBy,
    required int limit,
    required T Function(Map<String, Object?>) map,
    required String operation,
  }) async {
    try {
      final StringBuffer sql = StringBuffer(
        'select * from $table where tenant_id = ?',
      );
      final List<Object?> params = <Object?>[tenantId];
      for (final MapEntry<String, Object?> filter in filters.entries) {
        if (filter.value != null) {
          sql.write(' and ${filter.key} = ?');
          params.add(filter.value);
        }
      }
      sql.write(' order by $orderBy limit ?');
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(
        sql.toString(),
        params,
      );
      return rows.map(map).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, operation);
    }
  }

  Future<T?> _byId<T>({
    required String table,
    required String id,
    required T Function(Map<String, Object?>) map,
    required String operation,
  }) async {
    try {
      final Map<String, Object?>? row = await _store.getById(table, id);
      return row == null ? null : map(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, operation);
    }
  }

  Future<String> _insert(
    String table,
    Map<String, Object?> row,
    String operation,
  ) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(table, <String, Object?>{...row, 'id': id});
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, operation);
    }
  }

  Future<void> _update(
    String table,
    String id,
    Map<String, Object?> changes,
    String operation,
  ) async {
    try {
      await _store.update(table, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, operation);
    }
  }

  NodexError _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) {
      return error;
    }
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Local store operation failed.',
      operation: operation,
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    return mapped;
  }
}
