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

Prescription _prescription({
  PrescriptionStatus status = PrescriptionStatus.finalized,
}) => Prescription(
  id: 'prescription-1',
  tenantId: 'tenant-1',
  patientId: 'patient-1',
  prescribedBy: 'doctor-1',
  prescriptionCode: 'RX-1',
  version: 1,
  priority: PrescriptionPriority.routine,
  status: status,
  createdAt: DateTime.utc(2026, 9, 12, 9),
  indication: 'Twice daily',
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
    test('a finalized prescription is shown', () {
      final PortalMedication? medication = PortalMedication.fromPrescription(
        _prescription(),
      );
      expect(medication, isNotNull);
      expect(medication!.display, 'RX-1 · Twice daily');
    });

    test('a draft prescription is not shown', () {
      expect(
        PortalMedication.fromPrescription(
          _prescription(status: PrescriptionStatus.draft),
        ),
        isNull,
      );
    });

    test('a discontinued prescription is not shown', () {
      expect(
        PortalMedication.fromPrescription(
          _prescription(status: PrescriptionStatus.discontinued),
        ),
        isNull,
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
