/// Per-entity offline conflict policies.
///
/// The specification is explicit that NODEX must not use an undocumented global
/// "last write wins" policy for clinical data. Each entity declares a
/// deterministic, auditable strategy, and every strategy is covered by automated
/// tests.
///
/// This file is the single registry consulted by the sync layer when the backend
/// reports a conflicting write. Adding a clinical entity without registering its
/// policy is a defect, and [ConflictPolicyRegistry.policyFor] fails loudly rather
/// than defaulting to a permissive merge.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Deterministic conflict resolution strategies.
///
/// The wire values match the `entity_policy` check constraint on
/// `public.conflict_records`, so a client-detected conflict and a
/// server-recorded one describe the same strategy.
enum ConflictPolicy {
  /// Merge non-overlapping field changes; overlapping edits go to human review.
  ///
  /// Used for patient demographics, where two clerks may legitimately edit
  /// different fields of the same record while offline.
  fieldLevelMerge('field_level_merge'),

  /// Retain both versions as ordered revisions; nothing is overwritten.
  ///
  /// Used for clinical notes.
  versionedRevision('versioned_revision'),

  /// Append the new entry; existing entries are immutable.
  appendOnly('append_only'),

  /// Orders are immutable once issued; a change produces a new version.
  ///
  /// Used for prescriptions, so a superseded order remains readable exactly as
  /// it was authorized.
  immutableVersion('immutable_version'),

  /// Model the action as an event; duplicate events are deduplicated by identity.
  ///
  /// Used for medication administration, where the clinically meaningful fact is
  /// "this dose was given at this time by this nurse".
  eventTransaction('event_transaction'),

  /// Results are immutable; a change is recorded as an explicit correction.
  ///
  /// Used for laboratory results, preserving the original released value.
  immutableWithCorrection('immutable_with_correction'),

  /// Resolve by replaying the transaction against current server state.
  ///
  /// Used for inventory and billing, where the invariant is a balance rather
  /// than a field value.
  transactional('transactional'),

  /// The server's value wins unconditionally and the client is reconciled.
  ///
  /// Used for bed assignment: two devices cannot both be right about who
  /// occupies a bed, and the server holds the allocation.
  serverAuthoritative('server_authoritative');

  const ConflictPolicy(this.wireValue);

  /// Value persisted in `public.conflict_records.entity_policy`.
  final String wireValue;

  /// Whether this policy can complete without a human decision.
  bool get isAutomatic => switch (this) {
    ConflictPolicy.appendOnly => true,
    ConflictPolicy.versionedRevision => true,
    ConflictPolicy.immutableVersion => true,
    ConflictPolicy.eventTransaction => true,
    ConflictPolicy.transactional => true,
    ConflictPolicy.serverAuthoritative => true,
    // A field-level merge is automatic only when edits do not overlap; the
    // registry reports it as review-requiring so the caller must decide
    // explicitly rather than assuming a silent merge.
    ConflictPolicy.fieldLevelMerge => false,
    ConflictPolicy.immutableWithCorrection => false,
  };

  /// Whether resolving under this policy discards any client-committed data.
  ///
  /// Only [serverAuthoritative] does, and only for a projection the device does
  /// not own. No policy discards a clinical fact the device recorded.
  bool get discardsClientState => this == ConflictPolicy.serverAuthoritative;

  /// Parses a wire value, or null when unrecognised.
  static ConflictPolicy? fromWire(String value) {
    for (final ConflictPolicy policy in ConflictPolicy.values) {
      if (policy.wireValue == value) {
        return policy;
      }
    }
    return null;
  }
}

/// Registration of an entity's conflict behavior.
@immutable
final class ConflictPolicyEntry {
  /// Registers [policy] for [resourceType].
  const ConflictPolicyEntry({
    required this.resourceType,
    required this.policy,
    required this.rationale,
    this.mergeableFields = const <String>{},
  });

  /// The resource type as used by repositories and the mutation ledger.
  final String resourceType;

  /// The strategy that governs this resource type.
  final ConflictPolicy policy;

  /// Why this strategy is correct for this entity, for reviewers and ADRs.
  final String rationale;

  /// Fields eligible for automatic merge under [ConflictPolicy.fieldLevelMerge].
  ///
  /// Fields outside this set escalate to human review even when the policy
  /// permits merging, so an unlisted field is never merged by default.
  final Set<String> mergeableFields;
}

/// The authoritative mapping from resource type to conflict policy.
abstract final class ConflictPolicyRegistry {
  /// Patient demographic record.
  static const String patient = 'patient';

  /// Clinical note.
  static const String clinicalNote = 'clinical_note';

  /// Prescription order.
  static const String prescription = 'prescription';

  /// Medication administration event.
  static const String medicationAdministration = 'medication_administration';

  /// Laboratory result.
  static const String labResult = 'lab_result';

  /// Inventory stock movement.
  static const String stockMovement = 'stock_movement';

  /// Bed assignment.
  static const String bedAssignment = 'bed_assignment';

  /// Invoice or payment record.
  static const String billing = 'billing';

  /// Vital sign observation.
  static const String vitalObservation = 'vital_observation';

  /// Appointment booking.
  static const String appointment = 'appointment';

  /// Clinical encounter shell.
  static const String encounter = 'encounter';

  static const Map<String, ConflictPolicyEntry> _entries =
      <String, ConflictPolicyEntry>{
        patient: ConflictPolicyEntry(
          resourceType: patient,
          policy: ConflictPolicy.fieldLevelMerge,
          rationale:
              'Two registration desks may legitimately edit different '
              'demographic fields while offline. Overlapping edits to the same '
              'field are a human decision, not a merge.',
          mergeableFields: <String>{
            'phone_number',
            'email',
            'address',
            'next_of_kin',
            'occupation',
            'marital_status',
            'preferred_language',
          },
        ),
        clinicalNote: ConflictPolicyEntry(
          resourceType: clinicalNote,
          policy: ConflictPolicy.versionedRevision,
          rationale:
              'A clinical note is a signed narrative. Concurrent authoring '
              'produces ordered revisions; no revision is overwritten.',
        ),
        prescription: ConflictPolicyEntry(
          resourceType: prescription,
          policy: ConflictPolicy.immutableVersion,
          rationale:
              'An authorized order must remain readable exactly as issued. A '
              'change creates a new version that supersedes, never mutates, '
              'the prior order.',
        ),
        medicationAdministration: ConflictPolicyEntry(
          resourceType: medicationAdministration,
          policy: ConflictPolicy.eventTransaction,
          rationale:
              'Administration is an event: a dose given at a time by a '
              'clinician. Duplicate uploads deduplicate by event identity so a '
              'retry cannot record a second dose.',
        ),
        labResult: ConflictPolicyEntry(
          resourceType: labResult,
          policy: ConflictPolicy.immutableWithCorrection,
          rationale:
              'A released result is a clinical fact others may have acted on. '
              'Corrections are additive and explicitly attributed.',
        ),
        stockMovement: ConflictPolicyEntry(
          resourceType: stockMovement,
          policy: ConflictPolicy.transactional,
          rationale:
              'The invariant is the resulting balance, not the field value. '
              'Movements replay against current stock rather than overwriting '
              'a quantity.',
        ),
        bedAssignment: ConflictPolicyEntry(
          resourceType: bedAssignment,
          policy: ConflictPolicy.serverAuthoritative,
          rationale:
              'Two devices cannot both be correct about bed occupancy. The '
              'server holds the allocation and the client reconciles to it.',
        ),
        billing: ConflictPolicyEntry(
          resourceType: billing,
          policy: ConflictPolicy.transactional,
          rationale:
              'Financial records reconcile as ledger transactions so that '
              'concurrent payments do not overwrite one another.',
        ),
        vitalObservation: ConflictPolicyEntry(
          resourceType: vitalObservation,
          policy: ConflictPolicy.appendOnly,
          rationale:
              'Observations are timestamped facts. Two nurses recording '
              'vitals produce two observations, not a conflict.',
        ),
        appointment: ConflictPolicyEntry(
          resourceType: appointment,
          policy: ConflictPolicy.serverAuthoritative,
          rationale:
              'Slot allocation is a scarce shared resource arbitrated by the '
              'server; the client cannot claim a slot unilaterally.',
        ),
        encounter: ConflictPolicyEntry(
          resourceType: encounter,
          policy: ConflictPolicy.versionedRevision,
          rationale:
              'The encounter shell carries clinical context that must not be '
              'silently replaced while a colleague is documenting.',
        ),
      };

  /// Every registered entry, keyed by resource type.
  static Map<String, ConflictPolicyEntry> get entries =>
      Map<String, ConflictPolicyEntry>.unmodifiable(_entries);

  /// Resource types with a registered policy.
  static Iterable<String> get registeredResourceTypes => _entries.keys;

  /// Returns the entry for [resourceType].
  ///
  /// Throws [IntegrityError] when the type is unregistered. Failing loudly is
  /// deliberate: an unregistered clinical entity would otherwise fall back to an
  /// implicit last-write-wins, which the specification prohibits.
  static ConflictPolicyEntry policyFor(String resourceType) {
    final ConflictPolicyEntry? entry = _entries[resourceType];
    if (entry == null) {
      throw IntegrityError(
        message:
            'No conflict policy is registered for resource type '
            '"$resourceType". A clinical entity must declare a deterministic '
            'conflict strategy before it can synchronize.',
        subject: 'conflict_policy',
        code: 'unregistered_conflict_policy',
        context: <String, Object?>{'resource_type': resourceType},
      );
    }
    return entry;
  }

  /// Whether [resourceType] has a registered policy.
  static bool isRegistered(String resourceType) =>
      _entries.containsKey(resourceType);

  /// Whether a conflict on [resourceType] can be resolved without human review.
  ///
  /// For [ConflictPolicy.fieldLevelMerge], resolution is automatic only when
  /// every changed field is registered as mergeable and no field was edited on
  /// both sides.
  static bool canResolveAutomatically(
    String resourceType, {
    Set<String> clientChangedFields = const <String>{},
    Set<String> serverChangedFields = const <String>{},
  }) {
    final ConflictPolicyEntry entry = policyFor(resourceType);
    if (entry.policy != ConflictPolicy.fieldLevelMerge) {
      return entry.policy.isAutomatic;
    }

    final bool allMergeable = clientChangedFields.every(
      entry.mergeableFields.contains,
    );
    final bool overlapping = clientChangedFields
        .intersection(serverChangedFields)
        .isNotEmpty;
    return allMergeable && !overlapping;
  }
}
