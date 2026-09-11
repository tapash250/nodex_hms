/// Field-level 3-way merge for patient demographics (Module 10).
///
/// The registry declares *which* columns may merge; this file implements *how*.
/// Given the last-synced base row plus the local and server versions, each
/// column resolves independently:
///
/// * Only one side changed the column → take the changed value.
/// * Both sides changed it to the same value → take it.
/// * Both sides changed it differently → conflict, always human-reviewed.
/// * Neither changed it → keep the base value.
///
/// Automatic application additionally requires every locally changed column to
/// sit inside the registry's mergeable set (via
/// `ConflictPolicyRegistry.canResolveAutomatically`). Identity columns — MRN,
/// names, date of birth, gender, national ID hash, blood group — are never in
/// that set, so touching identity offline always escalates to review.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/sync/conflict_policy.dart';

/// Outcome of merging one patient row.
@immutable
final class PatientMergeResult {
  /// Creates a merge result.
  const PatientMergeResult._({
    required this.automatic,
    required this.merged,
    required this.conflictingFields,
    required this.autoMergedFields,
  });

  /// An automatic merge: [merged] holds the resolved row.
  const PatientMergeResult.merged({
    required Map<String, Object?> merged,
    required Set<String> autoMergedFields,
  }) : this._(
         automatic: true,
         merged: merged,
         conflictingFields: const <String>{},
         autoMergedFields: autoMergedFields,
       );

  /// Escalation: overlapping edits need a human decision.
  const PatientMergeResult.needsReview({required Set<String> conflictingFields})
    : this._(
        automatic: false,
        merged: const <String, Object?>{},
        conflictingFields: conflictingFields,
        autoMergedFields: const <String>{},
      );

  /// Whether the merge completed without human input.
  final bool automatic;

  /// Resolved row. Empty unless [automatic].
  final Map<String, Object?> merged;

  /// Columns both sides edited differently. Empty when [automatic].
  final Set<String> conflictingFields;

  /// Columns taken from a changed side during an automatic merge.
  final Set<String> autoMergedFields;
}

/// Merges one patient row from its last-synced base plus both edited versions.
///
/// All three maps use local column names (`phone_number`, not `phone`) with
/// `updated_at`/`created_at` excluded by the caller: timestamps are
/// write-metadata, not clinical content, and comparing them would flag every
/// row as conflicted.
///
/// One refinement over the registry's conservative gate: coincident identical
/// edits on both sides count as agreement, not overlap. Two desks arriving at
/// the same correction independently is corroboration — forcing review would
/// punish agreement. True overlap (same column, different values) always
/// escalates.
PatientMergeResult mergePatientRow({
  required Map<String, Object?> base,
  required Map<String, Object?> local,
  required Map<String, Object?> server,
}) {
  final Set<String> columns = <String>{
    ...base.keys,
    ...local.keys,
    ...server.keys,
  }..removeAll(const <String>{'id', 'tenant_id', 'created_at', 'updated_at'});

  final Map<String, Object?> merged = <String, Object?>{};
  final Set<String> conflicts = <String>{};
  final Set<String> autoMerged = <String>{};

  final Set<String> clientChanged = <String>{};
  final Set<String> serverChanged = <String>{};

  for (final String column in columns) {
    final Object? baseValue = base[column];
    final Object? localValue = local.containsKey(column)
        ? local[column]
        : baseValue;
    final Object? serverValue = server.containsKey(column)
        ? server[column]
        : baseValue;

    final bool localTouched = !_valuesEqual(localValue, baseValue);
    final bool serverTouched = !_valuesEqual(serverValue, baseValue);

    if (localTouched) {
      clientChanged.add(column);
    }
    if (serverTouched) {
      serverChanged.add(column);
    }

    if (localTouched &&
        serverTouched &&
        !_valuesEqual(localValue, serverValue)) {
      // Both sides edited the same column to different values. No merge rule
      // may prefer one clinician's entry over another's.
      conflicts.add(column);
      continue;
    }

    if (localTouched || serverTouched) {
      merged[column] = localTouched ? localValue : serverValue;
      autoMerged.add(column);
    } else {
      merged[column] = baseValue;
    }
  }

  // Coincident identical edits are agreement: remove them from the changed
  // sets before applying the registry gate, so agreement never escalates.
  final Set<String> agreed = clientChanged
      .intersection(serverChanged)
      .where((String column) => !conflicts.contains(column))
      .toSet();
  final Set<String> effectiveClient = clientChanged.difference(agreed);
  final Set<String> effectiveServer = serverChanged.difference(agreed);

  if (conflicts.isNotEmpty ||
      !ConflictPolicyRegistry.canResolveAutomatically(
        ConflictPolicyRegistry.patient,
        clientChangedFields: effectiveClient,
        serverChangedFields: effectiveServer,
      )) {
    final Set<String> reviewFields = <String>{...conflicts};
    if (conflicts.isEmpty) {
      // No overlap, but a locally changed column sits outside the mergeable
      // set (identity data). Escalate naming exactly those columns.
      reviewFields.addAll(
        effectiveClient.where(
          (String column) =>
              !ConflictPolicyRegistry.policyFor(ConflictPolicyRegistry.patient)
                  .mergeableFields
                  .contains(column),
        ),
      );
    }
    return PatientMergeResult.needsReview(conflictingFields: reviewFields);
  }

  return PatientMergeResult.merged(
    merged: Map<String, Object?>.unmodifiable(merged),
    autoMergedFields: Set<String>.unmodifiable(autoMerged),
  );
}

/// Value equality across the representations PowerSync and PostgreSQL use.
///
/// Integers 0/1 and booleans compare equal. Date strings compare by calendar
/// day when both sides are bare dates (`date_of_birth` is a civil date, not an
/// instant, so `1984-03-17` equals `1984-03-17T00:00:00.000Z` in any timezone);
/// full timestamps compare by instant.
bool _valuesEqual(Object? a, Object? b) {
  if (a == b) {
    return true;
  }
  if (a == null || b == null) {
    return false;
  }
  if (a is bool && b is int) {
    return (a ? 1 : 0) == b;
  }
  if (a is int && b is bool) {
    return a == (b ? 1 : 0);
  }
  if (a is String && b is String) {
    final RegExp bareDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (bareDate.hasMatch(a) && bareDate.hasMatch(b)) {
      return a == b;
    }
    final DateTime? da = DateTime.tryParse(a);
    final DateTime? db = DateTime.tryParse(b);
    if (da != null && db != null) {
      // Compare calendar days in UTC: a bare date parses to local midnight,
      // which shifts under toUtc() outside UTC zones.
      if (bareDate.hasMatch(a) || bareDate.hasMatch(b)) {
        return da.year == db.year && da.month == db.month && da.day == db.day;
      }
      return da.toUtc().isAtSameMomentAs(db.toUtc());
    }
  }
  return false;
}
