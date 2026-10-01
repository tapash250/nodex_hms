/// Problem-list and scribe-draft repository contract and local implementation
/// (Module 16).
///
/// The problem list and its resolutions are stored. The occupancy of a scribe
/// draft is never inferred: what a clinician accepted is recorded explicitly, so
/// the record cannot imply a section was signed off when it was not.
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/encounters/problem_list.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

/// Read and write access to the problem list and ambient scribe drafts.
abstract interface class ProblemListRepository {
  /// A patient's problem list, active first then most recent.
  Future<List<ClinicalProblem>> problemsForPatient(
    String patientId, {
    bool activeOnly = false,
  });

  /// One problem by id.
  Future<ClinicalProblem?> problemById(String id);

  /// Records a new problem and returns its id.
  Future<String> recordProblem(Map<String, Object?> row);

  /// Applies resolution changes to a problem.
  Future<void> resolveProblem(String id, Map<String, Object?> changes);

  /// Every scribe draft raised against an encounter, newest first.
  Future<List<ScribeDraft>> draftsForEncounter(String encounterId);

  /// One scribe draft by id.
  Future<ScribeDraft?> draftById(String id);

  /// Scribe drafts still awaiting a clinician.
  Future<List<ScribeDraft>> pendingDrafts(String tenantId);

  /// Records a fresh dictation and returns its id.
  Future<String> recordDraft(Map<String, Object?> row);

  /// Applies a review decision to a draft.
  Future<void> reviewDraft(String id, Map<String, Object?> changes);
}

/// Default repository over the encrypted local projection.
final class DefaultProblemListRepository implements ProblemListRepository {
  const DefaultProblemListRepository({
    required this._store,
    required this._logger,
  });

  static const String _module = 'domain.encounters.problems';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) {
      throw error;
    }
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Problem-list repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }

  @override
  Future<List<ClinicalProblem>> problemsForPatient(
    String patientId, {
    bool activeOnly = false,
  }) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.clinicalProblems} '
        'where patient_id = ?'
        '${activeOnly ? " and clinical_status = 'active'" : ''} '
        'order by clinical_status asc, created_at desc',
        <Object?>[patientId],
      );
      return rows.map(ClinicalProblem.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'problems.forPatient');
    }
  }

  @override
  Future<ClinicalProblem?> problemById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.clinicalProblems,
        id,
      );
      return row == null ? null : ClinicalProblem.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'problems.byId');
    }
  }

  @override
  Future<String> recordProblem(Map<String, Object?> row) async {
    try {
      final String id = const Uuid().v4();
      await _store.insert(LocalTables.clinicalProblems, <String, Object?>{
        'id': id,
        ...row,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'problems.record');
    }
  }

  @override
  Future<void> resolveProblem(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.clinicalProblems, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'problems.resolve');
    }
  }

  @override
  Future<List<ScribeDraft>> draftsForEncounter(String encounterId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.encounterScribeDrafts} '
        'where encounter_id = ? order by created_at desc',
        <Object?>[encounterId],
      );
      return rows.map(ScribeDraft.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'scribe.forEncounter');
    }
  }

  @override
  Future<ScribeDraft?> draftById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.encounterScribeDrafts,
        id,
      );
      return row == null ? null : ScribeDraft.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'scribe.byId');
    }
  }

  @override
  Future<List<ScribeDraft>> pendingDrafts(String tenantId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.encounterScribeDrafts} '
        "where tenant_id = ? and status = 'pending_review' "
        'order by created_at desc',
        <Object?>[tenantId],
      );
      return rows.map(ScribeDraft.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'scribe.pending');
    }
  }

  @override
  Future<String> recordDraft(Map<String, Object?> row) async {
    try {
      final String id = const Uuid().v4();
      await _store.insert(LocalTables.encounterScribeDrafts, <String, Object?>{
        'id': id,
        ...row,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'scribe.record');
    }
  }

  @override
  Future<void> reviewDraft(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.encounterScribeDrafts, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'scribe.review');
    }
  }
}
