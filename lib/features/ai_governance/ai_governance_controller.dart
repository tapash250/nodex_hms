/// AI governance controller (Module 39).
///
/// The controller reads the replicated registry and performs the two governance
/// acts the product exposes: approve an evaluated model and activate an approved
/// one. Both are online-only because the permission is online-only; an offline
/// tap is refused by the authorization policy before it reaches the queue.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/ai/model_registry/model_registry.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Registered models for the governance surface.
final AsyncNotifierProvider<AiGovernanceNotifier, List<ModelRecord>>
aiGovernanceModelsProvider =
    AsyncNotifierProvider.autoDispose<AiGovernanceNotifier, List<ModelRecord>>(
      AiGovernanceNotifier.new,
    );

/// Reads and transitions the registered models.
final class AiGovernanceNotifier extends AsyncNotifier<List<ModelRecord>> {
  @override
  Future<List<ModelRecord>> build() async {
    final SessionState session = ref.watch(sessionProvider);
    return _read(session.authorization);
  }

  /// Approves [model] as [approvedBy].
  Future<void> approve(ModelRecord model, {required String approvedBy}) async {
    final SessionState session = ref.read(sessionProvider);
    await ref
        .read(approveAiModelUseCaseProvider)
        .call(
          policy: session.authorization,
          model: model,
          approvedBy: approvedBy,
        );
    await _refresh(session.authorization);
  }

  /// Activates [model] so it may receive clinical traffic.
  Future<void> activate(ModelRecord model) async {
    final SessionState session = ref.read(sessionProvider);
    await ref
        .read(activateAiModelUseCaseProvider)
        .call(policy: session.authorization, model: model);
    await _refresh(session.authorization);
  }

  Future<List<ModelRecord>> _read(AuthorizationPolicy policy) {
    return ref.read(readAiGovernanceUseCaseProvider).call(policy: policy);
  }

  Future<void> _refresh(AuthorizationPolicy policy) async {
    state = AsyncData(await _read(policy));
  }
}
