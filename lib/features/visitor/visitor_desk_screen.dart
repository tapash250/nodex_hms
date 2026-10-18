/// Visitor & Pass Security Management (Module 37).
///
/// Three tabs: the gate, the passes and the ward visiting hours. The gate tab is
/// who is inside and who has been taken but not admitted; the pass tab is the
/// badges in circulation and the ones whose window has already closed; the hours
/// tab is the rule each ward admits visitors under.
///
/// A pass carries no stored expiry: whether it still admits anyone is derived from
/// the clock against its validity window, so a badge cannot sit on a device
/// claiming to be valid after its own window closed. The badge print log is read
/// where it matters, in the pass sheet, because a reprint is a fact about a
/// physical token rather than a correction to the pass.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/visitor/visitor.dart';
import 'package:nodex_hms/domain/visitor/visitor_use_cases.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The visitor and pass security desk.
class VisitorDeskScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const VisitorDeskScreen({super.key});

  @override
  ConsumerState<VisitorDeskScreen> createState() => _VisitorDeskScreenState();
}

class _VisitorDeskScreenState extends ConsumerState<VisitorDeskScreen> {
  VisitorDeskBoard? _board;
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
      final VisitorDeskBoard board = await ref
          .read(readVisitorDeskUseCaseProvider)
          .board(tenantId: tenantId, policy: session.authorization);
      if (!mounted) return;
      setState(() {
        _board = board;
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

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      _snack(error.toString());
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// The tenant, acting user and facility the screen is working under.
  ({String tenantId, String userId, String facilityId})? get _actingScope {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    if (tenantId == null || userId == null || facilities.isEmpty) {
      return null;
    }
    return (tenantId: tenantId, userId: userId, facilityId: facilities.first);
  }

  Future<void> _registerVisitor() async {
    final scope = _actingScope;
    if (scope == null) return;
    final _VisitorFormResult? result = await showDialog<_VisitorFormResult>(
      context: context,
      builder: (BuildContext context) => const _VisitorFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(registerVisitorUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            tenantId: scope.tenantId,
            facilityId: scope.facilityId,
            registrationNumber: result.registrationNumber,
            fullName: result.fullName,
            registeredBy: scope.userId,
            createdBy: scope.userId,
            purpose: result.purpose,
            phone: result.phone,
            sex: result.sex,
            ageYears: result.ageYears,
            idDocumentType: result.idDocumentType,
            idDocumentNumber: result.idDocumentNumber,
            relationship: result.relationship,
            patientId: result.patientId,
            wardId: result.wardId,
          );
    });
  }

  Future<void> _admit(VisitorRegistration registration) async {
    await _run(() async {
      await ref
          .read(admitVisitorUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            registration: registration,
          );
    });
  }

  Future<void> _depart(VisitorRegistration registration) async {
    await _run(() async {
      await ref
          .read(recordVisitorDepartureUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            registration: registration,
          );
    });
  }

  Future<void> _refuse(VisitorRegistration registration) async {
    final String? reason = await _askValue(
      title: 'Turn the visitor away',
      label: 'Why',
      confirm: 'Refuse entry',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(refuseVisitorUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            registration: registration,
            reason: reason,
          );
    });
  }

  Future<void> _voidRegistration(VisitorRegistration registration) async {
    final String? reason = await _askValue(
      title: 'Withdraw the registration',
      label: 'Reason',
      confirm: 'Withdraw',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(voidVisitorRegistrationUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            registration: registration,
            reason: reason,
          );
    });
  }

  Future<void> _issuePass(VisitorRegistration registration) async {
    final scope = _actingScope;
    if (scope == null) return;
    final _PassFormResult? result = await showDialog<_PassFormResult>(
      context: context,
      builder: (BuildContext context) =>
          _PassFormDialog(suggestedBadge: registration.registrationNumber),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(issueVisitorPassUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            registration: registration,
            badgeNumber: result.badgeNumber,
            issuedBy: scope.userId,
            createdBy: scope.userId,
            validUntil: DateTime.now().toUtc().add(
              Duration(hours: result.validHours),
            ),
            accessScope: result.accessScope,
            escortCount: result.escortCount,
          );
    });
  }

  Future<void> _activatePass(VisitorPass pass) async {
    await _run(() async {
      await ref
          .read(activateVisitorPassUseCaseProvider)
          .call(policy: ref.read(sessionProvider).authorization, pass: pass);
    });
  }

  Future<void> _returnPass(VisitorPass pass) async {
    await _run(() async {
      await ref
          .read(returnVisitorPassUseCaseProvider)
          .call(policy: ref.read(sessionProvider).authorization, pass: pass);
    });
  }

  Future<void> _revokePass(VisitorPass pass) async {
    final String? reason = await _askValue(
      title: 'Revoke the pass',
      label: 'Why',
      confirm: 'Revoke',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(revokeVisitorPassUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            pass: pass,
            reason: reason,
          );
    });
  }

  Future<void> _printBadge(VisitorPass pass) async {
    final scope = _actingScope;
    if (scope == null) return;
    final _PrintFormResult? result = await showDialog<_PrintFormResult>(
      context: context,
      builder: (BuildContext context) => const _PrintFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(recordBadgePrintUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            pass: pass,
            printerLabel: result.printerLabel,
            printedBy: scope.userId,
            note: result.note,
          );
    });
  }

  Future<void> _setWindow() async {
    final scope = _actingScope;
    if (scope == null) return;
    final _WindowFormResult? result = await showDialog<_WindowFormResult>(
      context: context,
      builder: (BuildContext context) => const _WindowFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(setVisitingWindowUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            tenantId: scope.tenantId,
            facilityId: scope.facilityId,
            wardId: result.wardId,
            dayOfWeek: result.dayOfWeek,
            startsMinute: result.startsMinute,
            endsMinute: result.endsMinute,
            createdBy: scope.userId,
            maxVisitors: result.maxVisitors,
            allowsChildren: result.allowsChildren,
          );
    });
  }

  Future<void> _archiveWindow(WardVisitingWindow window) async {
    await _run(() async {
      await ref
          .read(archiveVisitingWindowUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            window: window,
          );
    });
  }

  Future<String?> _askValue({
    required String title,
    required String label,
    required String confirm,
  }) async {
    final TextEditingController controller = TextEditingController();
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(labelText: label),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    final String value = controller.text.trim();
    controller.dispose();
    if (accepted != true || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> _showPass(VisitorPass pass) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    List<VisitorBadgePrint> prints = const <VisitorBadgePrint>[];
    if (tenantId != null) {
      try {
        prints = await ref
            .read(readVisitorDeskUseCaseProvider)
            .badgePrints(
              policy: session.authorization,
              tenantId: tenantId,
              passId: pass.id,
            );
      } on Object catch (error) {
        if (!mounted) return;
        _snack(error.toString());
        return;
      }
    }
    final VisitorDeskBoard? board = _board;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text('${pass.badgeNumber} · ${pass.accessScope.label}'),
              subtitle: Text(
                <String>[
                  pass.status.label,
                  'Valid until ${_formatMoment(pass.validUntil)}',
                  if (board != null &&
                      isVisitorPassExpired(pass: pass, now: board.asOf))
                    'The window has closed',
                  if (pass.escortCount > 0)
                    'Admits ${pass.escortCount + 1} people',
                  if (pass.revokeReason case final String why) 'Revoked: $why',
                ].join('\n'),
              ),
            ),
            if (pass.status == VisitorPassStatus.issued)
              ListTile(
                leading: const Icon(Icons.login_outlined),
                title: const Text('Activate at the gate'),
                onTap: () {
                  Navigator.of(context).pop();
                  _activatePass(pass);
                },
              ),
            if (pass.status == VisitorPassStatus.active)
              ListTile(
                leading: const Icon(Icons.logout_outlined),
                title: const Text('Take the badge back'),
                onTap: () {
                  Navigator.of(context).pop();
                  _returnPass(pass);
                },
              ),
            if (pass.isLive)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('Print the thermal badge'),
                onTap: () {
                  Navigator.of(context).pop();
                  _printBadge(pass);
                },
              ),
            if (pass.isLive)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Revoke the pass'),
                onTap: () {
                  Navigator.of(context).pop();
                  _revokePass(pass);
                },
              ),
            for (final VisitorBadgePrint print in prints)
              ListTile(
                dense: true,
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(
                  print.isReprint
                      ? 'Reprint ${print.printOrdinal} at ${print.printerLabel}'
                      : 'Printed at ${print.printerLabel}',
                ),
                subtitle: Text(
                  <String>[
                    _formatMoment(print.printedAt),
                    if (print.note case final String note) note,
                  ].join(' · '),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRegistration(VisitorRegistration registration) async {
    final VisitorDeskBoard? board = _board;
    final List<VisitorPass> passes =
        board?.livePassesFor(registration.id) ?? const <VisitorPass>[];
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.how_to_reg_outlined),
              title: Text(
                '${registration.registrationNumber} · ${registration.fullName}',
              ),
              subtitle: Text(
                <String>[
                  '${registration.purpose.label} · ${registration.status.label}',
                  'Registered ${_formatMoment(registration.registeredAt)}',
                  if (registration.phone case final String phone) phone,
                  if (registration.idDocumentType case final VisitorIdType type)
                    '${type.label} ${registration.idDocumentNumber}',
                  if (registration.relationship case final String relation)
                    'Relationship: $relation',
                  if (registration.wardId case final String ward) 'Ward $ward',
                  if (registration.patientId case final String patient)
                    'Patient $patient',
                  if (registration.checkedInAt case final DateTime at)
                    'Came in ${_formatMoment(at)}',
                  if (registration.checkedOutAt case final DateTime at)
                    'Left ${_formatMoment(at)}',
                  if (registration.refuseReason case final String why)
                    'Refused: $why',
                  if (registration.voidReason case final String why)
                    'Withdrawn: $why',
                ].join('\n'),
              ),
            ),
            if (registration.status == VisitorRegistrationStatus.registered)
              ListTile(
                leading: const Icon(Icons.login_outlined),
                title: const Text('Admit the visitor'),
                onTap: () {
                  Navigator.of(context).pop();
                  _admit(registration);
                },
              ),
            if (registration.isOnSite)
              ListTile(
                leading: const Icon(Icons.logout_outlined),
                title: const Text('Record the departure'),
                onTap: () {
                  Navigator.of(context).pop();
                  _depart(registration);
                },
              ),
            if (registration.isLive)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Issue an entry pass'),
                onTap: () {
                  Navigator.of(context).pop();
                  _issuePass(registration);
                },
              ),
            if (registration.status == VisitorRegistrationStatus.registered)
              ListTile(
                leading: const Icon(Icons.do_not_disturb_on_outlined),
                title: const Text('Refuse entry'),
                onTap: () {
                  Navigator.of(context).pop();
                  _refuse(registration);
                },
              ),
            if (registration.status == VisitorRegistrationStatus.registered)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Withdraw the registration'),
                onTap: () {
                  Navigator.of(context).pop();
                  _voidRegistration(registration);
                },
              ),
            for (final VisitorPass pass in passes)
              ListTile(
                dense: true,
                leading: const Icon(Icons.badge_outlined),
                title: Text('${pass.badgeNumber} · ${pass.status.label}'),
                subtitle: Text('Valid until ${_formatMoment(pass.validUntil)}'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showPass(pass);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final VisitorDeskBoard? board = _board;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || board == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Visitors')),
        body: Center(child: Text(_error ?? 'The visitor desk is unavailable.')),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Visitor & pass security'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Gate'),
              Tab(text: 'Passes'),
              Tab(text: 'Visiting hours'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _gateTab(board),
            _passTab(board),
            _windowTab(board),
          ],
        ),
      ),
    );
  }

  Widget _gateTab(VisitorDeskBoard board) {
    final List<VisitorRegistration> onSite = board.onSiteVisitors;
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.how_to_reg_outlined),
              title: Text('${onSite.length} visitors inside'),
              subtitle: Text(
                '${board.registrationsWithoutLivePass.length} taken without a '
                'pass · ${board.expiredLivePasses.length} passes out of time',
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: board.registrations.isEmpty
                  ? const Center(child: Text('No visitors on this device.'))
                  : ListView.builder(
                      itemCount: board.registrations.length,
                      itemBuilder: (BuildContext context, int index) {
                        final VisitorRegistration registration =
                            board.registrations[index];
                        final bool needsPass =
                            registration.isLive &&
                            board.livePassesFor(registration.id).isEmpty;
                        return ListTile(
                          leading: Icon(
                            registration.isOnSite
                                ? Icons.person_outline
                                : Icons.person_add_alt_outlined,
                            color: needsPass
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                          title: Text(registration.fullName),
                          subtitle: Text(
                            <String>[
                              registration.registrationNumber,
                              registration.purpose.label,
                              registration.status.label,
                              if (needsPass) 'No pass issued',
                            ].join(' · '),
                          ),
                          onTap: () => _showRegistration(registration),
                        );
                      },
                    ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _registerVisitor,
            icon: const Icon(Icons.add),
            label: const Text('Register visitor'),
          ),
        ),
      ],
    );
  }

  Widget _passTab(VisitorDeskBoard board) {
    return Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: Text('${board.passes.length} passes on this device'),
          subtitle: Text(
            '${board.passesAwaitingActivation.length} awaiting activation · '
            '${board.expiredLivePasses.length} out of time',
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: board.passes.isEmpty
              ? const Center(child: Text('No passes on this device.'))
              : ListView.builder(
                  itemCount: board.passes.length,
                  itemBuilder: (BuildContext context, int index) {
                    final VisitorPass pass = board.passes[index];
                    final bool expired = isVisitorPassExpired(
                      pass: pass,
                      now: board.asOf,
                    );
                    return ListTile(
                      leading: Icon(
                        pass.isLive ? Icons.badge_outlined : Icons.badge,
                        color: expired && pass.isLive
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      title: Text(pass.badgeNumber),
                      subtitle: Text(
                        <String>[
                          pass.accessScope.label,
                          pass.status.label,
                          'until ${_formatMoment(pass.validUntil)}',
                          if (expired && pass.isLive) 'Window closed',
                        ].join(' · '),
                      ),
                      onTap: () => _showPass(pass),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _windowTab(VisitorDeskBoard board) {
    final List<WardVisitingWindow> windows = board.windows;
    return Stack(
      children: <Widget>[
        windows.isEmpty
            ? const Center(child: Text('No visiting hours set on this device.'))
            : ListView.builder(
                itemCount: windows.length,
                itemBuilder: (BuildContext context, int index) {
                  final WardVisitingWindow window = windows[index];
                  return ListTile(
                    leading: Icon(
                      window.isActive
                          ? Icons.schedule_outlined
                          : Icons.schedule,
                    ),
                    title: Text(
                      '${window.wardId} · ${_dayLabel(window.dayOfWeek)}',
                    ),
                    subtitle: Text(
                      '${_minuteLabel(window.startsMinute)} to '
                      '${_minuteLabel(window.endsMinute)} · '
                      '${window.maxVisitors} visitors'
                      '${window.allowsChildren ? ' · children allowed' : ''}',
                    ),
                    trailing: Text(window.status.label),
                    onTap: window.isActive
                        ? () => _confirmArchive(window)
                        : null,
                  );
                },
              ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _setWindow,
            icon: const Icon(Icons.add),
            label: const Text('Set visiting hours'),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmArchive(WardVisitingWindow window) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Retire the visiting window'),
        content: const Text(
          'The window stops admitting visitors and becomes immutable. It is kept '
          'so a past pass still resolves to the rule it was issued under.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retire'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _archiveWindow(window);
  }
}

class _VisitorFormResult {
  const _VisitorFormResult({
    required this.registrationNumber,
    required this.fullName,
    required this.purpose,
    this.phone,
    this.sex,
    this.ageYears,
    this.idDocumentType,
    this.idDocumentNumber,
    this.relationship,
    this.patientId,
    this.wardId,
  });

  final String registrationNumber;
  final String fullName;
  final VisitorPurpose purpose;
  final String? phone;
  final VisitorSex? sex;
  final int? ageYears;
  final VisitorIdType? idDocumentType;
  final String? idDocumentNumber;
  final String? relationship;
  final String? patientId;
  final String? wardId;
}

class _VisitorFormDialog extends StatefulWidget {
  const _VisitorFormDialog();

  @override
  State<_VisitorFormDialog> createState() => _VisitorFormDialogState();
}

class _VisitorFormDialogState extends State<_VisitorFormDialog> {
  final TextEditingController _number = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _age = TextEditingController();
  final TextEditingController _documentNumber = TextEditingController();
  final TextEditingController _relationship = TextEditingController();
  final TextEditingController _patient = TextEditingController();
  final TextEditingController _ward = TextEditingController();
  VisitorPurpose _purpose = VisitorPurpose.patientVisit;
  VisitorSex? _sex;
  VisitorIdType? _document;

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _phone.dispose();
    _age.dispose();
    _documentNumber.dispose();
    _relationship.dispose();
    _patient.dispose();
    _ward.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Register visitor'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _number,
            decoration: const InputDecoration(labelText: 'Registration number'),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          DropdownButtonFormField<VisitorPurpose>(
            initialValue: _purpose,
            decoration: const InputDecoration(labelText: 'Purpose'),
            items: <DropdownMenuItem<VisitorPurpose>>[
              for (final VisitorPurpose value in VisitorPurpose.values)
                DropdownMenuItem<VisitorPurpose>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (VisitorPurpose? value) {
              if (value != null) setState(() => _purpose = value);
            },
          ),
          DropdownButtonFormField<VisitorSex?>(
            initialValue: _sex,
            decoration: const InputDecoration(labelText: 'Sex (optional)'),
            items: <DropdownMenuItem<VisitorSex?>>[
              const DropdownMenuItem<VisitorSex?>(child: Text('Not stated')),
              for (final VisitorSex value in VisitorSex.values)
                DropdownMenuItem<VisitorSex?>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (VisitorSex? value) => setState(() => _sex = value),
          ),
          TextField(
            controller: _age,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Age in years (optional)',
            ),
          ),
          DropdownButtonFormField<VisitorIdType?>(
            initialValue: _document,
            decoration: const InputDecoration(
              labelText: 'Document shown (optional)',
            ),
            items: <DropdownMenuItem<VisitorIdType?>>[
              const DropdownMenuItem<VisitorIdType?>(
                child: Text('No document recorded'),
              ),
              for (final VisitorIdType value in VisitorIdType.values)
                DropdownMenuItem<VisitorIdType?>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (VisitorIdType? value) =>
                setState(() => _document = value),
          ),
          TextField(
            controller: _documentNumber,
            decoration: const InputDecoration(
              labelText: 'Document number (optional)',
            ),
          ),
          TextField(
            controller: _relationship,
            decoration: const InputDecoration(
              labelText: 'Relationship to the patient (optional)',
            ),
          ),
          TextField(
            controller: _ward,
            decoration: const InputDecoration(labelText: 'Ward id (optional)'),
          ),
          TextField(
            controller: _patient,
            decoration: const InputDecoration(
              labelText: 'Patient id (optional)',
            ),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _VisitorFormResult(
            registrationNumber: _number.text.trim(),
            fullName: _name.text.trim(),
            purpose: _purpose,
            phone: _nullIfEmpty(_phone),
            sex: _sex,
            ageYears: int.tryParse(_age.text.trim()),
            idDocumentType: _document,
            idDocumentNumber: _document == null
                ? null
                : _nullIfEmpty(_documentNumber),
            relationship: _nullIfEmpty(_relationship),
            patientId: _nullIfEmpty(_patient),
            wardId: _nullIfEmpty(_ward),
          ),
        ),
        child: const Text('Register'),
      ),
    ],
  );

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }
}

class _PassFormResult {
  const _PassFormResult({
    required this.badgeNumber,
    required this.accessScope,
    required this.escortCount,
    required this.validHours,
  });

  final String badgeNumber;
  final VisitorAccessScope accessScope;
  final int escortCount;
  final int validHours;
}

class _PassFormDialog extends StatefulWidget {
  const _PassFormDialog({required this.suggestedBadge});

  /// The badge number the pass number is prefilled from.
  final String suggestedBadge;

  @override
  State<_PassFormDialog> createState() => _PassFormDialogState();
}

class _PassFormDialogState extends State<_PassFormDialog> {
  late final TextEditingController _badge = TextEditingController(
    text: widget.suggestedBadge,
  );
  final TextEditingController _escorts = TextEditingController(text: '0');
  VisitorAccessScope _scope = VisitorAccessScope.ward;
  int _hours = 8;

  @override
  void dispose() {
    _badge.dispose();
    _escorts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Issue an entry pass'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _badge,
            decoration: const InputDecoration(labelText: 'Badge number'),
          ),
          DropdownButtonFormField<VisitorAccessScope>(
            initialValue: _scope,
            decoration: const InputDecoration(labelText: 'Where it admits'),
            items: <DropdownMenuItem<VisitorAccessScope>>[
              for (final VisitorAccessScope value in VisitorAccessScope.values)
                DropdownMenuItem<VisitorAccessScope>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (VisitorAccessScope? value) {
              if (value != null) setState(() => _scope = value);
            },
          ),
          TextField(
            controller: _escorts,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Escorts on the pass'),
          ),
          DropdownButtonFormField<int>(
            initialValue: _hours,
            decoration: const InputDecoration(labelText: 'Valid for'),
            items: <DropdownMenuItem<int>>[
              for (final int hours in const <int>[2, 4, 8, 12, 24])
                DropdownMenuItem<int>(
                  value: hours,
                  child: Text('$hours hours'),
                ),
            ],
            onChanged: (int? value) {
              if (value != null) setState(() => _hours = value);
            },
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _PassFormResult(
            badgeNumber: _badge.text.trim(),
            accessScope: _scope,
            escortCount: int.tryParse(_escorts.text.trim()) ?? 0,
            validHours: _hours,
          ),
        ),
        child: const Text('Issue'),
      ),
    ],
  );
}

class _PrintFormResult {
  const _PrintFormResult({required this.printerLabel, this.note});

  final String printerLabel;
  final String? note;
}

class _PrintFormDialog extends StatefulWidget {
  const _PrintFormDialog();

  @override
  State<_PrintFormDialog> createState() => _PrintFormDialogState();
}

class _PrintFormDialogState extends State<_PrintFormDialog> {
  final TextEditingController _printer = TextEditingController(
    text: 'Gate desk printer',
  );
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _printer.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Print the thermal badge'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _printer,
            decoration: const InputDecoration(labelText: 'Printer'),
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Why it was printed (optional)',
            ),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _PrintFormResult(
            printerLabel: _printer.text.trim(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          ),
        ),
        child: const Text('Print'),
      ),
    ],
  );
}

class _WindowFormResult {
  const _WindowFormResult({
    required this.wardId,
    required this.dayOfWeek,
    required this.startsMinute,
    required this.endsMinute,
    required this.maxVisitors,
    required this.allowsChildren,
  });

  final String wardId;
  final int dayOfWeek;
  final int startsMinute;
  final int endsMinute;
  final int maxVisitors;
  final bool allowsChildren;
}

class _WindowFormDialog extends StatefulWidget {
  const _WindowFormDialog();

  @override
  State<_WindowFormDialog> createState() => _WindowFormDialogState();
}

class _WindowFormDialogState extends State<_WindowFormDialog> {
  final TextEditingController _ward = TextEditingController();
  final TextEditingController _limit = TextEditingController(text: '2');
  int _day = DateTime.now().weekday % 7;
  TimeOfDay _opens = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _closes = const TimeOfDay(hour: 12, minute: 0);
  bool _children = false;

  @override
  void dispose() {
    _ward.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool opening}) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: opening ? _opens : _closes,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (opening) {
        _opens = picked;
      } else {
        _closes = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set visiting hours'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _ward,
            decoration: const InputDecoration(labelText: 'Ward id'),
          ),
          DropdownButtonFormField<int>(
            initialValue: _day,
            decoration: const InputDecoration(labelText: 'Day'),
            items: <DropdownMenuItem<int>>[
              for (int day = 0; day <= 6; day++)
                DropdownMenuItem<int>(value: day, child: Text(_dayLabel(day))),
            ],
            onChanged: (int? value) {
              if (value != null) setState(() => _day = value);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Opens ${_opens.hour.toString().padLeft(2, '0')}:'
              '${_opens.minute.toString().padLeft(2, '0')}',
            ),
            trailing: TextButton(
              onPressed: () => _pick(opening: true),
              child: const Text('Change'),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Closes ${_closes.hour.toString().padLeft(2, '0')}:'
              '${_closes.minute.toString().padLeft(2, '0')}',
            ),
            trailing: TextButton(
              onPressed: () => _pick(opening: false),
              child: const Text('Change'),
            ),
          ),
          TextField(
            controller: _limit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Visitors admitted at once',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _children,
            title: const Text('Children may visit'),
            onChanged: (bool value) => setState(() => _children = value),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _WindowFormResult(
            wardId: _ward.text.trim(),
            dayOfWeek: _day,
            startsMinute: _opens.hour * 60 + _opens.minute,
            endsMinute: _closes.hour * 60 + _closes.minute,
            maxVisitors: int.tryParse(_limit.text.trim()) ?? 2,
            allowsChildren: _children,
          ),
        ),
        child: const Text('Set'),
      ),
    ],
  );
}

String _dayLabel(int dayOfWeek) => switch (dayOfWeek) {
  0 => 'Sunday',
  1 => 'Monday',
  2 => 'Tuesday',
  3 => 'Wednesday',
  4 => 'Thursday',
  5 => 'Friday',
  6 => 'Saturday',
  _ => 'Day $dayOfWeek',
};

String _minuteLabel(int minuteOfDay) {
  final int hour = minuteOfDay ~/ 60;
  final int minute = minuteOfDay % 60;
  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

String _formatMoment(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')} '
      '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')}';
}
