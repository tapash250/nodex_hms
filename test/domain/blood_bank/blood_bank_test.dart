/// Blood bank entity decoding tests (Module 26).
///
/// The transfusion flow, unit lifecycle, and administration outcomes are all
/// decoded from snake_case projection rows; a wrong wire value silently
/// reclassifies a clinical state, so every enum and nullable column round
/// trips through the row form.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank.dart';

void main() {
  group('enum wire decoding', () {
    test('blood group decodes stored ABO/Rhesus values', () {
      expect(BloodGroup.fromWire('A+'), BloodGroup.aPositive);
      expect(BloodGroup.fromWire('O-'), BloodGroup.oNegative);
      expect(BloodGroup.fromWire('AB+'), BloodGroup.abPositive);
      expect(BloodGroup.fromWire('not-a-group'), BloodGroup.oPositive);
    });

    test('component decodes every stored value', () {
      expect(BloodComponent.fromWire('red_cells'), BloodComponent.redCells);
      expect(BloodComponent.fromWire('whole_blood'), BloodComponent.wholeBlood);
      expect(
        BloodComponent.fromWire('cryoprecipitate'),
        BloodComponent.cryoprecipitate,
      );
      expect(BloodComponent.fromWire(''), BloodComponent.redCells);
    });

    test('unit status decodes and flags terminal units', () {
      expect(BloodUnitStatus.fromWire('reserved'), BloodUnitStatus.reserved);
      expect(BloodUnitStatus.fromWire('issued'), BloodUnitStatus.issued);
      expect(BloodUnitStatus.fromWire('nope'), BloodUnitStatus.available);
      expect(BloodUnitStatus.expired.isTerminal, isTrue);
      expect(BloodUnitStatus.discarded.isTerminal, isTrue);
      expect(BloodUnitStatus.available.isTerminal, isFalse);
      expect(BloodUnitStatus.reserved.isTerminal, isFalse);
    });

    test('request status decodes and flags closed requests', () {
      expect(
        TransfusionRequestStatus.fromWire('crossmatched'),
        TransfusionRequestStatus.crossmatched,
      );
      expect(
        TransfusionRequestStatus.fromWire('completed'),
        TransfusionRequestStatus.completed,
      );
      expect(
        TransfusionRequestStatus.fromWire('unknown'),
        TransfusionRequestStatus.pending,
      );
      expect(TransfusionRequestStatus.completed.isTerminal, isTrue);
      expect(TransfusionRequestStatus.cancelled.isTerminal, isTrue);
      expect(TransfusionRequestStatus.rejected.isTerminal, isTrue);
      expect(TransfusionRequestStatus.approved.isTerminal, isFalse);
      expect(TransfusionRequestStatus.crossmatched.isTerminal, isFalse);
    });

    test('crossmatch result decodes and reports compatibility', () {
      expect(
        CrossmatchResult.fromWire('compatible'),
        CrossmatchResult.compatible,
      );
      expect(
        CrossmatchResult.fromWire('incompatible'),
        CrossmatchResult.incompatible,
      );
      expect(CrossmatchResult.fromWire(''), CrossmatchResult.pending);
      expect(CrossmatchResult.compatible.isCompatible, isTrue);
      expect(CrossmatchResult.incompatible.isCompatible, isFalse);
    });

    test('urgency decodes and flags emergencies', () {
      expect(TransfusionUrgency.fromWire('urgent'), TransfusionUrgency.urgent);
      expect(
        TransfusionUrgency.fromWire('emergency'),
        TransfusionUrgency.emergency,
      );
      expect(TransfusionUrgency.fromWire('nope'), TransfusionUrgency.routine);
      expect(TransfusionUrgency.emergency.isEmergency, isTrue);
      expect(TransfusionUrgency.routine.isEmergency, isFalse);
    });

    test('transfusion status decodes administration outcomes', () {
      expect(
        TransfusionStatus.fromWire('transfused'),
        TransfusionStatus.transfused,
      );
      expect(
        TransfusionStatus.fromWire('reaction'),
        TransfusionStatus.reaction,
      );
      expect(TransfusionStatus.fromWire(''), TransfusionStatus.started);
    });
  });

  group('TransfusionRequest.fromRow', () {
    test('decodes a fully-populated request row', () {
      final DateTime at = DateTime.utc(2026, 10, 1, 8);
      final TransfusionRequest request = TransfusionRequest.fromRow(
        <String, Object?>{
          'id': 'req-1',
          'tenant_id': 'tenant-1',
          'patient_id': 'patient-1',
          'encounter_id': 'enc-1',
          'requested_by': 'doctor-1',
          'requested_blood_group': 'O+',
          'component': 'red_cells',
          'units_requested': 2,
          'indication': 'Pre-operative anaemia',
          'urgency': 'urgent',
          'status': 'approved',
          'crossmatch_result': 'compatible',
          'requested_at': at,
          'approved_by': 'doctor-2',
          'approved_at': at,
          'created_at': at,
          'updated_at': at,
        },
      );

      expect(request.id, 'req-1');
      expect(request.requestedBloodGroup, BloodGroup.oPositive);
      expect(request.component, BloodComponent.redCells);
      expect(request.unitsRequested, 2);
      expect(request.urgency, TransfusionUrgency.urgent);
      expect(request.status, TransfusionRequestStatus.approved);
      expect(request.crossmatchResult, CrossmatchResult.compatible);
      expect(request.isApproved, isTrue);
      expect(request.isTerminal, isFalse);
      expect(request.approvedBy, 'doctor-2');
      expect(request.encounterId, 'enc-1');
    });

    test('defaults missing unit count and clears absent links', () {
      final DateTime at = DateTime.utc(2026, 10, 1, 8);
      final TransfusionRequest request = TransfusionRequest.fromRow(
        <String, Object?>{
          'id': 'req-2',
          'tenant_id': 'tenant-1',
          'patient_id': 'patient-1',
          'encounter_id': null,
          'requested_by': 'doctor-1',
          'requested_blood_group': 'A-',
          'component': 'platelets',
          'units_requested': null,
          'indication': null,
          'urgency': 'routine',
          'status': 'pending',
          'crossmatch_result': 'pending',
          'requested_at': at,
          'approved_by': null,
          'approved_at': null,
          'created_at': at,
          'updated_at': at,
        },
      );

      expect(request.unitsRequested, 0);
      expect(request.encounterId, isNull);
      expect(request.indication, isNull);
      expect(request.approvedBy, isNull);
      expect(request.approvedAt, isNull);
      expect(request.isApproved, isFalse);
    });
  });

  group('BloodUnit.fromRow', () {
    test('decodes a reserved unit bound to a request', () {
      final DateTime collected = DateTime.utc(2026, 9, 20);
      final DateTime expires = DateTime.utc(2026, 10, 18);
      final BloodUnit unit = BloodUnit.fromRow(<String, Object?>{
        'id': 'unit-1',
        'tenant_id': 'tenant-1',
        'unit_number': 'BU-0001',
        'blood_group': 'B+',
        'component': 'whole_blood',
        'volume_ml': 450,
        'collected_at': collected,
        'expires_at': expires,
        'status': 'reserved',
        'location_id': 'loc-1',
        'patient_id': 'patient-1',
        'transfusion_request_id': 'req-1',
        'created_by': 'lab-1',
        'created_at': collected,
        'updated_at': collected,
      });

      expect(unit.unitNumber, 'BU-0001');
      expect(unit.bloodGroup, BloodGroup.bPositive);
      expect(unit.volumeMl, 450);
      expect(unit.status, BloodUnitStatus.reserved);
      expect(unit.isReserved, isTrue);
      expect(unit.isAvailable, isFalse);
      expect(unit.isIssued, isFalse);
      expect(unit.patientId, 'patient-1');
      expect(unit.transfusionRequestId, 'req-1');
      expect(unit.isTerminal, isFalse);
    });

    test('clears absent volume, location, and links', () {
      final DateTime at = DateTime.utc(2026, 9, 20);
      final BloodUnit unit = BloodUnit.fromRow(<String, Object?>{
        'id': 'unit-2',
        'tenant_id': 'tenant-1',
        'unit_number': 'BU-0002',
        'blood_group': 'AB-',
        'component': 'plasma',
        'volume_ml': null,
        'collected_at': at,
        'expires_at': at.add(const Duration(days: 7)),
        'status': 'available',
        'location_id': null,
        'patient_id': null,
        'transfusion_request_id': null,
        'created_by': 'lab-1',
        'created_at': at,
        'updated_at': at,
      });

      expect(unit.volumeMl, isNull);
      expect(unit.locationId, isNull);
      expect(unit.patientId, isNull);
      expect(unit.isAvailable, isTrue);
      expect(BloodUnitStatus.discarded.isTerminal, isTrue);
      expect(BloodUnitStatus.expired.isTerminal, isTrue);
    });
  });

  group('Transfusion.fromRow', () {
    test('decodes a started administration record', () {
      final DateTime started = DateTime.utc(2026, 10, 2, 10);
      final Transfusion transfusion = Transfusion.fromRow(<String, Object?>{
        'id': 'tr-1',
        'tenant_id': 'tenant-1',
        'transfusion_request_id': 'req-1',
        'blood_unit_id': 'unit-1',
        'patient_id': 'patient-1',
        'recorded_by': 'nurse-1',
        'started_at': started,
        'finished_at': null,
        'status': 'started',
        'volume_ml': null,
        'reaction_notes': null,
        'created_at': started,
        'updated_at': started,
      });

      expect(transfusion.status, TransfusionStatus.started);
      expect(transfusion.isComplete, isFalse);
      expect(transfusion.hasReaction, isFalse);
      expect(transfusion.finishedAt, isNull);
      expect(transfusion.volumeMl, isNull);
    });

    test('flags closed records and recorded reactions', () {
      final DateTime started = DateTime.utc(2026, 10, 2, 10);
      final Transfusion transfusion = Transfusion.fromRow(<String, Object?>{
        'id': 'tr-2',
        'tenant_id': 'tenant-1',
        'transfusion_request_id': 'req-1',
        'blood_unit_id': 'unit-1',
        'patient_id': 'patient-1',
        'recorded_by': 'nurse-1',
        'started_at': started,
        'finished_at': started.add(const Duration(hours: 2)),
        'status': 'reaction',
        'volume_ml': 250,
        'reaction_notes': 'Rigors reported.',
        'created_at': started,
        'updated_at': started,
      });

      expect(transfusion.status, TransfusionStatus.reaction);
      expect(transfusion.hasReaction, isTrue);
      expect(transfusion.isComplete, isTrue);
      expect(transfusion.volumeMl, 250);
      expect(transfusion.reactionNotes, 'Rigors reported.');
    });
  });
}
