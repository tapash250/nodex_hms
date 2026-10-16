/// Nurse ward station use cases (Module 06).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station_repository.dart';

/// Records a routine ward observation.
final class RecordWardVitalsUseCase {
  /// Creates the use case.
  RecordWardVitalsUseCase({required this._repository});

  final NursingStationRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String wardId,
    required String recordedBy,
    String? encounterId,
    String? bedId,
    String? observedAt,
    double? temperatureCelsius,
    int? pulseBpm,
    int? respiratoryRate,
    int? systolicBp,
    int? diastolicBp,
    int? spo2,
    int? painScore,
    ConsciousnessLevel consciousness = ConsciousnessLevel.alert,
    bool onOxygen = false,
    String? notes,
    String vitalId = '',
  }) async {
    policy.require(NodexPermissions.vitalsRecord);
    return _repository.recordVitals(
      WardVital.registerRow(
        tenantId: tenantId,
        patientId: patientId,
        wardId: wardId,
        recordedBy: recordedBy,
        encounterId: encounterId,
        bedId: bedId,
        observedAt: observedAt,
        temperatureCelsius: temperatureCelsius,
        pulseBpm: pulseBpm,
        respiratoryRate: respiratoryRate,
        systolicBp: systolicBp,
        diastolicBp: diastolicBp,
        spo2: spo2,
        painScore: painScore,
        consciousness: consciousness,
        onOxygen: onOxygen,
        notes: notes,
        vitalId: vitalId,
      ),
    );
  }
}

/// Records a shift nursing handover.
final class RecordWardHandoverUseCase {
  /// Creates the use case.
  RecordWardHandoverUseCase({required this._repository});

  final NursingStationRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String wardId,
    required String fromUser,
    required String summary,
    String? shiftId,
    String? toUser,
    String? handoverAt,
    String? pendingItems,
    String handoverId = '',
  }) async {
    policy.require(NodexPermissions.nursingHandoverRecord);
    return _repository.recordHandover(
      WardHandover.registerRow(
        tenantId: tenantId,
        wardId: wardId,
        fromUser: fromUser,
        summary: summary,
        shiftId: shiftId,
        toUser: toUser,
        handoverAt: handoverAt,
        pendingItems: pendingItems,
        handoverId: handoverId,
      ),
    );
  }
}

/// Creates a ward task.
final class CreateWardTaskUseCase {
  /// Creates the use case.
  CreateWardTaskUseCase({required this._repository});

  final NursingStationRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String wardId,
    required String createdBy,
    required String title,
    String? patientId,
    String? encounterId,
    String? detail,
    WardTaskType taskType = WardTaskType.observation,
    WardTaskPriority priority = WardTaskPriority.routine,
    String? dueAt,
    String? assignedTo,
    String taskId = '',
  }) async {
    policy.require(NodexPermissions.nursingTaskWrite);
    return _repository.createTask(
      WardTask.registerRow(
        tenantId: tenantId,
        wardId: wardId,
        createdBy: createdBy,
        title: title,
        patientId: patientId,
        encounterId: encounterId,
        detail: detail,
        taskType: taskType,
        priority: priority,
        dueAt: dueAt,
        assignedTo: assignedTo,
        taskId: taskId,
      ),
    );
  }
}

/// Delegates an open task to a named nurse.
final class AssignWardTaskUseCase {
  /// Creates the use case.
  AssignWardTaskUseCase({required this._repository});

  final NursingStationRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required WardTask task,
    String? assignedTo,
  }) async {
    policy.require(NodexPermissions.nursingTaskWrite);
    if (task.status.isTerminal) {
      throw const AuthorizationError(
        message: 'A closed task cannot be reassigned.',
        code: 'ward_task_closed',
      );
    }
    await _repository.updateTask(
      task.id,
      wardTaskAssignmentChanges(assignedTo: assignedTo),
    );
  }
}

/// Moves an open task into progress.
final class StartWardTaskUseCase {
  /// Creates the use case.
  StartWardTaskUseCase({required this._repository});

  final NursingStationRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required WardTask task,
  }) async {
    policy.require(NodexPermissions.nursingTaskWrite);
    if (task.status != WardTaskStatus.open) {
      throw const AuthorizationError(
        message: 'Only an open task can be started.',
        code: 'ward_task_not_open',
      );
    }
    await _repository.updateTask(task.id, wardTaskStartChanges());
  }
}

/// Closes a task as done or cancelled, recording who closed it.
final class CloseWardTaskUseCase {
  /// Creates the use case.
  CloseWardTaskUseCase({required this._repository});

  final NursingStationRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required WardTask task,
    required WardTaskStatus status,
    required String completedBy,
  }) async {
    policy.require(NodexPermissions.nursingTaskWrite);
    if (!status.isTerminal) {
      throw const ValidationError(
        message: 'A task closes as done or cancelled.',
        code: 'ward_task_close_invalid',
      );
    }
    if (task.status.isTerminal) {
      throw const AuthorizationError(
        message: 'This task is already closed.',
        code: 'ward_task_closed',
      );
    }
    await _repository.updateTask(
      task.id,
      wardTaskCloseChanges(status: status, completedBy: completedBy),
    );
  }
}

/// Reads the ward station board.
final class ReadWardStationUseCase {
  /// Creates the use case.
  ReadWardStationUseCase({required this._repository});

  final NursingStationRepository _repository;

  Future<List<WardVital>> recentVitals({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String wardId,
  }) async {
    policy.require(NodexPermissions.nursingStationRead);
    return _repository.listVitals(tenantId, wardId: wardId);
  }

  /// Observations whose advisory band is warning or critical.
  Future<List<WardVital>> urgentVitals({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String wardId,
  }) async {
    policy.require(NodexPermissions.nursingStationRead);
    final List<WardVital> vitals = await _repository.listVitals(
      tenantId,
      wardId: wardId,
    );
    return vitals
        .where((WardVital vital) => vital.alert.isUrgent)
        .toList(growable: false);
  }

  Future<List<WardHandover>> handovers({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String wardId,
  }) async {
    policy.require(NodexPermissions.nursingStationRead);
    return _repository.listHandovers(tenantId, wardId: wardId);
  }

  /// The tasks still needing attention: open and in progress.
  Future<List<WardTask>> openTasks({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String wardId,
  }) async {
    policy.require(NodexPermissions.nursingStationRead);
    final List<WardTask> tasks = await _repository.listTasks(
      tenantId,
      wardId: wardId,
    );
    return tasks.where((WardTask task) => task.isOpen).toList(growable: false);
  }
}
