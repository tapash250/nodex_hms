/// Clinical object storage service.
///
/// DICOM/PACS images, clinical PDFs and encounter signatures live in Supabase
/// Storage; the clinical tables keep only references. This service owns the
/// three things that make an upload trustworthy, all enforced here rather than
/// left to each call site:
///
/// * **Tenant scoping.** Every path is written as `<tenant_id>/…` because the
///   bucket policies scope objects on that first segment. A path built any
///   other way is rejected locally instead of reaching the server only to be
///   refused, which would leave no useful record of why.
/// * **Checksum on upload.** The SHA-256 of the payload is computed before the
///   bytes leave the device and recorded as the object's `sha256` metadata,
///   which the bucket's insert policy requires. A tampered-in-transit file is
///   detectable rather than silently adopted.
/// * **Short-lived reads.** Downloads are granted through a signed URL whose
///   lifetime is capped at 60 seconds by default, so a link pasted into a handoff
///   note cannot be reused later.
///
/// The Supabase SDK stays inside the gateway; this class never imports it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// The buckets defined by the storage migration, by content class.
abstract final class ClinicalBuckets {
  /// DICOM/PACS studies and scans (Module 18).
  static const String imagingImages = 'clinical-images';

  /// Clinical PDFs and reports attached to an encounter.
  static const String documents = 'clinical-documents';

  /// Encounter signature images.
  static const String signatures = 'clinical-signatures';

  /// Every bucket this app writes to.
  static const Set<String> all = <String>{imagingImages, documents, signatures};
}

/// The result of an upload: where the object landed and what it hashed to.
final class StoredObject {
  /// Creates a stored-object descriptor.
  const StoredObject({
    required this.bucket,
    required this.path,
    required this.sha256,
  });

  /// Bucket the object was written to.
  final String bucket;

  /// Full object path, including the leading tenant segment.
  final String path;

  /// Lowercase hex SHA-256 of the uploaded bytes.
  final String sha256;
}

/// A reference to one stored object, as recorded on a clinical row.
///
/// The path is the full tenant-prefixed object path and the digest is the
/// checksum the uploader computed, so a reader can verify a fetched object
/// against what was recorded when it was written.
@immutable
final class StudyImageRef {
  /// Creates a reference.
  const StudyImageRef({required this.path, required this.sha256});

  /// Reads a reference list from a stored JSON value.
  ///
  /// Accepts the JSON-encoded string the local projection stores and a decoded
  /// list from the gateway, so the same entity construction works on both sides
  /// of the sync boundary. Anything unreadable decodes to empty rather than
  /// throwing: a row with a corrupt reference loses its objects, which is a
  /// recovery matter, not a crash.
  static List<StudyImageRef> decodeList(Object? raw) {
    final Object? value = raw is String && raw.isNotEmpty
        ? _tryDecode(raw)
        : raw;
    if (value is! List<Object?>) {
      return const <StudyImageRef>[];
    }
    return <StudyImageRef>[
      for (final Object? entry in value)
        if (entry is Map)
          StudyImageRef(path: '${entry['path']}', sha256: '${entry['sha256']}'),
    ];
  }

  /// Encodes [refs] to the JSON-encoded string the projection stores.
  ///
  /// Returns null for an empty list so a caller writing a row never overwrites
  /// existing references with a placeholder.
  static Object? encodeList(List<StudyImageRef> refs) {
    if (refs.isEmpty) {
      return null;
    }
    return jsonEncode(<Map<String, String>>[
      for (final StudyImageRef ref in refs)
        <String, String>{'path': ref.path, 'sha256': ref.sha256},
    ]);
  }

  static Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  /// Full object path, tenant-prefixed.
  final String path;

  /// Lowercase hex SHA-256 recorded at upload.
  final String sha256;

  @override
  bool operator ==(Object other) =>
      other is StudyImageRef && other.path == path && other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(path, sha256);
}

/// Uploads and reads clinical objects.
abstract interface class StorageService {
  /// Uploads [bytes] to [bucket] under [objectPath], prefixing [tenantId].
  ///
  ///
  /// [objectPath] is relative: it must not itself begin with the tenant, since
  /// the tenant prefix is applied here. Passing `../../etc` or an absolute
  /// path is rejected before any network call, because a traversal would write
  /// outside the tenant's scope and the bucket policy would refuse it anyway.
  Future<StoredObject> uploadFile({
    required String tenantId,
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String mimeType,
  });

  /// Resolves a 60-second signed URL for an object, or null when absent.
  Future<String?> getSecureUrl({
    required String tenantId,
    required String bucket,
    required String objectPath,
    int expiresInSeconds = 60,
  });

  /// Resolves a signed URL for an already-prefixed [path].
  Future<String?> getSecureUrlForPath({
    required String bucket,
    required String path,
    int expiresInSeconds = 60,
  });

  /// Removes an object. The bucket carries no delete policy, so this normally
  /// surfaces a refusal.
  Future<void> deleteFile({
    required String tenantId,
    required String bucket,
    required String objectPath,
  });
}

/// The narrow upload surface [GatewayStorageService] needs.
///
/// Abstracted rather than taking the gateway directly so a test can drive
/// the service against a recording double without a Supabase client, and so the
/// SDK stays confined to the gateway that satisfies this.
abstract interface class ObjectStore {
  /// Writes [bytes] to [bucket]/[path] with [metadata] alongside.
  Future<void> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
    required Map<String, String> metadata,
  });

  /// Mints an expiring URL for [bucket]/[path].
  Future<String?> signedUrl({
    required String bucket,
    required String path,
    required int expiresInSeconds,
  });

  /// Removes [bucket]/[path].
  Future<void> remove({required String bucket, required String path});
}

/// [StorageService] backed by the Supabase gateway.
final class GatewayStorageService implements StorageService {
  /// Creates the service over an object store.
  GatewayStorageService(this._store);

  final ObjectStore _store;

  @override
  Future<StoredObject> uploadFile({
    required String tenantId,
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final String path = _resolvePath(tenantId, bucket, objectPath);

    // Checksum before transmission: the bucket policy requires it, and a value
    // computed here is the one the reader can later verify against.
    final String digest = sha256.convert(bytes).toString();

    await _store.upload(
      bucket: bucket,
      path: path,
      bytes: bytes,
      mimeType: mimeType,
      metadata: <String, String>{'sha256': digest},
    );

    return StoredObject(bucket: bucket, path: path, sha256: digest);
  }

  @override
  Future<String?> getSecureUrl({
    required String tenantId,
    required String bucket,
    required String objectPath,
    int expiresInSeconds = 60,
  }) => _store.signedUrl(
    bucket: bucket,
    path: _resolvePath(tenantId, bucket, objectPath),
    expiresInSeconds: _capped(expiresInSeconds),
  );

  @override
  Future<String?> getSecureUrlForPath({
    required String bucket,
    required String path,
    int expiresInSeconds = 60,
  }) => _store.signedUrl(
    bucket: bucket,
    path: path,
    expiresInSeconds: _capped(expiresInSeconds),
  );

  @override
  Future<void> deleteFile({
    required String tenantId,
    required String bucket,
    required String objectPath,
  }) async {
    await _store.remove(
      bucket: bucket,
      path: _resolvePath(tenantId, bucket, objectPath),
    );
  }

  /// Composes the tenant-prefixed object path, refusing anything that would
  /// escape it.
  String _resolvePath(String tenantId, String bucket, String objectPath) {
    if (!ClinicalBuckets.all.contains(bucket)) {
      throw ValidationError(
        message: 'The bucket "$bucket" is not a clinical storage bucket.',
        code: 'storage_bucket_unknown',
      );
    }

    final String normalized = objectPath.trim().replaceAll(r'\', '/');

    // An absolute path is refused outright: the tenant prefix is applied here,
    // so a caller handing in an already-prefixed path is making a mistake that
    // stripping the leading slash would silently paper over.
    if (normalized.startsWith('/')) {
      throw const ValidationError(
        message:
            'The object path must be relative to the tenant, not absolute.',
        code: 'storage_path_invalid',
      );
    }

    // A drive letter or a scheme would put the write outside this bucket.
    if (RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(normalized)) {
      throw const ValidationError(
        message: 'The object path is not a valid path within the tenant.',
        code: 'storage_path_invalid',
      );
    }

    final List<String> segments = normalized
        .split('/')
        .where((String segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);

    // `..` anywhere, or an empty path, is a traversal or a no-op. Both are
    // refused here so the caller learns immediately.
    if (segments.isEmpty || segments.any((String s) => s == '..')) {
      throw const ValidationError(
        message: 'The object path is not a valid path within the tenant.',
        code: 'storage_path_invalid',
      );
    }

    return <String>[tenantId, ...segments].join('/');
  }

  /// Caps a requested expiry at 60 seconds.
  ///
  /// A caller asking for longer is asking for a credential that outlives the
  /// handoff it was created for. The cap is enforced here so a future call site
  /// cannot weaken it by passing a larger number.
  int _capped(int requested) =>
      requested <= 0 ? 60 : (requested > 60 ? 60 : requested);
}
