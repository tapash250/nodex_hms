/// Operation theatre presentation providers (Module 19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/ot/ot.dart';

/// All theatre bookings visible to the signed-in user.
final otBookingsProvider = FutureProvider.autoDispose<List<OtBooking>>((
  Ref ref,
) async {
  return ref.watch(otRepositoryProvider).allBookings();
});

/// A single booking, or a not-found error when the row is missing locally.
final otBookingDetailProvider = FutureProvider.autoDispose
    .family<OtBooking, String>((Ref ref, String bookingId) async {
      final OtBooking? booking = await ref
          .watch(otRepositoryProvider)
          .bookingById(bookingId);
      if (booking == null) {
        throw const PersistenceError(
          message: 'This theatre booking is not available on this device.',
          code: 'ot_booking_not_found_locally',
        );
      }
      return booking;
    });

/// Bookings scheduled for a patient, soonest first.
final otBookingsForPatientProvider = FutureProvider.autoDispose
    .family<List<OtBooking>, String>((Ref ref, String patientId) async {
      return ref.watch(otRepositoryProvider).bookingsForPatient(patientId);
    });

/// The pre-op assessment recorded for a booking, when one exists.
final otPreOpForBookingProvider = FutureProvider.autoDispose
    .family<OtPreOpAssessment?, String>((Ref ref, String bookingId) async {
      return ref.watch(otRepositoryProvider).preOpForBooking(bookingId);
    });

/// The anesthesia record for a booking, when one exists.
final otAnesthesiaForBookingProvider = FutureProvider.autoDispose
    .family<OtAnesthesiaRecord?, String>((Ref ref, String bookingId) async {
      return ref.watch(otRepositoryProvider).anesthesiaForBooking(bookingId);
    });

/// The procedure log for a booking, when one exists.
final otProcedureLogForBookingProvider = FutureProvider.autoDispose
    .family<OtProcedureLog?, String>((Ref ref, String bookingId) async {
      return ref.watch(otRepositoryProvider).procedureLogForBooking(bookingId);
    });

/// The post-op record for a booking, when one exists.
final otPostOpForBookingProvider = FutureProvider.autoDispose
    .family<OtPostOpRecord?, String>((Ref ref, String bookingId) async {
      return ref.watch(otRepositoryProvider).postOpForBooking(bookingId);
    });
