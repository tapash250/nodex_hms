/// Task board use cases (Module 41).
///
/// Every write goes through the same shape: check the permission, check that
/// the transition is one the task actually offers, then hand the row to the
/// repository. The transition check runs before the write so a device that is
/// offline can tell the user why nothing happened instead of queueing a
/// mutation the server will refuse.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/tasks/hospital_task.dart';
import 'package:nodex_hms/domain/tasks/task_repository.dart';

/// Raises a task for another department.
final class RaiseTaskUseCase {
  /// Creates the use case.
  RaiseTaskUseCase({required this._repository});

  final TaskRepository _repository;

  /// Raises the task, returning its local id.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String taskCode,
    required String title,
    required String requestedBy,
    TaskCategory category = TaskCategory.other,
    TaskPriority priority = TaskPriority.medium,
    String? detail,
    String? patientId,
    String? encounterId,
    String? fromLocation,
    String? toLocation,
    String? dueAt,
  }) async {
    policy.require(NodexPermissions.tasksManage);
    return _repository.raiseTask(
      HospitalTask.raiseRow(
        tenantId: tenantId,
        taskCode: taskCode,
        title: title,
        requestedBy: requestedBy,
        category: category,
        priority: priority,
        detail: detail,
        patientId: patientId,
        encounterId: encounterId,
        fromLocation: fromLocation,
        toLocation: toLocation,
        dueAt: dueAt,
      ),
    );
  }
}

/// Claims an open task for the current user.
final class ClaimTaskUseCase {
  /// Creates the use case.
  ClaimTaskUseCase({required this._repository});

  final TaskRepository _repository;

  /// Claims the task.
  ///
  /// The claim is the moment ownership is recorded: two devices may both try,
  /// and the server keeps the first, which is why a task never arrives with an
  /// assignee already set.
  Future<void> call({
    required AuthorizationPolicy policy,
    required HospitalTask task,
    required String user,
  }) async {
    policy.require(NodexPermissions.tasksManage);
    if (task.status != TaskStatus.open) {
      throw const ValidationError(
        message: 'This task is already owned by somebody else.',
        fieldErrors: <String, String>{
          'status': 'Only an open task can be claimed.',
        },
        code: 'task_already_claimed',
      );
    }
    await _repository.updateTask(
      task.id,
      HospitalTask.claimChanges(user: user),
    );
  }
}

/// Moves a claimed task into progress.
final class StartTaskUseCase {
  /// Creates the use case.
  StartTaskUseCase({required this._repository});

  final TaskRepository _repository;

  /// Starts the task.
  Future<void> call({
    required AuthorizationPolicy policy,
    required HospitalTask task,
    required String user,
  }) async {
    policy.require(NodexPermissions.tasksManage);
    if (task.assignedTo != null && task.assignedTo != user) {
      throw const AuthorizationError(
        message: 'Only the person who claimed this task can start it.',
        code: 'task_not_owned',
      );
    }
    if (task.status != TaskStatus.claimed) {
      throw const ValidationError(
        message: 'Claim the task before starting it.',
        fieldErrors: <String, String>{'status': 'Expected a claimed task.'},
        code: 'task_not_claimed',
      );
    }
    await _repository.updateTask(task.id, HospitalTask.startChanges());
  }
}

/// Completes a task, stating what was done.
final class CompleteTaskUseCase {
  /// Creates the use case.
  CompleteTaskUseCase({required this._repository});

  final TaskRepository _repository;

  /// Completes the task.
  Future<void> call({
    required AuthorizationPolicy policy,
    required HospitalTask task,
    required String user,
    required String note,
  }) async {
    policy.require(NodexPermissions.tasksManage);
    if (!TaskStatus.completed.isReachableFrom(task.status)) {
      throw const ValidationError(
        message: 'Only a claimed or started task can be completed.',
        fieldErrors: <String, String>{'status': 'Nothing to complete.'},
        code: 'task_not_completable',
      );
    }
    if (task.assignedTo != null && task.assignedTo != user) {
      throw const AuthorizationError(
        message: 'This task belongs to somebody else.',
        code: 'task_not_owned',
      );
    }
    await _repository.updateTask(
      task.id,
      HospitalTask.completeChanges(completedBy: user, note: note),
    );
  }
}

/// Cancels a task, stating why.
final class CancelTaskUseCase {
  /// Creates the use case.
  CancelTaskUseCase({required this._repository});

  final TaskRepository _repository;

  /// Cancels the task.
  ///
  /// A STAT errand that cannot be run is cancelled here rather than left on the
  /// board: a board that never empties stops being read.
  Future<void> call({
    required AuthorizationPolicy policy,
    required HospitalTask task,
    required String reason,
  }) async {
    policy.require(NodexPermissions.tasksManage);
    if (!TaskStatus.cancelled.isReachableFrom(task.status)) {
      throw const ValidationError(
        message: 'A closed task cannot be cancelled again.',
        fieldErrors: <String, String>{'status': 'Nothing left to cancel.'},
        code: 'task_already_closed',
      );
    }
    await _repository.updateTask(
      task.id,
      HospitalTask.cancelChanges(reason: reason),
    );
  }
}

/// Raises an open task's priority.
final class ReprioritiseTaskUseCase {
  /// Creates the use case.
  ReprioritiseTaskUseCase({required this._repository});

  final TaskRepository _repository;

  /// Applies the new priority.
  Future<void> call({
    required AuthorizationPolicy policy,
    required HospitalTask task,
    required TaskPriority priority,
  }) async {
    policy.require(NodexPermissions.tasksManage);
    final Map<String, Object?>? changes = HospitalTask.reprioritise(
      from: task.priority,
      to: priority,
    );
    if (changes == null) return;
    await _repository.updateTask(task.id, changes);
  }
}

/// The board as one screen sees it: live work first, then the closed record.
@immutable
final class TaskBoard {
  /// Creates a board.
  const TaskBoard({required this.live, required this.closed});

  /// Tasks that still need doing, most urgent first.
  final List<HospitalTask> live;

  /// Recently finished tasks.
  final List<HospitalTask> closed;

  /// Live tasks nobody owns yet.
  List<HospitalTask> get unclaimed => live
      .where((HospitalTask t) => t.status == TaskStatus.open)
      .toList(growable: false);

  /// Live tasks owned by [user].
  List<HospitalTask> claimedBy(String user) => live
      .where((HospitalTask t) => t.assignedTo == user && t.status.isLive)
      .toList(growable: false);

  /// Live tasks past their due time at [now], most overdue first.
  List<HospitalTask> overdueAt(DateTime now) {
    final List<HospitalTask> overdue = live
        .where((HospitalTask task) => task.isOverdueAt(now))
        .toList();
    overdue.sort(
      (HospitalTask a, HospitalTask b) => a.dueAt!.compareTo(b.dueAt!),
    );
    return List<HospitalTask>.unmodifiable(overdue);
  }
}

/// Reads the task board.
final class ReadTaskBoardUseCase {
  /// Creates the use case.
  ReadTaskBoardUseCase({required this._repository});

  final TaskRepository _repository;

  /// Reads the board, splitting live work from the closed record.
  Future<TaskBoard> call({
    required AuthorizationPolicy policy,
    String? patientId,
    int limit = 200,
  }) async {
    policy.require(NodexPermissions.tasksRead);
    final List<HospitalTask> tasks = await _repository.listBoard(
      patientId: patientId,
      limit: limit,
    );
    return TaskBoard(
      live: tasks
          .where((HospitalTask task) => task.status.isLive)
          .toList(growable: false),
      closed: tasks
          .where((HospitalTask task) => task.status.isTerminal)
          .toList(growable: false),
    );
  }
}
