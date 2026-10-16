/// Hospital contacts directory entities (Module 42).
///
/// Specification scope: the institution's contact book — who to call.
///
/// This is deliberately not the staff directory (Module 08, a registry of
/// people and their credentials) or the department registry (Module 12, an
/// organisational structure). A contact is an operational reachability fact —
/// an emergency number, a ward help desk, a duty engineer, an ambulance
/// provider — and internal contact points are often role-based rather than
/// person-based, because the number outlives whoever is holding the phone.
///
/// Contacts are archived, never deleted: an archived row still explains the
/// number a historical document or incident report names. Archiving is a
/// one-way transition; a contact that must come back is registered afresh.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// What kind of contact point this is.
enum ContactCategory {
  /// A number reached in an emergency.
  emergency('emergency'),

  /// A clinical service (blood bank, laboratory, on-call clinician).
  clinical('clinical'),

  /// Operational support (engineering, portering, security, IT).
  support('support'),

  /// Administration (HR, billing, records, reception).
  administrative('administrative'),

  /// An outside organisation (referral hospital, vendor, ambulance, insurer).
  external('external');

  const ContactCategory(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ContactCategory.emergency => 'Emergency',
    ContactCategory.clinical => 'Clinical',
    ContactCategory.support => 'Support',
    ContactCategory.administrative => 'Administration',
    ContactCategory.external => 'External',
  };

  /// Parses a stored value.
  static ContactCategory fromWire(String value) =>
      ContactCategory.values.firstWhere(
        (ContactCategory category) => category.wireValue == value,
        orElse: () => ContactCategory.support,
      );
}

/// Registry status of a contact.
enum ContactStatus {
  /// Current and reachable.
  active('active'),

  /// Retired; retained as a historical reference and frozen.
  archived('archived');

  const ContactStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static ContactStatus fromWire(String value) =>
      ContactStatus.values.firstWhere(
        (ContactStatus status) => status.wireValue == value,
        orElse: () => ContactStatus.active,
      );

  /// Whether the contact may still be edited.
  bool get isEditable => this == ContactStatus.active;
}

/// A hospital contact directory entry.
@immutable
final class DirectoryContact {
  /// Creates a contact.
  const DirectoryContact({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.category,
    required this.phonePrimary,
    required this.isEmergency,
    required this.available24_7,
    required this.displayOrder,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.facilityId,
    this.departmentId,
    this.contactRole,
    this.organisation,
    this.phoneSecondary,
    this.extension,
    this.email,
    this.address,
    this.notes,
    this.createdAt,
  });

  /// Validates and builds a new contact row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String createdBy,
    required String name,
    required String phonePrimary,
    ContactCategory category = ContactCategory.support,
    String? facilityId,
    String? departmentId,
    String? contactRole,
    String? organisation,
    String? phoneSecondary,
    String? extension,
    String? email,
    String? address,
    String? notes,
    bool isEmergency = false,
    bool available24_7 = false,
    int displayOrder = 100,
    String contactId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (name.trim().isEmpty) {
      fieldErrors['name'] = 'A contact name is required.';
    }
    if (phonePrimary.trim().isEmpty) {
      fieldErrors['phone_primary'] = 'A primary phone number is required.';
    }
    final String? mail = _trimmed(email);
    if (mail != null && !_emailPattern.hasMatch(mail)) {
      fieldErrors['email'] = 'Expected a valid email address.';
    }
    if (displayOrder < 0 || displayOrder > 10000) {
      fieldErrors['display_order'] = 'Expected a value between 0 and 10000.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Contact entry failed validation.',
        fieldErrors: fieldErrors,
        code: 'contact_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (contactId.isNotEmpty) 'id': contactId,
      'tenant_id': tenantId,
      'facility_id': _trimmed(facilityId),
      'department_id': _trimmed(departmentId),
      'name': name.trim(),
      'category': category.wireValue,
      'contact_role': _trimmed(contactRole),
      'organisation': _trimmed(organisation),
      'phone_primary': phonePrimary.trim(),
      'phone_secondary': _trimmed(phoneSecondary),
      'extension': _trimmed(extension),
      'email': mail,
      'address': _trimmed(address),
      'notes': _trimmed(notes),
      'is_emergency': isEmergency,
      'available_24_7': available24_7,
      'display_order': displayOrder,
      'status': ContactStatus.active.wireValue,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a contact from a local row.
  factory DirectoryContact.fromRow(Map<String, Object?> row) =>
      DirectoryContact(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        name: row['name']! as String,
        category: ContactCategory.fromWire(
          (row['category'] as String?) ?? ContactCategory.support.wireValue,
        ),
        phonePrimary: row['phone_primary']! as String,
        isEmergency: _asBool(row['is_emergency']),
        available24_7: _asBool(row['available_24_7']),
        displayOrder: _asInt(row['display_order']),
        status: ContactStatus.fromWire(
          (row['status'] as String?) ?? ContactStatus.active.wireValue,
        ),
        createdBy: row['created_by']! as String,
        updatedAt: _parse(row['updated_at']),
        facilityId: row['facility_id'] as String?,
        departmentId: row['department_id'] as String?,
        contactRole: row['contact_role'] as String?,
        organisation: row['organisation'] as String?,
        phoneSecondary: row['phone_secondary'] as String?,
        extension: row['extension'] as String?,
        email: row['email'] as String?,
        address: row['address'] as String?,
        notes: row['notes'] as String?,
        createdAt: _parse(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Facility the contact belongs to, or null when tenant-wide.
  final String? facilityId;

  /// Related department, when any.
  final String? departmentId;

  /// Human-readable contact point name.
  final String name;

  /// What kind of contact point this is.
  final ContactCategory category;

  /// The role or position the number reaches, when role-based.
  final String? contactRole;

  /// External counterpart organisation, when not internal.
  final String? organisation;

  /// Primary phone number.
  final String phonePrimary;

  /// Secondary phone number.
  final String? phoneSecondary;

  /// Internal extension.
  final String? extension;

  /// Email address.
  final String? email;

  /// Postal address.
  final String? address;

  /// Free-text note.
  final String? notes;

  /// Whether this is an emergency contact.
  final bool isEmergency;

  /// Whether the contact is staffed around the clock.
  final bool available24_7;

  /// Ordering hint within a category, lowest first.
  final int displayOrder;

  /// Registry status.
  final ContactStatus status;

  /// Who registered the contact.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// When the contact was registered, UTC.
  final DateTime? createdAt;

  /// Whether the contact may be edited or archived.
  bool get isEditable => status.isEditable;
}

/// The full editable change set for a contact.
Map<String, Object?> contactChanges({
  String? facilityId,
  String? departmentId,
  required String name,
  required ContactCategory category,
  String? contactRole,
  String? organisation,
  required String phonePrimary,
  String? phoneSecondary,
  String? extension,
  String? email,
  String? address,
  String? notes,
  required bool isEmergency,
  required bool available24_7,
  required int displayOrder,
}) {
  final String? mail = _trimmed(email);
  if (mail != null && !_emailPattern.hasMatch(mail)) {
    throw const ValidationError(
      message: 'Contact entry failed validation.',
      fieldErrors: <String, String>{'email': 'Expected a valid email address.'},
      code: 'contact_invalid',
    );
  }
  if (displayOrder < 0 || displayOrder > 10000) {
    throw const ValidationError(
      message: 'Contact entry failed validation.',
      fieldErrors: <String, String>{
        'display_order': 'Expected a value between 0 and 10000.',
      },
      code: 'contact_invalid',
    );
  }
  return <String, Object?>{
    'facility_id': _trimmed(facilityId),
    'department_id': _trimmed(departmentId),
    'name': name.trim(),
    'category': category.wireValue,
    'contact_role': _trimmed(contactRole),
    'organisation': _trimmed(organisation),
    'phone_primary': phonePrimary.trim(),
    'phone_secondary': _trimmed(phoneSecondary),
    'extension': _trimmed(extension),
    'email': mail,
    'address': _trimmed(address),
    'notes': _trimmed(notes),
    'is_emergency': isEmergency,
    'available_24_7': available24_7,
    'display_order': displayOrder,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

/// The change set for archiving a contact. The row is retained and frozen.
Map<String, Object?> contactArchiveChanges() => <String, Object?>{
  'status': ContactStatus.archived.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// Whether a contact matches a free-text directory query.
///
/// The query is matched case-insensitively against the fields someone types
/// when they are looking for a number: the name, the role, the organisation
/// and both phone numbers.
bool contactMatchesQuery(DirectoryContact contact, String query) {
  final String needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return true;
  }
  return <String?>[
    contact.name,
    contact.contactRole,
    contact.organisation,
    contact.phonePrimary,
    contact.phoneSecondary,
    contact.extension,
  ].any(
    (String? value) => value != null && value.toLowerCase().contains(needle),
  );
}

/// Orders contacts for display: emergency first, then within a category by
/// display order and finally by name.
int compareContacts(DirectoryContact a, DirectoryContact b) {
  if (a.isEmergency != b.isEmergency) {
    return a.isEmergency ? -1 : 1;
  }
  final int order = a.displayOrder.compareTo(b.displayOrder);
  if (order != 0) {
    return order;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? _trimmed(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

DateTime _parse(Object? value) => value is String
    ? DateTime.parse(value).toUtc()
    : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.parse(value);
  }
  return 0;
}

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return false;
}
