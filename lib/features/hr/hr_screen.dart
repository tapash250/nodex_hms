/// Human resources & payroll suite (Module 13).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/hr/hr.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// HR surface: employee records, leave, holidays and payroll runs.
class HrScreen extends ConsumerStatefulWidget {
  /// Creates the HR screen.
  const HrScreen({super.key});

  @override
  ConsumerState<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends ConsumerState<HrScreen> {
  List<HrEmployee> _employees = const <HrEmployee>[];
  List<HrLeaveRequest> _leave = const <HrLeaveRequest>[];
  List<HrHoliday> _holidays = const <HrHoliday>[];
  List<HrPayrollPeriod> _periods = const <HrPayrollPeriod>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) {
      setState(() {
        _error = 'Session is not ready.';
        _loading = false;
      });
      return;
    }
    try {
      final readHr = ref.read(readHrUseCaseProvider);
      final readPayroll = ref.read(readPayrollUseCaseProvider);
      final List<HrEmployee> employees = await readHr.employees(
        policy: session.authorization,
        tenantId: tenantId,
      );
      // Payroll read is a distinct permission; a role may hold only HR read.
      final bool canReadPayroll = session.authorization.canAny(<String>{
        'payroll.read',
      });
      final List<HrLeaveRequest> leave = await readHr.leaveRequests(
        policy: session.authorization,
        tenantId: tenantId,
      );
      final List<HrHoliday> holidays = await readHr.holidays(
        policy: session.authorization,
        tenantId: tenantId,
      );
      final List<HrPayrollPeriod> periods = canReadPayroll
          ? await readPayroll.periods(
              policy: session.authorization,
              tenantId: tenantId,
            )
          : const <HrPayrollPeriod>[];
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _leave = leave;
        _holidays = holidays;
        _periods = periods;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('HR & payroll')),
        body: Center(child: Text(_error!)),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('HR & payroll'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Employees'),
              Tab(text: 'Leave'),
              Tab(text: 'Holidays'),
              Tab(text: 'Payroll'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _employeesTab(),
            _leaveTab(),
            _holidaysTab(),
            _payrollTab(),
          ],
        ),
      ),
    );
  }

  Widget _employeesTab() => _employees.isEmpty
      ? const Center(child: Text('No employee records yet.'))
      : ListView.builder(
          itemCount: _employees.length,
          itemBuilder: (BuildContext context, int index) {
            final HrEmployee employee = _employees[index];
            return ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(employee.employeeCode),
              subtitle: Text(
                '${employee.designation ?? 'Unassigned'} · '
                '${employee.employmentType.label} · '
                '${employee.employmentStatus.label}',
              ),
              trailing: Text(employee.joinedOn),
            );
          },
        );

  Widget _leaveTab() => _leave.isEmpty
      ? const Center(child: Text('No leave applications.'))
      : ListView.builder(
          itemCount: _leave.length,
          itemBuilder: (BuildContext context, int index) {
            final HrLeaveRequest request = _leave[index];
            return ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: Text('${request.leaveType.label} leave'),
              subtitle: Text('${request.startsOn} to ${request.endsOn}'),
              trailing: Text(request.status.label),
              onTap: request.isPending ? () => _decide(request) : null,
            );
          },
        );

  Widget _holidaysTab() => Scaffold(
    body: _holidays.isEmpty
        ? const Center(child: Text('No holidays recorded.'))
        : ListView.builder(
            itemCount: _holidays.length,
            itemBuilder: (BuildContext context, int index) {
              final HrHoliday holiday = _holidays[index];
              return ListTile(
                leading: const Icon(Icons.beach_access_outlined),
                title: Text(holiday.displayName),
                subtitle: Text(
                  '${holiday.holidayType.label} · '
                  '${holiday.isTenantWide ? 'Tenant-wide' : 'Facility'}',
                ),
                trailing: Text(holiday.holidayDate),
              );
            },
          ),
    floatingActionButton: FloatingActionButton(
      onPressed: _addHoliday,
      tooltip: 'Add holiday',
      child: const Icon(Icons.add),
    ),
  );

  Widget _payrollTab() => Scaffold(
    body: _periods.isEmpty
        ? const Center(child: Text('No payroll runs yet.'))
        : ListView.builder(
            itemCount: _periods.length,
            itemBuilder: (BuildContext context, int index) {
              final HrPayrollPeriod period = _periods[index];
              return ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text('${period.periodStart} to ${period.periodEnd}'),
                subtitle: Text(
                  '${period.currency} · pay ${period.payDate} · '
                  '${period.status.label}',
                ),
                trailing: period.status == PayrollStatus.draft
                    ? TextButton(
                        onPressed: () => _finalize(period),
                        child: const Text('Finalize'),
                      )
                    : null,
              );
            },
          ),
    floatingActionButton: FloatingActionButton(
      onPressed: _openPeriod,
      tooltip: 'Open payroll run',
      child: const Icon(Icons.add),
    ),
  );

  Future<void> _decide(HrLeaveRequest request) async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;
    final LeaveStatus? decision = await showDialog<LeaveStatus>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('${request.leaveType.label} leave'),
        content: Text('${request.startsOn} to ${request.endsOn}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(LeaveStatus.rejected),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(LeaveStatus.approved),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (decision == null) return;
    try {
      await ref
          .read(decideLeaveUseCaseProvider)
          .call(
            policy: session.authorization,
            request: request,
            decision: decision,
            decidedBy: userId,
          );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _addHoliday() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) return;
    final ({String date, String name, HolidayType type})? entry =
        await showDialog<({String date, String name, HolidayType type})>(
          context: context,
          builder: (BuildContext context) => const _HolidayDialog(),
        );
    if (entry == null) return;
    try {
      await ref
          .read(setHolidayUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            holidayDate: entry.date,
            displayName: entry.name,
            holidayType: entry.type,
          );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openPeriod() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    if (tenantId == null || facilities.isEmpty) return;
    final ({String start, String end, String payDate})? entry =
        await showDialog<({String start, String end, String payDate})>(
          context: context,
          builder: (BuildContext context) => const _PayrollDialog(),
        );
    if (entry == null) return;
    try {
      await ref
          .read(openPayrollPeriodUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            facilityId: facilities.first,
            periodStart: entry.start,
            periodEnd: entry.end,
            payDate: entry.payDate,
          );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _finalize(HrPayrollPeriod period) async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(finalizePayrollPeriodUseCaseProvider)
          .call(
            policy: session.authorization,
            period: period,
            finalizedBy: userId,
          );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _HolidayDialog extends StatefulWidget {
  const _HolidayDialog();

  @override
  State<_HolidayDialog> createState() => _HolidayDialogState();
}

class _HolidayDialogState extends State<_HolidayDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _date = TextEditingController(
    text: DateTime.now().toUtc().toIso8601String().substring(0, 10),
  );
  HolidayType _type = HolidayType.public;

  @override
  void dispose() {
    _name.dispose();
    _date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add holiday'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Holiday name'),
        ),
        TextField(
          controller: _date,
          decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
        ),
        DropdownButtonFormField<HolidayType>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: <DropdownMenuItem<HolidayType>>[
            for (final HolidayType type in HolidayType.values)
              DropdownMenuItem<HolidayType>(
                value: type,
                child: Text(type.label),
              ),
          ],
          onChanged: (HolidayType? value) {
            if (value != null) {
              setState(() => _type = value);
            }
          },
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(
          context,
        ).pop((date: _date.text.trim(), name: _name.text.trim(), type: _type)),
        child: const Text('Add'),
      ),
    ],
  );
}

class _PayrollDialog extends StatefulWidget {
  const _PayrollDialog();

  @override
  State<_PayrollDialog> createState() => _PayrollDialogState();
}

class _PayrollDialogState extends State<_PayrollDialog> {
  final TextEditingController _start = TextEditingController();
  final TextEditingController _end = TextEditingController();
  final TextEditingController _payDate = TextEditingController();

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _payDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Open payroll run'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _start,
          decoration: const InputDecoration(labelText: 'Period start'),
        ),
        TextField(
          controller: _end,
          decoration: const InputDecoration(labelText: 'Period end'),
        ),
        TextField(
          controller: _payDate,
          decoration: const InputDecoration(labelText: 'Pay date'),
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop((
          start: _start.text.trim(),
          end: _end.text.trim(),
          payDate: _payDate.text.trim(),
        )),
        child: const Text('Open'),
      ),
    ],
  );
}
