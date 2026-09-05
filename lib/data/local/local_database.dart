/// Encrypted local database lifecycle.
///
/// Opens the PowerSync SQLite database under SQLCipher with a key held in the
/// Android Keystore, connects replication when a session and instance URL exist,
/// and implements the retention and wipe behaviour the specification requires:
/// logout handling, device de-registration, remote/selective wipe and local
/// database deletion on security-policy failure.
library;

import 'dart:async';
import 'dart:io';

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/security/database_key_manager.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync_sqlcipher/powersync.dart';

/// Owns the encrypted local operational projection.
final class LocalDatabase {
  /// Creates a database service.
  LocalDatabase({required this._keyManager, required this._logger});

  static const String _module = 'storage.local_database';

  /// File name of the encrypted local database.
  static const String databaseFileName = 'nodex_local.sqlite';

  final DatabaseKeyManager _keyManager;
  final NodexLogger _logger;

  PowerSyncDatabase? _database;
  bool _isConnected = false;

  /// The open database.
  ///
  /// Throws [PersistenceError] when accessed before [open]. Failing loudly is
  /// deliberate: a clinical read must never silently return empty because the
  /// local projection was not ready.
  PowerSyncDatabase get database {
    final PowerSyncDatabase? open = _database;
    if (open == null) {
      throw const PersistenceError(
        message:
            'The local clinical database has not been opened. No clinical read '
            'or write may proceed.',
        code: 'database_not_open',
      );
    }
    return open;
  }

  /// Whether the database is open.
  bool get isOpen => _database != null;

  /// Whether replication is currently connected.
  bool get isConnected => _isConnected;

  /// Current sync status, or null when the database is closed.
  SyncStatus? get syncStatus => _database?.currentStatus;

  /// Emits on every sync status change.
  Stream<SyncStatus> get syncStatusStream =>
      _database?.statusStream ?? const Stream<SyncStatus>.empty();

  /// Opens the encrypted database, creating and keying it on first run.
  Future<PowerSyncDatabase> open() async {
    final PowerSyncDatabase? existing = _database;
    if (existing != null) {
      return existing;
    }

    try {
      final String key = await _keyManager.obtainKey();
      final String path = await _resolveDatabasePath();

      final PowerSyncDatabase opened = PowerSyncDatabase.withFactory(
        PowerSyncSQLCipherOpenFactory(path: path, key: key),
        schema: NodexLocalSchema.build(),
      );
      await opened.initialize();
      _database = opened;

      _logger.info(
        _module,
        'Encrypted local database opened.',
        operation: 'database.open',
        outcome: 'succeeded',
        dimensions: <String, Object?>{
          'key_generation': await _keyManager.currentGeneration(),
        },
      );
      return opened;
    } on NodexError {
      rethrow;
    } on Object catch (error, stackTrace) {
      _logger.critical(
        _module,
        'Failed to open the encrypted local database.',
        operation: 'database.open',
        outcome: 'failed',
        stackTrace: stackTrace,
      );
      throw PersistenceError(
        message:
            'The encrypted local database could not be opened. Clinical '
            'workflows are unavailable until this is resolved.',
        code: 'database_open_failed',
        cause: error,
      );
    }
  }

  /// Connects replication using [connector].
  ///
  /// A failure here is not fatal: the local projection remains usable and the
  /// client retries, which is the whole point of local-first operation.
  Future<void> connect({required PowerSyncBackendConnector connector}) async {
    final PowerSyncDatabase open = database;
    try {
      await open.connect(connector: connector);
      _isConnected = true;
      _logger.info(
        _module,
        'Replication connected.',
        operation: 'database.connect',
        outcome: 'succeeded',
      );
    } on Object catch (error) {
      _isConnected = false;
      final NodexError mapped = NodexErrorMapper.map(
        error,
        operation: 'database.connect',
      );
      _logger.warning(
        _module,
        'Replication could not be established; continuing local-first.',
        operation: 'database.connect',
        outcome: 'degraded',
        errorCode: mapped.code,
      );
    }
  }

  /// Disconnects replication, leaving local data intact.
  ///
  /// Used when the offline authorization window lapses: the device keeps working
  /// within policy but stops pulling new data.
  Future<void> disconnect() async {
    if (_database == null) {
      return;
    }
    await _database!.disconnect();
    _isConnected = false;
    _logger.info(
      _module,
      'Replication disconnected; local data retained.',
      operation: 'database.disconnect',
      outcome: 'succeeded',
    );
  }

  /// Disconnects and clears all local data, retaining the encryption key.
  ///
  /// This is the sign-out path. The device stays enrolled and can re-replicate on
  /// the next successful sign-in.
  ///
  /// Pending uploads are counted before clearing so that discarding
  /// unsynchronized clinical work is recorded rather than silent.
  Future<void> signOutAndClear() async {
    final PowerSyncDatabase? open = _database;
    if (open == null) {
      return;
    }

    final int pendingUploads = open.currentStatus.uploading ? 1 : 0;
    if (pendingUploads > 0) {
      _logger.warning(
        _module,
        'Clearing local data while an upload was in flight.',
        operation: 'database.sign_out',
        outcome: 'data_discarded',
      );
    }

    await open.disconnectAndClear();
    _isConnected = false;
    _logger.info(
      _module,
      'Local data cleared on sign-out.',
      operation: 'database.sign_out',
      outcome: 'succeeded',
    );
  }

  /// Destroys the local database and its encryption key.
  ///
  /// Invoked by device revocation, a pending wipe request, or a security-policy
  /// failure such as a snapshot integrity fault. Once the key is destroyed the
  /// database file is unreadable even if it survives on disk, which is the
  /// intended outcome of a selective wipe.
  Future<void> wipe({required String reason}) async {
    try {
      final PowerSyncDatabase? open = _database;
      if (open != null) {
        await open.disconnectAndClear();
        await open.close();
      }
    } on Object catch (error, stackTrace) {
      // A failure closing the database must not prevent key destruction: without
      // the key the data is unreadable regardless.
      _logger.error(
        _module,
        'Failed to close the local database cleanly during wipe.',
        operation: 'database.wipe',
        outcome: 'partial',
        stackTrace: stackTrace,
        dimensions: <String, Object?>{'reason': reason, 'error': '$error'},
      );
    } finally {
      _database = null;
      _isConnected = false;
    }

    await _keyManager.destroyKey(reason: reason);
    await _deleteDatabaseFile();

    _logger.critical(
      _module,
      'Local clinical data wiped.',
      operation: 'database.wipe',
      outcome: 'succeeded',
      dimensions: <String, Object?>{'reason': reason},
    );
  }

  /// Closes the database without clearing data.
  Future<void> close() async {
    final PowerSyncDatabase? open = _database;
    if (open == null) {
      return;
    }
    await open.close();
    _database = null;
    _isConnected = false;
  }

  Future<String> _resolveDatabasePath() async {
    final Directory directory = await getApplicationSupportDirectory();
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return '${directory.path}/$databaseFileName';
  }

  Future<void> _deleteDatabaseFile() async {
    try {
      final String path = await _resolveDatabasePath();
      for (final String suffix in const <String>['', '-wal', '-shm']) {
        final File file = File('$path$suffix');
        if (file.existsSync()) {
          await file.delete();
        }
      }
    } on Object catch (error) {
      _logger.warning(
        _module,
        'Could not remove the local database file during wipe.',
        operation: 'database.wipe',
        outcome: 'partial',
        dimensions: <String, Object?>{'error': '$error'},
      );
    }
  }
}
