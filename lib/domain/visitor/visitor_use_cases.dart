/// Visitor and pass use cases (Module 37).
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/visitor/visitor.dart';
import 'package:nodex_hms/domain/visitor/visitor_repository.dart';

/// Sets the visiting window a ward admits visitors under.
final class SetVisitingWindowUseCase {
  /// Creates the use case.
  SetVisitingWindowUseCase({required this._repository});

  final VisitorRepository _repository;

  /// A ward has one window per day. Replacing one means retiring the old window
  /// first, because the retired row is the rule a past pass was issued under.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String wardId,
    required int dayOfWeek,
    required int startsMinute,
    required int endsMinute,
    required String createdBy,
    int maxVisitors = 2,
    bool allowsChildren = false,
    String windowId = '',
  }) async {
    policy.require(NodexPermissions.visitorConfigure);
    final List<WardVisitingWindow> existing = await _repository
        .listVisitingWindows(tenantId, wardId: wardId);
    for (final WardVisitingWindow window in existing) {
      if (window.dayOfWeek == dayOfWeek &&
          window.isActive &&
          window.id != windowId) {
        throw const ValidationError(
          message: 'Visiting window failed validation.',
          fieldErrors: <String, String>{
            'day_of_week': 'That ward already has a window on that day.',
          },
          code: 'ward_visiting_window_duplicate',
        );
      }
    }
    return _repository.registerVisitingWindow(
      WardVisitingWindow.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        wardId: wardId,
        dayOfWeek: dayOfWeek,
        startsMinute: startsMinute,
        endsMinute: endsMinute,
        createdBy: createdBy,
        maxVisitors: maxVisitors,
        allowsChildren: allowsChildren,
        windowId: windowId,
      ),
    );
  }
}

/// Retires a visiting window.
final class ArchiveVisitingWindowUseCase {
  /// Creates the use case.
  ArchiveVisitingWindowUseCase({required this._repository});

  final VisitorRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required WardVisitingWindow window,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.visitorConfigure);
    if (!window.isActive) {
      throw const AuthorizationError(
        message: 'That window is already retired.',
        code: 'ward_visiting_window_transition_invalid',
      );
    }
    await _repository.updateVisitingWindow(
      window.id,
      wardVisitingWindowArchiveChanges(at: at),
    );
  }
}

/// Takes a visitor at the gate.
final class RegisterVisitorUseCase {
  /// Creates the use case.
  RegisterVisitorUseCase({required this._repository});

  final VisitorRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String registrationNumber,
    required String fullName,
    required String registeredBy,
    required String createdBy,
    VisitorPurpose purpose = VisitorPurpose.patientVisit,
    String? phone,
    VisitorSex? sex,
    int? ageYears,
    VisitorIdType? idDocumentType,
    String? idDocumentNumber,
    String? relationship,
    String? patientId,
    String? wardId,
    DateTime? registeredAt,
    String registrationId = '',
  }) async {
    policy.require(NodexPermissions.visitorRegister);
    await _requireFreeNumber(
      tenantId,
      registrationNumber,
      exceptId: registrationId,
    );
    return _repository.registerRegistration(
      VisitorRegistration.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        registrationNumber: registrationNumber,
        fullName: fullName,
        registeredBy: registeredBy,
        createdBy: createdBy,
        purpose: purpose,
        phone: phone,
        sex: sex,
        ageYears: ageYears,
        idDocumentType: idDocumentType,
        idDocumentNumber: idDocumentNumber,
        relationship: relationship,
        patientId: patientId,
        wardId: wardId,
        registeredAt: registeredAt,
        registrationId: registrationId,
      ),
    );
  }

  /// The gate log is a sequence: two rows sharing a number make it unreadable.
  Future<void> _requireFreeNumber(
    String tenantId,
    String registrationNumber, {
    required String exceptId,
  }) async {
    final List<VisitorRegistration> registrations = await _repository
        .listRegistrations(tenantId);
    for (final VisitorRegistration other in registrations) {
      if (other.registrationNumber == registrationNumber.trim() &&
          other.id != exceptId) {
        throw const ValidationError(
          message: 'Visitor registration failed validation.',
          fieldErrors: <String, String>{
            'registration_number': 'That registration number is already used.',
          },
          code: 'visitor_registration_number_duplicate',
        );
      }
    }
  }
}

/// Admits a visitor.
final class AdmitVisitorUseCase {
  /// Creates the use case.
  AdmitVisitorUseCase({required this._repository});

  final VisitorRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required VisitorRegistration registration,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.visitorRegister);
    if (!visitorRegistrationCanTransition(
      registration.status,
      VisitorRegistrationStatus.onSite,
    )) {
      throw AuthorizationError(
        message: registration.status.isTerminal
            ? 'That visitor is no longer at the gate.'
            : 'That visitor is already inside.',
        code: 'visitor_registration_transition_invalid',
      );
    }
    await _repository.updateRegistration(
      registration.id,
      visitorRegistrationCheckInChanges(at: at),
    );
  }
}

/// Records a visitor leaving.
final class RecordVisitorDepartureUseCase {
  /// Creates the use case.
  RecordVisitorDepartureUseCase({required this._repository});

  final VisitorRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required VisitorRegistration registration,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.visitorRegister);
    if (!visitorRegistrationCanTransition(
      registration.status,
      VisitorRegistrationStatus.left,
    )) {
      throw AuthorizationError(
        message: registration.status.isOnSite
            ? 'An unadmitted visitor has nothing to check out.'
            : 'That visitor has already left.',
        code: 'visitor_registration_transition_invalid',
      );
    }
    await _repository.updateRegistration(
      registration.id,
      visitorRegistrationCheckOutChanges(at: at),
    );
  }
}

/// Turns a visitor away at the gate.
final class RefuseVisitorUseCase {
  /// Creates the use case.
  RefuseVisitorUseCase({required this._repository});

  final VisitorRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required VisitorRegistration registration,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.visitorRegister);
    if (!visitorRegistrationCanTransition(
      registration.status,
      VisitorRegistrationStatus.refused,
    )) {
      throw AuthorizationError(
        message: registration.status.isTerminal
            ? 'That visitor has already been dealt with.'
            : 'A visitor already inside is asked to leave, not refused.',
        code: 'visitor_registration_transition_invalid',
      );
    }
    await _repository.updateRegistration(
      registration.id,
      visitorRegistrationRefuseChanges(reason: reason, at: at),
    );
  }
}

/// Withdraws a registration entered in error.
final class VoidVisitorRegistrationUseCase {
  /// Creates the use case.
  VoidVisitorRegistrationUseCase({required this._repository});

  final VisitorRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required VisitorRegistration registration,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.visitorRegister);
    if (!visitorRegistrationCanTransition(
      registration.status,
      VisitorRegistrationStatus.voided,
    )) {
      throw AuthorizationError(
        message: registration.status.isTerminal
            ? 'That visitor is already settled.'
            : 'A visitor who came in is checked out, not withdrawn.',
        code: 'visitor_registration_transition_invalid',
      );
    }
    await _repository.updateRegistration(
      registration.id,
      visitorRegistrationVoidChanges(reason: reason, at: at),
    );
  }
}

/// Issues a digital entry pass against a registration.
final class IssueVisitorPassUseCase {
  /// Creates the use case.
  IssueVisitorPassUseCase({required this._repository});

  final VisitorRepository _repository;

  /// A pass is issued against a registration that is still live. A visitor who
  /// was refused at the gate, or whose row was withdrawn, has no authority to
  /// pass on.
  Future<String> call({
    required AuthorizationPolicy policy,
    required VisitorRegistration registration,
    required String badgeNumber,
    required String issuedBy,
    required String createdBy,
    required DateTime validUntil,
    VisitorAccessScope accessScope = VisitorAccessScope.ward,
    int escortCount = 0,
    DateTime? validFrom,
    String passId = '',
  }) async {
    policy.require(NodexPermissions.visitorPass);
    if (!registration.isLive) {
      throw const AuthorizationError(
        message:
            'That visitor is no longer at the gate, so there is nothing '
            'to issue a pass against.',
        code: 'visitor_pass_registration_settled',
      );
    }
    final List<VisitorPass> passes = await _repository.listPasses(
      registration.tenantId,
    );
    for (final VisitorPass other in passes) {
      if (other.badgeNumber == badgeNumber.trim() && other.id != passId) {
        throw const ValidationError(
          message: 'Visitor pass failed validation.',
          fieldErrors: <String, String>{
            'badge_number': 'That badge number is already in use.',
          },
          code: 'visitor_pass_badge_duplicate',
        );
      }
    }
    return _repository.registerPass(
      VisitorPass.registerRow(
        tenantId: registration.tenantId,
        facilityId: registration.facilityId,
        registrationId: registration.id,
        badgeNumber: badgeNumber,
        issuedBy: issuedBy,
        createdBy: createdBy,
        validUntil: validUntil,
        accessScope: accessScope,
        escortCount: escortCount,
        validFrom: validFrom,
        passId: passId,
      ),
    );
  }
}

/// Activates a pass as its holder goes in.
final class ActivateVisitorPassUseCase {
  /// Creates the use case.
  ActivateVisitorPassUseCase({required this._repository});

  final VisitorRepository _repository;

  /// A pass whose window has already closed is not activated: it is revoked or
  /// replaced, so the record says what actually happened.
  Future<void> call({
    required AuthorizationPolicy policy,
    required VisitorPass pass,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.visitorPass);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    if (!visitorPassCanTransition(pass.status, VisitorPassStatus.active)) {
      throw AuthorizationError(
        message: pass.status.isTerminal
            ? 'That pass is settled.'
            : 'That pass is already active.',
        code: 'visitor_pass_transition_invalid',
      );
    }
    if (isVisitorPassExpired(pass: pass, now: now)) {
      throw const AuthorizationError(
        message: 'The pass window closed before it was used.',
        code: 'visitor_pass_expired',
      );
    }
    await _repository.updatePass(pass.id, visitorPassActivateChanges(at: at));
  }
}

/// Records a badge handed back at the gate.
final class ReturnVisitorPassUseCase {
  /// Creates the use case.
  ReturnVisitorPassUseCase({required this._repository});

  final VisitorRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required VisitorPass pass,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.visitorPass);
    if (!visitorPassCanTransition(pass.status, VisitorPassStatus.returned)) {
      throw AuthorizationError(
        message: pass.status.isTerminal
            ? 'That pass is settled.'
            : 'A pass is returned once it has been active.',
        code: 'visitor_pass_transition_invalid',
      );
    }
    await _repository.updatePass(pass.id, visitorPassReturnChanges(at: at));
  }
}

/// Revokes a pass before its window closed.
final class RevokeVisitorPassUseCase {
  /// Creates the use case.
  RevokeVisitorPassUseCase({required this._repository});

  final VisitorRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required VisitorPass pass,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.visitorPass);
    if (!visitorPassCanTransition(pass.status, VisitorPassStatus.revoked)) {
      throw const AuthorizationError(
        message: 'That pass is settled and cannot be revoked.',
        code: 'visitor_pass_transition_invalid',
      );
    }
    await _repository.updatePass(
      pass.id,
      visitorPassRevokeChanges(reason: reason, at: at),
    );
  }
}

/// Records a thermal badge print.
final class RecordBadgePrintUseCase {
  /// Creates the use case.
  RecordBadgePrintUseCase({required this._repository});

  final VisitorRepository _repository;

  /// The ordinal is derived from the log rather than supplied, so a reprint is
  /// numbered on the record instead of overwriting the first print.
  Future<String> call({
    required AuthorizationPolicy policy,
    required VisitorPass pass,
    required String printerLabel,
    required String printedBy,
    String? note,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.visitorPass);
    if (pass.status == VisitorPassStatus.returned ||
        pass.status == VisitorPassStatus.revoked) {
      throw const AuthorizationError(
        message: 'That pass is settled, so its badge is not printed again.',
        code: 'visitor_pass_transition_invalid',
      );
    }
    final List<VisitorBadgePrint> prints = await _repository.listBadgePrints(
      pass.tenantId,
      passId: pass.id,
    );
    int ordinal = 1;
    for (final VisitorBadgePrint print in prints) {
      if (print.printOrdinal >= ordinal) {
        ordinal = print.printOrdinal + 1;
      }
    }
    return _repository.appendBadgePrint(
      VisitorBadgePrint.registerRow(
        tenantId: pass.tenantId,
        passId: pass.id,
        badgeNumber: pass.badgeNumber,
        printOrdinal: ordinal,
        printerLabel: printerLabel,
        printedBy: printedBy,
        note: note,
        printedAt: at,
      ),
    );
  }
}

/// The front desk as the screen shows it.
@immutable
final class VisitorDeskBoard {
  /// Creates a desk snapshot.
  const VisitorDeskBoard({
    required this.registrations,
    required this.passes,
    required this.windows,
    required this.asOf,
  });

  /// Registrations, newest first.
  final List<VisitorRegistration> registrations;

  /// Passes, soonest to fall out of validity first.
  final List<VisitorPass> passes;

  /// Visiting windows, by ward and weekday.
  final List<WardVisitingWindow> windows;

  /// The instant the derived markers were computed at.
  final DateTime asOf;

  /// The visitors currently inside.
  List<VisitorRegistration> get onSiteVisitors => registrations
      .where((VisitorRegistration r) => r.isOnSite)
      .toList(growable: false);

  /// The registrations still to be worked.
  List<VisitorRegistration> get liveRegistrations => registrations
      .where((VisitorRegistration r) => r.isLive)
      .toList(growable: false);

  /// The live passes of one registration.
  List<VisitorPass> livePassesFor(String registrationId) => passes
      .where((VisitorPass p) => p.registrationId == registrationId && p.isLive)
      .toList(growable: false);

  /// The live registrations with no live pass against them.
  List<VisitorRegistration> get registrationsWithoutLivePass =>
      liveRegistrations
          .where((VisitorRegistration r) => livePassesFor(r.id).isEmpty)
          .toList(growable: false);

  /// The issued passes that have not been used yet.
  List<VisitorPass> get passesAwaitingActivation => passes
      .where(
        (VisitorPass p) =>
            p.status == VisitorPassStatus.issued &&
            !isVisitorPassExpired(pass: p, now: asOf),
      )
      .toList(growable: false);

  /// The live passes whose window has already closed.
  List<VisitorPass> get expiredLivePasses => passes
      .where(
        (VisitorPass p) => p.isLive && isVisitorPassExpired(pass: p, now: asOf),
      )
      .toList(growable: false);

  /// How many visitors are inside a ward.
  int visitorsOnSiteForWard(String wardId) => registrations
      .where((VisitorRegistration r) => r.isOnSite && r.wardId == wardId)
      .length;

  /// The window in force for the ward a registration belongs to.
  WardVisitingWindow? windowForRegistration(
    VisitorRegistration registration, {
    required int dayOfWeek,
  }) {
    final String? wardId = registration.wardId;
    if (wardId == null) {
      return null;
    }
    return visitingWindowFor(
      wardId: wardId,
      dayOfWeek: dayOfWeek,
      windows: windows,
    );
  }

  /// Whether an admission falls outside the ward's hours, or into a ward whose
  /// visiting hours are not set at all.
  bool isOutsideVisitingHours(
    VisitorRegistration registration, {
    required int dayOfWeek,
    required int minuteOfDay,
  }) {
    if (registration.wardId == null) {
      return false;
    }
    final WardVisitingWindow? window = windowForRegistration(
      registration,
      dayOfWeek: dayOfWeek,
    );
    if (window == null) {
      return true;
    }
    return !isWithinVisitingWindow(window: window, minuteOfDay: minuteOfDay);
  }

  /// Whether the desk has something that needs attention: a live registration
  /// with no pass, or a pass that has run out while still live.
  bool get needsAttention =>
      registrationsWithoutLivePass.isNotEmpty || expiredLivePasses.isNotEmpty;
}

/// Reads the visitor desk.
final class ReadVisitorDeskUseCase {
  /// Creates the use case.
  ReadVisitorDeskUseCase({required this._repository});

  final VisitorRepository _repository;

  /// The registrations, newest first.
  Future<List<VisitorRegistration>> registrations({
    required AuthorizationPolicy policy,
    required String tenantId,
    VisitorRegistrationStatus? status,
    String? wardId,
    bool includeSettled = true,
  }) async {
    policy.require(NodexPermissions.visitorRead);
    final List<VisitorRegistration> registrations = await _repository
        .listRegistrations(tenantId, status: status?.wireValue, wardId: wardId);
    return registrations
        .where((VisitorRegistration r) => includeSettled || r.isLive)
        .toList(growable: false);
  }

  /// The passes, soonest to fall out of validity first.
  Future<List<VisitorPass>> passes({
    required AuthorizationPolicy policy,
    required String tenantId,
    VisitorPassStatus? status,
    String? registrationId,
    bool includeSettled = true,
  }) async {
    policy.require(NodexPermissions.visitorRead);
    final List<VisitorPass> passes = await _repository.listPasses(
      tenantId,
      status: status?.wireValue,
      registrationId: registrationId,
    );
    return passes
        .where((VisitorPass p) => includeSettled || p.isLive)
        .toList(growable: false);
  }

  /// The visiting windows held on this device.
  Future<List<WardVisitingWindow>> windows({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? wardId,
    bool includeArchived = false,
  }) async {
    policy.require(NodexPermissions.visitorRead);
    final List<WardVisitingWindow> windows = await _repository
        .listVisitingWindows(tenantId, wardId: wardId);
    return windows
        .where((WardVisitingWindow w) => includeArchived || w.isActive)
        .toList(growable: false);
  }

  /// The badge print log of one pass, oldest first.
  Future<List<VisitorBadgePrint>> badgePrints({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String passId,
  }) async {
    policy.require(NodexPermissions.visitorRead);
    return _repository.listBadgePrints(tenantId, passId: passId);
  }

  /// The desk: who is inside, whose pass has run out, and the ward windows.
  Future<VisitorDeskBoard> board({
    required AuthorizationPolicy policy,
    required String tenantId,
    DateTime? now,
  }) async {
    policy.require(NodexPermissions.visitorRead);
    final DateTime asOf = (now ?? DateTime.now().toUtc()).toUtc();
    final List<VisitorRegistration> registrations = await _repository
        .listRegistrations(tenantId);
    final List<VisitorPass> passes = await _repository.listPasses(tenantId);
    final List<WardVisitingWindow> windows = await _repository
        .listVisitingWindows(tenantId);
    registrations.sort(
      (VisitorRegistration a, VisitorRegistration b) =>
          b.registeredAt.compareTo(a.registeredAt),
    );
    passes.sort(
      (VisitorPass a, VisitorPass b) => a.validUntil.compareTo(b.validUntil),
    );
    return VisitorDeskBoard(
      registrations: registrations,
      passes: passes,
      windows: windows,
      asOf: asOf,
    );
  }
}
