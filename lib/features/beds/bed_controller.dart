/// Bed presentation providers (Module 11).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/beds/bed.dart';
import 'package:nodex_hms/domain/beds/bed_repository.dart';

/// Wards in the local scope, for the census picker.
final censusWardsProvider = FutureProvider.autoDispose<List<WardInfo>>((
  Ref ref,
) async {
  return ref.watch(bedRepositoryProvider).listWards();
});

/// One ward's beds with their live occupants.
final wardCensusProvider = FutureProvider.autoDispose
    .family<List<BedCensusEntry>, String>((Ref ref, String wardId) async {
      final BedRepository repository = ref.watch(bedRepositoryProvider);
      final List<BedCensusEntry> entries = <BedCensusEntry>[];
      for (final bed in await repository.listBedsForWard(wardId)) {
        entries.add(
          BedCensusEntry(
            bed: bed,
            assignment: await repository.activeAssignmentForBed(bed.id),
          ),
        );
      }
      return entries;
    });

/// A patient's active stay, or null when not admitted.
final patientStayProvider = FutureProvider.autoDispose.family((
  Ref ref,
  String patientId,
) async {
  return ref.watch(bedRepositoryProvider).activeAssignmentForPatient(patientId);
});

/// Display name for an occupant, falling back to the id prefix.
final bedOccupantNameProvider = FutureProvider.autoDispose
    .family<String, String>((Ref ref, String patientId) async {
      final patient = await ref
          .watch(patientRepositoryProvider)
          .getPatient(patientId);
      if (patient == null) return patientId.substring(0, 8);
      return patient.displayName;
    });

/// How full one ward is.
final class WardOccupancy {
  /// Creates an occupancy reading.
  const WardOccupancy({
    required this.wardId,
    required this.name,
    required this.total,
    required this.occupied,
  });

  /// Ward identifier.
  final String wardId;

  /// Ward name.
  final String name;

  /// Beds registered in the ward.
  final int total;

  /// Beds with a live occupant.
  final int occupied;

  /// Beds free to take a patient.
  int get free => total - occupied;

  /// The share of the ward that is occupied, as a fraction.
  double get ratio => total == 0 ? 0 : occupied / total;
}

/// Bed occupancy for every ward in scope (Module 49).
///
/// Occupancy is counted from the live assignments rather than from a stored
/// number, so the graph cannot disagree with the board below it.
final wardOccupancyProvider = FutureProvider.autoDispose<List<WardOccupancy>>((
  Ref ref,
) async {
  final BedRepository repository = ref.watch(bedRepositoryProvider);
  final List<WardInfo> wards = await repository.listWards();
  final List<WardOccupancy> occupancies = <WardOccupancy>[];
  for (final WardInfo ward in wards) {
    final List<Bed> beds = await repository.listBedsForWard(ward.id);
    int occupied = 0;
    for (final Bed bed in beds) {
      final BedAssignment? assignment = await repository.activeAssignmentForBed(
        bed.id,
      );
      if (assignment != null) occupied++;
    }
    occupancies.add(
      WardOccupancy(
        wardId: ward.id,
        name: ward.displayName,
        total: beds.length,
        occupied: occupied,
      ),
    );
  }
  return occupancies;
});
