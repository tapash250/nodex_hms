/// Tests for the hospital task engine (Module 41).
///
/// The task engine's promise is that a request survives being handed to
/// somebody else: the substance of the request cannot change, priority only
/// goes up, a claim has an owner, and closing states why. These tests pin those
/// rules at the domain layer, where a device can still tell the user why a
/// button did nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/tasks/hospital_task.dart';
import 'package:nodex_hms/domain/tasks/task_repository.dart';
import 'package:nodex_hms/domain/tasks/task_use_cases.dart';

/// Records what the task commands were asked to write.
final class RecordingTaskRepository implements TaskRepository {
  final List<Map<String, Object?>> raised = <Map<String, Object?>>[];
  final List<Map<String, Object?>> patches = <Map<String, Object?>>[];

  /// Rows the board should return.
  List<HospitalTask> board = <HospitalTask>[];

  @override
  Future<List<HospitalTask>> listBoard({
    TaskStatus? status,
    TaskPriority? priority,
    String? assignedTo,
    String? requestedBy,
    String? patientId,
    int limit = 200,
  }) async => board;

  @override
  Future<HospitalTask?> getTask(String id) async =>
      board.where((HospitalTask task) => task.id == id).firstOrNull;

  @override
  Future<List<HospitalTask>> listClaimable(String userId) async => board;

  @override
  Future<String> raiseTask(Map<String, Object?> row) async {
    raised.add(row);
    return 'task-new';
  }

  @override
  Future<void> updateTask(String id, Map<String, Object?> changes) async {
    patches.add(<String, Object?>{'id': id, ...changes});
  }
}

/// A policy holding the permitted keys.
AuthorizationPolicy policyWith(Set<String> permissions) {
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
      roles: const <String>{NodexRoles.nursingStaff},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

/// A task in [status] owned by the standard fixture identity.
HospitalTask taskWith({
  TaskStatus status = TaskStatus.open,
  TaskPriority priority = TaskPriority.medium,
  String? assignedTo,
  String id = 'task-1',
  DateTime? dueAt,
}) => HospitalTask(
  id: id,
  tenantId: 'tenant-1',
  taskCode: 'TASK-001',
  title: 'Carry blood samples to the lab',
  category: TaskCategory.specimenTransport,
  priority: priority,
  status: status,
  requestedBy: 'doctor-1',
  assignedTo: assignedTo,
  dueAt: dueAt,
  fromLocation: 'Ward 3',
  toLocation: 'Central lab',
  createdAt: DateTime.utc(2026, 9, 12, 9),
);

void main() {
  group('raising a task', () {
    test('opens unowned and open', () {
      final Map<String, Object?> row = HospitalTask.raiseRow(
        tenantId: 'tenant-1',
        taskCode: 'TASK-001',
        title: 'Carry blood samples to the lab',
        requestedBy: 'doctor-1',
        category: TaskCategory.specimenTransport,
        toLocation: 'Central lab',
      );
      expect(row['status'], 'open');
      expect(row['assigned_to'], isNull);
      expect(row['claimed_at'], isNull);
      expect(row['priority'], 'medium');
    });

    test('a transport errand must say where it ends', () {
      expect(
        () => HospitalTask.raiseRow(
          tenantId: 'tenant-1',
          taskCode: 'TASK-002',
          title: 'Carry samples',
          requestedBy: 'doctor-1',
          category: TaskCategory.specimenTransport,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'hospital_task_invalid',
          ),
        ),
      );
    });

    test('a sanitization request needs no destination', () {
      final Map<String, Object?> row = HospitalTask.raiseRow(
        tenantId: 'tenant-1',
        taskCode: 'TASK-003',
        title: 'Clean bay 4',
        requestedBy: 'nurse-1',
        category: TaskCategory.sanitization,
      );
      expect(row['to_location'], isNull);
    });
  });

  group('priority', () {
    test('may be raised', () {
      final Map<String, Object?>? changes = HospitalTask.reprioritise(
        from: TaskPriority.medium,
        to: TaskPriority.stat,
      );
      expect(changes!['priority'], 'stat');
    });

    test('refuses a downgrade', () {
      expect(
        () => HospitalTask.reprioritise(
          from: TaskPriority.stat,
          to: TaskPriority.medium,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'task_priority_downgrade_refused',
          ),
        ),
      );
    });

    test('an unchanged priority is not a write', () {
      expect(
        HospitalTask.reprioritise(
          from: TaskPriority.urgent,
          to: TaskPriority.urgent,
        ),
        isNull,
      );
    });

    test('the ladder orders stat above urgent above routine work', () {
      expect(TaskPriority.stat.isAtLeast(TaskPriority.urgent), isTrue);
      expect(TaskPriority.low.isAtLeast(TaskPriority.medium), isFalse);
    });
  });

  group('transitions', () {
    test('an open task is claimed, not completed', () {
      expect(TaskStatus.completed.isReachableFrom(TaskStatus.open), isFalse);
      expect(TaskStatus.claimed.isReachableFrom(TaskStatus.open), isTrue);
    });

    test('a closed task offers nothing further', () {
      expect(
        taskWith(status: TaskStatus.completed).availableTransitions,
        isEmpty,
      );
      expect(
        taskWith(status: TaskStatus.cancelled).availableTransitions,
        isEmpty,
      );
    });

    test('a claimed task may start, complete or be cancelled', () {
      expect(
        taskWith(status: TaskStatus.claimed).availableTransitions,
        containsAll(<TaskStatus>[
          TaskStatus.inProgress,
          TaskStatus.completed,
          TaskStatus.cancelled,
        ]),
      );
    });

    test('completing demands a note', () {
      expect(
        () => HospitalTask.completeChanges(completedBy: 'nurse-1', note: '  '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'task_completion_note_required',
          ),
        ),
      );
    });

    test('cancelling demands a reason', () {
      expect(
        () => HospitalTask.cancelChanges(reason: ''),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'task_cancellation_reason_required',
          ),
        ),
      );
    });

    test('a claim records who owns the task', () {
      final Map<String, Object?> changes = HospitalTask.claimChanges(
        user: 'porter-1',
      );
      expect(changes['status'], 'claimed');
      expect(changes['assigned_to'], 'porter-1');
    });
  });

  group('use-case gates', () {
    late RecordingTaskRepository repository;

    setUp(() {
      repository = RecordingTaskRepository();
    });

    test('raising requires the manage permission', () async {
      await expectLater(
        RaiseTaskUseCase(repository: repository).call(
          policy: policyWith(<String>{NodexPermissions.tasksRead}),
          tenantId: 'tenant-1',
          taskCode: 'TASK-001',
          title: 'Carry samples',
          requestedBy: 'doctor-1',
          category: TaskCategory.specimenTransport,
          toLocation: 'Central lab',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      expect(repository.raised, isEmpty);
    });

    test('raising writes an open, unowned task', () async {
      await RaiseTaskUseCase(repository: repository).call(
        policy: policyWith(<String>{NodexPermissions.tasksManage}),
        tenantId: 'tenant-1',
        taskCode: 'TASK-001',
        title: 'Carry samples',
        requestedBy: 'doctor-1',
        category: TaskCategory.specimenTransport,
        toLocation: 'Central lab',
      );
      expect(repository.raised.single['status'], 'open');
      expect(repository.raised.single['assigned_to'], isNull);
    });

    test('a claimed task cannot be claimed again', () async {
      await expectLater(
        ClaimTaskUseCase(repository: repository).call(
          policy: policyWith(<String>{NodexPermissions.tasksManage}),
          task: taskWith(status: TaskStatus.claimed, assignedTo: 'porter-2'),
          user: 'porter-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'task_already_claimed',
          ),
        ),
      );
      expect(repository.patches, isEmpty);
    });

    test('somebody else\'s task cannot be started or completed', () async {
      final HospitalTask theirs = taskWith(
        status: TaskStatus.claimed,
        assignedTo: 'porter-2',
      );
      await expectLater(
        StartTaskUseCase(repository: repository).call(
          policy: policyWith(<String>{NodexPermissions.tasksManage}),
          task: theirs,
          user: 'porter-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        CompleteTaskUseCase(repository: repository).call(
          policy: policyWith(<String>{NodexPermissions.tasksManage}),
          task: theirs,
          user: 'porter-1',
          note: 'Delivered',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      expect(repository.patches, isEmpty);
    });

    test('completing writes the note and the closer', () async {
      await CompleteTaskUseCase(repository: repository).call(
        policy: policyWith(<String>{NodexPermissions.tasksManage}),
        task: taskWith(status: TaskStatus.claimed, assignedTo: 'porter-1'),
        user: 'porter-1',
        note: 'Handed to the lab bench',
      );
      expect(repository.patches.single['status'], 'completed');
      expect(
        repository.patches.single['completion_note'],
        'Handed to the lab bench',
      );
      expect(repository.patches.single['completed_by'], 'porter-1');
    });

    test('a closed task cannot be cancelled twice', () async {
      await expectLater(
        CancelTaskUseCase(repository: repository).call(
          policy: policyWith(<String>{NodexPermissions.tasksManage}),
          task: taskWith(status: TaskStatus.completed),
          reason: 'Not needed',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'task_already_closed',
          ),
        ),
      );
      expect(repository.patches, isEmpty);
    });

    test('an open task may be cancelled by anyone who manages tasks', () async {
      await CancelTaskUseCase(repository: repository).call(
        policy: policyWith(<String>{NodexPermissions.tasksManage}),
        task: taskWith(),
        reason: 'Patient discharged before the errand ran',
      );
      expect(repository.patches.single['status'], 'cancelled');
      expect(
        repository.patches.single['cancellation_reason'],
        'Patient discharged before the errand ran',
      );
    });
  });

  group('the board', () {
    test('splits live work from the closed record', () async {
      final RecordingTaskRepository repository = RecordingTaskRepository()
        ..board = <HospitalTask>[
          taskWith(),
          taskWith(status: TaskStatus.completed, id: 'task-2'),
          taskWith(status: TaskStatus.cancelled, id: 'task-3'),
        ];

      final TaskBoard board = await ReadTaskBoardUseCase(repository: repository)
          .call(policy: policyWith(<String>{NodexPermissions.tasksRead}));

      expect(board.live, hasLength(1));
      expect(board.closed, hasLength(2));
    });

    test('reading requires the read permission', () async {
      await expectLater(
        ReadTaskBoardUseCase(repository: RecordingTaskRepository())
            .call(policy: policyWith(<String>{NodexPermissions.tasksManage})),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('unclaimed work is what nobody owns', () {
      final TaskBoard board = TaskBoard(
        live: <HospitalTask>[
          taskWith(),
          taskWith(status: TaskStatus.claimed, assignedTo: 'porter-1'),
        ],
        closed: const <HospitalTask>[],
      );
      expect(board.unclaimed, hasLength(1));
      expect(board.claimedBy('porter-1'), hasLength(1));
      expect(board.claimedBy('porter-2'), isEmpty);
    });

    test('overdue work is derived from the clock, worst first', () {
      final DateTime now = DateTime.utc(2026, 9, 12, 12);
      final TaskBoard board = TaskBoard(
        live: <HospitalTask>[
          taskWith(id: 'task-a', dueAt: now.subtract(const Duration(hours: 2))),
          taskWith(id: 'task-b', dueAt: now.subtract(const Duration(hours: 5))),
          taskWith(id: 'task-c', dueAt: now.add(const Duration(hours: 1))),
          taskWith(id: 'task-d'),
        ],
        closed: const <HospitalTask>[],
      );
      final List<HospitalTask> overdue = board.overdueAt(now);
      expect(overdue.map((HospitalTask t) => t.id), <String>[
        'task-b',
        'task-a',
      ]);
    });

    test('a closed task is never overdue, however old', () {
      final DateTime now = DateTime.utc(2026, 9, 12, 12);
      final TaskBoard board = TaskBoard(
        live: const <HospitalTask>[],
        closed: <HospitalTask>[
          taskWith(
            status: TaskStatus.completed,
            dueAt: now.subtract(const Duration(days: 2)),
          ),
        ],
      );
      expect(board.overdueAt(now), isEmpty);
    });
  });
}
