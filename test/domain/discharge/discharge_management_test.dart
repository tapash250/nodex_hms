/// Discharge management entity decoding and enum wire tests (Module 23).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/domain/discharge/discharge_management.dart';

void main() {
  group('DischargeClearanceStatus wire decoding', () {
    test('round-trips every wire value', () {
      for (final DischargeClearanceStatus status
          in DischargeClearanceStatus.values) {
        expect(DischargeClearanceStatus.fromWire(status.wireValue), status);
      }
    });

    test('falls back to pending for unknown values', () {
      expect(
        DischargeClearanceStatus.fromWire('withdrawn'),
        DischargeClearanceStatus.pending,
      );
    });

    test('classifies cleared and pending', () {
      expect(DischargeClearanceStatus.cleared.isCleared, isTrue);
      expect(DischargeClearanceStatus.pending.isCleared, isFalse);
    });
  });

  group('DischargeReconciliationStatus wire decoding', () {
    test('round-trips every wire value', () {
      for (final DischargeReconciliationStatus status
          in DischargeReconciliationStatus.values) {
        expect(
          DischargeReconciliationStatus.fromWire(status.wireValue),
          status,
        );
      }
    });

    test('classifies reconciled and pending', () {
      expect(DischargeReconciliationStatus.reconciled.isReconciled, isTrue);
      expect(DischargeReconciliationStatus.pending.isReconciled, isFalse);
    });
  });

  group('DischargeMedicationAction wire decoding', () {
    test('round-trips every wire value', () {
      for (final DischargeMedicationAction action
          in DischargeMedicationAction.values) {
        expect(DischargeMedicationAction.fromWire(action.wireValue), action);
      }
    });

    test('anything other than continue is a discrepancy', () {
      expect(
        DischargeMedicationAction.continueMedication.isDiscrepancy,
        isFalse,
      );
      expect(DischargeMedicationAction.stop.isDiscrepancy, isTrue);
      expect(DischargeMedicationAction.change.isDiscrepancy, isTrue);
      expect(DischargeMedicationAction.hold.isDiscrepancy, isTrue);
    });

    test('falls back to continue for unknown values', () {
      expect(
        DischargeMedicationAction.fromWire('taper'),
        DischargeMedicationAction.continueMedication,
      );
    });
  });

  group('DischargeAiSummaryStatus wire decoding', () {
    test('round-trips every wire value', () {
      for (final DischargeAiSummaryStatus status
          in DischargeAiSummaryStatus.values) {
        expect(DischargeAiSummaryStatus.fromWire(status.wireValue), status);
      }
    });

    test('decodes the multi-word wire value', () {
      expect(
        DischargeAiSummaryStatus.fromWire('pending_review'),
        DischargeAiSummaryStatus.pendingReview,
      );
    });

    test('classifies review state', () {
      expect(DischargeAiSummaryStatus.pendingReview.isPendingReview, isTrue);
      expect(DischargeAiSummaryStatus.pendingReview.isReviewed, isFalse);
      expect(DischargeAiSummaryStatus.accepted.isAccepted, isTrue);
      expect(DischargeAiSummaryStatus.accepted.isReviewed, isTrue);
      expect(DischargeAiSummaryStatus.rejected.isReviewed, isTrue);
    });
  });

  group('DischargeClearance.fromRow', () {
    test('decodes a granted clearance', () {
      final DischargeClearance clearance = DischargeClearance.fromRow(
        <String, Object?>{
          'id': 'clearance-1',
          'tenant_id': 'tenant-1',
          'discharge_id': 'discharge-1',
          'reviewed_by': 'doctor-1',
          'status': 'cleared',
          'outstanding_items': 0,
          'notes': 'Vitals stable, no pending results.',
          'cleared_by': 'doctor-2',
          'cleared_at': DateTime.utc(2026, 9, 20, 11),
          'created_at': DateTime.utc(2026, 9, 20, 10),
          'updated_at': DateTime.utc(2026, 9, 20, 11),
        },
      );

      expect(clearance.isCleared, isTrue);
      expect(clearance.hasOutstandingItems, isFalse);
      expect(clearance.clearedBy, 'doctor-2');
      expect(clearance.clearedAt, DateTime.utc(2026, 9, 20, 11));
    });

    test('decodes a pending review with outstanding items', () {
      final DischargeClearance clearance = DischargeClearance.fromRow(
        <String, Object?>{
          'id': 'clearance-2',
          'tenant_id': 'tenant-1',
          'discharge_id': 'discharge-1',
          'reviewed_by': 'doctor-1',
          'status': 'pending',
          'outstanding_items': 3,
          'notes': null,
          'cleared_by': null,
          'cleared_at': null,
          'created_at': DateTime.utc(2026, 9, 20, 10),
          'updated_at': DateTime.utc(2026, 9, 20, 10),
        },
      );

      expect(clearance.isCleared, isFalse);
      expect(clearance.outstandingItems, 3);
      expect(clearance.hasOutstandingItems, isTrue);
      expect(clearance.notes, isNull);
      expect(clearance.clearedAt, isNull);
    });
  });

  group('DischargeMedicationReconciliation.fromRow', () {
    test('decodes a completed reconciliation with counts', () {
      final DischargeMedicationReconciliation reconciliation =
          DischargeMedicationReconciliation.fromRow(<String, Object?>{
            'id': 'reconciliation-1',
            'tenant_id': 'tenant-1',
            'discharge_id': 'discharge-1',
            'status': 'reconciled',
            'medications_reviewed': 6,
            'discrepancies_found': 2,
            'reviewed_by': 'nurse-1',
            'reviewed_at': DateTime.utc(2026, 9, 20, 12),
            'notes': 'Two holds pending specialist input.',
            'created_at': DateTime.utc(2026, 9, 20, 10),
            'updated_at': DateTime.utc(2026, 9, 20, 12),
          });

      expect(reconciliation.isReconciled, isTrue);
      expect(reconciliation.medicationsReviewed, 6);
      expect(reconciliation.discrepanciesFound, 2);
      expect(reconciliation.reviewedBy, 'nurse-1');
    });

    test('decodes a pending reconciliation', () {
      final DischargeMedicationReconciliation reconciliation =
          DischargeMedicationReconciliation.fromRow(<String, Object?>{
            'id': 'reconciliation-2',
            'tenant_id': 'tenant-1',
            'discharge_id': 'discharge-1',
            'status': 'pending',
            'medications_reviewed': 0,
            'discrepancies_found': 0,
            'reviewed_by': null,
            'reviewed_at': null,
            'notes': null,
            'created_at': DateTime.utc(2026, 9, 20, 10),
            'updated_at': DateTime.utc(2026, 9, 20, 10),
          });

      expect(reconciliation.isReconciled, isFalse);
      expect(reconciliation.reviewedBy, isNull);
      expect(reconciliation.notes, isNull);
    });
  });

  group('DischargeMedicationReconciliationItem.fromRow', () {
    test('decodes a discrepancy decision from an integer flag', () {
      final DischargeMedicationReconciliationItem item =
          DischargeMedicationReconciliationItem.fromRow(<String, Object?>{
            'id': 'item-1',
            'tenant_id': 'tenant-1',
            'reconciliation_id': 'reconciliation-1',
            'medication_name': 'Warfarin',
            'action': 'hold',
            'discrepancy': 1,
            'detail': 'INR unstable.',
            'recorded_by': 'nurse-1',
            'recorded_at': DateTime.utc(2026, 9, 20, 11),
            'created_at': DateTime.utc(2026, 9, 20, 11),
            'updated_at': DateTime.utc(2026, 9, 20, 11),
          });

      expect(item.medicationName, 'Warfarin');
      expect(item.action, DischargeMedicationAction.hold);
      expect(item.discrepancy, isTrue);
      expect(item.detail, 'INR unstable.');
    });

    test('decodes a continuing medication with a boolean flag', () {
      final DischargeMedicationReconciliationItem item =
          DischargeMedicationReconciliationItem.fromRow(<String, Object?>{
            'id': 'item-2',
            'tenant_id': 'tenant-1',
            'reconciliation_id': 'reconciliation-1',
            'medication_name': 'Paracetamol',
            'action': 'continue',
            'discrepancy': false,
            'detail': null,
            'recorded_by': 'nurse-1',
            'recorded_at': DateTime.utc(2026, 9, 20, 11),
            'created_at': DateTime.utc(2026, 9, 20, 11),
            'updated_at': DateTime.utc(2026, 9, 20, 11),
          });

      expect(item.discrepancy, isFalse);
      expect(item.detail, isNull);
      expect(item.action.isDiscrepancy, isFalse);
    });
  });

  group('DischargeSettlement.fromRow', () {
    test('decodes a settled invoice', () {
      final DischargeSettlement settlement = DischargeSettlement.fromRow(
        <String, Object?>{
          'id': 'settlement-1',
          'tenant_id': 'tenant-1',
          'discharge_id': 'discharge-1',
          'invoice_id': 'invoice-1',
          'amount_minor': 450000,
          'settled_by': 'accounts-1',
          'settled_at': DateTime.utc(2026, 9, 20, 13),
          'created_at': DateTime.utc(2026, 9, 20, 13),
          'updated_at': DateTime.utc(2026, 9, 20, 13),
        },
      );

      expect(settlement.amountMinor, 450000);
      expect(settlement.invoiceId, 'invoice-1');
      expect(settlement.settledBy, 'accounts-1');
    });
  });

  group('DischargeAiSummary.fromRow', () {
    test('decodes a summary awaiting review', () {
      final DischargeAiSummary summary = DischargeAiSummary.fromRow(
        <String, Object?>{
          'id': 'summary-1',
          'tenant_id': 'tenant-1',
          'discharge_id': 'discharge-1',
          'model_id': 'clinical-summarizer-v2',
          'summary_text': 'Admitted with community-acquired pneumonia...',
          'status': 'pending_review',
          'safety_decision': 'allow',
          'requested_by': 'doctor-1',
          'reviewed_by': null,
          'reviewed_at': null,
          'rejection_reason': null,
          'created_at': DateTime.utc(2026, 9, 20, 14),
          'updated_at': DateTime.utc(2026, 9, 20, 14),
        },
      );

      expect(summary.isPendingReview, isTrue);
      expect(summary.modelId, 'clinical-summarizer-v2');
      expect(summary.safetyDecision, 'allow');
      expect(summary.reviewedBy, isNull);
    });

    test('decodes a rejected summary with its reason', () {
      final DischargeAiSummary summary = DischargeAiSummary.fromRow(
        <String, Object?>{
          'id': 'summary-2',
          'tenant_id': 'tenant-1',
          'discharge_id': 'discharge-1',
          'model_id': 'clinical-summarizer-v2',
          'summary_text': 'Summary text.',
          'status': 'rejected',
          'safety_decision': 'allow',
          'requested_by': 'doctor-1',
          'reviewed_by': 'doctor-2',
          'reviewed_at': DateTime.utc(2026, 9, 20, 15),
          'rejection_reason': 'Omits the penicillin allergy.',
          'created_at': DateTime.utc(2026, 9, 20, 14),
          'updated_at': DateTime.utc(2026, 9, 20, 15),
        },
      );

      expect(summary.isAccepted, isFalse);
      expect(summary.isPendingReview, isFalse);
      expect(summary.rejectionReason, 'Omits the penicillin allergy.');
      expect(summary.reviewedAt, DateTime.utc(2026, 9, 20, 15));
    });
  });

  group('DischargeReadiness', () {
    test('finalization needs all three gates', () {
      const DischargeReadiness nothing = DischargeReadiness(
        cleared: false,
        reconciled: false,
        settled: false,
        outstandingClearanceItems: 0,
        pendingMedications: 0,
      );
      expect(nothing.canFinalize, isFalse);

      const DischargeReadiness partial = DischargeReadiness(
        cleared: true,
        reconciled: true,
        settled: false,
        outstandingClearanceItems: 0,
        pendingMedications: 0,
      );
      expect(partial.canFinalize, isFalse);

      const DischargeReadiness complete = DischargeReadiness(
        cleared: true,
        reconciled: true,
        settled: true,
        outstandingClearanceItems: 0,
        pendingMedications: 0,
      );
      expect(complete.canFinalize, isTrue);
    });

    test('a reviewed AI summary is reported but never required', () {
      const DischargeReadiness withoutSummary = DischargeReadiness(
        cleared: true,
        reconciled: true,
        settled: true,
        outstandingClearanceItems: 0,
        pendingMedications: 0,
      );
      expect(withoutSummary.aiSummaryReviewed, isFalse);
      expect(
        withoutSummary.canFinalize,
        isTrue,
        reason: 'an AI summary is documentation, not a safety gate',
      );
    });
  });
}
