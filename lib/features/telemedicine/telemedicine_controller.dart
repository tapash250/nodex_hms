/// Telemedicine presentation providers (Module 22).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine_repository.dart';

/// Consultation detail bundle for the telemedicine screen.
final class TeleConsultationDetail {
  /// Creates a bundle.
  const TeleConsultationDetail({
    required this.consultation,
    required this.overlays,
    this.archive,
  });

  /// The consultation itself.
  final TeleConsultation consultation;

  /// Live vitals readings taken during the call, oldest first.
  final List<TeleVitalsOverlay> overlays;

  /// The retained archive, once one exists.
  final TeleConsultationArchive? archive;
}

/// Virtual consultations for one patient.
final teleConsultationsForPatientProvider = FutureProvider.autoDispose
    .family<List<TeleConsultation>, String>((Ref ref, String patientId) async {
      return ref
          .watch(telemedicineRepositoryProvider)
          .consultationsForPatient(patientId);
    });

/// One consultation with its vitals overlays and archive.
final teleConsultationDetailProvider = FutureProvider.autoDispose
    .family<TeleConsultationDetail, String>((
      Ref ref,
      String consultationId,
    ) async {
      final TelemedicineRepository repository = ref.watch(
        telemedicineRepositoryProvider,
      );
      final TeleConsultation? consultation = await repository.consultationById(
        consultationId,
      );
      if (consultation == null) {
        throw const PersistenceError(
          message: 'This consultation is not available on this device.',
          code: 'tele_consultation_not_found_locally',
        );
      }
      return TeleConsultationDetail(
        consultation: consultation,
        overlays: await repository.overlaysForConsultation(consultationId),
        archive: await repository.archiveForConsultation(consultationId),
      );
    });
