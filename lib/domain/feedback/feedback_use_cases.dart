/// Patient feedback and grievance use cases (Module 36).
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/feedback/feedback.dart';
import 'package:nodex_hms/domain/feedback/feedback_repository.dart';

/// Captures a Net Promoter Score response.
final class RecordSurveyUseCase {
  /// Creates the use case.
  RecordSurveyUseCase({required this._repository});

  final FeedbackRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String surveyNumber,
    required int npsScore,
    required String recordedBy,
    required String createdBy,
    FeedbackTouchpoint touchpoint = FeedbackTouchpoint.opd,
    String? patientId,
    String? encounterId,
    String? comment,
    DateTime? recordedAt,
    String surveyId = '',
  }) async {
    policy.require(NodexPermissions.feedbackRecord);
    await _requireFreeNumber(tenantId, surveyNumber, exceptId: surveyId);
    return _repository.registerSurvey(
      FeedbackSurvey.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        surveyNumber: surveyNumber,
        npsScore: npsScore,
        recordedBy: recordedBy,
        createdBy: createdBy,
        touchpoint: touchpoint,
        patientId: patientId,
        encounterId: encounterId,
        comment: comment,
        recordedAt: recordedAt,
        surveyId: surveyId,
      ),
    );
  }

  /// One response number per tenant: a response filed twice would be counted
  /// twice in the net promoter score.
  Future<void> _requireFreeNumber(
    String tenantId,
    String surveyNumber, {
    required String exceptId,
  }) async {
    final List<FeedbackSurvey> surveys = await _repository.listSurveys(
      tenantId,
    );
    for (final FeedbackSurvey other in surveys) {
      if (other.surveyNumber == surveyNumber.trim() && other.id != exceptId) {
        throw const ValidationError(
          message: 'Survey response failed validation.',
          fieldErrors: <String, String>{
            'survey_number': 'That response is already recorded.',
          },
          code: 'feedback_survey_number_duplicate',
        );
      }
    }
  }
}

/// Records what was done about a detractor.
final class ActionSurveyUseCase {
  /// Creates the use case.
  ActionSurveyUseCase({required this._repository});

  final FeedbackRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required FeedbackSurvey survey,
    required String note,
    required String actionedBy,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.feedbackResolve);
    if (!surveyCanTransition(survey.status, SurveyStatus.actioned)) {
      throw AuthorizationError(
        message: survey.status.isTerminal
            ? 'This response is settled.'
            : 'That response has already been followed up.',
        code: 'feedback_survey_transition_invalid',
      );
    }
    await _repository.updateSurvey(
      survey.id,
      surveyActionChanges(note: note, actionedBy: actionedBy, at: at),
    );
  }
}

/// Withdraws a response that should not count.
final class VoidSurveyUseCase {
  /// Creates the use case.
  VoidSurveyUseCase({required this._repository});

  final FeedbackRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required FeedbackSurvey survey,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.feedbackResolve);
    if (!surveyCanTransition(survey.status, SurveyStatus.voided)) {
      throw AuthorizationError(
        message: survey.status.isTerminal
            ? 'This response is settled.'
            : 'That response can no longer be withdrawn.',
        code: 'feedback_survey_transition_invalid',
      );
    }
    await _repository.updateSurvey(
      survey.id,
      surveyVoidChanges(reason: reason, at: at),
    );
  }
}

/// Logs a grievance at the desk that took it.
final class LogComplaintUseCase {
  /// Creates the use case.
  LogComplaintUseCase({required this._repository});

  final FeedbackRepository _repository;

  /// Logs the grievance and appends the intake event to its routing history, so
  /// the history starts before the first re-routing rather than at it.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String complaintNumber,
    required String complainantName,
    required String description,
    required String loggedBy,
    required String createdBy,
    ComplaintChannel channel = ComplaintChannel.counter,
    ComplaintCategory category = ComplaintCategory.other,
    ComplaintSeverity severity = ComplaintSeverity.medium,
    String? patientId,
    String? complainantContact,
    String? routedDepartmentId,
    String? routedTo,
    DateTime? receivedAt,
    String complaintId = '',
  }) async {
    policy.require(NodexPermissions.feedbackRecord);
    await _requireFreeNumber(tenantId, complaintNumber, exceptId: complaintId);
    final String id = await _repository.registerComplaint(
      FeedbackComplaint.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        complaintNumber: complaintNumber,
        complainantName: complainantName,
        description: description,
        loggedBy: loggedBy,
        createdBy: createdBy,
        channel: channel,
        category: category,
        severity: severity,
        patientId: patientId,
        complainantContact: complainantContact,
        routedDepartmentId: routedDepartmentId,
        routedTo: routedTo,
        receivedAt: receivedAt,
        complaintId: complaintId,
      ),
    );
    await _repository.appendRoutingEvent(
      ComplaintRoutingEvent.registerRow(
        tenantId: tenantId,
        complaintId: id,
        note: 'Grievance taken at intake.',
        recordedBy: loggedBy,
        eventType: RoutingEventType.logged,
        toDepartmentId: routedDepartmentId,
        assignedTo: routedTo,
        occurredAt: receivedAt,
      ),
    );
    return id;
  }

  /// One complaint number per tenant: two files for one grievance split the
  /// deadline and the answer.
  Future<void> _requireFreeNumber(
    String tenantId,
    String complaintNumber, {
    required String exceptId,
  }) async {
    final List<FeedbackComplaint> complaints = await _repository.listComplaints(
      tenantId,
    );
    for (final FeedbackComplaint other in complaints) {
      if (other.complaintNumber == complaintNumber.trim() &&
          other.id != exceptId) {
        throw const ValidationError(
          message: 'Grievance failed validation.',
          fieldErrors: <String, String>{
            'complaint_number': 'That complaint number is already logged.',
          },
          code: 'feedback_complaint_number_duplicate',
        );
      }
    }
  }
}

/// Tells the complainant the grievance is being looked at.
final class AcknowledgeComplaintUseCase {
  /// Creates the use case.
  AcknowledgeComplaintUseCase({required this._repository});

  final FeedbackRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required FeedbackComplaint complaint,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.feedbackResolve);
    if (!complaintCanTransition(
      complaint.status,
      ComplaintStatus.acknowledged,
    )) {
      throw AuthorizationError(
        message: complaint.status.isTerminal
            ? 'This grievance is settled.'
            : 'That grievance is already acknowledged.',
        code: 'feedback_complaint_transition_invalid',
      );
    }
    await _repository.updateComplaint(
      complaint.id,
      complaintAcknowledgeChanges(at: at),
    );
  }
}

/// Sends a grievance to a department, or moves it to another one.
final class RouteComplaintUseCase {
  /// Creates the use case.
  RouteComplaintUseCase({required this._repository});

  final FeedbackRepository _repository;

  /// Routing does not move the status: the case is still the same case, it now
  /// belongs to someone else. The move itself is appended to the history.
  Future<void> call({
    required AuthorizationPolicy policy,
    required FeedbackComplaint complaint,
    required String note,
    required String recordedBy,
    String? departmentId,
    String? routedTo,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.feedbackResolve);
    if (complaint.isTerminal) {
      throw const AuthorizationError(
        message: 'This grievance is settled.',
        code: 'feedback_complaint_transition_invalid',
      );
    }
    await _repository.updateComplaint(
      complaint.id,
      complaintRouteChanges(
        departmentId: departmentId,
        routedTo: routedTo,
        at: at,
      ),
    );
    await _repository.appendRoutingEvent(
      ComplaintRoutingEvent.registerRow(
        tenantId: complaint.tenantId,
        complaintId: complaint.id,
        note: note,
        recordedBy: recordedBy,
        eventType: complaint.isRouted
            ? RoutingEventType.rerouted
            : RoutingEventType.routed,
        fromDepartmentId: complaint.routedDepartmentId,
        toDepartmentId: departmentId,
        assignedTo: routedTo,
        occurredAt: at,
      ),
    );
  }
}

/// Escalates a grievance without moving it, so the escalation is on the record.
final class EscalateComplaintUseCase {
  /// Creates the use case.
  EscalateComplaintUseCase({required this._repository});

  final FeedbackRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required FeedbackComplaint complaint,
    required String note,
    required String recordedBy,
    String? toDepartmentId,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.feedbackResolve);
    if (complaint.isTerminal) {
      throw const AuthorizationError(
        message: 'This grievance is settled.',
        code: 'feedback_complaint_transition_invalid',
      );
    }
    await _repository.appendRoutingEvent(
      ComplaintRoutingEvent.registerRow(
        tenantId: complaint.tenantId,
        complaintId: complaint.id,
        note: note,
        recordedBy: recordedBy,
        eventType: RoutingEventType.escalated,
        fromDepartmentId: complaint.routedDepartmentId,
        toDepartmentId: toDepartmentId,
        occurredAt: at,
      ),
    );
  }
}

/// Opens an investigation.
final class InvestigateComplaintUseCase {
  /// Creates the use case.
  InvestigateComplaintUseCase({required this._repository});

  final FeedbackRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required FeedbackComplaint complaint,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.feedbackResolve);
    if (!complaintCanTransition(
      complaint.status,
      ComplaintStatus.investigating,
    )) {
      throw AuthorizationError(
        message: complaint.status.isTerminal
            ? 'This grievance is settled.'
            : 'An investigation follows the acknowledgement.',
        code: 'feedback_complaint_transition_invalid',
      );
    }
    await _repository.updateComplaint(
      complaint.id,
      complaintInvestigateChanges(at: at),
    );
  }
}

/// Answers a grievance.
final class ResolveComplaintUseCase {
  /// Creates the use case.
  ResolveComplaintUseCase({required this._repository});

  final FeedbackRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required FeedbackComplaint complaint,
    required String summary,
    required String resolvedBy,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.feedbackResolve);
    if (!complaintCanTransition(complaint.status, ComplaintStatus.resolved)) {
      throw AuthorizationError(
        message: complaint.status.isTerminal
            ? 'This grievance is settled.'
            : 'A grievance is answered out of the investigation.',
        code: 'feedback_complaint_transition_invalid',
      );
    }
    await _repository.updateComplaint(
      complaint.id,
      complaintResolveChanges(summary: summary, resolvedBy: resolvedBy, at: at),
    );
  }
}

/// Closes a resolved grievance once the complainant knows the answer.
final class CloseComplaintUseCase {
  /// Creates the use case.
  CloseComplaintUseCase({required this._repository});

  final FeedbackRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required FeedbackComplaint complaint,
    required String note,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.feedbackResolve);
    if (!complaintCanTransition(complaint.status, ComplaintStatus.closed)) {
      throw AuthorizationError(
        message: complaint.status.isTerminal
            ? 'This grievance is settled.'
            : 'A grievance is closed once it has been answered.',
        code: 'feedback_complaint_transition_invalid',
      );
    }
    await _repository.updateComplaint(
      complaint.id,
      complaintCloseChanges(note: note, at: at),
    );
  }
}

/// Dismisses a grievance that has no substance.
final class DismissComplaintUseCase {
  /// Creates the use case.
  DismissComplaintUseCase({required this._repository});

  final FeedbackRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required FeedbackComplaint complaint,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.feedbackResolve);
    if (!complaintCanTransition(complaint.status, ComplaintStatus.dismissed)) {
      throw AuthorizationError(
        message: complaint.status.isTerminal
            ? 'This grievance is settled.'
            : 'That grievance can no longer be dismissed.',
        code: 'feedback_complaint_transition_invalid',
      );
    }
    await _repository.updateComplaint(
      complaint.id,
      complaintDismissChanges(reason: reason, at: at),
    );
  }
}

/// Withdraws a grievance that was filed in error.
final class VoidComplaintUseCase {
  /// Creates the use case.
  VoidComplaintUseCase({required this._repository});

  final FeedbackRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required FeedbackComplaint complaint,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.feedbackResolve);
    if (!complaintCanTransition(complaint.status, ComplaintStatus.voided)) {
      throw AuthorizationError(
        message: complaint.status.isTerminal ? 'This grievance is settled.' : 'Only a freshly logged grievance is withdrawn; an old one is dismissed.',
        code: 'feedback_complaint_transition_invalid',
      );
    }
    await _repository.updateComplaint(
      complaint.id,
      complaintVoidChanges(reason: reason, at: at),
    );
  }
}

/// The feedback board as the screen shows it.
@immutable
final class FeedbackBoard {
  /// Creates a board snapshot.
  const FeedbackBoard({
    required this.surveys,
    required this.complaints,
    required this.asOf,
  });

  /// Survey responses, newest first.
  final List<FeedbackSurvey> surveys;

  /// Grievances, live first and newest received first.
  final List<FeedbackComplaint> complaints;

  /// The instant the derived markers were computed at.
  final DateTime asOf;

  /// The responses that count towards the score: neither withdrawn nor
  /// anonymous-only in any special way, simply the ones that stand.
  List<FeedbackSurvey> get countedSurveys => surveys
      .where((FeedbackSurvey survey) => survey.status != SurveyStatus.voided)
      .toList(growable: false);

  /// The derived net promoter score over the counted responses, or null when
  /// nothing stands to be counted.
  double? get nps =>
      netPromoterScore(countedSurveys.map((FeedbackSurvey s) => s.npsScore));

  /// How many promoters, passives and detractors the responses contain.
  Map<NpsBand, int> get bandCounts {
    final Map<NpsBand, int> counts = <NpsBand, int>{
      NpsBand.promoter: 0,
      NpsBand.passive: 0,
      NpsBand.detractor: 0,
    };
    for (final FeedbackSurvey survey in countedSurveys) {
      counts[survey.band] = (counts[survey.band] ?? 0) + 1;
    }
    return counts;
  }

  /// Whether a detractor has gone unfollowed past the window.
  bool followUpOverdue(FeedbackSurvey survey) =>
      isSurveyFollowUpOverdue(survey: survey, now: asOf);

  /// Whether a grievance is past its acknowledgement deadline.
  bool acknowledgementOverdue(FeedbackComplaint complaint) =>
      isComplaintAcknowledgementOverdue(complaint: complaint, now: asOf);

  /// Whether a grievance is past its severity resolution deadline.
  bool resolutionOverdue(FeedbackComplaint complaint) =>
      isComplaintResolutionOverdue(complaint: complaint, now: asOf);

  /// Whether either deadline on a grievance has been missed.
  bool slaBreached(FeedbackComplaint complaint) =>
      isComplaintSlaBreached(complaint: complaint, now: asOf);

  /// The detractors still waiting on a follow-up.
  List<FeedbackSurvey> get detractorsAwaitingFollowUp => surveys
      .where(
        (FeedbackSurvey survey) =>
            survey.status == SurveyStatus.recorded && survey.isDetractor,
      )
      .toList(growable: false);

  /// The grievances still waiting to be acknowledged.
  List<FeedbackComplaint> get unacknowledgedComplaints => complaints
      .where((FeedbackComplaint complaint) => complaint.isUnacknowledged)
      .toList(growable: false);

  /// The grievances that are still to be answered.
  List<FeedbackComplaint> get openComplaints => complaints
      .where((FeedbackComplaint complaint) => complaint.status.awaitsResolution)
      .toList(growable: false);

  /// Whether anything on the board needs attention.
  bool get hasOverdue =>
      surveys.any(followUpOverdue) || complaints.any(slaBreached);
}

/// Reads the feedback registers and their derived markers.
final class ReadFeedbackHubUseCase {
  /// Creates the use case.
  ReadFeedbackHubUseCase({required this._repository});

  final FeedbackRepository _repository;

  /// The survey responses, newest first.
  Future<List<FeedbackSurvey>> surveys({
    required AuthorizationPolicy policy,
    required String tenantId,
    SurveyStatus? status,
    bool includeSettled = true,
  }) async {
    policy.require(NodexPermissions.feedbackRead);
    final List<FeedbackSurvey> surveys = await _repository.listSurveys(
      tenantId,
      status: status?.wireValue,
    );
    return surveys
        .where((FeedbackSurvey survey) => includeSettled || !survey.isTerminal)
        .toList(growable: false);
  }

  /// The grievances, live first and newest received first.
  Future<List<FeedbackComplaint>> complaints({
    required AuthorizationPolicy policy,
    required String tenantId,
    ComplaintStatus? status,
    String? departmentId,
    bool includeSettled = true,
  }) async {
    policy.require(NodexPermissions.feedbackRead);
    final List<FeedbackComplaint> complaints = await _repository.listComplaints(
      tenantId,
      status: status?.wireValue,
      departmentId: departmentId,
    );
    return complaints
        .where(
          (FeedbackComplaint complaint) => includeSettled || complaint.isLive,
        )
        .toList(growable: false);
  }

  /// The routing history of one grievance, oldest first.
  Future<List<ComplaintRoutingEvent>> routingHistory({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String complaintId,
  }) async {
    policy.require(NodexPermissions.feedbackRead);
    return _repository.listRoutingEvents(tenantId, complaintId: complaintId);
  }

  /// The board: the derived net promoter score, the unresolved detractors and
  /// the grievances whose deadlines have passed.
  Future<FeedbackBoard> board({
    required AuthorizationPolicy policy,
    required String tenantId,
    DateTime? now,
  }) async {
    policy.require(NodexPermissions.feedbackRead);
    final DateTime asOf = (now ?? DateTime.now().toUtc()).toUtc();
    final List<FeedbackSurvey> surveys = await _repository.listSurveys(
      tenantId,
    );
    final List<FeedbackComplaint> complaints = await _repository.listComplaints(
      tenantId,
    );
    surveys.sort(
      (FeedbackSurvey a, FeedbackSurvey b) =>
          b.recordedAt.compareTo(a.recordedAt),
    );
    complaints.sort((FeedbackComplaint a, FeedbackComplaint b) {
      final int rank = (a.isTerminal ? 1 : 0) - (b.isTerminal ? 1 : 0);
      return rank != 0 ? rank : b.receivedAt.compareTo(a.receivedAt);
    });
    return FeedbackBoard(surveys: surveys, complaints: complaints, asOf: asOf);
  }
}
