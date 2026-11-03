/// Upload-pipeline contract tests.
///
/// These exercise the four failure modes the codebase audit found in the
/// PowerSync upload path: a server conflict that was treated as a permanent
/// rejection, positional decision matching that could skip entries, a hard
/// delete that could wedge the retry queue, and an oversized batch that the
/// server rejects with HTTP 413.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/sync/conflict_policy.dart';
import 'package:nodex_hms/data/sync/backend_connector.dart';
import 'package:nodex_hms/data/sync/mutation_batch.dart';
import 'package:powersync/powersync.dart';

CrudTransaction _transaction(
  List<CrudEntry> entries, {
  int? transactionId,
  void Function()? onComplete,
}) => CrudTransaction(
  complete: ({String? writeCheckpoint}) async {
    onComplete?.call();
  },
  crud: entries,
  transactionId: transactionId,
);

CrudEntry _entry({
  required int clientId,
  required String table,
  String? id,
  UpdateType op = UpdateType.put,
  Map<String, Object?>? opData,
  int? transactionId,
}) => CrudEntry(
  clientId,
  op,
  table,
  id ?? '00000000-0000-4000-8000-${clientId.toString().padLeft(12, '0')}',
  transactionId,
  opData,
);

MutationUploader _uploader(
  MutationSubmitter submit, {
  MutationJournal? journal,
}) => MutationUploader(
  submit: submit,
  logger: NodexLogger(sinks: <NodexLogSink>[]),
  journal: journal,
);

final class _RecordingJournal implements MutationJournal {
  final List<MutationJournalRecord> records = <MutationJournalRecord>[];
  int reconciliations = 0;
  bool fail = false;

  @override
  Future<void> record(MutationJournalRecord record) async {
    if (fail) {
      throw const PersistenceError(
        message: 'journal unavailable',
        code: 'journal_unavailable',
      );
    }
    records.add(record);
  }

  @override
  Future<void> reconcileServerAuthoritative(
    MutationJournalRecord record,
  ) async {
    reconciliations++;
  }
}

List<MutationDecision> _applied(List<Map<String, Object?>> payload) =>
    <MutationDecision>[
      for (final Map<String, Object?> mutation in payload)
        MutationDecision(
          mutationId: mutation['id']! as String,
          outcome: MutationOutcome.applied,
        ),
    ];

List<MutationDecision> _conflict(List<Map<String, Object?>> payload) =>
    <MutationDecision>[
      for (final Map<String, Object?> mutation in payload)
        MutationDecision(
          mutationId: mutation['id']! as String,
          outcome: MutationOutcome.rejected,
          rejectionClass: 'conflict',
          detail: 'conflicting key value',
        ),
    ];

void main() {
  const String deviceId = '22222222-2222-2222-2222-222222222222';

  group('conflict decisions', () {
    test('a transactional conflict stays queued for reconciliation', () async {
      int completions = 0;
      final CrudTransaction transaction = _transaction(
        <CrudEntry>[
          _entry(clientId: 1, table: 'stock_movements', transactionId: 7),
        ],
        transactionId: 7,
        onComplete: () => completions++,
      );

      Future<List<MutationDecision>> submit(
        List<Map<String, Object?>> mutations, {
        String? deviceId,
      }) async => _conflict(mutations);

      await expectLater(
        _uploader(submit).upload(transaction, deviceId: deviceId),
        throwsA(isA<SyncConflictError>()),
      );
      expect(completions, 0);
    });

    test(
      'a server-authoritative conflict discards the local projection',
      () async {
        int completions = 0;
        final CrudTransaction transaction = _transaction(
          <CrudEntry>[
            _entry(clientId: 1, table: 'bed_assignments', transactionId: 7),
          ],
          transactionId: 7,
          onComplete: () => completions++,
        );

        Future<List<MutationDecision>> submit(
          List<Map<String, Object?>> mutations, {
          String? deviceId,
        }) async => _conflict(mutations);

        final UploadOutcome outcome = await _uploader(submit)
            .upload(transaction, deviceId: deviceId);

        expect(outcome, UploadOutcome.conflicted);
        expect(completions, 1);
      },
    );

    test('the registered policy is named on the error', () async {
      final CrudTransaction transaction = _transaction(<CrudEntry>[
        _entry(clientId: 1, table: 'stock_movements', transactionId: 7),
      ], transactionId: 7);

      Future<List<MutationDecision>> submit(
        List<Map<String, Object?>> mutations, {
        String? deviceId,
      }) async => _conflict(mutations);

      await expectLater(
        _uploader(submit).upload(transaction),
        throwsA(
          isA<SyncConflictError>()
              .having(
                (SyncConflictError error) => error.policy,
                'policy',
                ConflictPolicy.transactional.wireValue,
              )
              .having(
                (SyncConflictError error) => error.requiresHumanReview,
                'requiresHumanReview',
                isFalse,
              ),
        ),
      );
    });
  });

  group('decision matching', () {
    test('a short response throws before the transaction completes', () async {
      int completions = 0;
      final CrudTransaction transaction = _transaction(
        <CrudEntry>[
          _entry(clientId: 1, table: 'lab_orders', transactionId: 7),
          _entry(clientId: 2, table: 'lab_orders', transactionId: 7),
        ],
        transactionId: 7,
        onComplete: () => completions++,
      );

      Future<List<MutationDecision>> submit(
        List<Map<String, Object?>> mutations, {
        String? deviceId,
      }) async => _applied(mutations).take(1).toList();

      await expectLater(
        _uploader(submit).upload(transaction),
        throwsA(
          isA<RemoteError>().having(
            (RemoteError error) => error.code,
            'code',
            'mutation_decision_count_mismatch',
          ),
        ),
      );
      expect(completions, 0);
    });

    test(
      'an unknown decision id throws before the transaction completes',
      () async {
        int completions = 0;
        final CrudTransaction transaction = _transaction(
          <CrudEntry>[
            _entry(clientId: 1, table: 'lab_orders', transactionId: 7),
          ],
          transactionId: 7,
          onComplete: () => completions++,
        );

        Future<List<MutationDecision>> submit(
          List<Map<String, Object?>> mutations, {
          String? deviceId,
        }) async => <MutationDecision>[
          const MutationDecision(
            mutationId: '99999999-9999-4999-8999-999999999999',
            outcome: MutationOutcome.applied,
          ),
        ];

        await expectLater(
          _uploader(submit).upload(transaction),
          throwsA(
            isA<RemoteError>().having(
              (RemoteError error) => error.code,
              'code',
              'mutation_decision_id_mismatch',
            ),
          ),
        );
        expect(completions, 0);
      },
    );

    test('decisions are matched by id, not by position', () async {
      final CrudTransaction transaction = _transaction(<CrudEntry>[
        _entry(clientId: 1, table: 'lab_orders', transactionId: 7),
        _entry(clientId: 2, table: 'lab_orders', transactionId: 7),
      ], transactionId: 7);

      Future<List<MutationDecision>> submit(
        List<Map<String, Object?>> mutations, {
        String? deviceId,
      }) async => _applied(mutations).reversed.toList();

      final UploadOutcome outcome = await _uploader(submit).upload(transaction);
      expect(outcome, UploadOutcome.accepted);
    });
  });

  group('hard deletes', () {
    test(
      'a hard delete is classified and the transaction is completed',
      () async {
        int completions = 0;
        int submissions = 0;
        final CrudTransaction transaction = _transaction(
          <CrudEntry>[
            _entry(
              clientId: 1,
              table: 'patients',
              op: UpdateType.delete,
              transactionId: 7,
            ),
          ],
          transactionId: 7,
          onComplete: () => completions++,
        );

        Future<List<MutationDecision>> submit(
          List<Map<String, Object?>> mutations, {
          String? deviceId,
        }) async {
          submissions++;
          return _applied(mutations);
        }

        final UploadOutcome outcome = await _uploader(submit)
            .upload(transaction);

        expect(outcome, UploadOutcome.rejected);
        expect(submissions, 0);
        expect(completions, 1);
      },
    );
  });

  group('chunking', () {
    test(
      'a transaction larger than the server cap is sent in chunks',
      () async {
        final List<CrudEntry> entries = <CrudEntry>[
          for (int clientId = 1; clientId <= 250; clientId++)
            _entry(clientId: clientId, table: 'lab_orders', transactionId: 7),
        ];
        int completions = 0;
        final List<int> sizes = <int>[];
        final CrudTransaction transaction = _transaction(
          entries,
          transactionId: 7,
          onComplete: () => completions++,
        );

        Future<List<MutationDecision>> submit(
          List<Map<String, Object?>> mutations, {
          String? deviceId,
        }) async {
          sizes.add(mutations.length);
          return _applied(mutations);
        }

        final UploadOutcome outcome = await _uploader(submit)
            .upload(transaction, deviceId: deviceId);

        expect(outcome, UploadOutcome.accepted);
        expect(sizes, <int>[100, 100, 50]);
        expect(completions, 1);
      },
    );

    test('the transaction is not completed when a later chunk fails', () async {
      final List<CrudEntry> entries = <CrudEntry>[
        for (int clientId = 1; clientId <= 150; clientId++)
          _entry(clientId: clientId, table: 'lab_orders', transactionId: 7),
      ];
      int completions = 0;
      int calls = 0;
      final List<int> sizes = <int>[];
      final CrudTransaction transaction = _transaction(
        entries,
        transactionId: 7,
        onComplete: () => completions++,
      );

      Future<List<MutationDecision>> submit(
        List<Map<String, Object?>> mutations, {
        String? deviceId,
      }) async {
        calls++;
        sizes.add(mutations.length);
        if (calls == 2) {
          throw const ConnectivityError(message: 'offline');
        }
        return _applied(mutations);
      }

      await expectLater(
        _uploader(submit).upload(transaction),
        throwsA(isA<ConnectivityError>()),
      );
      expect(sizes, <int>[100, 50]);
      expect(completions, 0);
    });
  });

  group('authentication failures', () {
    test('a 401 leaves the batch queued for a token refresh', () async {
      int completions = 0;
      final CrudTransaction transaction = _transaction(
        <CrudEntry>[_entry(clientId: 1, table: 'lab_orders', transactionId: 7)],
        transactionId: 7,
        onComplete: () => completions++,
      );

      Future<List<MutationDecision>> submit(
        List<Map<String, Object?>> mutations, {
        String? deviceId,
      }) async => throw const RemoteError(
        message: 'token expired',
        statusCode: 401,
        isTransient: true,
        code: 'mutation_authentication_expired',
      );

      await expectLater(
        _uploader(submit).upload(transaction),
        throwsA(isA<RemoteError>()),
      );
      expect(completions, 0);
    });

    test('an AuthorizationError is not treated as permanent', () async {
      int completions = 0;
      final CrudTransaction transaction = _transaction(
        <CrudEntry>[_entry(clientId: 1, table: 'lab_orders', transactionId: 7)],
        transactionId: 7,
        onComplete: () => completions++,
      );

      Future<List<MutationDecision>> submit(
        List<Map<String, Object?>> mutations, {
        String? deviceId,
      }) async => throw const AuthorizationError(
        message: 'no session',
        code: 'no_session',
      );

      await expectLater(
        _uploader(submit).upload(transaction),
        throwsA(isA<AuthorizationError>()),
      );
      expect(completions, 0);
    });
  });

  group('rejection journal', () {
    test('a rejected entry is recorded before the queue is cleared', () async {
      final _RecordingJournal journal = _RecordingJournal();
      bool recordedBeforeComplete = false;
      final CrudTransaction transaction = _transaction(
        <CrudEntry>[_entry(clientId: 1, table: 'lab_orders', transactionId: 7)],
        transactionId: 7,
        onComplete: () => recordedBeforeComplete = journal.records.isNotEmpty,
      );

      Future<List<MutationDecision>> submit(
        List<Map<String, Object?>> mutations, {
        String? deviceId,
      }) async => <MutationDecision>[
        for (final Map<String, Object?> mutation in mutations)
          MutationDecision(
            mutationId: mutation['id']! as String,
            outcome: MutationOutcome.rejected,
            rejectionClass: 'forbidden',
            detail: 'permission denied',
          ),
      ];

      final UploadOutcome outcome = await _uploader(
        submit,
        journal: journal,
      ).upload(transaction);

      expect(outcome, UploadOutcome.rejected);
      expect(journal.records, hasLength(1));
      expect(journal.records.single.status, 'rejected');
      expect(journal.records.single.rejectionClass, 'forbidden');
      expect(journal.records.single.idempotencyKey, '7-1');
      expect(recordedBeforeComplete, isTrue);
    });

    test(
      'a server-authoritative conflict is recorded and reconciled first',
      () async {
        final _RecordingJournal journal = _RecordingJournal();
        bool recordedBeforeComplete = false;
        final CrudTransaction transaction = _transaction(
          <CrudEntry>[
            _entry(clientId: 1, table: 'bed_assignments', transactionId: 7),
          ],
          transactionId: 7,
          onComplete: () => recordedBeforeComplete = journal.records.isNotEmpty,
        );

        Future<List<MutationDecision>> submit(
          List<Map<String, Object?>> mutations, {
          String? deviceId,
        }) async => _conflict(mutations);

        final UploadOutcome outcome = await _uploader(
          submit,
          journal: journal,
        ).upload(transaction);

        expect(outcome, UploadOutcome.conflicted);
        expect(journal.records, hasLength(1));
        expect(journal.records.single.status, 'server_authoritative');
        expect(journal.reconciliations, 1);
        expect(recordedBeforeComplete, isTrue);
      },
    );

    test('a journal failure keeps the batch queued', () async {
      int completions = 0;
      final _RecordingJournal journal = _RecordingJournal()..fail = true;
      final CrudTransaction transaction = _transaction(
        <CrudEntry>[_entry(clientId: 1, table: 'lab_orders', transactionId: 7)],
        transactionId: 7,
        onComplete: () => completions++,
      );

      Future<List<MutationDecision>> submit(
        List<Map<String, Object?>> mutations, {
        String? deviceId,
      }) async => <MutationDecision>[
        for (final Map<String, Object?> mutation in mutations)
          MutationDecision(
            mutationId: mutation['id']! as String,
            outcome: MutationOutcome.rejected,
            rejectionClass: 'forbidden',
          ),
      ];

      await expectLater(
        _uploader(submit, journal: journal).upload(transaction),
        throwsA(isA<PersistenceError>()),
      );
      expect(completions, 0);
    });
  });
}
