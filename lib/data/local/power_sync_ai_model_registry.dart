/// AI model and routing configuration over the replicated local projection.
///
/// The Orchestrator must decide what may run without a network call, and a
/// governance decision made on one device must reach every device through
/// replication. Reading the local tables is therefore the only correct source:
/// an empty registry is a truthful "nothing is approved", not a reason to fall
/// back to a provider catalogue.
library;

import 'package:nodex_hms/ai/model_registry/model_registry.dart';
import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// [AiModelRegistry] over the encrypted local database.
final class PowerSyncAiModelRegistry implements AiModelRegistry {
  /// Creates a registry over a local store.
  PowerSyncAiModelRegistry({required this._store, required this._logger});

  static const String _module = 'data.local.ai_registry';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<ModelRecord?> model(String modelKey) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.aiModelRegistry} '
        'WHERE model_key = ? LIMIT 1',
        <Object?>[modelKey],
      );
      return rows.isEmpty ? null : ModelRecord.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ai_registry.model');
    }
  }

  @override
  Future<RoutingPolicy?> policy(String engineKey) async {
    try {
      // Production is preferred when several environments are replicated. A
      // staging policy must never govern a clinical request merely because it
      // sorted first.
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.aiRoutingPolicies} '
        'WHERE engine_key = ? '
        "ORDER BY CASE environment WHEN 'production' THEN 0 "
        "WHEN 'staging' THEN 1 ELSE 2 END, enabled DESC, updated_at DESC "
        'LIMIT 1',
        <Object?>[engineKey],
      );
      return rows.isEmpty ? null : RoutingPolicy.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ai_registry.policy');
    }
  }

  @override
  Future<List<ModelRecord>> allModels() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.aiModelRegistry} '
        'ORDER BY priority, model_key',
        const <Object?>[],
      );
      return rows.map(ModelRecord.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ai_registry.all_models');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'AI registry read failed.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
