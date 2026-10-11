/// Unit tests for [StorageService].
///
/// The service's job is the guarantees it adds on top of the gateway — tenant
/// path composition, checksum metadata, the 60-second cap, and refusing a path
/// that would escape the tenant. Those are asserted against a recording gateway
/// that captures exactly what would cross the network, so a regression in any of
/// them fails here rather than at a bucket policy.
///
/// The gateway itself is a concrete class, so the seam used is a minimal
/// subclass overriding the three storage methods; everything the service calls
/// beyond them is irrelevant to these tests.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/storage/storage_service.dart';

/// Records what the service asked the store to do, and serves canned replies.
final class RecordingStore implements ObjectStore {
  /// Arguments captured on the last [upload] call.
  String? uploadedBucket;
  String? uploadedPath;
  Uint8List? uploadedBytes;
  String? uploadedMime;
  Map<String, String>? uploadedMetadata;

  /// Arguments captured on the last signed-URL call.
  String? signedBucket;
  String? signedPath;
  int? signedExpiry;

  /// Reply the next signed-URL call returns.
  String? signedUrlReply;

  /// Target of the last removal.
  String? removedBucket;
  String? removedPath;

  int uploadCalls = 0;
  int removeCalls = 0;

  @override
  Future<void> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
    required Map<String, String> metadata,
  }) async {
    uploadCalls++;
    uploadedBucket = bucket;
    uploadedPath = path;
    uploadedBytes = bytes;
    uploadedMime = mimeType;
    uploadedMetadata = metadata;
  }

  @override
  Future<String?> signedUrl({
    required String bucket,
    required String path,
    required int expiresInSeconds,
  }) async {
    signedBucket = bucket;
    signedPath = path;
    signedExpiry = expiresInSeconds;
    return signedUrlReply;
  }

  @override
  Future<void> remove({required String bucket, required String path}) async {
    removeCalls++;
    removedBucket = bucket;
    removedPath = path;
  }
}

/// A known digest: SHA-256 of the ASCII bytes `abc`.
const String _sha256Abc =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

void main() {
  const String tenantId = '11111111-1111-1111-1111-111111111111';

  late RecordingStore store;
  late GatewayStorageService service;

  setUp(() {
    store = RecordingStore();
    service = GatewayStorageService(store);
  });

  group('uploadFile', () {
    test('prefixes the tenant and records the checksum as metadata', () async {
      final StoredObject stored = await service.uploadFile(
        tenantId: tenantId,
        bucket: ClinicalBuckets.imagingImages,
        objectPath: 'studies/abc/slice-1.dcm',
        bytes: Uint8List.fromList(<int>[97, 98, 99]),
        mimeType: 'application/dicom',
      );

      // The path's first segment is the tenant, which is what storage RLS
      // scopes on.
      expect(stored.path, '$tenantId/studies/abc/slice-1.dcm');
      expect(store.uploadedBucket, ClinicalBuckets.imagingImages);
      expect(store.uploadedPath, stored.path);
      expect(store.uploadedBytes, Uint8List.fromList(<int>[97, 98, 99]));
      expect(store.uploadedMime, 'application/dicom');
      // The checksum is computed client-side and carried as metadata, which the
      // bucket's insert policy requires.
      expect(stored.sha256, _sha256Abc);
      expect(store.uploadedMetadata?['sha256'], _sha256Abc);
    });

    test('refuses an unknown bucket before any network call', () async {
      await expectLater(
        service.uploadFile(
          tenantId: tenantId,
          bucket: 'clinical-everything',
          objectPath: 'x.bin',
          bytes: Uint8List.fromList(<int>[1]),
          mimeType: 'application/octet-stream',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError e) => e.code,
            'code',
            'storage_bucket_unknown',
          ),
        ),
      );
      expect(store.uploadCalls, 0);
    });

    test('refuses a traversal before any network call', () async {
      for (final String path in <String>[
        '../../etc/passwd',
        'studies/../../escape',
        '/absolute/path',
      ]) {
        await expectLater(
          service.uploadFile(
            tenantId: tenantId,
            bucket: ClinicalBuckets.documents,
            objectPath: path,
            bytes: Uint8List.fromList(<int>[1]),
            mimeType: 'application/pdf',
          ),
          throwsA(
            isA<ValidationError>().having(
              (ValidationError e) => e.code,
              'code',
              'storage_path_invalid',
            ),
          ),
          reason: 'expected "$path" to be refused',
        );
      }
      expect(store.uploadCalls, 0);
    });

    test('does not double-prefix a tenant already supplied', () async {
      final StoredObject stored = await service.uploadFile(
        tenantId: tenantId,
        bucket: ClinicalBuckets.documents,
        objectPath: 'consults/c1/a1/recording',
        bytes: Uint8List.fromList(<int>[97]),
        mimeType: 'audio/webm',
      );
      expect(stored.path.startsWith(tenantId), isTrue);
      expect(
        stored.path.split('/').where((String s) => s == tenantId).length,
        1,
      );
    });
  });

  group('getSecureUrl', () {
    test('resolves a 60-second URL for the tenant-scoped path', () async {
      store.signedUrlReply = 'https://example/signed?token=abc';
      final String? url = await service.getSecureUrl(
        tenantId: tenantId,
        bucket: ClinicalBuckets.signatures,
        objectPath: 'e1/sig.png',
      );

      expect(url, 'https://example/signed?token=abc');
      expect(store.signedBucket, ClinicalBuckets.signatures);
      expect(store.signedPath, '$tenantId/e1/sig.png');
      expect(store.signedExpiry, 60);
    });

    test('caps a longer requested expiry at 60 seconds', () async {
      await service.getSecureUrl(
        tenantId: tenantId,
        bucket: ClinicalBuckets.documents,
        objectPath: 'x/y.pdf',
        expiresInSeconds: 3600,
      );
      // The cap exists so a call site cannot mint a credential that outlives
      // the handoff it was created for.
      expect(store.signedExpiry, 60);
    });

    test('treats a non-positive expiry as the default', () async {
      await service.getSecureUrl(
        tenantId: tenantId,
        bucket: ClinicalBuckets.documents,
        objectPath: 'x/y.pdf',
        expiresInSeconds: 0,
      );
      expect(store.signedExpiry, 60);
    });

    test('returns null when the object is absent', () async {
      store.signedUrlReply = null;
      final String? url = await service.getSecureUrl(
        tenantId: tenantId,
        bucket: ClinicalBuckets.imagingImages,
        objectPath: 'studies/none/slice.dcm',
      );
      // A study with no image yet resolves nothing rather than failing.
      expect(url, isNull);
    });

    test('forPath serves an already-prefixed path unchanged', () async {
      store.signedUrlReply = 'https://example/s2';
      const String prefixed = '$tenantId/studies/x/slice.dcm';
      await service.getSecureUrlForPath(
        bucket: ClinicalBuckets.imagingImages,
        path: prefixed,
      );
      expect(store.signedPath, prefixed);
      expect(store.signedExpiry, 60);
    });
  });

  group('deleteFile', () {
    test('forwards the tenant-scoped path', () async {
      await service.deleteFile(
        tenantId: tenantId,
        bucket: ClinicalBuckets.documents,
        objectPath: 'consults/c1/a1/recording',
      );
      expect(store.removeCalls, 1);
      expect(store.removedBucket, ClinicalBuckets.documents);
      expect(store.removedPath, '$tenantId/consults/c1/a1/recording');
    });

    test('refuses a traversal before any network call', () async {
      await expectLater(
        service.deleteFile(
          tenantId: tenantId,
          bucket: ClinicalBuckets.documents,
          objectPath: '../escape',
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(store.removeCalls, 0);
    });
  });

  group('StudyImageRef', () {
    test('round-trips through the encoding the projection stores', () {
      const List<StudyImageRef> refs = <StudyImageRef>[
        StudyImageRef(path: 't/s/a.dcm', sha256: 'aa'),
        StudyImageRef(path: 't/s/b.dcm', sha256: 'bb'),
      ];
      final Object? encoded = StudyImageRef.encodeList(refs);
      expect(encoded, isA<String>());
      expect(StudyImageRef.decodeList(encoded), refs);
    });

    test('decodes a corrupt value to empty rather than throwing', () {
      expect(StudyImageRef.decodeList('not json'), isEmpty);
      expect(StudyImageRef.decodeList(null), isEmpty);
      expect(StudyImageRef.decodeList(<Object?>[1, 2, 3]), isEmpty);
    });
  });
}
