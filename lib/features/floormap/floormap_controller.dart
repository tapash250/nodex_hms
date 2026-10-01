/// Floor map presentation providers (Module 24).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/floormap/floormap.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Floors that have rooms drawn on them, ordered for the floor selector.
final floorLabelsProvider = FutureProvider.autoDispose<List<String>>((
  Ref ref,
) async {
  final List<WardRoom> rooms = await ref
      .watch(floorMapRepositoryProvider)
      .allRooms();
  final List<String> floors =
      rooms
          .map((WardRoom room) => room.floorLabel)
          .toSet()
          .toList(growable: false)
        ..sort();
  return floors;
});

/// Wards drawn on one floor, so a room can be linked to the ward whose
/// patients it will show.
final floorSpacesProvider = FutureProvider.autoDispose
    .family<List<FloorSpace>, String>((Ref ref, String floorLabel) async {
      return ref.watch(floorMapRepositoryProvider).spacesForFloor(floorLabel);
    });

/// Live occupancy of one floor.
///
/// Reading the floor map is itself permission-gated, so the provider supplies
/// the signed-in session's policy rather than bypassing the use case.
final floorOccupancyProvider = FutureProvider.autoDispose
    .family<FloorOccupancy, String>((Ref ref, String floorLabel) async {
      return ref
          .watch(floorOccupancyUseCaseProvider)
          .call(
            policy: ref.watch(sessionProvider).authorization,
            floorLabel: floorLabel,
          );
    });
