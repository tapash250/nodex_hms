/// Practitioner directory use cases (Module 08).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/roster/practitioner.dart';
import 'package:nodex_hms/domain/roster/practitioner_repository.dart';

/// Registers a practitioner into the directory.
final class RecordPractitionerProfileUseCase {
  /// Creates the use case.
  RecordPractitionerProfileUseCase({required this._repository});

  final PractitionerRepository _repository;

  /// Records the entry locally, gated on directory administration.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    String profileId = '',
    required String userId,
    required String facilityId,
    required String specialty,
    int yearsExperience = 0,
    bool acceptingReferrals = true,
    String? departmentId,
    String? subSpecialty,
    String? credentials,
    String? registrationNo,
    String? consultationRoomId,
  }) async {
    policy.require(NodexPermissions.staffDirectoryAdminister);
    final Map<String, Object?> row = PractitionerProfile.registerRow(
      tenantId: tenantId,
      userId: userId,
      facilityId: facilityId,
      specialty: specialty,
      yearsExperience: yearsExperience,
      acceptingReferrals: acceptingReferrals,
      departmentId: departmentId,
      subSpecialty: subSpecialty,
      credentials: credentials,
      registrationNo: registrationNo,
      consultationRoomId: consultationRoomId,
      profileId: profileId,
    );
    return _repository.registerProfile(row);
  }
}

/// Updates a practitioner's directory facts (sub-specialty, credentials,
/// referral acceptance, consultation room).
final class UpdatePractitionerProfileUseCase {
  /// Creates the use case.
  UpdatePractitionerProfileUseCase({required this._repository});

  final PractitionerRepository _repository;

  /// Applies the edits, gated on administration and only on mutable rows.
  Future<void> call({
    required AuthorizationPolicy policy,
    required PractitionerProfile profile,
    bool acceptingReferrals = true,
    String? subSpecialty,
    String? credentials,
    String? consultationRoomId,
  }) async {
    policy.require(NodexPermissions.staffDirectoryAdminister);
    if (!profile.isEditable) {
      throw const AuthorizationError(
        message: 'A retired practitioner directory entry is frozen as a credential record.',
        code: 'practitioner_retired_immutable',
      );
    }
    await _repository.updateProfile(
      profile.id,
      practitionerChanges(
        acceptingReferrals: acceptingReferrals,
        subSpecialty: subSpecialty,
        credentials: credentials,
        consultationRoomId: consultationRoomId,
        updatedBy: profile.userId,
      ),
    );
  }
}

/// Retires a practitioner. The profile freezes as the credential record for
/// historical referrals; re-registration creates a fresh entry.
final class RetirePractitionerProfileUseCase {
  /// Creates the use case.
  RetirePractitionerProfileUseCase({required this._repository});

  final PractitionerRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required PractitionerProfile profile,
    required String retiredBy,
    required String reason,
  }) async {
    policy.require(NodexPermissions.staffDirectoryAdminister);
    if (profile.status == PractitionerStatus.retired) {
      throw const AuthorizationError(
        message: 'This practitioner is already retired.',
        code: 'practitioner_already_retired',
      );
    }
    final Map<String, Object?> changes = practitionerRetirementChanges(
      retiredBy: retiredBy,
      reason: reason,
    );
    await _repository.updateProfile(profile.id, changes);
  }
}

/// Records an on-call rotation for a practitioner.
final class ScheduleOnCallRotationUseCase {
  /// Creates the use case.
  ScheduleOnCallRotationUseCase({required this._repository});

  final PractitionerRepository _repository;

  /// Schedules the rotation, gated on directory administration.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String practitionerId,
    required OnCallType rotationType,
    required DateTime startsAt,
    required DateTime endsAt,
    required String recordedBy,
    String? location,
    String? contactNote,
    String rotationId = '',
  }) async {
    policy.require(NodexPermissions.staffDirectoryAdminister);
    final Map<String, Object?> row = OnCallRotation.eventRow(
      tenantId: tenantId,
      practitionerId: practitionerId,
      rotationType: rotationType,
      startsAt: startsAt,
      endsAt: endsAt,
      recordedBy: recordedBy,
      location: location,
      contactNote: contactNote,
    );
    if (rotationId.isNotEmpty) {
      return _repository.registerOnCall(<String, Object?>{
        ...row,
        'id': rotationId,
      });
    }
    return _repository.registerOnCall(row);
  }
}

/// A reach note attached to an existing rotation (who to call and how).
final class AttachOnCallNoteUseCase {
  /// Creates the use case.
  AttachOnCallNoteUseCase({required this._repository});

  final PractitionerRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required OnCallRotation rotation,
    required String contactNote,
  }) async {
    policy.require(NodexPermissions.staffDirectoryAdminister);
    await _repository.updateOnCall(
      rotation.id,
      onCallNoteChanges(contactNote: contactNote),
    );
  }
}

/// Reads directory entries. Gated on read permission rather than admin.
final class SearchPractitionersUseCase {
  /// Creates the use case.
  SearchPractitionersUseCase({required this._repository});

  final PractitionerRepository _repository;

  Future<List<PractitionerProfile>> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? specialty,
    int limit = 200,
  }) async {
    policy.require(NodexPermissions.staffDirectoryRead);
    return _repository.listProfiles(
      tenantId,
      specialty: specialty,
      limit: limit,
    );
  }
}

/// Reads on-call rotations for a practitioner, gated on directory read.
final class PractitionerOnCallUseCase {
  /// Creates the use case.
  PractitionerOnCallUseCase({required this._repository});

  final PractitionerRepository _repository;

  Future<List<OnCallRotation>> forPractitioner({
    required AuthorizationPolicy policy,
    required String practitionerId,
  }) async {
    policy.require(NodexPermissions.staffDirectoryRead);
    return _repository.listOnCalls(practitionerId);
  }

  Future<List<OnCallRotation>> upcoming({
    required AuthorizationPolicy policy,
    required String tenantId,
    required DateTime at,
  }) async {
    policy.require(NodexPermissions.staffDirectoryRead);
    return _repository.upcomingOnCalls(tenantId, at);
  }
}
