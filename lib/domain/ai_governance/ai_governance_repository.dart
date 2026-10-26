/// AI model governance repository and use cases (Module 39).
///
/// The registry is global configuration, but approval is an act by a named
/// administrator. The use cases check the permission the specification marks
/// online-only, check that the evaluation evidence exists, and then write the
/// transition locally. The server re-checks all three through RLS and the
/// lifecycle trigger; a rejected upload reconciles back to server state rather
/// than being merged.
library;

import 'package:nodex_hms/ai/model_registry/model_registry.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Repository operations for the AI governance surface.
abstract interface class AiGovernanceRepository {
  /// Every registered model, in governance priority order.
  Future<List<ModelRecord>> listModels();

  /// One model by local row id, or null when it has been retired and removed.
  Future<ModelRecord?> modelById(String id);

  /// Writes governance columns of one model.
  Future<void> updateModelGovernance(String id, Map<String, Object?> changes);
}

/// PowerSync-backed AI governance repository.
final class DefaultAiGovernanceRepository implements AiGovernanceRepository {
  /// Creates a repository over a local store.
  DefaultAiGovernanceRepository({required this._store, required this._logger});

  static const String _module = 'domain.ai_governance';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<ModelRecord>> listModels() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.aiModelRegistry} '
        'ORDER BY priority, model_key',
        const <Object?>[],
      );
      return rows.map(ModelRecord.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ai_governance.list_models');
    }
  }

  @override
  Future<ModelRecord?> modelById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.aiModelRegistry,
        id,
      );
      return row == null ? null : ModelRecord.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ai_governance.model_by_id');
    }
  }

  @override
  Future<void> updateModelGovernance(
    String id,
    Map<String, Object?> changes,
  ) async {
    try {
      await _store.update(LocalTables.aiModelRegistry, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ai_governance.update_model');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'AI governance repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}

/// Reads the registered models for the governance surface.
final class ReadAiGovernanceUseCase {
  /// Creates the use case.
  const ReadAiGovernanceUseCase({required this._repository});

  final AiGovernanceRepository _repository;

  /// Every registered model, read-only and available offline.
  Future<List<ModelRecord>> call({required AuthorizationPolicy policy}) async {
    policy.require(NodexPermissions.aiGovernanceRead);
    return _repository.listModels();
  }
}

/// Approves a model whose evaluation has passed.
final class ApproveAiModelUseCase {
  /// Creates the use case.
  const ApproveAiModelUseCase({required this._repository});

  final AiGovernanceRepository _repository;

  /// Moves an evaluated model to APPROVED, naming [approvedBy] as approver.
  Future<void> call({
    required AuthorizationPolicy policy,
    required ModelRecord model,
    required String approvedBy,
    DateTime? at,
  }) async {
    // Online-only: the catalogue marks ai_governance.administer as requiring
    // revalidation, so an offline snapshot can never approve a model.
    policy.require(NodexPermissions.aiGovernanceAdminister);
    if (model.id.isEmpty) {
      throw const ValidationError(
        message: 'That model has not been persisted on this device yet.',
        code: 'ai_model_not_persisted',
      );
    }
    if (model.lifecycleStatus != ModelLifecycleStatus.evaluating) {
      throw AuthorizationError(
        message: model.lifecycleStatus == ModelLifecycleStatus.discovered
            ? 'That model has not entered evaluation, so it cannot be approved.'
            : 'That model is not awaiting approval.',
        code: 'ai_model_approval_state_invalid',
      );
    }
    if (model.evaluationStatus != ModelEvaluationStatus.passed) {
      throw const ValidationError(
        message:
            'The evaluation has not passed. A model cannot be approved on '
            'provider availability alone.',
        code: 'ai_model_evaluation_incomplete',
      );
    }
    final String revision = model.evaluationSetRevision?.trim() ?? '';
    if (revision.isEmpty) {
      throw const ValidationError(
        message:
            'The evaluation did not record the acceptance-set revision, so '
            'the evidence cannot be reproduced.',
        code: 'ai_model_evaluation_set_missing',
      );
    }
    final String approver = approvedBy.trim();
    if (approver.isEmpty) {
      throw const ValidationError(
        message: 'An approval must name the administrator who gave it.',
        code: 'ai_model_approver_missing',
      );
    }

    final DateTime now = (at ?? DateTime.now()).toUtc();
    await _repository.updateModelGovernance(model.id, <String, Object?>{
      'lifecycle_status': ModelLifecycleStatus.approved.wireValue,
      'approved_by': approver,
      'approved_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }
}

/// Activates an approved model so it may receive clinical traffic.
final class ActivateAiModelUseCase {
  /// Creates the use case.
  const ActivateAiModelUseCase({required this._repository});

  final AiGovernanceRepository _repository;

  /// Moves an approved model to ACTIVE and enables it.
  Future<void> call({
    required AuthorizationPolicy policy,
    required ModelRecord model,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.aiGovernanceAdminister);
    if (model.id.isEmpty) {
      throw const ValidationError(
        message: 'That model has not been persisted on this device yet.',
        code: 'ai_model_not_persisted',
      );
    }
    if (model.lifecycleStatus != ModelLifecycleStatus.approved) {
      throw AuthorizationError(
        message: model.lifecycleStatus == ModelLifecycleStatus.active
            ? 'That model is already serving clinical traffic.'
            : 'That model has not been approved, so it cannot be activated.',
        code: 'ai_model_activation_state_invalid',
      );
    }
    if (model.evaluationStatus != ModelEvaluationStatus.passed ||
        (model.evaluationSetRevision?.trim().isEmpty ?? true)) {
      throw const ValidationError(
        message:
            'Activation needs a passed evaluation against a recorded '
            'acceptance-set revision.',
        code: 'ai_model_evaluation_incomplete',
      );
    }

    final DateTime now = (at ?? DateTime.now()).toUtc();
    await _repository.updateModelGovernance(model.id, <String, Object?>{
      'lifecycle_status': ModelLifecycleStatus.active.wireValue,
      'enabled': 1,
      'updated_at': now.toIso8601String(),
    });
  }
}
