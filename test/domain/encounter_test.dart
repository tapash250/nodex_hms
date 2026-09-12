/// Tests for the clinical encounter domain entities.
///
/// The signature gate is the load-bearing invariant: an encounter is editable
/// while unsigned and frozen once signed, with corrections recorded only as
/// amendments carrying a reason. These tests pin the entity-level half of that
/// contract; the server trigger enforces the other half.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';

void main() {
  group('ClinicalEncounter.draftRow', () {
    test('starts unsigned and in progress', () {
      final Map<String, Object?> row = ClinicalEncounter.draftRow(
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        attendingPhysicianId: 'doctor-1',
        encounterType: EncounterType.outpatient,
        createdBy: 'doctor-1',
        assessment: '  Working diagnosis  ',
      );

      expect(row['status'], EncounterStatus.inProgress.wireValue);
      expect(row['signed_at'], isNull);
      expect(row['encounter_type'], 'outpatient');
      expect(row['assessment'], 'Working diagnosis');
      expect(row.containsKey('id'), isFalse);
    });

    test('rejects missing identity fields together', () {
      try {
        ClinicalEncounter.draftRow(
          tenantId: '',
          patientId: '',
          attendingPhysicianId: '',
          encounterType: EncounterType.emergency,
          createdBy: 'u',
        );
        fail('expected ValidationError');
      } on ValidationError catch (error) {
        expect(
          error.fieldErrors.keys,
          containsAll(<String>[
            'tenant_id',
            'patient_id',
            'attending_physician_id',
          ]),
        );
      }
    });

    test('normalizes blank SOAP fields to null', () {
      final Map<String, Object?> row = ClinicalEncounter.draftRow(
        tenantId: 't',
        patientId: 'p',
        attendingPhysicianId: 'd',
        encounterType: EncounterType.telehealth,
        createdBy: 'd',
        subjectiveNote: '   ',
      );

      expect(row['subjective_note'], isNull);
    });
  });

  group('ClinicalEncounter.fromRow', () {
    test('maps status, type and signature', () {
      final ClinicalEncounter encounter = ClinicalEncounter.fromRow(
        const <String, Object?>{
          'id': 'e1',
          'tenant_id': 't',
          'patient_id': 'p',
          'attending_physician_id': 'd',
          'encounter_type': 'emergency',
          'status': 'signed_and_locked',
          'diagnoses': '[{"code":"J06.9","description":"URI"}]',
          'signed_at': '2026-09-12T10:00:00.000Z',
        },
      );

      expect(encounter.encounterType, EncounterType.emergency);
      expect(encounter.status, EncounterStatus.signedAndLocked);
      expect(encounter.isSigned, isTrue);
      expect(encounter.isEditable, isFalse);
      expect(encounter.diagnoses.single.code, 'J06.9');
    });

    test('an unsigned encounter is editable', () {
      final ClinicalEncounter encounter = ClinicalEncounter.fromRow(
        const <String, Object?>{
          'id': 'e1',
          'tenant_id': 't',
          'patient_id': 'p',
          'attending_physician_id': 'd',
          'encounter_type': 'inpatient',
          'status': 'in_progress',
          'diagnoses': '[]',
        },
      );

      expect(encounter.isEditable, isTrue);
      expect(encounter.isSigned, isFalse);
      expect(encounter.signedAt, isNull);
    });

    test('malformed diagnoses yield an empty list, not a crash', () {
      final ClinicalEncounter encounter = ClinicalEncounter.fromRow(
        const <String, Object?>{
          'id': 'e1',
          'tenant_id': 't',
          'patient_id': 'p',
          'attending_physician_id': 'd',
          'encounter_type': 'outpatient',
          'status': 'in_progress',
          'diagnoses': 'not-json{{{',
        },
      );

      expect(encounter.diagnoses, isEmpty);
    });
  });

  group('ClinicalEncounter.signChanges', () {
    test('sets the signed status with a timestamp', () {
      final Map<String, Object?> changes = ClinicalEncounter.signChanges();

      expect(changes['status'], 'signed_and_locked');
      expect(DateTime.parse(changes['signed_at']! as String), isNotNull);
      expect(changes['updated_at'], isNotNull);
    });
  });

  group('EncounterStatus', () {
    test('only unsigned states are editable', () {
      expect(EncounterStatus.planned.isEditable, isTrue);
      expect(EncounterStatus.inProgress.isEditable, isTrue);
      expect(EncounterStatus.signedAndLocked.isEditable, isFalse);
      expect(EncounterStatus.amended.isEditable, isFalse);
    });

    test('signed states are exactly the frozen ones', () {
      for (final EncounterStatus status in EncounterStatus.values) {
        expect(
          status.isSigned,
          status == EncounterStatus.signedAndLocked ||
              status == EncounterStatus.amended,
        );
      }
    });

    test('fromWire defaults to inProgress on unrecognised input', () {
      expect(
        EncounterStatus.fromWire('in_progress'),
        EncounterStatus.inProgress,
      );
      expect(EncounterStatus.fromWire('bogus'), EncounterStatus.inProgress);
    });

    test('EncounterType.fromWire returns null on unrecognised input', () {
      expect(EncounterType.fromWire('telehealth'), EncounterType.telehealth);
      expect(EncounterType.fromWire('bogus'), isNull);
    });
  });

  group('EncounterAmendment.amendmentRow', () {
    test('builds an insert-ready row with encoded changes', () {
      final Map<String, Object?> row = EncounterAmendment.amendmentRow(
        tenantId: 't',
        encounterId: 'e',
        reason: 'Diagnosis reclassified',
        amendedBy: 'd',
        fieldChanges: const <String, Object?>{'assessment': 'Revised'},
      );

      expect(row['reason'], 'Diagnosis reclassified');
      expect(row['field_changes'], '{"assessment":"Revised"}');
      expect(row['amendment_type'], 'correction');
    });

    test('rejects a missing reason', () {
      expect(
        () => EncounterAmendment.amendmentRow(
          tenantId: 't',
          encounterId: 'e',
          reason: '  ',
          amendedBy: 'd',
          fieldChanges: const <String, Object?>{'assessment': 'x'},
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError e) => e.code,
            'code',
            'amendment_reason_required',
          ),
        ),
      );
    });

    test('rejects an empty change set', () {
      expect(
        () => EncounterAmendment.amendmentRow(
          tenantId: 't',
          encounterId: 'e',
          reason: 'Because',
          amendedBy: 'd',
          fieldChanges: const <String, Object?>{},
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError e) => e.code,
            'code',
            'amendment_empty',
          ),
        ),
      );
    });

    test('fromRow decodes the encoded changes', () {
      final EncounterAmendment amendment = EncounterAmendment.fromRow(
        const <String, Object?>{
          'id': 'a',
          'tenant_id': 't',
          'encounter_id': 'e',
          'amendment_type': 'addendum',
          'reason': 'Late lab result',
          'field_changes': '{"plan_description":"Added iron studies"}',
          'amended_by': 'd',
          'created_at': '2026-09-12T10:00:00.000Z',
        },
      );

      expect(amendment.amendmentType, 'addendum');
      expect(amendment.fieldChanges['plan_description'], 'Added iron studies');
    });
  });
}
