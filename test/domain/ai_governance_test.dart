/// Tests for AI model governance (Module 39).
///
/// The registry's invariant is that an available model is not an approved
/// model. These tests pin the three facts an approval must carry — a passed
/// evaluation, a recorded acceptance set and a named administrator — and the
/// online-only rule that keeps an offline device from approving anything.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/ai/contracts/ai_contracts.dart';
import 'package:nodex_hms/ai/model_registry/model_registry.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/ai_governance/ai_governance_repository.dart';

/// A repository that records governance writes.
final class _FakeAiGovernanceRepository implements AiGovernanceRepository {
  _FakeAiGovernanceRepository(this.models);

  final List<ModelRecord> models;
  final List<Map<String, Object?>> updates = <Map<String, Object?>>[];
  final List<String> updatedIds = <String>[];

  @override
  Future<List<ModelRecord>> listModels() async => models;

  @override
  Future<ModelRecord?> modelById(String id) async {
    for (final ModelRecord model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  @override
  Future<void> updateModelGovernance(
    String id,
    Map<String, Object?> changes,
  ) async {
    updatedIds.add(id);
    updates.add(changes);
  }
}

AuthorizationPolicy _policy(
  Set<String> permissions, {
  ConnectivityState connectivity = ConnectivityState.online,
}) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'user-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.hospitalSuperAdmin},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: connectivity,
  );
}

ModelRecord _model({
  String id = 'model-row-1',
  ModelLifecycleStatus lifecycle = ModelLifecycleStatus.evaluating,
  ModelEvaluationStatus evaluation = ModelEvaluationStatus.passed,
  String? revision = 'acceptance-2026.09',
  bool enabled = false,
}) => ModelRecord(
  id: id,
  modelKey: 'reasoning_cloud_primary',
  provider: 'open_router',
  displayName: 'Reasoning Cloud Primary',
  modelRevision: 'rev-1',
  modalities: const <Modality>{Modality.text},
  clinicalRiskTier: ClinicalRiskLevel.high,
  privacyClass: DataPrivacyClass.phiPermitted,
  lifecycleStatus: lifecycle,
  evaluationStatus: evaluation,
  enabled: enabled,
  evaluationSetRevision: revision,
);

void main() {
  group('reading the registry', () {
    test('it requires ai_governance.read', () async {
      await expectLater(
        ReadAiGovernanceUseCase(
          repository: _FakeAiGovernanceRepository(const <ModelRecord>[]),
        ).call(policy: _policy(<String>{NodexPermissions.patientRead})),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('it returns the registered models to an auditor', () async {
      final _FakeAiGovernanceRepository repository =
          _FakeAiGovernanceRepository(<ModelRecord>[_model()]);
      final List<ModelRecord> models = await ReadAiGovernanceUseCase(
        repository: repository,
      ).call(policy: _policy(<String>{NodexPermissions.aiGovernanceRead}));
      expect(models.single.modelKey, 'reasoning_cloud_primary');
    });
  });

  group('approving a model', () {
    test('it refuses an offline approval', () async {
      await expectLater(
        ApproveAiModelUseCase(
          repository: _FakeAiGovernanceRepository(<ModelRecord>[_model()]),
        ).call(
          policy: _policy(<String>{
            NodexPermissions.aiGovernanceAdminister,
          }, connectivity: ConnectivityState.offline),
          model: _model(),
          approvedBy: 'user-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            AuthorizationDenialReason.requiresOnlineRevalidation.name,
          ),
        ),
      );
    });

    test('it requires ai_governance.administer', () async {
      await expectLater(
        ApproveAiModelUseCase(
          repository: _FakeAiGovernanceRepository(<ModelRecord>[_model()]),
        ).call(
          policy: _policy(<String>{NodexPermissions.aiGovernanceRead}),
          model: _model(),
          approvedBy: 'user-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a discovered model cannot skip evaluation', () async {
      await expectLater(
        ApproveAiModelUseCase(
          repository: _FakeAiGovernanceRepository(<ModelRecord>[]),
        ).call(
          policy: _policy(<String>{NodexPermissions.aiGovernanceAdminister}),
          model: _model(lifecycle: ModelLifecycleStatus.discovered),
          approvedBy: 'user-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'ai_model_approval_state_invalid',
          ),
        ),
      );
    });

    test('a failed evaluation cannot be approved', () async {
      await expectLater(
        ApproveAiModelUseCase(
          repository: _FakeAiGovernanceRepository(<ModelRecord>[]),
        ).call(
          policy: _policy(<String>{NodexPermissions.aiGovernanceAdminister}),
          model: _model(evaluation: ModelEvaluationStatus.failed),
          approvedBy: 'user-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'ai_model_evaluation_incomplete',
          ),
        ),
      );
    });

    test(
      'a passed evaluation without a recorded set cannot be approved',
      () async {
        await expectLater(
          ApproveAiModelUseCase(
            repository: _FakeAiGovernanceRepository(<ModelRecord>[]),
          ).call(
            policy: _policy(<String>{NodexPermissions.aiGovernanceAdminister}),
            model: _model(revision: null),
            approvedBy: 'user-1',
          ),
          throwsA(
            isA<ValidationError>().having(
              (ValidationError error) => error.code,
              'code',
              'ai_model_evaluation_set_missing',
            ),
          ),
        );
      },
    );

    test('a successful approval names the approver and the moment', () async {
      final _FakeAiGovernanceRepository repository =
          _FakeAiGovernanceRepository(<ModelRecord>[_model()]);
      await ApproveAiModelUseCase(repository: repository).call(
        policy: _policy(<String>{NodexPermissions.aiGovernanceAdminister}),
        model: _model(),
        approvedBy: 'user-1',
        at: DateTime.utc(2026, 9, 18, 12),
      );
      expect(repository.updatedIds, <String>['model-row-1']);
      expect(repository.updates.single, <String, Object?>{
        'lifecycle_status': 'approved',
        'approved_by': 'user-1',
        'approved_at': '2026-09-18T12:00:00.000Z',
        'updated_at': '2026-09-18T12:00:00.000Z',
      });
    });
  });

  group('activating a model', () {
    test('an approved model becomes active and enabled', () async {
      final _FakeAiGovernanceRepository repository =
          _FakeAiGovernanceRepository(<ModelRecord>[]);
      await ActivateAiModelUseCase(repository: repository).call(
        policy: _policy(<String>{NodexPermissions.aiGovernanceAdminister}),
        model: _model(lifecycle: ModelLifecycleStatus.approved),
        at: DateTime.utc(2026, 9, 18, 12),
      );
      expect(repository.updates.single, <String, Object?>{
        'lifecycle_status': 'active',
        'enabled': 1,
        'updated_at': '2026-09-18T12:00:00.000Z',
      });
    });

    test('an evaluating model cannot be activated', () async {
      await expectLater(
        ActivateAiModelUseCase(
          repository: _FakeAiGovernanceRepository(<ModelRecord>[]),
        ).call(
          policy: _policy(<String>{NodexPermissions.aiGovernanceAdminister}),
          model: _model(),
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'ai_model_activation_state_invalid',
          ),
        ),
      );
    });
  });

  group('model row', () {
    test('it carries the row id and the approval evidence', () {
      final ModelRecord model = ModelRecord.fromRow(<String, Object?>{
        'id': 'model-row-1',
        'model_key': 'reasoning_cloud_primary',
        'provider': 'open_router',
        'display_name': 'Reasoning Cloud Primary',
        'model_revision': 'rev-1',
        'modality': '["text"]',
        'clinical_risk_tier': 'high',
        'privacy_class': 'phi_permitted',
        'lifecycle_status': 'approved',
        'evaluation_status': 'passed',
        'evaluation_set_revision': 'acceptance-2026.09',
        'approved_by': 'user-1',
        'approved_at': '2026-09-18T12:00:00.000Z',
        'enabled': 0,
      });
      expect(model.id, 'model-row-1');
      expect(model.approvedBy, 'user-1');
      expect(model.approvedAt, DateTime.utc(2026, 9, 18, 12));
      expect(model.isEligibleForClinicalExecution, isFalse);
    });
  });
}
