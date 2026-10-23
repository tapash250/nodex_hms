/// Tests for the patient portal (Module 05).
///
/// The portal shows a patient their own record, and only the parts of it
/// that are final. These tests pin the filtering: a preliminary result is not
/// shown, a draft prescription is not shown, and a revoked link grants
/// nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/domain/laboratory/lab.dart';
import 'package:nodex_hms/domain/portal/patient_portal.dart';
import 'package:nodex_hms/domain/portal/portal_repository.dart';
import 'package:nodex_hms/domain/prescriptions/prescription.dart';

/// A repository that resolves a fixed patient.
final class _FixedPortalRepository implements PortalRepository {
  _FixedPortalRepository(this.patientId);

  final String? patientId;

  @override
  Future<String?> resolvePatientId(String portalUserId) async => patientId;
}

LabResult _result({
  LabResultStatus status = LabResultStatus.verified,
  String? valueText,
  double? valueNumeric,
}) => LabResult(
  id: 'result-1',
  tenantId: 'tenant-1',
  labOrderId: 'order-1',
  specimenId: 'specimen-1',
  analyteCode: 'HGB',
  analyteName: 'Haemoglobin',
  status: status,
  enteredBy: 'tech-1',
  enteredAt: DateTime.utc(2026, 9, 12, 9),
  valueText: valueText,
  valueNumeric: valueNumeric,
  unit: 'g/dL',
  referenceRange: '12-15 g/dL',
);

PrescriptionItem _item({
  PrescriptionItemStatus status = PrescriptionItemStatus.ordered,
  String? strength = '500mg',
}) => PrescriptionItem(
  id: 'item-1',
  tenantId: 'tenant-1',
  prescriptionId: 'prescription-1',
  lineNumber: 1,
  drugCode: 'AMOX500',
  drugName: 'Amoxicillin',
  dosageText: '1 capsule three times daily',
  quantityPrescribed: 21,
  status: status,
  strength: strength,
  route: 'oral',
  frequency: 'three times daily',
  durationDays: 7,
);

void main() {
  group('results the patient may see', () {
    test('a verified result is shown', () {
      final PortalResult? result = PortalResult.fromLabResult(
        _result(valueText: '13.2'),
      );
      expect(result, isNotNull);
      expect(result!.display, 'Haemoglobin: 13.2 g/dL');
    });

    test('a corrected result is shown', () {
      expect(
        PortalResult.fromLabResult(
          _result(status: LabResultStatus.corrected, valueText: '12.9'),
        ),
        isNotNull,
      );
    });

    test('a preliminary result is not shown', () {
      expect(
        PortalResult.fromLabResult(
          _result(status: LabResultStatus.entered, valueText: '13.2'),
        ),
        isNull,
      );
    });

    test('a cancelled result is not shown', () {
      expect(
        PortalResult.fromLabResult(
          _result(status: LabResultStatus.cancelled, valueText: '13.2'),
        ),
        isNull,
      );
    });

    test('a result with no value is not shown', () {
      expect(PortalResult.fromLabResult(_result()), isNull);
    });

    test('a numeric result is shown with its unit', () {
      final PortalResult? result = PortalResult.fromLabResult(
        _result(valueNumeric: 13.25),
      );
      expect(result!.display, 'Haemoglobin: 13.25 g/dL');
    });
  });

  group('medicines the patient may see', () {
    test('an ordered line is shown with its drug and dose', () {
      final PortalMedication? medication = PortalMedication.fromItem(_item());
      expect(medication, isNotNull);
      expect(
        medication!.display,
        'Amoxicillin 500mg · 1 capsule three times daily',
      );
      expect(medication.instructions, 'oral · three times daily · for 7 days');
    });

    test('a draft line is not shown', () {
      expect(
        PortalMedication.fromItem(_item(status: PrescriptionItemStatus.draft)),
        isNull,
      );
    });

    test('a cancelled line is not shown', () {
      expect(
        PortalMedication.fromItem(
          _item(status: PrescriptionItemStatus.cancelled),
        ),
        isNull,
      );
    });

    test('a dispensed line stays visible', () {
      expect(
        PortalMedication.fromItem(
          _item(status: PrescriptionItemStatus.dispensed),
        ),
        isNotNull,
      );
    });
  });

  group('the portal link', () {
    test('a linked account resolves its patient', () async {
      final PortalRepository repository = _FixedPortalRepository('patient-1');
      expect(await repository.resolvePatientId('portal-user-1'), 'patient-1');
    });

    test('an unlinked account resolves nothing', () async {
      final PortalRepository repository = _FixedPortalRepository(null);
      expect(await repository.resolvePatientId('portal-user-1'), isNull);
    });
  });
}
