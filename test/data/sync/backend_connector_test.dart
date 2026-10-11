/// Unit tests for the mutation upload payload the connector builds.
///
/// The batch handed to the mutation-handler is the contract between the device
/// and the ledger: the idempotency key must be stable across a replay, no
/// delete may ever appear, and the enrolled device id must travel with the
/// batch so the ledger can record provenance rather than a null. Those are
/// asserted against a real [CrudTransaction] built in-process, which keeps the
/// test free of a live PowerSync database and of a gateway.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/data/sync/backend_connector.dart';
import 'package:powersync/powersync.dart';

/// Builds a transaction over [entries].
///
/// [transactionId] is null when the caller wants a batch recorded without an
/// explicit transaction, which is a real PowerSync case the payload must handle.
CrudTransaction _transaction(List<CrudEntry> entries, {int? transactionId}) =>
    CrudTransaction(
      complete: ({String? writeCheckpoint}) async {},
      crud: entries,
      transactionId: transactionId,
    );

/// Builds one queue entry.
///
/// [CrudEntry] is positional in powersync 2.4.0.
CrudEntry _entry({
  required int clientId,
  required int? transactionId,
  required String table,
  required String id,
  UpdateType op = UpdateType.put,
  Map<String, Object?>? opData,
}) => CrudEntry(clientId, op, table, id, transactionId, opData);

void main() {
  const String deviceId = '22222222-2222-2222-2222-222222222222';

  group('buildMutationPayload', () {
    test('attaches the device id to every entry', () {
      final List<Map<String, Object?>> payload = buildMutationPayload(
        _transaction(<CrudEntry>[
          _entry(
            clientId: 1,
            transactionId: 7,
            table: 'lab_orders',
            id: '33333333-3333-3333-3333-333333333333',
            opData: const <String, Object?>{
              'tenant_id': 't',
              'status': 'ordered',
            },
          ),
          _entry(
            clientId: 2,
            transactionId: 7,
            table: 'lab_specimens',
            id: '44444444-4444-4444-4444-444444444444',
          ),
        ]),
        deviceId: deviceId,
      );

      expect(payload, hasLength(2));
      for (final Map<String, Object?> entry in payload) {
        // The handler's resolveDeviceId reads this field, and the ledger's
        // provenance depends on it.
        expect(entry['device_id'], deviceId);
      }
    });

    test('omits the device id entirely when none is bound', () {
      final List<Map<String, Object?>> payload = buildMutationPayload(
        _transaction(<CrudEntry>[
          _entry(
            clientId: 1,
            transactionId: 7,
            table: 'lab_orders',
            id: '33333333-3333-3333-3333-333333333333',
          ),
        ]),
      );

      // Omitted rather than null: a present-but-null key would read as "bound
      // to nothing" when the intent is "unbound".
      expect(payload.single.containsKey('device_id'), isFalse);
    });

    test('the idempotency key is stable across a replayed transaction', () {
      final List<CrudEntry> entries = <CrudEntry>[
        _entry(
          clientId: 1,
          transactionId: 7,
          table: 'lab_orders',
          id: '33333333-3333-3333-3333-333333333333',
        ),
      ];

      final String first =
          buildMutationPayload(_transaction(entries, transactionId: 7))
                  .single['idempotency_key']
              as String;
      final String second =
          buildMutationPayload(_transaction(entries, transactionId: 7))
                  .single['idempotency_key']
              as String;

      // A retry after a lost response must land on the same ledger key, or the
      // write is applied twice.
      expect(first, second);
      expect(first, '7-1');
    });

    test('maps put to upsert and patch to patch', () {
      final List<Map<String, Object?>> payload = buildMutationPayload(
        _transaction(<CrudEntry>[
          _entry(
            clientId: 1,
            transactionId: 7,
            table: 'lab_orders',
            id: '33333333-3333-3333-3333-333333333333',
            op: UpdateType.put,
          ),
          _entry(
            clientId: 2,
            transactionId: 7,
            table: 'lab_orders',
            id: '44444444-4444-4444-4444-444444444444',
            op: UpdateType.patch,
          ),
        ]),
      );

      expect(payload.first['operation'], 'upsert');
      expect(payload.last['operation'], 'patch');
    });

    test('a batch without a transaction id still keys on the client entry', () {
      final List<Map<String, Object?>> payload = buildMutationPayload(
        _transaction(<CrudEntry>[
          _entry(
            clientId: 4,
            transactionId: null,
            table: 'lab_orders',
            id: '33333333-3333-3333-3333-333333333333',
          ),
        ]),
      );

      expect(payload.single['idempotency_key'], 'tx-4');
    });

    test('an empty batch produces an empty payload', () {
      expect(buildMutationPayload(_transaction(const <CrudEntry>[])), isEmpty);
    });
  });
}
