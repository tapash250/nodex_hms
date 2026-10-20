/// Tests for the productivity apps (Module 44).
///
/// The board is a shared surface, so the rules that matter are about who owns
/// a card and whether a finished thing can quietly become unfinished. The
/// scratchpad is the opposite: it is private, and the tests say so.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/productivity/productivity_repository.dart';
import 'package:nodex_hms/domain/productivity/productivity_use_cases.dart';
import 'package:nodex_hms/domain/productivity/work_item.dart';

/// A repository that records what it was asked to do.
final class _RecordingProductivityRepository implements ProductivityRepository {
  final List<Map<String, Object?>> cards = <Map<String, Object?>>[];
  final List<Map<String, Object?>> moves = <Map<String, Object?>>[];
  final List<Map<String, Object?>> tickets = <Map<String, Object?>>[];
  final List<Map<String, Object?>> ticketUpdates = <Map<String, Object?>>[];
  List<WorkItem> board = <WorkItem>[];
  List<ItTicket> openTickets = <ItTicket>[];
  String? scratchpad;

  @override
  Future<List<WorkItem>> listBoard(String boardKey) async => board;

  @override
  Future<String> addWorkItem(Map<String, Object?> row) async {
    cards.add(row);
    return 'card-1';
  }

  @override
  Future<void> moveWorkItem(String id, Map<String, Object?> changes) async {
    moves.add(<String, Object?>{'id': id, ...changes});
  }

  @override
  Future<List<ItTicket>> listTickets() async => openTickets;

  @override
  Future<String> addTicket(Map<String, Object?> row) async {
    tickets.add(row);
    return 'ticket-1';
  }

  @override
  Future<void> updateTicket(String id, Map<String, Object?> changes) async {
    ticketUpdates.add(<String, Object?>{'id': id, ...changes});
  }

  @override
  Future<String?> readScratchpad() async => scratchpad;

  @override
  Future<void> writeScratchpad(String note) async {
    scratchpad = note;
  }
}

/// A policy holding the given permissions.
AuthorizationPolicy _policy(Set<String> permissions) {
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

WorkItem _card({WorkLane lane = WorkLane.todo, DateTime? dueAt}) => WorkItem(
  id: 'card-1',
  tenantId: 'tenant-1',
  boardKey: 'ward.handover',
  title: 'Bring the laundry',
  lane: lane,
  priority: WorkPriority.medium,
  createdBy: 'nurse-1',
  dueAt: dueAt,
);

void main() {
  group('raising a card', () {
    test('a card starts in the to-do lane', () {
      final Map<String, Object?> row = WorkItem.raiseRow(
        tenantId: 'tenant-1',
        boardKey: 'ward.handover',
        title: 'Bring the laundry',
        createdBy: 'nurse-1',
      );
      expect(row['lane'], 'todo');
      expect(row['completed_at'], isNull);
    });

    test('a card must say what it is for', () {
      expect(
        () => WorkItem.raiseRow(
          tenantId: 'tenant-1',
          boardKey: 'ward.handover',
          title: '   ',
          createdBy: 'nurse-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'work_item_invalid',
          ),
        ),
      );
    });

    test('a card must name its board', () {
      expect(
        () => WorkItem.raiseRow(
          tenantId: 'tenant-1',
          boardKey: '',
          title: 'Bring the laundry',
          createdBy: 'nurse-1',
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('moving a card', () {
    test('a card moves to the next lane', () {
      final Map<String, Object?>? changes = WorkItem.moveChanges(
        from: WorkLane.todo,
        to: WorkLane.doing,
      );
      expect(changes!['lane'], 'doing');
    });

    test('a card that is already in the lane does not move', () {
      expect(
        WorkItem.moveChanges(from: WorkLane.doing, to: WorkLane.doing),
        isNull,
      );
    });

    test('a finished card does not go back to the board', () {
      expect(
        () => WorkItem.moveChanges(from: WorkLane.done, to: WorkLane.todo),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'work_item_completed',
          ),
        ),
      );
    });

    test('a card past its due time is overdue', () {
      final DateTime now = DateTime.utc(2026, 9, 12, 12);
      expect(
        _card(dueAt: now.subtract(const Duration(hours: 1))).isOverdueAt(now),
        isTrue,
      );
      expect(
        _card(dueAt: now.add(const Duration(hours: 1))).isOverdueAt(now),
        isFalse,
      );
    });

    test('a finished card is never overdue', () {
      final DateTime now = DateTime.utc(2026, 9, 12, 12);
      expect(_card(lane: WorkLane.done, dueAt: now).isOverdueAt(now), isFalse);
    });
  });

  group('service requests', () {
    test('a ticket is opened', () {
      final Map<String, Object?> row = ItTicket.raiseRow(
        tenantId: 'tenant-1',
        ticketCode: 'IT-1',
        title: 'Printer out of paper',
        reportedBy: 'nurse-1',
      );
      expect(row['status'], 'open');
      expect(row['resolution_note'], isNull);
    });

    test('a ticket must say what is wrong', () {
      expect(
        () => ItTicket.raiseRow(
          tenantId: 'tenant-1',
          ticketCode: 'IT-1',
          title: '',
          reportedBy: 'nurse-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'it_ticket_invalid',
          ),
        ),
      );
    });

    test('resolving a ticket states what was done', () {
      final Map<String, Object?> changes = ItTicket.resolveChanges(
        note: 'Cartridge replaced',
      );
      expect(changes['status'], 'resolved');
      expect(changes['resolution_note'], 'Cartridge replaced');
    });

    test('a ticket cannot be resolved without a note', () {
      expect(
        () => ItTicket.resolveChanges(note: '  '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'it_ticket_resolution_required',
          ),
        ),
      );
    });
  });

  group('use-case gates', () {
    late _RecordingProductivityRepository repository;

    setUp(() {
      repository = _RecordingProductivityRepository();
    });

    test('reading the board requires the read permission', () async {
      await expectLater(
        ReadBoardUseCase(repository: repository).call(
          policy: _policy(<String>{NodexPermissions.ticketsRead}),
          boardKey: 'ward.handover',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('moving a card requires the manage permission', () async {
      await expectLater(
        MoveWorkItemUseCase(repository: repository).call(
          policy: _policy(<String>{NodexPermissions.workItemsRead}),
          item: _card(),
          lane: WorkLane.doing,
        ),
        throwsA(isA<AuthorizationError>()),
      );
      expect(repository.moves, isEmpty);
    });

    test('moving a card writes the new lane', () async {
      await MoveWorkItemUseCase(repository: repository).call(
        policy: _policy(<String>{NodexPermissions.workItemsManage}),
        item: _card(),
        lane: WorkLane.doing,
      );
      expect(repository.moves.single['lane'], 'doing');
    });

    test('raising a ticket requires the submit permission', () async {
      await expectLater(
        RaiseTicketUseCase(repository: repository).call(
          policy: _policy(<String>{NodexPermissions.ticketsRead}),
          tenantId: 'tenant-1',
          ticketCode: 'IT-1',
          title: 'Printer out of paper',
          reportedBy: 'nurse-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      expect(repository.tickets, isEmpty);
    });

    test('resolving a closed ticket is refused', () async {
      const ItTicket closed = ItTicket(
        id: 'ticket-1',
        tenantId: 'tenant-1',
        ticketCode: 'IT-1',
        title: 'Printer out of paper',
        category: 'printer',
        priority: 'medium',
        status: 'resolved',
        reportedBy: 'nurse-1',
      );
      await expectLater(
        ResolveTicketUseCase(repository: repository).call(
          policy: _policy(<String>{NodexPermissions.ticketsManage}),
          ticket: closed,
          note: 'Cartridge replaced',
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('the scratchpad', () {
    test('notes are read back from the device', () async {
      final _RecordingProductivityRepository repository =
          _RecordingProductivityRepository();
      await WriteScratchpadUseCase(repository: repository)
          .call(note: 'Ask about the drain');
      final String? note = await ReadScratchpadUseCase(repository: repository)
          .call();
      expect(note, 'Ask about the drain');
    });

    test('the scratchpad needs no permission of its own', () async {
      // The notes are the clinician's own words on their own device; there is
      // nothing in them for a role to be allowed to see.
      final _RecordingProductivityRepository repository =
          _RecordingProductivityRepository();
      await WriteScratchpadUseCase(repository: repository).call(note: 'x');
      expect(await ReadScratchpadUseCase(repository: repository).call(), 'x');
    });
  });
}
