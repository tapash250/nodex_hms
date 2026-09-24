/// ER and triage use cases (Module 05).
///
/// Each write gates on the authorization policy before touching the
/// repository. Escalation additionally requires `triage.escalate`.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/er/er.dart';
import 'package:nodex_hms/domain/er/er_repository.dart';
import 'package:uuid/uuid.dart';

/// Records a triage assessment. Requires `triage.write`.
final class RecordTriageUseCase {
  RecordTriageUseCase({required this._repository});

  final ErRepository _repository;

  Future<TriageAssessment> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String assessedBy,
    required TriageAcuity acuity,
    required String chiefComplaint,
    required TriageDisposition disposition,
    String? encounterId,
    Map<String, Object?> vitals = const <String, Object?>{},
    List<String> redFlags = const <String>[],
  }) async {
    policy.require(NodexPermissions.triageWrite);
    final DateTime now = DateTime.now().toUtc();
    final TriageAssessment assessment = TriageAssessment(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      encounterId: encounterId,
      assessedBy: assessedBy,
      acuity: acuity,
      chiefComplaint: chiefComplaint,
      vitals: vitals,
      redFlags: redFlags,
      disposition: disposition,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.createTriage(assessment);
  }
}

/// Escalates a triage assessment. One-way; requires `triage.escalate`.
final class EscalateTriageUseCase {
  EscalateTriageUseCase({required this._repository});

  final ErRepository _repository;

  Future<TriageAssessment> call({
    required AuthorizationPolicy policy,
    required TriageAssessment assessment,
    required String escalatedBy,
  }) async {
    policy.require(NodexPermissions.triageEscalate);
    if (assessment.escalated) {
      throw const AuthorizationError(
        message: 'Triage assessment is already escalated.',
        code: 'triage_already_escalated',
      );
    }
    return _repository.updateTriage(assessment.id, <String, Object?>{
      'escalated': true,
      'escalated_by': escalatedBy,
      'escalated_at': DateTime.now().toUtc(),
    });
  }
}

/// Opens an ER visit linked to a triage assessment. Requires
/// `er.visit.write`.
final class OpenErVisitUseCase {
  OpenErVisitUseCase({required this._repository});

  final ErRepository _repository;

  Future<ErVisit> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String triageId,
    required String providerId,
    ArrivalMode? arrivalMode,
    String? bedId,
    String? encounterId,
  }) async {
    policy.require(NodexPermissions.erVisitWrite);
    final DateTime now = DateTime.now().toUtc();
    final ErVisit visit = ErVisit(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      triageId: triageId,
      encounterId: encounterId,
      providerId: providerId,
      status: ErVisitStatus.inProgress,
      arrivalMode: arrivalMode,
      bedId: bedId,
      startedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.createVisit(visit);
  }
}

/// Transitions an ER visit toward a terminal or admitted status. Requires
/// `er.visit.write`.
final class TransitionErVisitUseCase {
  TransitionErVisitUseCase({required this._repository});

  final ErRepository _repository;

  Future<ErVisit> call({
    required AuthorizationPolicy policy,
    required ErVisit visit,
    required ErVisitStatus nextStatus,
    String? disposition,
    String? dispositionReason,
    DateTime? dischargedAt,
    String? bedId,
  }) async {
    policy.require(NodexPermissions.erVisitWrite);
    if (visit.status.isTerminal) {
      throw const AuthorizationError(
        message: 'Terminal ER visit status cannot transition.',
        code: 'er_visit_terminal',
      );
    }
    final Map<String, Object?> changes = <String, Object?>{
      'status': nextStatus.wireValue,
      'updated_at': DateTime.now().toUtc(),
    };
    if (disposition != null) changes['disposition'] = disposition;
    if (dispositionReason != null) {
      changes['disposition_reason'] = dispositionReason;
    }
    if (dischargedAt != null) changes['discharged_at'] = dischargedAt;
    if (bedId != null) changes['bed_id'] = bedId;
    return _repository.updateVisit(visit.id, changes);
  }
}
