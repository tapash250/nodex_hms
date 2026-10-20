/// Portal repository (Module 05).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Reads the link between a portal account and a patient record.
abstract interface class PortalRepository {
  /// The patient a portal account may read, or null when there is no link.
  Future<String?> resolvePatientId(String portalUserId);
}

/// PowerSync-backed portal repository.
final class DefaultPortalRepository implements PortalRepository {
  /// Creates a repository over a local store.
  DefaultPortalRepository({required this._store, required this._logger});

  static const String _module = 'domain.portal';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<String?> resolvePatientId(String portalUserId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.patientPortalLinks} WHERE portal_user_id = ? '
        'AND revoked_at IS NULL',
        <Object?>[portalUserId],
      );
      if (rows.isEmpty) return null;
      return rows.first['patient_id'] as String?;
    } on Object catch (error, stackTrace) {
      if (error is NodexError) rethrow;
      final NodexError mapped = NodexErrorMapper.map(
        error,
        operation: 'portal.resolve',
      );
      _logger.error(
        _module,
        'Portal repository failure.',
        operation: 'portal.resolve',
        outcome: 'failed',
        errorCode: mapped.code,
        stackTrace: stackTrace,
      );
      throw mapped;
    }
  }
}
