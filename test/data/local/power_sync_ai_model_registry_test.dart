/// Tests for the PowerSync-backed AI registry adapter.
///
/// The Orchestrator reads model and routing configuration from the local
/// projection. These tests pin the two shapes it depends on: a row becomes a
/// [ModelRecord] or [RoutingPolicy] without losing the governance fields, and a
/// missing row is null rather than an invented default.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/ai/model_registry/model_registry.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/data/local/power_sync_ai_model_registry.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

final class _FakeStore implements PatientLocalStore {
  _FakeStore({
    this.modelRows = const <Map<String, Object?>>[],
    this.policyRows = const <Map<String, Object?>>[],
  });

  final List<Map<String, Object?>> modelRows;
  final List<Map<String, Object?>> policyRows;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    if (sql.contains('ai_model_registry')) {
      if (sql.contains('WHERE model_key')) {
        return modelRows
            .where(
              (Map<String, Object?> row) =>
                  row['model_key'] == parameters.first,
            )
            .toList(growable: false);
      }
      return modelRows;
    }
    if (sql.contains('ai_routing_policies')) return policyRows;
    return const <Map<String, Object?>>[];
  }

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async => null;

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {}

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> changes,
  ) async {}
}

Map<String, Object?> _modelRow({
  String modelKey = 'reasoning_cloud_primary',
  String lifecycle = 'approved',
  String evaluation = 'passed',
}) => <String, Object?>{
  'id': 'model-row-1',
  'model_key': modelKey,
  'provider': 'open_router',
  'display_name': 'Reasoning Cloud Primary',
  'model_revision': 'rev-1',
  'modality': '["text"]',
  'clinical_risk_tier': 'high',
  'privacy_class': 'phi_permitted',
  'lifecycle_status': lifecycle,
  'evaluation_status': evaluation,
  'evaluation_set_revision': 'acceptance-2026.09',
  'approved_by': 'user-1',
  'approved_at': '2026-09-18T12:00:00.000Z',
  'enabled': 0,
  'priority': 10,
};

Map<String, Object?> _policyRow() => <String, Object?>{
  'engine_key': 'ai_triage_advisory',
  'environment': 'production',
  'primary_model_key': 'reasoning_cloud_primary',
  'secondary_model_key': null,
  'tertiary_model_key': null,
  'offline_fallback_model_key': 'reasoning_local_offline',
  'timeout_ms': 12000,
  'max_attempts': 1,
  'circuit_breaker_threshold': 3,
  'circuit_breaker_seconds': 300,
  'require_structured_output': 1,
  'require_human_review': 1,
  'allow_manual_fallback': 1,
  'minimum_risk_capability': 'high',
  'policy_revision': 'policy-2026.09.01',
  'enabled': 1,
};

NodexLogger _logger() => NodexLogger(
  sinks: <NodexLogSink>[InMemoryLogSink()],
  minimumLevel: NodexLogLevel.trace,
);

void main() {
  test('a model row becomes a governance-aware record', () async {
    final PowerSyncAiModelRegistry registry = PowerSyncAiModelRegistry(
      store: _FakeStore(
        modelRows: <Map<String, Object?>>[_modelRow()],
        policyRows: <Map<String, Object?>>[_policyRow()],
      ),
      logger: _logger(),
    );

    final ModelRecord? model = await registry.model('reasoning_cloud_primary');
    expect(model, isNotNull);
    expect(model!.id, 'model-row-1');
    expect(model.lifecycleStatus, ModelLifecycleStatus.approved);
    expect(model.evaluationSetRevision, 'acceptance-2026.09');
    expect(model.approvedBy, 'user-1');
    expect(model.isEligibleForClinicalExecution, isFalse);
  });

  test('an unregistered model is null, not a default', () async {
    final PowerSyncAiModelRegistry registry = PowerSyncAiModelRegistry(
      store: _FakeStore(),
      logger: _logger(),
    );
    expect(await registry.model('missing_model'), isNull);
  });

  test('a routing row becomes the engine policy', () async {
    final PowerSyncAiModelRegistry registry = PowerSyncAiModelRegistry(
      store: _FakeStore(policyRows: <Map<String, Object?>>[_policyRow()]),
      logger: _logger(),
    );
    final RoutingPolicy? policy = await registry.policy('ai_triage_advisory');
    expect(policy, isNotNull);
    expect(policy!.primaryModelKey, 'reasoning_cloud_primary');
    expect(policy.offlineFallbackModelKey, 'reasoning_local_offline');
    expect(policy.minimumRiskCapability.name, 'high');
    expect(policy.policyRevision, 'policy-2026.09.01');
  });

  test('all models are returned in the stored order', () async {
    final PowerSyncAiModelRegistry registry = PowerSyncAiModelRegistry(
      store: _FakeStore(
        modelRows: <Map<String, Object?>>[
          _modelRow(modelKey: 'a_model'),
          _modelRow(modelKey: 'b_model'),
        ],
      ),
      logger: _logger(),
    );
    final List<ModelRecord> models = await registry.allModels();
    expect(models.map((ModelRecord m) => m.modelKey), <String>[
      'a_model',
      'b_model',
    ]);
  });
}
