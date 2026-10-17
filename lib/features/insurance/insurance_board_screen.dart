/// Health Insurance & TPA board (Module 32).
///
/// The board is patient-scoped: the cover, the authorisations and the claims
/// below belong to the selected patient, because that is how the desk works a
/// case. With no patient selected the board shows the whole tenant, which is
/// what a finance review wants.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/insurance/insurance.dart';
import 'package:nodex_hms/domain/insurance/insurance_use_cases.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The insurance and TPA board.
class InsuranceBoardScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const InsuranceBoardScreen({super.key});

  @override
  ConsumerState<InsuranceBoardScreen> createState() =>
      _InsuranceBoardScreenState();
}

class _InsuranceBoardScreenState extends ConsumerState<InsuranceBoardScreen> {
  List<PolicyBoardEntry> _board = const <PolicyBoardEntry>[];
  List<PreAuthorisationRequest> _preAuthorisations =
      const <PreAuthorisationRequest>[];
  List<InsuranceClaim> _claims = const <InsuranceClaim>[];
  List<InsurancePayer> _payers = const <InsurancePayer>[];
  Map<String, InsurancePayer> _payerById = const <String, InsurancePayer>{};
  Patient? _patient;
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
      final ReadInsuranceUseCase read = ref.read(readInsuranceUseCaseProvider);
      final List<PolicyBoardEntry> board = await read.board(
        policy: session.authorization,
        tenantId: tenantId,
      );
      final List<PreAuthorisationRequest> requests = await read
          .preAuthorisations(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: _patient?.id,
          );
      final List<InsuranceClaim> claims = await read.claims(
        policy: session.authorization,
        tenantId: tenantId,
        patientId: _patient?.id,
      );
      final List<InsurancePayer> payers = await read.payers(
        policy: session.authorization,
        tenantId: tenantId,
        includeInactive: true,
      );
      if (!mounted) return;
      setState(() {
        _board = _patient == null
            ? board
            : board
                  .where(
                    (PolicyBoardEntry entry) =>
                        entry.policy.patientId == _patient!.id,
                  )
                  .toList(growable: false);
        _preAuthorisations = requests;
        _claims = claims;
        _payers = payers;
        _payerById = <String, InsurancePayer>{
          for (final InsurancePayer payer in payers) payer.id: payer,
        };
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  List<InsurancePayer> get _activePayers => _payers
      .where((InsurancePayer payer) => payer.isActive)
      .toList(growable: false);

  String _payerName(String payerId) =>
      _payerById[payerId]?.name ?? 'Unknown payer';

  String? _policyNo(String policyId) {
    for (final PolicyBoardEntry entry in _board) {
      if (entry.policy.id == policyId) {
        return entry.policy.policyNo;
      }
    }
    return null;
  }

  Future<void> _choosePatient() async {
    final Patient? patient = await showDialog<Patient>(
      context: context,
      builder: (BuildContext context) => const _PatientPickerDialog(),
    );
    if (patient == null) return;
    setState(() {
      _patient = patient;
      _loading = true;
    });
    await _load();
  }

  Future<void> _clearPatient() async {
    setState(() {
      _patient = null;
      _loading = true;
    });
    await _load();
  }

  Future<void> _registerPayer() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) return;
    final _PayerFormResult? result = await showDialog<_PayerFormResult>(
      context: context,
      builder: (BuildContext context) => const _PayerFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(registerPayerUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            createdBy: userId,
            code: result.code,
            name: result.name,
            payerType: result.payerType,
            claimPortalRef: result.claimPortalRef,
            contactPhone: result.contactPhone,
            contactEmail: result.contactEmail,
          );
    });
  }

  Future<void> _editPayer(InsurancePayer payer) async {
    final session = ref.read(sessionProvider);
    final _PayerFormResult? result = await showDialog<_PayerFormResult>(
      context: context,
      builder: (BuildContext context) => _PayerFormDialog(payer: payer),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(updatePayerUseCaseProvider)
          .call(
            policy: session.authorization,
            payer: payer,
            code: result.code,
            name: result.name,
            payerType: result.payerType,
            claimPortalRef: result.claimPortalRef,
            contactPhone: result.contactPhone,
            contactEmail: result.contactEmail,
            isActive: result.isActive,
          );
    });
  }

  Future<void> _registerPolicy() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    final Patient? patient = _patient;
    if (tenantId == null || userId == null) return;
    if (patient == null) {
      _snack('Choose a patient first.');
      return;
    }
    if (_activePayers.isEmpty) {
      _snack('Add a payer first.');
      return;
    }
    final _PolicyFormResult? result = await showDialog<_PolicyFormResult>(
      context: context,
      builder: (BuildContext context) =>
          _PolicyFormDialog(payers: _activePayers),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(registerPolicyUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: patient.id,
            payerId: result.payerId,
            createdBy: userId,
            policyNo: result.policyNo,
            validFrom: result.validFrom,
            validTo: result.validTo,
            coverageType: result.coverageType,
            sumInsuredMinor: result.sumInsuredMinor,
            memberId: result.memberId,
            planName: result.planName,
            notes: result.notes,
          );
    });
  }

  Future<void> _verifyPolicy(InsurancePolicy cover) async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    final TextEditingController controller = TextEditingController();
    final String? reference = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Record verification'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Payer reference (optional)',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reference == null) return;
    await _run(() async {
      await ref
          .read(verifyPolicyUseCaseProvider)
          .call(
            policy: session.authorization,
            insurancePolicy: cover,
            verifiedBy: userId,
            reference: reference.isEmpty ? null : reference,
          );
    });
  }

  Future<void> _cancelPolicy(InsurancePolicy cover) async {
    final session = ref.read(sessionProvider);
    final String? reason = await _askReason(
      title: 'Cancel cover',
      label: 'Reason',
      confirm: 'Cancel cover',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(cancelPolicyUseCaseProvider)
          .call(
            policy: session.authorization,
            insurancePolicy: cover,
            reason: reason,
          );
    });
  }

  Future<void> _editPolicy(InsurancePolicy cover) async {
    final session = ref.read(sessionProvider);
    final _PolicyFormResult? result = await showDialog<_PolicyFormResult>(
      context: context,
      builder: (BuildContext context) =>
          _PolicyFormDialog(payers: _payers, policy: cover),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(updatePolicyUseCaseProvider)
          .call(
            policy: session.authorization,
            insurancePolicy: cover,
            policyNo: result.policyNo,
            validFrom: result.validFrom,
            validTo: result.validTo,
            coverageType: result.coverageType,
            sumInsuredMinor: result.sumInsuredMinor,
            memberId: result.memberId,
            planName: result.planName,
            notes: result.notes,
          );
    });
  }

  Future<void> _raisePreAuthorisation(InsurancePolicy cover) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    final String? facilityId = facilities.isEmpty ? null : facilities.first;
    if (tenantId == null || userId == null || facilityId == null) return;
    final _PreAuthFormResult? result = await showDialog<_PreAuthFormResult>(
      context: context,
      builder: (BuildContext context) => const _PreAuthFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(raisePreAuthorisationUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            policyId: cover.id,
            patientId: cover.patientId,
            facilityId: facilityId,
            requestedBy: userId,
            diagnosis: result.diagnosis,
            procedureText: result.procedureText,
            estimatedCostMinor: result.estimatedCostMinor,
          );
    });
  }

  Future<void> _advancePreAuth(
    PreAuthorisationRequest request,
    PreAuthStatus to,
  ) async {
    final session = ref.read(sessionProvider);
    int? amount;
    String? notes;
    String? reason;
    if (to.isApproved) {
      final String? entered = await _askAmount(
        title: 'Record approval',
        label: 'Approved amount',
        confirm: 'Record',
        out: (int value) => amount = value,
      );
      if (entered == null) return;
    } else if (to == PreAuthStatus.rejected) {
      notes = await _askReason(
        title: 'Record refusal',
        label: 'Reason',
        confirm: 'Record',
      );
      if (notes == null) return;
    } else if (to == PreAuthStatus.cancelled) {
      reason = await _askReason(
        title: 'Withdraw request',
        label: 'Reason',
        confirm: 'Withdraw',
      );
      if (reason == null) return;
    }
    await _run(() async {
      await ref
          .read(advancePreAuthorisationUseCaseProvider)
          .call(
            policy: session.authorization,
            request: request,
            to: to,
            approvedAmountMinor: amount,
            decisionNotes: notes,
            cancellationReason: reason,
          );
    });
  }

  Future<void> _createClaim(InsurancePolicy cover) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    final String? facilityId = facilities.isEmpty ? null : facilities.first;
    if (tenantId == null || userId == null || facilityId == null) return;
    final _ClaimFormResult? result = await showDialog<_ClaimFormResult>(
      context: context,
      builder: (BuildContext context) => const _ClaimFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(createClaimUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            policyId: cover.id,
            patientId: cover.patientId,
            facilityId: facilityId,
            createdBy: userId,
            claimNo: result.claimNo,
            claimedAmountMinor: result.claimedAmountMinor,
            notes: result.notes,
          );
    });
  }

  Future<void> _advanceClaim(InsuranceClaim claim, ClaimStatus to) async {
    final session = ref.read(sessionProvider);
    int? approved;
    int? settled;
    String? reason;
    if (to.isApproved) {
      final String? amount = await _askAmount(
        title: 'Record decision',
        label: 'Approved amount',
        confirm: 'Record',
        out: (int value) => approved = value,
      );
      if (amount == null) return;
    } else if (to == ClaimStatus.rejected) {
      reason = await _askReason(
        title: 'Record refusal',
        label: 'Reason',
        confirm: 'Record',
      );
      if (reason == null) return;
    } else if (to == ClaimStatus.settled) {
      final String? amount = await _askAmount(
        title: 'Record settlement',
        label: 'Settled amount',
        confirm: 'Record',
        out: (int value) => settled = value,
      );
      if (amount == null) return;
    } else if (to == ClaimStatus.cancelled) {
      reason = await _askReason(
        title: 'Withdraw claim',
        label: 'Reason',
        confirm: 'Withdraw',
      );
      if (reason == null) return;
    }
    await _run(() async {
      await ref
          .read(advanceClaimUseCaseProvider)
          .call(
            policy: session.authorization,
            claim: claim,
            to: to,
            approvedAmountMinor: approved,
            settledAmountMinor: settled,
            rejectionReason: reason,
            cancellationReason: reason,
          );
    });
  }

  Future<String?> _askReason({
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
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// Asks for an amount in minor units and reports it through [out]. Returns
  /// the raw text so the caller can tell a cancel from a value. Entry is in
  /// minor units, as Module 31 enters money.
  Future<String?> _askAmount({
    required String title,
    required String label,
    required String confirm,
    required void Function(int minor) out,
  }) async {
    final TextEditingController controller = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: '$label (minor units)'),
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
    if (value == null || value.isEmpty) return null;
    final int minor = int.tryParse(value) ?? 0;
    if (minor <= 0) {
      _snack('Enter an amount greater than zero.');
      return null;
    }
    out(minor);
    return value;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showPolicy(PolicyBoardEntry entry) async {
    final InsurancePolicy cover = entry.policy;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: Text('${cover.policyNo} · ${_payerName(cover.payerId)}'),
              subtitle: Text(
                <String>[
                  cover.coverStateLabel(entry.coverState),
                  if (cover.planName case final String plan) plan,
                  _formatMinor(cover.sumInsuredMinor, cover.currency),
                  cover.isVerified ? 'Verified' : 'Not verified',
                  if (entry.openPreAuthorisationCount > 0)
                    '${entry.openPreAuthorisationCount} open pre-auth',
                  if (entry.openClaimCount > 0)
                    '${entry.openClaimCount} open claim',
                  if (entry.recoveryGapMinor > 0)
                    '${_formatMinor(entry.recoveryGapMinor, cover.currency)} to recover',
                ].join(' · '),
              ),
            ),
            if (cover.isVerified)
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: Text(
                  'Verified ${_formatDate(cover.verifiedAt!)}${cover.verificationReference == null ? '' : ' · ${cover.verificationReference}'}',
                ),
              ),
            if (cover.isEditable) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Record verification'),
                onTap: () {
                  Navigator.of(context).pop();
                  _verifyPolicy(cover);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit cover'),
                onTap: () {
                  Navigator.of(context).pop();
                  _editPolicy(cover);
                },
              ),
              ListTile(
                leading: const Icon(Icons.request_quote_outlined),
                title: const Text('Raise pre-authorisation'),
                onTap: () {
                  Navigator.of(context).pop();
                  _raisePreAuthorisation(cover);
                },
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Create claim'),
                onTap: () {
                  Navigator.of(context).pop();
                  _createClaim(cover);
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Cancel cover'),
                onTap: () {
                  Navigator.of(context).pop();
                  _cancelPolicy(cover);
                },
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(
                  cover.cancellationReason == null
                      ? 'Cancelled'
                      : 'Cancelled: ${cover.cancellationReason}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPreAuth(PreAuthorisationRequest request) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.request_quote_outlined),
              title: Text(
                '${_policyNo(request.policyId) ?? 'Policy'} · '
                '${request.status.label}',
              ),
              subtitle: Text(
                <String>[
                  request.diagnosis,
                  request.procedureText,
                  'Est. ${_formatMinor(request.estimatedCostMinor, request.currency)}',
                  if (request.approvedAmountMinor case final int approved)
                    'Approved ${_formatMinor(approved, request.currency)}',
                  if (request.decisionNotes case final String notes) notes,
                  if (request.cancellationReason case final String why)
                    'Withdrawn: $why',
                ].join(' · '),
              ),
            ),
            if (request.status == PreAuthStatus.requested)
              ListTile(
                leading: const Icon(Icons.send_outlined),
                title: const Text('Submit to payer'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advancePreAuth(request, PreAuthStatus.submitted);
                },
              ),
            if (request.status == PreAuthStatus.submitted) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Record approval'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advancePreAuth(request, PreAuthStatus.approved);
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text('Record partial approval'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advancePreAuth(request, PreAuthStatus.partiallyApproved);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Record refusal'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advancePreAuth(request, PreAuthStatus.rejected);
                },
              ),
            ],
            if (request.isLive)
              ListTile(
                leading: const Icon(Icons.undo_outlined),
                title: const Text('Withdraw request'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advancePreAuth(request, PreAuthStatus.cancelled);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClaim(InsuranceClaim claim) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text('${claim.claimNo} · ${claim.status.label}'),
              subtitle: Text(
                <String>[
                  _policyNo(claim.policyId) ?? 'Policy',
                  'Claimed ${_formatMinor(claim.claimedAmountMinor, claim.currency)}',
                  if (claim.approvedAmountMinor case final int approved)
                    'Approved ${_formatMinor(approved, claim.currency)}',
                  if (claim.settledAmountMinor case final int settled)
                    'Settled ${_formatMinor(settled, claim.currency)}',
                  if (claim.recoveryGapMinor > 0)
                    '${_formatMinor(claim.recoveryGapMinor, claim.currency)} to recover',
                  if (claim.rejectionReason case final String why)
                    'Refused: $why',
                  if (claim.cancellationReason case final String why)
                    'Withdrawn: $why',
                ].join(' · '),
              ),
            ),
            if (claim.status == ClaimStatus.draft)
              ListTile(
                leading: const Icon(Icons.send_outlined),
                title: const Text('Submit to payer'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advanceClaim(claim, ClaimStatus.submitted);
                },
              ),
            if (claim.status == ClaimStatus.submitted)
              ListTile(
                leading: const Icon(Icons.hourglass_bottom_outlined),
                title: const Text('Mark under review'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advanceClaim(claim, ClaimStatus.underReview);
                },
              ),
            if (claim.status == ClaimStatus.underReview) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Record approval'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advanceClaim(claim, ClaimStatus.approved);
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text('Record partial approval'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advanceClaim(claim, ClaimStatus.partiallyApproved);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Record refusal'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advanceClaim(claim, ClaimStatus.rejected);
                },
              ),
            ],
            if (claim.status.isApproved)
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Record settlement'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advanceClaim(claim, ClaimStatus.settled);
                },
              ),
            if (claim.isOpen)
              ListTile(
                leading: const Icon(Icons.undo_outlined),
                title: const Text('Withdraw claim'),
                onTap: () {
                  Navigator.of(context).pop();
                  _advanceClaim(claim, ClaimStatus.cancelled);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Insurance')),
        body: Center(child: Text(_error!)),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Insurance & TPA'),
          actions: <Widget>[
            if (_patient == null)
              TextButton.icon(
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Patient'),
                onPressed: _choosePatient,
              )
            else
              TextButton.icon(
                icon: const Icon(Icons.close),
                label: Text(_patient!.displayName),
                onPressed: _clearPatient,
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Cover'),
              Tab(text: 'Pre-auth'),
              Tab(text: 'Claims'),
              Tab(text: 'Payers'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _coverTab(),
            _preAuthTab(),
            _claimTab(),
            _payerTab(),
          ],
        ),
      ),
    );
  }

  Widget _coverTab() {
    return Stack(
      children: <Widget>[
        if (_board.isEmpty)
          const Center(child: Text('No insurance cover on the board.'))
        else
          ListView.builder(
            itemCount: _board.length,
            itemBuilder: (BuildContext context, int index) {
              final PolicyBoardEntry entry = _board[index];
              final InsurancePolicy cover = entry.policy;
              return ListTile(
                leading: Icon(
                  entry.needsAttention
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  color: entry.coverState.needsAttention
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Text('${cover.policyNo} · ${_payerName(cover.payerId)}'),
                subtitle: Text(
                  <String>[
                    entry.coverState.label,
                    cover.isVerified ? 'Verified' : 'Not verified',
                    if (entry.openPreAuthorisationCount > 0)
                      '${entry.openPreAuthorisationCount} pre-auth',
                    if (entry.openClaimCount > 0)
                      '${entry.openClaimCount} claim',
                    if (entry.recoveryGapMinor > 0)
                      '${_formatMinor(entry.recoveryGapMinor, cover.currency)} to recover',
                  ].join(' · '),
                ),
                onTap: () => _showPolicy(entry),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _registerPolicy,
            tooltip: 'Register cover',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _preAuthTab() {
    if (_preAuthorisations.isEmpty) {
      return const Center(child: Text('No pre-authorisation requests.'));
    }
    return ListView.builder(
      itemCount: _preAuthorisations.length,
      itemBuilder: (BuildContext context, int index) {
        final PreAuthorisationRequest request = _preAuthorisations[index];
        return ListTile(
          leading: Icon(
            request.isLive ? Icons.hourglass_empty : Icons.task_alt,
            color: request.status == PreAuthStatus.rejected
                ? Theme.of(context).colorScheme.error
                : null,
          ),
          title: Text(
            '${_policyNo(request.policyId) ?? 'Policy'} · '
            '${request.status.label}',
          ),
          subtitle: Text(
            '${request.procedureText} · '
            '${_formatMinor(request.estimatedCostMinor, request.currency)}',
          ),
          onTap: () => _showPreAuth(request),
        );
      },
    );
  }

  Widget _claimTab() {
    if (_claims.isEmpty) {
      return const Center(child: Text('No claims.'));
    }
    return ListView.builder(
      itemCount: _claims.length,
      itemBuilder: (BuildContext context, int index) {
        final InsuranceClaim claim = _claims[index];
        return ListTile(
          leading: Icon(
            claim.isOpen ? Icons.hourglass_empty : Icons.task_alt,
            color: claim.status == ClaimStatus.rejected
                ? Theme.of(context).colorScheme.error
                : null,
          ),
          title: Text('${claim.claimNo} · ${claim.status.label}'),
          subtitle: Text(
            '${_policyNo(claim.policyId) ?? 'Policy'} · '
            '${_formatMinor(claim.claimedAmountMinor, claim.currency)}'
            '${claim.recoveryGapMinor > 0 ? ' · ${_formatMinor(claim.recoveryGapMinor, claim.currency)} to recover' : ''}',
          ),
          onTap: () => _showClaim(claim),
        );
      },
    );
  }

  Widget _payerTab() {
    return Stack(
      children: <Widget>[
        if (_payers.isEmpty)
          const Center(child: Text('No payers contracted with.'))
        else
          ListView.builder(
            itemCount: _payers.length,
            itemBuilder: (BuildContext context, int index) {
              final InsurancePayer payer = _payers[index];
              return ListTile(
                leading: const Icon(Icons.business_outlined),
                title: Text('${payer.code} · ${payer.name}'),
                subtitle: Text(
                  <String>[
                    payer.payerType.label,
                    if (!payer.isActive) 'Not contracted',
                    if (payer.claimPortalRef case final String portal) portal,
                    if (payer.contactPhone case final String phone) phone,
                  ].join(' · '),
                ),
                onTap: () => _editPayer(payer),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _registerPayer,
            tooltip: 'Add payer',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

/// The cover-state label, extended with the board's own framing.
extension PolicyBoardDisplay on InsurancePolicy {
  /// Cover state as the board shows it.
  String coverStateLabel(PolicyCoverState state) => switch (state) {
    PolicyCoverState.active => 'In force',
    PolicyCoverState.expiringSoon => 'Expires soon',
    PolicyCoverState.expired => 'Expired',
    PolicyCoverState.cancelled => 'Cancelled',
  };
}

/// Formats a minor-unit amount for display.
String _formatMinor(int minor, String currency) {
  final int whole = minor ~/ 100;
  final int cents = (minor % 100).abs();
  return '$currency $whole.${cents.toString().padLeft(2, '0')}';
}

String _formatDate(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

class _PatientPickerDialog extends ConsumerStatefulWidget {
  const _PatientPickerDialog();

  @override
  ConsumerState<_PatientPickerDialog> createState() =>
      _PatientPickerDialogState();
}

class _PatientPickerDialogState extends ConsumerState<_PatientPickerDialog> {
  final TextEditingController _query = TextEditingController();
  List<Patient> _results = const <Patient>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final List<Patient> patients = await ref
          .read(patientRepositoryProvider)
          .searchPatients(tenantId: tenantId, query: query);
      if (!mounted) return;
      setState(() {
        _results = patients;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose patient'),
    content: SizedBox(
      width: 420,
      height: 360,
      child: Column(
        children: <Widget>[
          TextField(
            controller: _query,
            decoration: const InputDecoration(labelText: 'MRN, name or phone'),
            onSubmitted: _search,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                ? const Center(child: Text('No matching patient.'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Patient patient = _results[index];
                      return ListTile(
                        title: Text(patient.displayName),
                        subtitle: Text(patient.mrn),
                        onTap: () => Navigator.of(context).pop(patient),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: () => _search(_query.text.trim()),
        child: const Text('Search'),
      ),
    ],
  );
}

class _PayerFormResult {
  const _PayerFormResult({
    required this.code,
    required this.name,
    required this.payerType,
    required this.isActive,
    this.claimPortalRef,
    this.contactPhone,
    this.contactEmail,
  });

  final String code;
  final String name;
  final PayerType payerType;
  final bool isActive;
  final String? claimPortalRef;
  final String? contactPhone;
  final String? contactEmail;
}

class _PayerFormDialog extends StatefulWidget {
  const _PayerFormDialog({this.payer});

  final InsurancePayer? payer;

  @override
  State<_PayerFormDialog> createState() => _PayerFormDialogState();
}

class _PayerFormDialogState extends State<_PayerFormDialog> {
  late final TextEditingController _code = TextEditingController(
    text: widget.payer?.code ?? '',
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.payer?.name ?? '',
  );
  late final TextEditingController _portal = TextEditingController(
    text: widget.payer?.claimPortalRef ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.payer?.contactPhone ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.payer?.contactEmail ?? '',
  );
  late PayerType _type = widget.payer?.payerType ?? PayerType.insurer;
  late bool _isActive = widget.payer?.isActive ?? true;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _code,
      _name,
      _portal,
      _phone,
      _email,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.payer == null ? 'Add payer' : 'Edit payer'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Code'),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          DropdownButtonFormField<PayerType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: <DropdownMenuItem<PayerType>>[
              for (final PayerType type in PayerType.values)
                DropdownMenuItem<PayerType>(
                  value: type,
                  child: Text(type.label),
                ),
            ],
            onChanged: (PayerType? value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          TextField(
            controller: _portal,
            decoration: const InputDecoration(labelText: 'Claim portal ref'),
          ),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Contact phone'),
          ),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Contact email'),
          ),
          if (widget.payer != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              title: const Text('Contracted'),
              onChanged: (bool? value) =>
                  setState(() => _isActive = value ?? false),
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
          _PayerFormResult(
            code: _code.text.trim(),
            name: _name.text.trim(),
            payerType: _type,
            isActive: _isActive,
            claimPortalRef: _nullIfEmpty(_portal),
            contactPhone: _nullIfEmpty(_phone),
            contactEmail: _nullIfEmpty(_email),
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}

class _PolicyFormResult {
  const _PolicyFormResult({
    required this.payerId,
    required this.policyNo,
    required this.validFrom,
    required this.validTo,
    required this.coverageType,
    required this.sumInsuredMinor,
    this.memberId,
    this.planName,
    this.notes,
  });

  final String payerId;
  final String policyNo;
  final DateTime validFrom;
  final DateTime validTo;
  final CoverageType coverageType;
  final int sumInsuredMinor;
  final String? memberId;
  final String? planName;
  final String? notes;
}

class _PolicyFormDialog extends StatefulWidget {
  const _PolicyFormDialog({required this.payers, this.policy});

  final List<InsurancePayer> payers;
  final InsurancePolicy? policy;

  @override
  State<_PolicyFormDialog> createState() => _PolicyFormDialogState();
}

class _PolicyFormDialogState extends State<_PolicyFormDialog> {
  late String _payerId = widget.policy?.payerId ?? widget.payers.first.id;
  late final TextEditingController _policyNo = TextEditingController(
    text: widget.policy?.policyNo ?? '',
  );
  late final TextEditingController _memberId = TextEditingController(
    text: widget.policy?.memberId ?? '',
  );
  late final TextEditingController _plan = TextEditingController(
    text: widget.policy?.planName ?? '',
  );
  late final TextEditingController _sumInsured = TextEditingController(
    text: widget.policy?.sumInsuredMinor.toString() ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.policy?.notes ?? '',
  );
  late CoverageType _coverage =
      widget.policy?.coverageType ?? CoverageType.cashless;
  late DateTime _validFrom =
      widget.policy?.validFrom.toUtc() ?? DateTime.now().toUtc();
  late DateTime _validTo =
      widget.policy?.validTo.toUtc() ??
      DateTime.now().toUtc().add(const Duration(days: 365));

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _policyNo,
      _memberId,
      _plan,
      _sumInsured,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _pick({required bool from}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: from ? _validFrom : _validTo,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null) return;
    setState(() {
      final DateTime day = DateTime.utc(picked.year, picked.month, picked.day);
      if (from) {
        _validFrom = day;
      } else {
        _validTo = day;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.policy == null ? 'Register cover' : 'Edit cover'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<String>(
            // A registered policy keeps the payer it was agreed with, so the
            // field is read-only in edit mode; the initial value is left null
            // so the disabled button cannot assert against the item list.
            initialValue: widget.policy == null ? _payerId : null,
            decoration: const InputDecoration(labelText: 'Payer'),
            items: <DropdownMenuItem<String>>[
              for (final InsurancePayer payer in widget.payers)
                DropdownMenuItem<String>(
                  value: payer.id,
                  child: Text('${payer.code} · ${payer.name}'),
                ),
            ],
            onChanged: widget.policy == null
                ? (String? value) {
                    if (value != null) setState(() => _payerId = value);
                  }
                : null,
            disabledHint: Text(_payerLabel(widget.payers, _payerId)),
          ),
          TextField(
            controller: _policyNo,
            decoration: const InputDecoration(labelText: 'Policy number'),
          ),
          TextField(
            controller: _memberId,
            decoration: const InputDecoration(labelText: 'Member id'),
          ),
          TextField(
            controller: _plan,
            decoration: const InputDecoration(labelText: 'Plan'),
          ),
          DropdownButtonFormField<CoverageType>(
            initialValue: _coverage,
            decoration: const InputDecoration(labelText: 'Coverage'),
            items: <DropdownMenuItem<CoverageType>>[
              for (final CoverageType type in CoverageType.values)
                DropdownMenuItem<CoverageType>(
                  value: type,
                  child: Text(type.label),
                ),
            ],
            onChanged: (CoverageType? value) {
              if (value != null) setState(() => _coverage = value);
            },
          ),
          TextField(
            controller: _sumInsured,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Sum insured (minor units)',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cover starts'),
            subtitle: Text(_formatDate(_validFrom)),
            onTap: () => _pick(from: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cover ends'),
            subtitle: Text(_formatDate(_validTo)),
            onTap: () => _pick(from: false),
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
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
          _PolicyFormResult(
            payerId: _payerId,
            policyNo: _policyNo.text.trim(),
            validFrom: _validFrom,
            validTo: _validTo,
            coverageType: _coverage,
            sumInsuredMinor: int.tryParse(_sumInsured.text.trim()) ?? 0,
            memberId: _nullIfEmpty(_memberId),
            planName: _nullIfEmpty(_plan),
            notes: _nullIfEmpty(_notes),
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );

  static String _payerLabel(List<InsurancePayer> payers, String payerId) {
    for (final InsurancePayer payer in payers) {
      if (payer.id == payerId) {
        return '${payer.code} · ${payer.name}';
      }
    }
    return 'Payer';
  }
}

class _PreAuthFormResult {
  const _PreAuthFormResult({
    required this.diagnosis,
    required this.procedureText,
    required this.estimatedCostMinor,
  });

  final String diagnosis;
  final String procedureText;
  final int estimatedCostMinor;
}

class _PreAuthFormDialog extends StatefulWidget {
  const _PreAuthFormDialog();

  @override
  State<_PreAuthFormDialog> createState() => _PreAuthFormDialogState();
}

class _PreAuthFormDialogState extends State<_PreAuthFormDialog> {
  final TextEditingController _diagnosis = TextEditingController();
  final TextEditingController _procedure = TextEditingController();
  final TextEditingController _cost = TextEditingController();

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _diagnosis,
      _procedure,
      _cost,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Raise pre-authorisation'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _diagnosis,
            decoration: const InputDecoration(labelText: 'Diagnosis'),
          ),
          TextField(
            controller: _procedure,
            decoration: const InputDecoration(labelText: 'Procedure'),
          ),
          TextField(
            controller: _cost,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Estimated cost (minor units)',
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
          _PreAuthFormResult(
            diagnosis: _diagnosis.text.trim(),
            procedureText: _procedure.text.trim(),
            estimatedCostMinor: int.tryParse(_cost.text.trim()) ?? 0,
          ),
        ),
        child: const Text('Raise'),
      ),
    ],
  );
}

class _ClaimFormResult {
  const _ClaimFormResult({
    required this.claimNo,
    required this.claimedAmountMinor,
    this.notes,
  });

  final String claimNo;
  final int claimedAmountMinor;
  final String? notes;
}

class _ClaimFormDialog extends StatefulWidget {
  const _ClaimFormDialog();

  @override
  State<_ClaimFormDialog> createState() => _ClaimFormDialogState();
}

class _ClaimFormDialogState extends State<_ClaimFormDialog> {
  final TextEditingController _claimNo = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _claimNo,
      _amount,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create claim'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _claimNo,
            decoration: const InputDecoration(labelText: 'Claim number'),
          ),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Claimed amount (minor units)',
            ),
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
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
        onPressed: () {
          final String notes = _notes.text.trim();
          Navigator.of(context).pop(
            _ClaimFormResult(
              claimNo: _claimNo.text.trim(),
              claimedAmountMinor: int.tryParse(_amount.text.trim()) ?? 0,
              notes: notes.isEmpty ? null : notes,
            ),
          );
        },
        child: const Text('Create'),
      ),
    ],
  );
}
