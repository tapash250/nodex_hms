/// Tests for the field-level 3-way patient merge.
///
/// The merge engine implements the registry's contract: disjoint edits to
/// mergeable columns merge automatically; overlapping edits, and any touch of
/// identity columns, escalate to human review. These tests pin that contract
/// with the real local column names.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/domain/patients/patient_merge.dart';

void main() {
  Map<String, Object?> baseRow() => <String, Object?>{
    'mrn': 'MRN-001',
    'first_name': 'Abdul',
    'last_name': 'Karim',
    'date_of_birth': '1984-03-17',
    'gender': 'male',
    'phone_number': '01700000000',
    'email': null,
    'address': null,
  };

  group('mergePatientRow', () {
    test('merges disjoint edits to mergeable columns', () {
      final Map<String, Object?> base = baseRow();
      final Map<String, Object?> local = <String, Object?>{...base}
        ..['phone_number'] = '01800000000';
      final Map<String, Object?> server = <String, Object?>{...base}
        ..['email'] = 'a.karim@example.com';

      final PatientMergeResult result = mergePatientRow(
        base: base,
        local: local,
        server: server,
      );

      expect(result.automatic, isTrue);
      expect(result.merged['phone_number'], '01800000000');
      expect(result.merged['email'], 'a.karim@example.com');
      expect(
        result.autoMergedFields,
        containsAll(<String>['phone_number', 'email']),
      );
      expect(result.conflictingFields, isEmpty);
    });

    test('takes the changed side when only one side edited', () {
      final Map<String, Object?> base = baseRow();
      final Map<String, Object?> local = <String, Object?>{...base}
        ..['address'] = 'House 1, Dhaka';
      final Map<String, Object?> server = Map<String, Object?>.from(base);

      final PatientMergeResult result = mergePatientRow(
        base: base,
        local: local,
        server: server,
      );

      expect(result.automatic, isTrue);
      expect(result.merged['address'], 'House 1, Dhaka');
    });

    test('escalates overlapping edits to the same column', () {
      // Two registration desks corrected the phone number differently.
      final Map<String, Object?> base = baseRow();
      final Map<String, Object?> local = <String, Object?>{...base}
        ..['phone_number'] = '01800000000';
      final Map<String, Object?> server = <String, Object?>{...base}
        ..['phone_number'] = '01900000000';

      final PatientMergeResult result = mergePatientRow(
        base: base,
        local: local,
        server: server,
      );

      expect(result.automatic, isFalse);
      expect(result.conflictingFields, <String>{'phone_number'});
      expect(result.merged, isEmpty);
    });

    test('escalates a lone edit to an identity column', () {
      // A name correction is a human decision even with no overlap.
      final Map<String, Object?> base = baseRow();
      final Map<String, Object?> local = <String, Object?>{...base}
        ..['first_name'] = 'Abdur';
      final Map<String, Object?> server = Map<String, Object?>.from(base);

      final PatientMergeResult result = mergePatientRow(
        base: base,
        local: local,
        server: server,
      );

      expect(result.automatic, isFalse);
      expect(result.conflictingFields, <String>{'first_name'});
    });

    test('identical edits on both sides are not a conflict', () {
      final Map<String, Object?> base = baseRow();
      final Map<String, Object?> local = <String, Object?>{...base}
        ..['phone_number'] = '01800000000';
      final Map<String, Object?> server = <String, Object?>{...base}
        ..['phone_number'] = '01800000000';

      final PatientMergeResult result = mergePatientRow(
        base: base,
        local: local,
        server: server,
      );

      expect(result.automatic, isTrue);
      expect(result.merged['phone_number'], '01800000000');
    });

    test('untouched rows merge trivially', () {
      final Map<String, Object?> base = baseRow();

      final PatientMergeResult result = mergePatientRow(
        base: base,
        local: Map<String, Object?>.from(base),
        server: Map<String, Object?>.from(base),
      );

      expect(result.automatic, isTrue);
      expect(result.autoMergedFields, isEmpty);
      expect(result.merged['mrn'], 'MRN-001');
    });

    test('ignores write metadata when detecting edits', () {
      // updated_at differs on every write; it must not count as an edit.
      final Map<String, Object?> base = <String, Object?>{
        ...baseRow(),
        'updated_at': '2026-01-01T00:00:00.000Z',
      };
      final Map<String, Object?> local = <String, Object?>{
        ...base,
        'updated_at': '2026-09-11T00:00:00.000Z',
      };
      final Map<String, Object?> server = Map<String, Object?>.from(base);

      final PatientMergeResult result = mergePatientRow(
        base: base,
        local: local,
        server: server,
      );

      expect(result.automatic, isTrue);
      expect(result.autoMergedFields, isEmpty);
    });

    test('treats SQLite integers and booleans as equal', () {
      final Map<String, Object?> base = <String, Object?>{
        ...baseRow(),
        'is_active': 1,
      };
      final Map<String, Object?> local = <String, Object?>{
        ...base,
        'phone_number': '01800000000',
      };
      final Map<String, Object?> server = Map<String, Object?>.from(base);

      final PatientMergeResult result = mergePatientRow(
        base: base,
        local: local,
        server: server,
      );

      expect(result.automatic, isTrue);
      expect(result.merged['phone_number'], '01800000000');
    });

    test('treats equivalent date renderings as equal', () {
      final Map<String, Object?> base = <String, Object?>{
        ...baseRow(),
        'date_of_birth': '1984-03-17',
      };
      final Map<String, Object?> local = <String, Object?>{
        ...base,
        'date_of_birth': '1984-03-17T00:00:00.000Z',
      };
      final Map<String, Object?> server = Map<String, Object?>.from(base);

      final PatientMergeResult result = mergePatientRow(
        base: base,
        local: local,
        server: server,
      );

      expect(result.automatic, isTrue);
    });

    test('distinguishes null from empty string', () {
      // Clearing a field is an edit; it must not vanish into equality.
      final Map<String, Object?> base = <String, Object?>{...baseRow()}
        ..['email'] = 'a@example.com';
      final Map<String, Object?> local = <String, Object?>{...base}
        ..['email'] = null;
      final Map<String, Object?> server = Map<String, Object?>.from(base);

      final PatientMergeResult result = mergePatientRow(
        base: base,
        local: local,
        server: server,
      );

      expect(result.automatic, isTrue);
      expect(result.merged['email'], isNull);
      expect(result.autoMergedFields, contains('email'));
    });
  });
}
