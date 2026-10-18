/// Statutory Records & Birth/Death Registry (Module 34).
///
/// Three tabs: the birth register, the death register with its cause-of-death
/// coding, and the medico-legal case log. Each register is a guarded state
/// machine, and the screen says so: a draft is entered, a registered entry is
/// frozen, and a certificate is issued against it. Once a fact is registered it
/// is changed by an appended amendment, never by an edit, which is why the
/// amendment sheet is the only edit control on a registered row.
///
/// The derived facts are shown where they matter: a registration past its
/// statutory window and a medico-legal case past its intimation window are
/// marked from the row and the clock, not from a stored flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/statutory/statutory.dart';
import 'package:nodex_hms/domain/statutory/statutory_use_cases.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The statutory registry board.
class StatutoryRegistryScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const StatutoryRegistryScreen({super.key});

  @override
  ConsumerState<StatutoryRegistryScreen> createState() =>
      _StatutoryRegistryScreenState();
}

class _StatutoryRegistryScreenState
    extends ConsumerState<StatutoryRegistryScreen> {
  StatutoryBoard? _board;
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
      final StatutoryBoard board = await ref
          .read(readStatutoryRegistryUseCaseProvider)
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

  Future<void> _raiseBirth() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    final String? facilityId = facilities.isEmpty ? null : facilities.first;
    if (tenantId == null || userId == null || facilityId == null) return;
    final _BirthFormResult? result = await showDialog<_BirthFormResult>(
      context: context,
      builder: (BuildContext context) => const _BirthFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(raiseBirthUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            facilityId: facilityId,
            childName: result.childName,
            sex: result.sex,
            birthAt: result.birthAt,
            placeOfBirth: result.placeOfBirth,
            motherName: result.motherName,
            createdBy: userId,
            deliveryType: result.deliveryType,
            plurality: result.plurality,
            weightGrams: result.weightGrams,
            fatherName: result.fatherName,
            informantName: result.informantName,
          );
    });
  }

  Future<void> _raiseDeath() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    final String? facilityId = facilities.isEmpty ? null : facilities.first;
    if (tenantId == null || userId == null || facilityId == null) return;
    final _DeathFormResult? result = await showDialog<_DeathFormResult>(
      context: context,
      builder: (BuildContext context) => const _DeathFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(raiseDeathUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            facilityId: facilityId,
            deceasedName: result.deceasedName,
            sex: result.sex,
            deathAt: result.deathAt,
            placeOfDeath: result.placeOfDeath,
            createdBy: userId,
            ageYears: result.ageYears,
            isMedicoLegal: result.isMedicoLegal,
            informantName: result.informantName,
            informantRelationship: result.informantRelationship,
          );
    });
  }

  Future<void> _raiseCase() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    final String? facilityId = facilities.isEmpty ? null : facilities.first;
    if (tenantId == null || userId == null || facilityId == null) return;
    final _MlcFormResult? result = await showDialog<_MlcFormResult>(
      context: context,
      builder: (BuildContext context) => const _MlcFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(raiseMlcIntimationUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            facilityId: facilityId,
            caseNumber: result.caseNumber,
            subjectName: result.subjectName,
            caseType: result.caseType,
            createdBy: userId,
            incidentAt: result.incidentAt,
            reportingClinician: userId,
          );
    });
  }

  Future<void> _registerBirth(BirthRecord record) async {
    final session = ref.read(sessionProvider);
    final String? number = await _askValue(
      title: 'Register birth',
      label: 'Register number',
      confirm: 'Register',
    );
    if (number == null) return;
    await _run(() async {
      await ref
          .read(registerBirthUseCaseProvider)
          .call(
            policy: session.authorization,
            record: record,
            registrationNumber: number,
          );
    });
  }

  Future<void> _certifyBirth(BirthRecord record) async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    final String? number = await _askValue(
      title: 'Issue birth certificate',
      label: 'Certificate number',
      confirm: 'Issue',
    );
    if (number == null) return;
    await _run(() async {
      await ref
          .read(certifyBirthUseCaseProvider)
          .call(
            policy: session.authorization,
            record: record,
            certificateNumber: number,
            certifiedBy: userId,
          );
    });
  }

  Future<void> _registerDeath(DeathRecord record) async {
    final session = ref.read(sessionProvider);
    final String? number = await _askValue(
      title: 'Register death',
      label: 'Register number',
      confirm: 'Register',
    );
    if (number == null) return;
    await _run(() async {
      await ref
          .read(registerDeathUseCaseProvider)
          .call(
            policy: session.authorization,
            record: record,
            registrationNumber: number,
          );
    });
  }

  Future<void> _certifyDeath(DeathRecord record) async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    final String? number = await _askValue(
      title: 'Issue death certificate',
      label: 'Certificate number',
      confirm: 'Issue',
    );
    if (number == null) return;
    await _run(() async {
      await ref
          .read(certifyDeathUseCaseProvider)
          .call(
            policy: session.authorization,
            record: record,
            certificateNumber: number,
            certifiedBy: userId,
          );
    });
  }

  Future<void> _recordCoding(DeathRecord record) async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final _DeathCodingResult? result = await showDialog<_DeathCodingResult>(
      context: context,
      builder: (BuildContext context) => const _DeathCodingDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(recordDeathCodingUseCaseProvider)
          .call(
            policy: session.authorization,
            record: record,
            causeOfDeathText: result.causeOfDeathText,
            icd10Code: result.icd10Code,
            mannerOfDeath: result.mannerOfDeath,
            isMedicoLegal: result.isMedicoLegal,
            certifyingClinician: userId,
          );
    });
  }

  Future<void> _intimatePolice(MlcIntimation record) async {
    final session = ref.read(sessionProvider);
    final _PoliceResult? result = await showDialog<_PoliceResult>(
      context: context,
      builder: (BuildContext context) => const _PoliceIntimationDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(intimatePoliceUseCaseProvider)
          .call(
            policy: session.authorization,
            record: record,
            policeStation: result.policeStation,
            policeOfficerName: result.policeOfficerName,
            policeContact: result.policeContact,
          );
    });
  }

  Future<void> _acknowledge(MlcIntimation record) async {
    final session = ref.read(sessionProvider);
    final String? reference = await _askValue(
      title: 'Record police acknowledgement',
      label: 'Police reference',
      confirm: 'Record',
    );
    if (reference == null) return;
    await _run(() async {
      await ref
          .read(acknowledgeMlcUseCaseProvider)
          .call(
            policy: session.authorization,
            record: record,
            policeReference: reference,
          );
    });
  }

  Future<void> _closeCase(MlcIntimation record) async {
    final session = ref.read(sessionProvider);
    final String? reason = await _askReason(
      title: 'Close medico-legal case',
      label: 'Reason',
      confirm: 'Close',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(closeMlcUseCaseProvider)
          .call(policy: session.authorization, record: record, reason: reason);
    });
  }

  Future<void> _voidRecord(StatutoryRecordRef record) async {
    final session = ref.read(sessionProvider);
    final String? reason = await _askReason(
      title: 'Withdraw ${record.kind.label.toLowerCase()} record',
      label: 'Reason',
      confirm: 'Withdraw',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(voidStatutoryRecordUseCaseProvider)
          .call(policy: session.authorization, record: record, reason: reason);
    });
  }

  Future<void> _amend(StatutoryRecordRef record) async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;
    final _AmendmentResult? result = await showDialog<_AmendmentResult>(
      context: context,
      builder: (BuildContext context) => const _AmendmentDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(appendStatutoryAmendmentUseCaseProvider)
          .call(
            policy: session.authorization,
            record: record,
            subjectField: result.subjectField,
            newValue: result.newValue,
            previousValue: result.previousValue,
            reason: result.reason,
            amendedBy: userId,
            tenantId: tenantId,
          );
    });
  }

  Future<String?> _askValue({
    required String title,
    required String label,
    required String confirm,
  }) async {
    final TextEditingController controller = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<String?> _askReason({
    required String title,
    required String label,
    required String confirm,
  }) => _askValue(title: title, label: label, confirm: confirm);

  Future<void> _showBirth(BirthRecord record) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    List<StatutoryAmendment> amendments = const <StatutoryAmendment>[];
    if (tenantId != null) {
      try {
        amendments = await ref
            .read(readStatutoryRegistryUseCaseProvider)
            .amendments(
              policy: session.authorization,
              tenantId: tenantId,
              kind: StatutoryRegistryKind.birth,
              recordId: record.id,
            );
      } on Object catch (error) {
        if (!mounted) return;
        _snack(error.toString());
        return;
      }
    }
    if (!mounted) return;
    final Map<String, String> effective = effectiveStatutoryValues(amendments);
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.child_care_outlined),
              title: Text('${record.childName} · ${record.status.label}'),
              subtitle: Text(
                <String>[
                  'Born ${_formatMoment(record.birthAt)}',
                  effective['place_of_birth'] ?? record.placeOfBirth,
                  '${effective['sex'] ?? record.sex.label} · ${record.deliveryType.label} · ${record.plurality.label}',
                  if (record.weightGrams case final int grams)
                    '$grams g at birth',
                  effective['mother_name'] ?? record.motherName,
                  if (record.registrationNumber case final String number)
                    'Register $number',
                  if (record.certificateNumber case final String number)
                    'Certificate $number',
                  if (record.voidReason case final String why)
                    'Withdrawn: $why',
                ].join('\n'),
              ),
            ),
            if (record.isDraft)
              ListTile(
                leading: const Icon(Icons.app_registration_outlined),
                title: const Text('Enter in the register'),
                onTap: () {
                  Navigator.of(context).pop();
                  _registerBirth(record);
                },
              ),
            if (record.status == BirthStatus.registered)
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Issue certificate (online)'),
                onTap: () {
                  Navigator.of(context).pop();
                  _certifyBirth(record);
                },
              ),
            if (!record.isDraft)
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text('Append a correction'),
                onTap: () {
                  Navigator.of(context).pop();
                  _amend(record.ref);
                },
              ),
            if (!record.isTerminal)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Withdraw registration'),
                onTap: () {
                  Navigator.of(context).pop();
                  _voidRecord(record.ref);
                },
              ),
            for (final StatutoryAmendment amendment in amendments)
              ListTile(
                dense: true,
                leading: const Icon(Icons.history_outlined),
                title: Text(
                  '${amendment.subjectField}: '
                  '${amendment.previousValue ?? '—'} to ${amendment.newValue}',
                ),
                subtitle: Text(
                  '${amendment.reason} · ${_formatMoment(amendment.amendedAt)}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeath(DeathRecord record) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    List<StatutoryAmendment> amendments = const <StatutoryAmendment>[];
    if (tenantId != null) {
      try {
        amendments = await ref
            .read(readStatutoryRegistryUseCaseProvider)
            .amendments(
              policy: session.authorization,
              tenantId: tenantId,
              kind: StatutoryRegistryKind.death,
              recordId: record.id,
            );
      } on Object catch (error) {
        if (!mounted) return;
        _snack(error.toString());
        return;
      }
    }
    if (!mounted) return;
    final Map<String, String> effective = effectiveStatutoryValues(amendments);
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.heart_broken_outlined),
              title: Text('${record.deceasedName} · ${record.status.label}'),
              subtitle: Text(
                <String>[
                  'Died ${_formatMoment(record.deathAt)}',
                  effective['place_of_death'] ?? record.placeOfDeath,
                  '${effective['sex'] ?? record.sex.label}${record.ageYears == null ? '' : ' · ${record.ageYears} years'}',
                  if (record.isCoded)
                    '${effective['icd10_code'] ?? record.icd10Code} · ${record.mannerOfDeath!.label}',
                  if (!record.isCoded) 'Cause of death not coded',
                  if (record.isMedicoLegal) 'Medico-legal',
                  if (record.registrationNumber case final String number)
                    'Register $number',
                  if (record.certificateNumber case final String number)
                    'Certificate $number',
                  if (record.voidReason case final String why)
                    'Withdrawn: $why',
                ].join('\n'),
              ),
            ),
            if (record.isDraft)
              ListTile(
                leading: const Icon(Icons.medical_information_outlined),
                title: const Text('Record cause-of-death coding'),
                onTap: () {
                  Navigator.of(context).pop();
                  _recordCoding(record);
                },
              ),
            if (record.isDraft)
              ListTile(
                leading: const Icon(Icons.app_registration_outlined),
                title: const Text('Enter in the register'),
                onTap: () {
                  Navigator.of(context).pop();
                  _registerDeath(record);
                },
              ),
            if (record.status == DeathStatus.registered)
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Issue certificate (online)'),
                onTap: () {
                  Navigator.of(context).pop();
                  _certifyDeath(record);
                },
              ),
            if (!record.isDraft)
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text('Append a correction'),
                onTap: () {
                  Navigator.of(context).pop();
                  _amend(record.ref);
                },
              ),
            if (!record.isTerminal)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Withdraw registration'),
                onTap: () {
                  Navigator.of(context).pop();
                  _voidRecord(record.ref);
                },
              ),
            for (final StatutoryAmendment amendment in amendments)
              ListTile(
                dense: true,
                leading: const Icon(Icons.history_outlined),
                title: Text(
                  '${amendment.subjectField}: '
                  '${amendment.previousValue ?? '—'} to ${amendment.newValue}',
                ),
                subtitle: Text(
                  '${amendment.reason} · ${_formatMoment(amendment.amendedAt)}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCase(MlcIntimation record) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    List<StatutoryAmendment> amendments = const <StatutoryAmendment>[];
    if (tenantId != null) {
      try {
        amendments = await ref
            .read(readStatutoryRegistryUseCaseProvider)
            .amendments(
              policy: session.authorization,
              tenantId: tenantId,
              kind: StatutoryRegistryKind.mlc,
              recordId: record.id,
            );
      } on Object catch (error) {
        if (!mounted) return;
        _snack(error.toString());
        return;
      }
    }
    if (!mounted) return;
    final StatutoryBoard? board = _board;
    final bool overdue = board?.caseOverdue(record) ?? false;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: Icon(
                overdue ? Icons.error_outline : Icons.gavel_outlined,
              ),
              title: Text('${record.caseNumber} · ${record.status.label}'),
              subtitle: Text(
                <String>[
                  record.subjectName,
                  record.caseType.label,
                  if (record.incidentAt case final DateTime at)
                    'Incident ${_formatMoment(at)}',
                  'Reported ${_formatMoment(record.reportedAt)}',
                  if (overdue) 'Police intimation overdue',
                  if (record.policeStation case final String station)
                    'Station $station',
                  if (record.policeReference case final String reference)
                    'Police ref $reference',
                  if (record.closureReason case final String why)
                    'Closed: $why',
                  if (record.voidReason case final String why)
                    'Withdrawn: $why',
                ].join('\n'),
              ),
            ),
            if (record.status == MlcStatus.reported)
              ListTile(
                leading: const Icon(Icons.local_police_outlined),
                title: const Text('Tell the police'),
                onTap: () {
                  Navigator.of(context).pop();
                  _intimatePolice(record);
                },
              ),
            if (record.status == MlcStatus.intimated)
              ListTile(
                leading: const Icon(Icons.assignment_turned_in_outlined),
                title: const Text('Record police acknowledgement'),
                onTap: () {
                  Navigator.of(context).pop();
                  _acknowledge(record);
                },
              ),
            if (record.status == MlcStatus.acknowledged)
              ListTile(
                leading: const Icon(Icons.task_alt_outlined),
                title: const Text('Close case'),
                onTap: () {
                  Navigator.of(context).pop();
                  _closeCase(record);
                },
              ),
            if (record.status != MlcStatus.reported)
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text('Append a correction'),
                onTap: () {
                  Navigator.of(context).pop();
                  _amend(record.ref);
                },
              ),
            if (!record.isTerminal)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Withdraw case'),
                onTap: () {
                  Navigator.of(context).pop();
                  _voidRecord(record.ref);
                },
              ),
            for (final StatutoryAmendment amendment in amendments)
              ListTile(
                dense: true,
                leading: const Icon(Icons.history_outlined),
                title: Text(
                  '${amendment.subjectField}: '
                  '${amendment.previousValue ?? '—'} to ${amendment.newValue}',
                ),
                subtitle: Text(
                  '${amendment.reason} · ${_formatMoment(amendment.amendedAt)}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final StatutoryBoard? board = _board;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || board == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Statutory registry')),
        body: Center(child: Text(_error ?? 'The register is unavailable.')),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Statutory registry'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Births'),
              Tab(text: 'Deaths'),
              Tab(text: 'Medico-legal'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _birthTab(board),
            _deathTab(board),
            _caseTab(board),
          ],
        ),
      ),
    );
  }

  Widget _birthTab(StatutoryBoard board) {
    return Stack(
      children: <Widget>[
        if (board.births.isEmpty)
          const Center(child: Text('No births registered on this device.'))
        else
          ListView.builder(
            itemCount: board.births.length,
            itemBuilder: (BuildContext context, int index) {
              final BirthRecord record = board.births[index];
              final bool overdue = board.birthOverdue(record);
              return ListTile(
                leading: Icon(
                  overdue ? Icons.error_outline : Icons.child_care_outlined,
                  color: overdue ? Theme.of(context).colorScheme.error : null,
                ),
                title: Text(record.childName),
                subtitle: Text(
                  <String>[
                    record.status.label,
                    _formatMoment(record.birthAt),
                    if (overdue) 'Registration overdue',
                    if (record.registrationNumber case final String number)
                      'Register $number',
                  ].join(' · '),
                ),
                onTap: () => _showBirth(record),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _raiseBirth,
            icon: const Icon(Icons.add),
            label: const Text('Register birth'),
          ),
        ),
      ],
    );
  }

  Widget _deathTab(StatutoryBoard board) {
    return Stack(
      children: <Widget>[
        if (board.deaths.isEmpty)
          const Center(child: Text('No deaths registered on this device.'))
        else
          ListView.builder(
            itemCount: board.deaths.length,
            itemBuilder: (BuildContext context, int index) {
              final DeathRecord record = board.deaths[index];
              final bool overdue = board.deathOverdue(record);
              return ListTile(
                leading: Icon(
                  overdue ? Icons.error_outline : Icons.heart_broken_outlined,
                  color: overdue ? Theme.of(context).colorScheme.error : null,
                ),
                title: Text(record.deceasedName),
                subtitle: Text(
                  <String>[
                    record.status.label,
                    _formatMoment(record.deathAt),
                    if (!record.isCoded) 'Not coded',
                    if (overdue) 'Registration overdue',
                    if (record.isMedicoLegal) 'Medico-legal',
                  ].join(' · '),
                ),
                onTap: () => _showDeath(record),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _raiseDeath,
            icon: const Icon(Icons.add),
            label: const Text('Register death'),
          ),
        ),
      ],
    );
  }

  Widget _caseTab(StatutoryBoard board) {
    return Stack(
      children: <Widget>[
        if (board.intimations.isEmpty)
          const Center(child: Text('No medico-legal cases logged.'))
        else
          ListView.builder(
            itemCount: board.intimations.length,
            itemBuilder: (BuildContext context, int index) {
              final MlcIntimation record = board.intimations[index];
              final bool overdue = board.caseOverdue(record);
              return ListTile(
                leading: Icon(
                  overdue ? Icons.error_outline : Icons.gavel_outlined,
                  color: overdue ? Theme.of(context).colorScheme.error : null,
                ),
                title: Text('${record.caseNumber} · ${record.subjectName}'),
                subtitle: Text(
                  <String>[
                    record.status.label,
                    record.caseType.label,
                    if (overdue) 'Police intimation overdue',
                  ].join(' · '),
                ),
                onTap: () => _showCase(record),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _raiseCase,
            icon: const Icon(Icons.add),
            label: const Text('Log MLC'),
          ),
        ),
      ],
    );
  }
}

class _BirthFormResult {
  const _BirthFormResult({
    required this.childName,
    required this.sex,
    required this.birthAt,
    required this.placeOfBirth,
    required this.motherName,
    required this.deliveryType,
    required this.plurality,
    this.weightGrams,
    this.fatherName,
    this.informantName,
  });

  final String childName;
  final StatutorySex sex;
  final DateTime birthAt;
  final String placeOfBirth;
  final String motherName;
  final DeliveryType deliveryType;
  final BirthPlurality plurality;
  final int? weightGrams;
  final String? fatherName;
  final String? informantName;
}

class _BirthFormDialog extends StatefulWidget {
  const _BirthFormDialog();

  @override
  State<_BirthFormDialog> createState() => _BirthFormDialogState();
}

class _BirthFormDialogState extends State<_BirthFormDialog> {
  final TextEditingController _child = TextEditingController();
  final TextEditingController _mother = TextEditingController();
  final TextEditingController _father = TextEditingController();
  final TextEditingController _place = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _informant = TextEditingController();
  StatutorySex _sex = StatutorySex.unknown;
  DeliveryType _delivery = DeliveryType.normal;
  BirthPlurality _plurality = BirthPlurality.singleton;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _child,
      _mother,
      _father,
      _place,
      _weight,
      _informant,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Register birth'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _child,
            decoration: const InputDecoration(labelText: "Child's name"),
          ),
          DropdownButtonFormField<StatutorySex>(
            initialValue: _sex,
            decoration: const InputDecoration(labelText: 'Sex'),
            items: <DropdownMenuItem<StatutorySex>>[
              for (final StatutorySex value in StatutorySex.values)
                DropdownMenuItem<StatutorySex>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (StatutorySex? value) {
              if (value != null) setState(() => _sex = value);
            },
          ),
          TextField(
            controller: _mother,
            decoration: const InputDecoration(labelText: "Mother's name"),
          ),
          TextField(
            controller: _father,
            decoration: const InputDecoration(
              labelText: "Father's name (optional)",
            ),
          ),
          TextField(
            controller: _place,
            decoration: const InputDecoration(labelText: 'Place of birth'),
          ),
          DropdownButtonFormField<DeliveryType>(
            initialValue: _delivery,
            decoration: const InputDecoration(labelText: 'Delivery'),
            items: <DropdownMenuItem<DeliveryType>>[
              for (final DeliveryType value in DeliveryType.values)
                DropdownMenuItem<DeliveryType>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (DeliveryType? value) {
              if (value != null) setState(() => _delivery = value);
            },
          ),
          DropdownButtonFormField<BirthPlurality>(
            initialValue: _plurality,
            decoration: const InputDecoration(labelText: 'Plurality'),
            items: <DropdownMenuItem<BirthPlurality>>[
              for (final BirthPlurality value in BirthPlurality.values)
                DropdownMenuItem<BirthPlurality>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (BirthPlurality? value) {
              if (value != null) setState(() => _plurality = value);
            },
          ),
          TextField(
            controller: _weight,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Birth weight in grams (optional)',
            ),
          ),
          TextField(
            controller: _informant,
            decoration: const InputDecoration(
              labelText: 'Informed by (optional)',
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
          _BirthFormResult(
            childName: _child.text.trim(),
            sex: _sex,
            birthAt: DateTime.now().toUtc(),
            placeOfBirth: _place.text.trim(),
            motherName: _mother.text.trim(),
            deliveryType: _delivery,
            plurality: _plurality,
            weightGrams: int.tryParse(_weight.text.trim()),
            fatherName: _nullIfEmpty(_father),
            informantName: _nullIfEmpty(_informant),
          ),
        ),
        child: const Text('Raise'),
      ),
    ],
  );

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }
}

class _DeathFormResult {
  const _DeathFormResult({
    required this.deceasedName,
    required this.sex,
    required this.deathAt,
    required this.placeOfDeath,
    required this.isMedicoLegal,
    this.ageYears,
    this.informantName,
    this.informantRelationship,
  });

  final String deceasedName;
  final StatutorySex sex;
  final DateTime deathAt;
  final String placeOfDeath;
  final bool isMedicoLegal;
  final int? ageYears;
  final String? informantName;
  final String? informantRelationship;
}

class _DeathFormDialog extends StatefulWidget {
  const _DeathFormDialog();

  @override
  State<_DeathFormDialog> createState() => _DeathFormDialogState();
}

class _DeathFormDialogState extends State<_DeathFormDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _age = TextEditingController();
  final TextEditingController _place = TextEditingController();
  final TextEditingController _informant = TextEditingController();
  final TextEditingController _relationship = TextEditingController();
  StatutorySex _sex = StatutorySex.unknown;
  bool _medicoLegal = false;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _name,
      _age,
      _place,
      _informant,
      _relationship,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Register death'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: "Deceased's name"),
          ),
          DropdownButtonFormField<StatutorySex>(
            initialValue: _sex,
            decoration: const InputDecoration(labelText: 'Sex'),
            items: <DropdownMenuItem<StatutorySex>>[
              for (final StatutorySex value in StatutorySex.values)
                DropdownMenuItem<StatutorySex>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (StatutorySex? value) {
              if (value != null) setState(() => _sex = value);
            },
          ),
          TextField(
            controller: _age,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Age in years'),
          ),
          TextField(
            controller: _place,
            decoration: const InputDecoration(labelText: 'Place of death'),
          ),
          TextField(
            controller: _informant,
            decoration: const InputDecoration(
              labelText: 'Informed by (optional)',
            ),
          ),
          TextField(
            controller: _relationship,
            decoration: const InputDecoration(
              labelText: 'Informant relationship (optional)',
            ),
          ),
          CheckboxListTile(
            value: _medicoLegal,
            contentPadding: EdgeInsets.zero,
            title: const Text('A medico-legal case'),
            onChanged: (bool? value) =>
                setState(() => _medicoLegal = value ?? false),
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
          _DeathFormResult(
            deceasedName: _name.text.trim(),
            sex: _sex,
            deathAt: DateTime.now().toUtc(),
            placeOfDeath: _place.text.trim(),
            isMedicoLegal: _medicoLegal,
            ageYears: int.tryParse(_age.text.trim()),
            informantName: _nullIfEmpty(_informant),
            informantRelationship: _nullIfEmpty(_relationship),
          ),
        ),
        child: const Text('Raise'),
      ),
    ],
  );

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }
}

class _DeathCodingResult {
  const _DeathCodingResult({
    required this.causeOfDeathText,
    required this.icd10Code,
    required this.mannerOfDeath,
    required this.isMedicoLegal,
  });

  final String causeOfDeathText;
  final String icd10Code;
  final MannerOfDeath mannerOfDeath;
  final bool isMedicoLegal;
}

class _DeathCodingDialog extends StatefulWidget {
  const _DeathCodingDialog();

  @override
  State<_DeathCodingDialog> createState() => _DeathCodingDialogState();
}

class _DeathCodingDialogState extends State<_DeathCodingDialog> {
  final TextEditingController _cause = TextEditingController();
  final TextEditingController _code = TextEditingController();
  MannerOfDeath _manner = MannerOfDeath.natural;
  bool _medicoLegal = false;

  @override
  void dispose() {
    _cause.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cause-of-death coding'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _cause,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Cause of death'),
          ),
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'ICD-10 code'),
          ),
          DropdownButtonFormField<MannerOfDeath>(
            initialValue: _manner,
            decoration: const InputDecoration(labelText: 'Manner of death'),
            items: <DropdownMenuItem<MannerOfDeath>>[
              for (final MannerOfDeath value in MannerOfDeath.values)
                DropdownMenuItem<MannerOfDeath>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (MannerOfDeath? value) {
              if (value != null) setState(() => _manner = value);
            },
          ),
          CheckboxListTile(
            value: _medicoLegal,
            contentPadding: EdgeInsets.zero,
            title: const Text('A medico-legal case'),
            onChanged: (bool? value) =>
                setState(() => _medicoLegal = value ?? false),
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
          _DeathCodingResult(
            causeOfDeathText: _cause.text.trim(),
            icd10Code: _code.text.trim(),
            mannerOfDeath: _manner,
            isMedicoLegal: _medicoLegal,
          ),
        ),
        child: const Text('Record'),
      ),
    ],
  );
}

class _MlcFormResult {
  const _MlcFormResult({
    required this.caseNumber,
    required this.subjectName,
    required this.caseType,
    this.incidentAt,
  });

  final String caseNumber;
  final String subjectName;
  final MlcCaseType caseType;
  final DateTime? incidentAt;
}

class _MlcFormDialog extends StatefulWidget {
  const _MlcFormDialog();

  @override
  State<_MlcFormDialog> createState() => _MlcFormDialogState();
}

class _MlcFormDialogState extends State<_MlcFormDialog> {
  final TextEditingController _number = TextEditingController();
  final TextEditingController _subject = TextEditingController();
  MlcCaseType _type = MlcCaseType.roadTrafficAccident;

  @override
  void dispose() {
    _number.dispose();
    _subject.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Log medico-legal case'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _number,
            decoration: const InputDecoration(labelText: 'Case number'),
          ),
          TextField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'Subject'),
          ),
          DropdownButtonFormField<MlcCaseType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Case type'),
            items: <DropdownMenuItem<MlcCaseType>>[
              for (final MlcCaseType value in MlcCaseType.values)
                DropdownMenuItem<MlcCaseType>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (MlcCaseType? value) {
              if (value != null) setState(() => _type = value);
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
          _MlcFormResult(
            caseNumber: _number.text.trim(),
            subjectName: _subject.text.trim(),
            caseType: _type,
            incidentAt: DateTime.now().toUtc(),
          ),
        ),
        child: const Text('Log'),
      ),
    ],
  );
}

class _PoliceResult {
  const _PoliceResult({
    required this.policeStation,
    this.policeOfficerName,
    this.policeContact,
  });

  final String policeStation;
  final String? policeOfficerName;
  final String? policeContact;
}

class _PoliceIntimationDialog extends StatefulWidget {
  const _PoliceIntimationDialog();

  @override
  State<_PoliceIntimationDialog> createState() =>
      _PoliceIntimationDialogState();
}

class _PoliceIntimationDialogState extends State<_PoliceIntimationDialog> {
  final TextEditingController _station = TextEditingController();
  final TextEditingController _officer = TextEditingController();
  final TextEditingController _contact = TextEditingController();

  @override
  void dispose() {
    _station.dispose();
    _officer.dispose();
    _contact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tell the police'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _station,
            decoration: const InputDecoration(labelText: 'Police station'),
          ),
          TextField(
            controller: _officer,
            decoration: const InputDecoration(
              labelText: 'Officer spoken to (optional)',
            ),
          ),
          TextField(
            controller: _contact,
            decoration: const InputDecoration(
              labelText: 'Station contact (optional)',
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
          _PoliceResult(
            policeStation: _station.text.trim(),
            policeOfficerName: _nullIfEmpty(_officer),
            policeContact: _nullIfEmpty(_contact),
          ),
        ),
        child: const Text('Record'),
      ),
    ],
  );

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }
}

class _AmendmentResult {
  const _AmendmentResult({
    required this.subjectField,
    required this.newValue,
    required this.reason,
    this.previousValue,
  });

  final String subjectField;
  final String newValue;
  final String reason;
  final String? previousValue;
}

class _AmendmentDialog extends StatefulWidget {
  const _AmendmentDialog();

  @override
  State<_AmendmentDialog> createState() => _AmendmentDialogState();
}

class _AmendmentDialogState extends State<_AmendmentDialog> {
  final TextEditingController _field = TextEditingController();
  final TextEditingController _previous = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    _previous.dispose();
    _next.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Append a correction'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _field,
            decoration: const InputDecoration(
              labelText: 'Field (for example child_name)',
            ),
          ),
          TextField(
            controller: _previous,
            decoration: const InputDecoration(
              labelText: 'Value before (optional)',
            ),
          ),
          TextField(
            controller: _next,
            decoration: const InputDecoration(labelText: 'Corrected value'),
          ),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
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
          _AmendmentResult(
            subjectField: _field.text.trim(),
            newValue: _next.text.trim(),
            reason: _reason.text.trim(),
            previousValue: _nullIfEmpty(_previous),
          ),
        ),
        child: const Text('Append'),
      ),
    ],
  );

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }
}

String _formatMoment(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')} '
      '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')}';
}
