/// Quality & NABH Compliance Hub use cases (Module 35).
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/quality/quality.dart';
import 'package:nodex_hms/domain/quality/quality_repository.dart';

/// Plans an accreditation compliance audit.
final class ScheduleComplianceAuditUseCase {
  /// Creates the use case.
  ScheduleComplianceAuditUseCase({required this._repository});

  final QualityRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String chapter,
    required String title,
    required DateTime scheduledFor,
    required String createdBy,
    AccreditationFramework framework = AccreditationFramework.nabh,
    String? standardReference,
    String? auditorId,
    String? findings,
    String auditId = '',
  }) async {
    policy.require(NodexPermissions.qualityAudit);
    return _repository.registerAudit(
      ComplianceAudit.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        chapter: chapter,
        title: title,
        scheduledFor: scheduledFor,
        createdBy: createdBy,
        framework: framework,
        standardReference: standardReference,
        auditorId: auditorId,
        findings: findings,
        auditId: auditId,
      ),
    );
  }
}

/// Starts a planned audit, which is the moment it stops being re-scoped.
final class StartComplianceAuditUseCase {
  /// Creates the use case.
  StartComplianceAuditUseCase({required this._repository});

  final QualityRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ComplianceAudit audit,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.qualityAudit);
    if (!auditCanTransition(audit.status, AuditStatus.inProgress)) {
      throw AuthorizationError(
        message: audit.status.isTerminal
            ? 'This audit is settled.'
            : 'That audit has already started.',
        code: 'compliance_audit_transition_invalid',
      );
    }
    await _repository.updateAudit(audit.id, auditStartChanges(at: at));
  }
}

/// Scores and completes an audit.
final class CompleteComplianceAuditUseCase {
  /// Creates the use case.
  CompleteComplianceAuditUseCase({required this._repository});

  final QualityRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ComplianceAudit audit,
    required int totalCriteria,
    required int compliantCriteria,
    required String completedBy,
    String? findings,
    DateTime? correctiveActionDueAt,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.qualityAudit);
    if (!auditCanTransition(audit.status, AuditStatus.completed)) {
      throw AuthorizationError(
        message: audit.status.isTerminal
            ? 'This audit is settled.'
            : 'An audit is scored once it has started.',
        code: 'compliance_audit_transition_invalid',
      );
    }
    await _repository.updateAudit(
      audit.id,
      auditCompleteChanges(
        totalCriteria: totalCriteria,
        compliantCriteria: compliantCriteria,
        completedBy: completedBy,
        findings: findings,
        correctiveActionDueAt: correctiveActionDueAt,
        at: at,
      ),
    );
  }
}

/// Calls an audit off with a reason.
final class CancelComplianceAuditUseCase {
  /// Creates the use case.
  CancelComplianceAuditUseCase({required this._repository});

  final QualityRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ComplianceAudit audit,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.qualityAudit);
    if (!auditCanTransition(audit.status, AuditStatus.cancelled)) {
      throw AuthorizationError(
        message: audit.status.isTerminal
            ? 'This audit is settled.'
            : 'That audit cannot be cancelled now.',
        code: 'compliance_audit_transition_invalid',
      );
    }
    await _repository.updateAudit(
      audit.id,
      auditCancelChanges(reason: reason, at: at),
    );
  }
}

/// Raises a patient safety incident report.
final class ReportIncidentUseCase {
  /// Creates the use case.
  ReportIncidentUseCase({required this._repository});

  final QualityRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String reportNumber,
    required String title,
    required String description,
    required DateTime occurredAt,
    required String reportedBy,
    required String createdBy,
    IncidentCategory category = IncidentCategory.other,
    IncidentSeverity severity = IncidentSeverity.minor,
    String? location,
    String? patientId,
    String? assignedTo,
    String? immediateAction,
    DateTime? reportedAt,
    DateTime? followUpDueAt,
    String incidentId = '',
  }) async {
    policy.require(NodexPermissions.qualityIncident);
    await _requireFreeNumber(tenantId, reportNumber, exceptId: incidentId);
    return _repository.registerIncident(
      IncidentReport.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        reportNumber: reportNumber,
        title: title,
        description: description,
        occurredAt: occurredAt,
        reportedBy: reportedBy,
        createdBy: createdBy,
        category: category,
        severity: severity,
        location: location,
        patientId: patientId,
        assignedTo: assignedTo,
        immediateAction: immediateAction,
        reportedAt: reportedAt,
        followUpDueAt: followUpDueAt,
        incidentId: incidentId,
      ),
    );
  }

  /// One report number per incident: two files for one incident split the
  /// evidence an accreditation body reads.
  Future<void> _requireFreeNumber(
    String tenantId,
    String reportNumber, {
    required String exceptId,
  }) async {
    final List<IncidentReport> incidents = await _repository.listIncidents(
      tenantId,
    );
    for (final IncidentReport other in incidents) {
      if (other.reportNumber == reportNumber.trim() && other.id != exceptId) {
        throw const ValidationError(
          message: 'Incident report failed validation.',
          fieldErrors: <String, String>{
            'report_number': 'That report number is already logged.',
          },
          code: 'incident_report_number_duplicate',
        );
      }
    }
  }
}

/// Opens an investigation into an incident.
final class InvestigateIncidentUseCase {
  /// Creates the use case.
  InvestigateIncidentUseCase({required this._repository});

  final QualityRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required IncidentReport incident,
    String? assignedTo,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.qualityIncident);
    if (!incidentCanTransition(incident.status, IncidentStatus.investigating)) {
      throw AuthorizationError(
        message: incident.status.isTerminal
            ? 'This incident report is settled.'
            : 'That incident is already under investigation.',
        code: 'incident_report_transition_invalid',
      );
    }
    await _repository.updateIncident(
      incident.id,
      incidentInvestigateChanges(assignedTo: assignedTo, at: at),
    );
  }
}

/// Records the corrective action agreed for an incident.
final class PlanIncidentActionUseCase {
  /// Creates the use case.
  PlanIncidentActionUseCase({required this._repository});

  final QualityRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required IncidentReport incident,
    required String actionPlan,
    required DateTime dueAt,
  }) async {
    policy.require(NodexPermissions.qualityIncident);
    if (!incidentCanTransition(incident.status, IncidentStatus.actionPlan)) {
      throw AuthorizationError(
        message: incident.status.isTerminal
            ? 'This incident report is settled.'
            : 'An action plan follows the investigation.',
        code: 'incident_report_transition_invalid',
      );
    }
    await _repository.updateIncident(
      incident.id,
      incidentActionPlanChanges(actionPlan: actionPlan, dueAt: dueAt),
    );
  }
}

/// Closes an incident with a note.
final class CloseIncidentUseCase {
  /// Creates the use case.
  CloseIncidentUseCase({required this._repository});

  final QualityRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required IncidentReport incident,
    required String note,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.qualityIncident);
    if (!incidentCanTransition(incident.status, IncidentStatus.closed)) {
      throw AuthorizationError(
        message: incident.status.isTerminal
            ? 'This incident report is settled.'
            : 'An incident is closed once the action plan is in place.',
        code: 'incident_report_transition_invalid',
      );
    }
    await _repository.updateIncident(
      incident.id,
      incidentCloseChanges(note: note, at: at),
    );
  }
}

/// Withdraws an incident report that should not have been raised.
final class VoidIncidentUseCase {
  /// Creates the use case.
  VoidIncidentUseCase({required this._repository});

  final QualityRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required IncidentReport incident,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.qualityIncident);
    if (!incidentCanTransition(incident.status, IncidentStatus.voided)) {
      throw AuthorizationError(
        message: incident.status.isTerminal
            ? 'This incident report is settled.'
            : 'That incident can no longer be withdrawn.',
        code: 'incident_report_transition_invalid',
      );
    }
    await _repository.updateIncident(
      incident.id,
      incidentVoidChanges(reason: reason, at: at),
    );
  }
}

/// Records a measured clinical indicator.
final class RecordClinicalIndicatorUseCase {
  /// Creates the use case.
  RecordClinicalIndicatorUseCase({required this._repository});

  final QualityRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String code,
    required String name,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String createdBy,
    IndicatorCategory category = IndicatorCategory.operational,
    IndicatorUnit unit = IndicatorUnit.percent,
    IndicatorDirection direction = IndicatorDirection.lowerIsBetter,
    int numerator = 0,
    int denominator = 0,
    int? targetValue,
    String? sourceNote,
    String indicatorId = '',
  }) async {
    policy.require(NodexPermissions.qualityIndicator);
    await _requireFreePeriod(
      tenantId,
      code,
      periodStart,
      exceptId: indicatorId,
    );
    return _repository.registerIndicator(
      ClinicalIndicator.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        code: code,
        name: name,
        periodStart: periodStart,
        periodEnd: periodEnd,
        createdBy: createdBy,
        category: category,
        unit: unit,
        direction: direction,
        numerator: numerator,
        denominator: denominator,
        targetValue: targetValue,
        sourceNote: sourceNote,
        indicatorId: indicatorId,
      ),
    );
  }

  /// One reading of one indicator for one period: a second reading of the same
  /// period is a correction, not a second figure.
  Future<void> _requireFreePeriod(
    String tenantId,
    String code,
    DateTime periodStart, {
    required String exceptId,
  }) async {
    final List<ClinicalIndicator> indicators = await _repository.listIndicators(
      tenantId,
    );
    final DateTime start = DateTime.utc(
      periodStart.toUtc().year,
      periodStart.toUtc().month,
      periodStart.toUtc().day,
    );
    for (final ClinicalIndicator other in indicators) {
      if (other.id == exceptId) {
        continue;
      }
      if (other.code != code.trim()) {
        continue;
      }
      final DateTime otherStart = DateTime.utc(
        other.periodStart.year,
        other.periodStart.month,
        other.periodStart.day,
      );
      if (otherStart == start) {
        throw const ValidationError(
          message: 'Clinical indicator failed validation.',
          fieldErrors: <String, String>{
            'period_start':
                'That indicator is already recorded for the period.',
          },
          code: 'clinical_indicator_period_duplicate',
        );
      }
    }
  }
}

/// Publishes a recorded indicator, which is the moment it is a figure.
final class PublishClinicalIndicatorUseCase {
  /// Creates the use case.
  PublishClinicalIndicatorUseCase({required this._repository});

  final QualityRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ClinicalIndicator indicator,
    required String publishedBy,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.qualityIndicator);
    if (!indicatorCanTransition(indicator.status, IndicatorStatus.published)) {
      throw AuthorizationError(
        message: indicator.status.isTerminal
            ? 'This reading is retracted.'
            : 'That reading is already published.',
        code: 'clinical_indicator_transition_invalid',
      );
    }
    await _repository.updateIndicator(
      indicator.id,
      indicatorPublishChanges(publishedBy: publishedBy, at: at),
    );
  }
}

/// Retracts a published indicator with a reason.
final class RetractClinicalIndicatorUseCase {
  /// Creates the use case.
  RetractClinicalIndicatorUseCase({required this._repository});

  final QualityRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ClinicalIndicator indicator,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.qualityIndicator);
    if (!indicatorCanTransition(indicator.status, IndicatorStatus.retracted)) {
      throw AuthorizationError(
        message: indicator.status.isTerminal
            ? 'This reading is retracted.'
            : 'A draft reading is discarded, not retracted.',
        code: 'clinical_indicator_transition_invalid',
      );
    }
    await _repository.updateIndicator(
      indicator.id,
      indicatorRetractChanges(reason: reason, at: at),
    );
  }
}

/// The quality hub as the board shows it.
@immutable
final class QualityBoard {
  /// Creates a board snapshot.
  const QualityBoard({
    required this.audits,
    required this.incidents,
    required this.indicators,
    required this.asOf,
  });

  /// Compliance audits, live audits first.
  final List<ComplianceAudit> audits;

  /// Incident reports, live incidents first.
  final List<IncidentReport> incidents;

  /// Clinical indicators, newest period first.
  final List<ClinicalIndicator> indicators;

  /// The instant the derived flags were computed at.
  final DateTime asOf;

  /// Whether an audit is past its scheduled moment.
  bool auditOverdue(ComplianceAudit audit) =>
      isAuditOverdue(audit: audit, now: asOf);

  /// Whether an incident is past its severity response window.
  bool incidentOverdue(IncidentReport incident) =>
      isIncidentResponseOverdue(incident: incident, now: asOf);

  /// Whether an incident's serology follow-up has fallen due.
  bool followUpOverdue(IncidentReport incident) =>
      isIncidentFollowUpOverdue(incident: incident, now: asOf);

  /// The audits scored below the conformance threshold.
  List<ComplianceAudit> get nonConformantAudits => audits
      .where(
        (ComplianceAudit audit) => audit.verdict == AuditVerdict.nonConformant,
      )
      .toList(growable: false);

  /// The published indicators missing their target.
  List<ClinicalIndicator> get indicatorsMissingTarget => indicators
      .where(
        (ClinicalIndicator indicator) =>
            indicator.isPublished && indicator.meetsTarget == false,
      )
      .toList(growable: false);

  /// The incidents still waiting on an investigation.
  List<IncidentReport> get incidentsAwaitingInvestigation => incidents
      .where((IncidentReport incident) => incident.status.awaitsInvestigation)
      .toList(growable: false);

  /// Whether anything on the board needs attention.
  bool get hasOverdue =>
      audits.any(auditOverdue) ||
      incidents.any(incidentOverdue) ||
      incidents.any(followUpOverdue);
}

/// Reads the quality hub and its derived markers.
final class ReadQualityHubUseCase {
  /// Creates the use case.
  ReadQualityHubUseCase({required this._repository});

  final QualityRepository _repository;

  /// The compliance audits, live audits first.
  Future<List<ComplianceAudit>> audits({
    required AuthorizationPolicy policy,
    required String tenantId,
    AuditStatus? status,
    bool includeSettled = true,
  }) async {
    policy.require(NodexPermissions.qualityRead);
    final List<ComplianceAudit> audits = await _repository.listAudits(
      tenantId,
      status: status?.wireValue,
    );
    return audits
        .where((ComplianceAudit audit) => includeSettled || !audit.isTerminal)
        .toList(growable: false);
  }

  /// The incident reports, live incidents first.
  Future<List<IncidentReport>> incidents({
    required AuthorizationPolicy policy,
    required String tenantId,
    IncidentStatus? status,
    bool includeSettled = true,
  }) async {
    policy.require(NodexPermissions.qualityRead);
    final List<IncidentReport> incidents = await _repository.listIncidents(
      tenantId,
      status: status?.wireValue,
    );
    return incidents
        .where((IncidentReport incident) => includeSettled || incident.isLive)
        .toList(growable: false);
  }

  /// The clinical indicators, newest period first.
  Future<List<ClinicalIndicator>> indicators({
    required AuthorizationPolicy policy,
    required String tenantId,
    IndicatorStatus? status,
    bool includeSettled = true,
  }) async {
    policy.require(NodexPermissions.qualityRead);
    final List<ClinicalIndicator> indicators = await _repository.listIndicators(
      tenantId,
      status: status?.wireValue,
    );
    return indicators
        .where(
          (ClinicalIndicator indicator) =>
              includeSettled || !indicator.isTerminal,
        )
        .toList(growable: false);
  }

  /// The quality hub: the three registers with their derived markers, most
  /// needing attention first.
  Future<QualityBoard> board({
    required AuthorizationPolicy policy,
    required String tenantId,
    DateTime? now,
  }) async {
    policy.require(NodexPermissions.qualityRead);
    final DateTime asOf = (now ?? DateTime.now().toUtc()).toUtc();
    final List<ComplianceAudit> audits = await _repository.listAudits(tenantId);
    final List<IncidentReport> incidents = await _repository.listIncidents(
      tenantId,
    );
    final List<ClinicalIndicator> indicators = await _repository.listIndicators(
      tenantId,
    );
    audits.sort((ComplianceAudit a, ComplianceAudit b) {
      final int rank = _rank(a.isTerminal) - _rank(b.isTerminal);
      return rank != 0 ? rank : b.scheduledFor.compareTo(a.scheduledFor);
    });
    incidents.sort((IncidentReport a, IncidentReport b) {
      final int rank = _rank(a.isTerminal) - _rank(b.isTerminal);
      return rank != 0 ? rank : b.occurredAt.compareTo(a.occurredAt);
    });
    indicators.sort(
      (ClinicalIndicator a, ClinicalIndicator b) =>
          b.periodStart.compareTo(a.periodStart),
    );
    return QualityBoard(
      audits: audits,
      incidents: incidents,
      indicators: indicators,
      asOf: asOf,
    );
  }

  static int _rank(bool isTerminal) => isTerminal ? 1 : 0;
}
