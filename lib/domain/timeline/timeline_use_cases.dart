/// Timeline use cases (Module 50).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/domain/timeline/patient_timeline.dart';
import 'package:nodex_hms/domain/timeline/timeline_repository.dart';

/// Reads a patient's journey.
///
/// The journey is the patient's own record, so it is read under the same
/// permission as the patient's chart rather than a permission of its own.
final class ReadPatientTimelineUseCase {
  /// Creates the use case.
  const ReadPatientTimelineUseCase({required this._repository});

  final TimelineRepository _repository;

  /// Reads the journey.
  Future<PatientTimeline> call({
    required AuthorizationPolicy policy,
    required String patientId,
  }) async {
    policy.require(NodexPermissions.patientRead);
    return _repository.readTimeline(patientId);
  }
}
