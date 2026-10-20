/// The medical icon repository (Module 51).
///
/// One vocabulary of clinical symbols, so a blood gas, a ventilator and a
/// prescription look the same in every module that draws them. Each icon is a
/// constant, which is what makes the set tree-shaken: a build that draws four
/// icons ships four, because the icon tree-shaker can see which constants
/// the app actually reaches.
library;

import 'package:flutter/material.dart';

/// The medical symbols the application uses.
///
/// The names are the contract: a screen asks for `MedicalIcons.ventilator`
/// and gets the same symbol every time, rather than picking whichever
/// Material icon looked closest.
abstract final class MedicalIcons {
  /// A blood gas or laboratory sample.
  static const IconData bloodSample = Icons.bloodtype_outlined;

  /// A ventilator or airway.
  static const IconData ventilator = Icons.air;

  /// A prescription.
  static const IconData prescription = Icons.medication_outlined;

  /// A medication administration.
  static const IconData medication = Icons.vaccines_outlined;

  /// A patient bed.
  static const IconData bed = Icons.bed_outlined;

  /// A ward or bay.
  static const IconData ward = Icons.apartment_outlined;

  /// A heart or cardiac event.
  static const IconData cardiac = Icons.monitor_heart_outlined;

  /// A theatre or procedure.
  static const IconData surgery = Icons.healing_outlined;

  /// A radiology or imaging study.
  static const IconData imaging = Icons.image_outlined;

  /// A pathology or specimen.
  static const IconData specimen = Icons.science_outlined;

  /// An emergency.
  static const IconData emergency = Icons.emergency_outlined;

  /// An ambulance or transfer.
  static const IconData transfer = Icons.local_shipping_outlined;

  /// Nutrition or diet.
  static const IconData nutrition = Icons.restaurant_outlined;

  /// Physiotherapy.
  static const IconData physiotherapy = Icons.accessibility_new_outlined;

  /// A nursing handover.
  static const IconData handover = Icons.swap_horiz_outlined;

  /// A critical or abnormal result.
  static const IconData critical = Icons.priority_high;

  /// A clinical note.
  static const IconData note = Icons.description_outlined;

  /// A diagnosis.
  static const IconData diagnosis = Icons.monitor_heart_outlined;

  /// An allergy.
  static const IconData allergy = Icons.warning_amber_outlined;

  /// A document or report.
  static const IconData document = Icons.folder_shared_outlined;

  /// A bill or invoice.
  static const IconData invoice = Icons.receipt_long_outlined;

  /// A blood product.
  static const IconData bloodProduct = Icons.bloodtype_outlined;

  /// A clinical message or thread.
  static const IconData message = Icons.forum_outlined;

  /// A working board.
  static const IconData board = Icons.view_kanban_outlined;

  /// A service request.
  static const IconData serviceRequest = Icons.build_outlined;

  /// Every icon, with the name it is known by.
  ///
  /// The registry is what the gallery renders and what the tests walk, so an
  /// icon that is added without a name is caught rather than shipped.
  static const Map<String, IconData> registry = <String, IconData>{
    'blood_sample': bloodSample,
    'ventilator': ventilator,
    'prescription': prescription,
    'medication': medication,
    'bed': bed,
    'ward': ward,
    'cardiac': cardiac,
    'surgery': surgery,
    'imaging': imaging,
    'specimen': specimen,
    'emergency': emergency,
    'transfer': transfer,
    'nutrition': nutrition,
    'physiotherapy': physiotherapy,
    'handover': handover,
    'critical': critical,
    'note': note,
    'diagnosis': diagnosis,
    'allergy': allergy,
    'document': document,
    'invoice': invoice,
    'blood_product': bloodProduct,
    'message': message,
    'board': board,
    'service_request': serviceRequest,
  };

  /// The icon known by [name], or null when there is no such icon.
  static IconData? byName(String name) => registry[name];

  /// How many icons the repository holds.
  static int get length => registry.length;
}
