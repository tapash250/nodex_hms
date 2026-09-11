/// Tests for the MPI domain entities.
///
/// Validation failures name fields, never values, so the resulting
/// [ValidationError] is safe to log and display. These tests assert that
/// contract alongside the mapping and identity helpers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/patients/patient.dart';

void main() {
  group('Patient.registrationRow', () {
    test('builds a valid row', () {
      final Map<String, Object?> row = Patient.registrationRow(
        tenantId: 'tenant-1',
        mrn: 'MRN-001',
        firstName: 'Abdul',
        lastName: 'Karim',
        dateOfBirth: DateTime.utc(1984, 3, 17),
        gender: PatientGender.male,
        bloodGroup: BloodGroup.oPositive,
        phoneNumber: '01712345678',
        createdBy: 'user-1',
      );

      expect(row['tenant_id'], 'tenant-1');
      expect(row['mrn'], 'MRN-001');
      expect(row['date_of_birth'], '1984-03-17');
      expect(row['gender'], 'male');
      expect(row['blood_group'], 'O+');
      expect(row['is_active'], 1);
      expect(row.containsKey('id'), isFalse);
    });

    test('trims names and MRN', () {
      final Map<String, Object?> row = Patient.registrationRow(
        tenantId: 'tenant-1',
        mrn: '  MRN-002 ',
        firstName: '  Fatima ',
        lastName: ' Begum  ',
        dateOfBirth: DateTime.utc(1990, 6, 1),
        gender: PatientGender.female,
      );

      expect(row['mrn'], 'MRN-002');
      expect(row['first_name'], 'Fatima');
      expect(row['last_name'], 'Begum');
    });

    test('rejects a future date of birth', () {
      expect(
        () => Patient.registrationRow(
          tenantId: 'tenant-1',
          mrn: 'MRN-003',
          firstName: 'A',
          lastName: 'B',
          dateOfBirth: DateTime.now().add(const Duration(days: 1)),
          gender: PatientGender.unknown,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError e) => e.fieldErrors.keys,
            'fields',
            contains('date_of_birth'),
          ),
        ),
      );
    });

    test('rejects blank required fields together', () {
      try {
        Patient.registrationRow(
          tenantId: '',
          mrn: '   ',
          firstName: '',
          lastName: '',
          dateOfBirth: DateTime.utc(2000, 1, 1),
          gender: PatientGender.unknown,
        );
        fail('expected ValidationError');
      } on ValidationError catch (error) {
        expect(
          error.fieldErrors.keys,
          containsAll(<String>['tenant_id', 'mrn', 'first_name', 'last_name']),
        );
        // Field names only: no submitted value may appear in the error.
        expect(error.toString(), isNot(contains('tenant-1')));
      }
    });

    test('rejects a short phone number', () {
      expect(
        () => Patient.registrationRow(
          tenantId: 'tenant-1',
          mrn: 'MRN-004',
          firstName: 'A',
          lastName: 'B',
          dateOfBirth: DateTime.utc(2000, 1, 1),
          gender: PatientGender.unknown,
          phoneNumber: '123',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('normalizes an empty phone to null', () {
      final Map<String, Object?> row = Patient.registrationRow(
        tenantId: 'tenant-1',
        mrn: 'MRN-005',
        firstName: 'A',
        lastName: 'B',
        dateOfBirth: DateTime.utc(2000, 1, 1),
        gender: PatientGender.unknown,
        phoneNumber: '   ',
      );

      expect(row['phone_number'], isNull);
    });
  });

  group('Patient.fromRow', () {
    test('round-trips the registration row', () {
      final Map<String, Object?> row = <String, Object?>{
        ...Patient.registrationRow(
          tenantId: 'tenant-1',
          mrn: 'MRN-010',
          firstName: 'Abdul',
          lastName: 'Karim',
          dateOfBirth: DateTime.utc(1984, 3, 17),
          gender: PatientGender.male,
          bloodGroup: BloodGroup.aNegative,
          phoneNumber: '01712345678',
        ),
        'id': 'patient-1',
      };

      final Patient patient = Patient.fromRow(row);

      expect(patient.id, 'patient-1');
      expect(patient.displayName, 'Karim, Abdul');
      expect(patient.gender, PatientGender.male);
      expect(patient.bloodGroup, BloodGroup.aNegative);
      expect(patient.isActive, isTrue);
      expect(patient.dateOfBirth, DateTime(1984, 3, 17));
    });

    test('ageAt counts completed years', () {
      final Patient patient = Patient.fromRow(const <String, Object?>{
        'id': 'p',
        'tenant_id': 't',
        'mrn': 'M',
        'first_name': 'A',
        'last_name': 'B',
        'date_of_birth': '2000-06-15',
        'gender': 'female',
        'is_active': 1,
      });

      expect(patient.ageAt(DateTime.utc(2026, 6, 14)), 25);
      expect(patient.ageAt(DateTime.utc(2026, 6, 15)), 26);
    });
  });

  group('Patient.contactUpdateRow', () {
    test('accepts mergeable columns', () {
      final Map<String, Object?> row = Patient.contactUpdateRow(
        <String, Object?>{
          'phone_number': '01800000000',
          'preferred_language': 'bn',
        },
      );

      expect(row['phone_number'], '01800000000');
      expect(row['updated_at'], isNotNull);
    });

    test('rejects identity columns', () {
      expect(
        () => Patient.contactUpdateRow(<String, Object?>{'mrn': 'X'}),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError e) => e.code,
            'code',
            'patient_identity_edit_blocked',
          ),
        ),
      );
      expect(
        () => Patient.contactUpdateRow(<String, Object?>{
          'first_name': 'X',
          'phone_number': '1',
        }),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejects marital status outside the closed vocabulary', () {
      expect(
        () => Patient.contactUpdateRow(<String, Object?>{
          'marital_status': 'complicated',
        }),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError e) => e.code,
            'code',
            'patient_marital_status_invalid',
          ),
        ),
      );
    });
  });

  group('PatientIdentity.hashNationalId', () {
    test('is deterministic and formatting-insensitive', () {
      final String a = PatientIdentity.hashNationalId('1234 567 890');
      final String b = PatientIdentity.hashNationalId('1234-567-890');
      final String c = PatientIdentity.hashNationalId('1234567890');

      expect(a, b);
      expect(b, c);
      expect(a, hasLength(64));
    });

    test('does not contain the raw number', () {
      final String hash = PatientIdentity.hashNationalId('9876543210');
      expect(hash, isNot(contains('9876543210')));
    });

    test('differs across numbers', () {
      expect(
        PatientIdentity.hashNationalId('1111111111'),
        isNot(PatientIdentity.hashNationalId('2222222222')),
      );
    });
  });

  group('enums', () {
    test('PatientGender defaults to unknown on unrecognised input', () {
      expect(PatientGender.fromWire('male'), PatientGender.male);
      expect(PatientGender.fromWire('x'), PatientGender.unknown);
    });

    test('BloodGroup returns null on unrecognised input', () {
      expect(BloodGroup.fromWire('O+'), BloodGroup.oPositive);
      expect(BloodGroup.fromWire(null), isNull);
      expect(BloodGroup.fromWire('Z+'), isNull);
    });

    test('AllergySeverity defaults to unknown', () {
      expect(AllergySeverity.fromWire('severe'), AllergySeverity.severe);
      expect(AllergySeverity.fromWire('critical'), AllergySeverity.unknown);
    });
  });

  group('PatientAllergy.reportRow', () {
    test('builds a valid active row', () {
      final Map<String, Object?> row = PatientAllergy.reportRow(
        tenantId: 't',
        patientId: 'p',
        substance: 'Penicillin',
        severity: AllergySeverity.severe,
        reaction: 'Anaphylaxis',
        recordedBy: 'u',
      );

      expect(row['substance'], 'Penicillin');
      expect(row['severity'], 'severe');
      expect(row['status'], 'active');
      expect(row['retired_reason'], isNull);
    });

    test('rejects a blank substance', () {
      expect(
        () => PatientAllergy.reportRow(
          tenantId: 't',
          patientId: 'p',
          substance: '  ',
          severity: AllergySeverity.mild,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('fromRow maps status and severity', () {
      final PatientAllergy allergy = PatientAllergy.fromRow(
        const <String, Object?>{
          'id': 'a',
          'tenant_id': 't',
          'patient_id': 'p',
          'substance': 'Sulfa',
          'severity': 'moderate',
          'status': 'active',
          'recorded_at': '2026-01-01T00:00:00.000Z',
        },
      );

      expect(allergy.isActive, isTrue);
      expect(allergy.severity, AllergySeverity.moderate);
    });
  });
}
