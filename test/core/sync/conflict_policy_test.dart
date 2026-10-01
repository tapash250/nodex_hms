/// Tests for the per-entity conflict policy registry.
///
/// The specification prohibits an undocumented global last-write-wins policy for
/// clinical data. These tests enforce that structurally: every clinical entity the
/// application writes must have a registered strategy, unregistered types fail
/// loudly, and the field-level merge path never merges an unlisted field or an
/// overlapping edit.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/sync/conflict_policy.dart';

void main() {
  group('ConflictPolicyRegistry coverage', () {
    test('registers a policy for every safety-critical clinical entity', () {
      // Entities the specification names in its conflict matrix.
      const List<String> required = <String>[
        ConflictPolicyRegistry.patient,
        ConflictPolicyRegistry.clinicalNote,
        ConflictPolicyRegistry.prescription,
        ConflictPolicyRegistry.medicationAdministration,
        ConflictPolicyRegistry.labResult,
        ConflictPolicyRegistry.stockMovement,
        ConflictPolicyRegistry.bedAssignment,
        ConflictPolicyRegistry.billing,
        ConflictPolicyRegistry.discharge,
        ConflictPolicyRegistry.triageAssessment,
        ConflictPolicyRegistry.erVisit,
        ConflictPolicyRegistry.icuBed,
        ConflictPolicyRegistry.icuVitals,
        ConflictPolicyRegistry.icuHandover,
        ConflictPolicyRegistry.ventilatorEvent,
        ConflictPolicyRegistry.bloodUnit,
        ConflictPolicyRegistry.transfusionRequest,
        ConflictPolicyRegistry.transfusion,
        ConflictPolicyRegistry.otBooking,
        ConflictPolicyRegistry.otPreOpAssessment,
        ConflictPolicyRegistry.otAnesthesiaRecord,
        ConflictPolicyRegistry.otProcedureLog,
        ConflictPolicyRegistry.otPostOpRecord,
        ConflictPolicyRegistry.imagingOrder,
        ConflictPolicyRegistry.imagingStudy,
        ConflictPolicyRegistry.imagingReport,
        ConflictPolicyRegistry.physioSession,
        ConflictPolicyRegistry.physioExercisePlan,
        ConflictPolicyRegistry.physioRecoveryNote,
        ConflictPolicyRegistry.dietAssessment,
        ConflictPolicyRegistry.dietMealPlan,
        ConflictPolicyRegistry.dietMealPlanDay,
        ConflictPolicyRegistry.dietIntakeLog,
        ConflictPolicyRegistry.teleConsultation,
        ConflictPolicyRegistry.teleVitalsOverlay,
        ConflictPolicyRegistry.teleConsultationArchive,
        ConflictPolicyRegistry.dischargeClearance,
        ConflictPolicyRegistry.dischargeReconciliation,
        ConflictPolicyRegistry.dischargeReconciliationItem,
        ConflictPolicyRegistry.dischargeSettlement,
        ConflictPolicyRegistry.dischargeAiSummary,
        ConflictPolicyRegistry.wardRoom,
      ];

      for (final String resourceType in required) {
        expect(
          ConflictPolicyRegistry.isRegistered(resourceType),
          isTrue,
          reason: '$resourceType must declare a conflict policy',
        );
      }
    });

    test('every entry carries a non-empty rationale', () {
      for (final ConflictPolicyEntry entry
          in ConflictPolicyRegistry.entries.values) {
        expect(
          entry.rationale.trim(),
          isNotEmpty,
          reason: '${entry.resourceType} must document why its policy applies',
        );
      }
    });

    test('entry keys match their resource type', () {
      ConflictPolicyRegistry.entries.forEach((
        String key,
        ConflictPolicyEntry entry,
      ) {
        expect(entry.resourceType, key);
      });
    });

    test('throws IntegrityError for an unregistered resource type', () {
      expect(
        () => ConflictPolicyRegistry.policyFor('unregistered_entity'),
        throwsA(
          isA<IntegrityError>()
              .having(
                (IntegrityError e) => e.subject,
                'subject',
                'conflict_policy',
              )
              .having(
                (IntegrityError e) => e.isRetryable,
                'isRetryable',
                isFalse,
              ),
        ),
      );
    });
  });

  group('specification conflict matrix', () {
    test('patient demographics use field-level merge', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.patient).policy,
        ConflictPolicy.fieldLevelMerge,
      );
    });

    test('clinical notes use versioned revisions', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.clinicalNote)
            .policy,
        ConflictPolicy.versionedRevision,
      );
    });

    test('prescriptions are immutable versioned orders', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.prescription)
            .policy,
        ConflictPolicy.immutableVersion,
      );
    });

    test('medication administration is an event transaction', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.medicationAdministration,
        ).policy,
        ConflictPolicy.eventTransaction,
      );
    });

    test('laboratory results are immutable with a correction workflow', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.labResult)
            .policy,
        ConflictPolicy.immutableWithCorrection,
      );
    });

    test('inventory resolves transactionally', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.stockMovement)
            .policy,
        ConflictPolicy.transactional,
      );
    });

    test('bed assignment is server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.bedAssignment)
            .policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('discharges are immutable versioned records', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.discharge)
            .policy,
        ConflictPolicy.immutableVersion,
      );
    });

    test('billing reconciles transactionally', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.billing).policy,
        ConflictPolicy.transactional,
      );
    });

    test('triage assessments use versioned revisions', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.triageAssessment,
        ).policy,
        ConflictPolicy.versionedRevision,
      );
    });

    test('ER visits are server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.erVisit).policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('ICU beds are server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.icuBed).policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('ICU vitals are append-only', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.icuVitals)
            .policy,
        ConflictPolicy.appendOnly,
      );
    });

    test('ICU handovers are append-only', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.icuHandover)
            .policy,
        ConflictPolicy.appendOnly,
      );
    });

    test('ventilator events resolve as event transactions', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.ventilatorEvent)
            .policy,
        ConflictPolicy.eventTransaction,
      );
    });

    test('blood units are server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.bloodUnit)
            .policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('transfusion requests are server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.transfusionRequest,
        ).policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('transfusions resolve as event transactions', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.transfusion)
            .policy,
        ConflictPolicy.eventTransaction,
      );
    });

    test('theatre bookings are server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.otBooking)
            .policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('theatre records resolve as event transactions', () {
      const List<String> records = <String>[
        ConflictPolicyRegistry.otPreOpAssessment,
        ConflictPolicyRegistry.otAnesthesiaRecord,
        ConflictPolicyRegistry.otProcedureLog,
        ConflictPolicyRegistry.otPostOpRecord,
      ];
      for (final String resourceType in records) {
        expect(
          ConflictPolicyRegistry.policyFor(resourceType).policy,
          ConflictPolicy.eventTransaction,
          reason: '$resourceType must deduplicate as an event',
        );
      }
    });

    test('imaging orders are server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.imagingOrder)
            .policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('imaging studies resolve as event transactions', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.imagingStudy)
            .policy,
        ConflictPolicy.eventTransaction,
      );
    });

    test(
      'verified imaging reports carry the immutable-with-correction policy',
      () {
        expect(
          ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.imagingReport)
              .policy,
          ConflictPolicy.immutableWithCorrection,
        );
      },
    );

    test('physiotherapy sessions are server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.physioSession)
            .policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('exercise regimens are server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.physioExercisePlan,
        ).policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('recovery notes resolve as versioned revisions', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.physioRecoveryNote,
        ).policy,
        ConflictPolicy.versionedRevision,
      );
    });

    test('nutrition assessments resolve as versioned revisions', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.dietAssessment)
            .policy,
        ConflictPolicy.versionedRevision,
      );
    });

    test('meal plans are server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.dietMealPlan)
            .policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('meal plan day menus are immutable versions', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.dietMealPlanDay)
            .policy,
        ConflictPolicy.immutableVersion,
      );
    });

    test('dietary intake resolves as event transactions', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.dietIntakeLog)
            .policy,
        ConflictPolicy.eventTransaction,
      );
    });

    test('telemedicine consultations are server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.teleConsultation,
        ).policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('live vitals overlays are append-only', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.teleVitalsOverlay,
        ).policy,
        ConflictPolicy.appendOnly,
      );
    });

    test('consultation archives are immutable versions', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.teleConsultationArchive,
        ).policy,
        ConflictPolicy.immutableVersion,
      );
    });

    test('discharge clearance resolves as versioned revisions', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.dischargeClearance,
        ).policy,
        ConflictPolicy.versionedRevision,
      );
    });

    test('a completed reconciliation is an immutable version', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.dischargeReconciliation,
        ).policy,
        ConflictPolicy.immutableVersion,
      );
    });

    test('medication decisions resolve as versioned revisions', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.dischargeReconciliationItem,
        ).policy,
        ConflictPolicy.versionedRevision,
      );
    });

    test('discharge settlement is server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.dischargeSettlement,
        ).policy,
        ConflictPolicy.serverAuthoritative,
      );
    });

    test('a reviewed AI summary is immutable with correction', () {
      expect(
        ConflictPolicyRegistry.policyFor(
          ConflictPolicyRegistry.dischargeAiSummary,
        ).policy,
        ConflictPolicy.immutableWithCorrection,
      );
    });

    test('ward rooms are server-authoritative', () {
      expect(
        ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.wardRoom)
            .policy,
        ConflictPolicy.serverAuthoritative,
      );
    });
  });

  group('automatic resolution', () {
    test('merges when all changed fields are mergeable and disjoint', () {
      expect(
        ConflictPolicyRegistry.canResolveAutomatically(
          ConflictPolicyRegistry.patient,
          clientChangedFields: <String>{'phone_number'},
          serverChangedFields: <String>{'address'},
        ),
        isTrue,
      );
    });

    test('escalates when the same field was edited on both sides', () {
      expect(
        ConflictPolicyRegistry.canResolveAutomatically(
          ConflictPolicyRegistry.patient,
          clientChangedFields: <String>{'phone_number'},
          serverChangedFields: <String>{'phone_number'},
        ),
        isFalse,
      );
    });

    test('escalates when a changed field is not registered as mergeable', () {
      // A name change is identity-relevant and must not be merged silently.
      expect(
        ConflictPolicyRegistry.canResolveAutomatically(
          ConflictPolicyRegistry.patient,
          clientChangedFields: <String>{'full_name'},
          serverChangedFields: <String>{'address'},
        ),
        isFalse,
      );
    });

    test('append-only entities resolve automatically', () {
      expect(
        ConflictPolicyRegistry.canResolveAutomatically(
          ConflictPolicyRegistry.vitalObservation,
        ),
        isTrue,
      );
    });

    test('immutable-with-correction entities require review', () {
      expect(
        ConflictPolicyRegistry.canResolveAutomatically(
          ConflictPolicyRegistry.labResult,
        ),
        isFalse,
      );
    });
  });

  group('ConflictPolicy semantics', () {
    test('only server-authoritative discards client state', () {
      for (final ConflictPolicy policy in ConflictPolicy.values) {
        expect(
          policy.discardsClientState,
          policy == ConflictPolicy.serverAuthoritative,
          reason: '${policy.name} must not discard client clinical state',
        );
      }
    });

    test('wire values are unique and round-trip', () {
      final Set<String> wireValues = ConflictPolicy.values
          .map((ConflictPolicy p) => p.wireValue)
          .toSet();
      expect(wireValues.length, ConflictPolicy.values.length);

      for (final ConflictPolicy policy in ConflictPolicy.values) {
        expect(ConflictPolicy.fromWire(policy.wireValue), policy);
      }
    });

    test('fromWire returns null for an unknown value', () {
      expect(ConflictPolicy.fromWire('last_write_wins'), isNull);
    });

    test('field-level merge is never reported as unconditionally automatic', () {
      // Overlap detection is the caller's responsibility, so the policy itself
      // must not advertise automatic resolution.
      expect(ConflictPolicy.fieldLevelMerge.isAutomatic, isFalse);
    });
  });
}
