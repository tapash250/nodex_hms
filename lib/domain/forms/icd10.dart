/// The ICD-10 catalogue and its search (Module 47).
///
/// The catalogue is reference data: the codes themselves are not PHI, so the
/// device holds them and searches them offline. The search ranks a typed code
/// above a typed description, because a clinician who types "E11" wants the
/// diabetes code, not every sentence that contains "eleven".
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';

/// One ICD-10 code.
@immutable
final class Icd10Code {
  /// Declares a code.
  const Icd10Code({
    required this.code,
    required this.description,
    this.category,
    this.isBillable = true,
  });

  /// The code itself, such as E11.9.
  final String code;

  /// What the code means.
  final String description;

  /// The chapter or group the code sits in.
  final String? category;

  /// Whether the code may be used for billing.
  final bool isBillable;

  /// Reads a code from a local row.
  factory Icd10Code.fromRow(Map<String, Object?> row) => Icd10Code(
    code: row['code']! as String,
    description: row['description']! as String,
    category: row['category'] as String?,
    isBillable: (row['is_billable'] as int?) == 1,
  );

  @override
  String toString() => '$code — $description';
}

/// Searches the catalogue.
///
/// The ranking is deliberate: an exact code first, then a code that starts
/// with what was typed, then a code that contains it, then a description that
/// contains the words. A search that returned every description match before
/// the code the clinician was typing would be useless.
List<Icd10Code> searchIcd10(
  List<Icd10Code> codes,
  String query, {
  int limit = 20,
}) {
  final String needle = query.trim().toUpperCase();
  if (needle.isEmpty) return const <Icd10Code>[];

  final List<({Icd10Code code, int rank})> hits =
      <({Icd10Code code, int rank})>[];
  for (final Icd10Code code in codes) {
    final String upper = code.code.toUpperCase();
    final String description = code.description.toUpperCase();
    if (upper == needle) {
      hits.add((code: code, rank: 0));
      continue;
    }
    if (upper.startsWith(needle)) {
      hits.add((code: code, rank: 1));
      continue;
    }
    if (upper.contains(needle)) {
      hits.add((code: code, rank: 2));
      continue;
    }
    if (description.contains(needle)) {
      hits.add((code: code, rank: 3));
    }
  }

  hits.sort((({Icd10Code code, int rank}) a, ({Icd10Code code, int rank}) b) {
    final int byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    return a.code.code.compareTo(b.code.code);
  });
  return hits
      .take(limit)
      .map((({Icd10Code code, int rank}) hit) => hit.code)
      .toList(growable: false);
}
