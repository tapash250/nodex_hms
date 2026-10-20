/// The patient portal (Module 05).
///
/// What a patient sees of their own record: their appointments, the results
/// that are final, and the medicines they are taking. The filtering is the
/// point of the module — a preliminary result is a work in progress, and the
/// portal does not show work in progress to a patient.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/domain/laboratory/lab.dart';
import 'package:nodex_hms/domain/prescriptions/prescription.dart';

/// A result the patient may see.
@immutable
final class PortalResult {
  /// Declares a visible result.
  const PortalResult({
    required this.analyteName,
    required this.value,
    this.unit,
    this.referenceRange,
    this.verifiedAt,
  });

  /// Builds a visible result from a laboratory result.
  ///
  /// Returns null for a result that is not final: a patient reads a value
  /// that may still be corrected, and a value that changes under the reader is
  /// worse than a value that has not arrived yet.
  static PortalResult? fromLabResult(LabResult result) {
    if (result.status != LabResultStatus.verified &&
        result.status != LabResultStatus.corrected) {
      return null;
    }
    final String value =
        result.valueText ?? result.valueNumeric?.toString() ?? '';
    if (value.trim().isEmpty) return null;
    return PortalResult(
      analyteName: result.analyteName,
      value: value,
      unit: result.unit,
      referenceRange: result.referenceRange,
      verifiedAt: result.verifiedAt,
    );
  }

  /// What was measured.
  final String analyteName;

  /// The value.
  final String value;

  /// The unit of measure.
  final String? unit;

  /// The interval the laboratory gave.
  final String? referenceRange;

  /// When it was signed off.
  final DateTime? verifiedAt;

  /// The line the patient reads.
  String get display {
    final String unitPart = unit == null ? '' : ' $unit';
    return '$analyteName: $value$unitPart';
  }
}

/// A medicine the patient is taking.
@immutable
final class PortalMedication {
  /// Declares a medicine.
  const PortalMedication({
    required this.name,
    required this.status,
    this.dose,
    this.instructions,
  });

  /// Builds a visible medicine from a prescription.
  ///
  /// A draft prescription is not shown: it is a clinician's working copy, and
  /// a patient reading an unfinished prescription would read it as a
  /// prescription.
  static PortalMedication? fromPrescription(Prescription prescription) {
    if (prescription.status != PrescriptionStatus.finalized) return null;
    return PortalMedication(
      name: prescription.prescriptionCode,
      status: prescription.status.wireValue,
      dose: prescription.indication,
    );
  }

  /// The name of the medicine.
  final String name;

  /// Where the prescription stands.
  final String status;

  /// The dose, when the record carries one.
  final String? dose;

  /// How to take it, when the record carries one.
  final String? instructions;

  /// The line the patient reads.
  String get display {
    final String dosePart = dose == null ? '' : ' · $dose';
    return '$name$dosePart';
  }
}
