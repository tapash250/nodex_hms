/// Hospital contacts directory use cases (Module 42).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/contacts/contact.dart';
import 'package:nodex_hms/domain/contacts/contact_repository.dart';

/// Registers a contact into the directory.
final class RegisterContactUseCase {
  /// Creates the use case.
  RegisterContactUseCase({required this._repository});

  final ContactRepository _repository;

  /// Records the contact locally, gated on directory administration.
  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.contactsAdminister);
    final Map<String, Object?> row = DirectoryContact.registerRow(
      tenantId: tenantId,
      createdBy: createdBy,
      name: name,
      phonePrimary: phonePrimary,
      category: category,
      facilityId: facilityId,
      departmentId: departmentId,
      contactRole: contactRole,
      organisation: organisation,
      phoneSecondary: phoneSecondary,
      extension: extension,
      email: email,
      address: address,
      notes: notes,
      isEmergency: isEmergency,
      available24_7: available24_7,
      displayOrder: displayOrder,
      contactId: contactId,
    );
    return _repository.registerContact(row);
  }
}

/// Updates a contact's directory facts. Only an active contact may be edited.
final class UpdateContactUseCase {
  /// Creates the use case.
  UpdateContactUseCase({required this._repository});

  final ContactRepository _repository;

  /// Applies the edits, gated on administration and only on mutable rows.
  Future<void> call({
    required AuthorizationPolicy policy,
    required DirectoryContact contact,
    String? facilityId,
    String? departmentId,
    String? name,
    ContactCategory? category,
    String? contactRole,
    String? organisation,
    String? phonePrimary,
    String? phoneSecondary,
    String? extension,
    String? email,
    String? address,
    String? notes,
    bool? isEmergency,
    bool? available24_7,
    int? displayOrder,
  }) async {
    policy.require(NodexPermissions.contactsAdminister);
    if (!contact.isEditable) {
      throw const AuthorizationError(
        message:
            'An archived contact is retained as a historical reference and '
            'cannot be edited.',
        code: 'contact_archived_immutable',
      );
    }
    await _repository.updateContact(
      contact.id,
      contactChanges(
        facilityId: facilityId ?? contact.facilityId,
        departmentId: departmentId ?? contact.departmentId,
        name: name ?? contact.name,
        category: category ?? contact.category,
        contactRole: contactRole ?? contact.contactRole,
        organisation: organisation ?? contact.organisation,
        phonePrimary: phonePrimary ?? contact.phonePrimary,
        phoneSecondary: phoneSecondary ?? contact.phoneSecondary,
        extension: extension ?? contact.extension,
        email: email ?? contact.email,
        address: address ?? contact.address,
        notes: notes ?? contact.notes,
        isEmergency: isEmergency ?? contact.isEmergency,
        available24_7: available24_7 ?? contact.available24_7,
        displayOrder: displayOrder ?? contact.displayOrder,
      ),
    );
  }
}

/// Archives a contact. The row is retained because historical records name the
/// number they reached.
final class ArchiveContactUseCase {
  /// Creates the use case.
  ArchiveContactUseCase({required this._repository});

  final ContactRepository _repository;

  /// Transitions the contact to archived, gated on administration.
  Future<void> call({
    required AuthorizationPolicy policy,
    required DirectoryContact contact,
  }) async {
    policy.require(NodexPermissions.contactsAdminister);
    if (contact.status == ContactStatus.archived) {
      throw const AuthorizationError(
        message: 'This contact is already archived.',
        code: 'contact_already_archived',
      );
    }
    await _repository.updateContact(contact.id, contactArchiveChanges());
  }
}

/// Reads the contacts directory.
final class ListContactsUseCase {
  /// Creates the use case.
  ListContactsUseCase({required this._repository});

  final ContactRepository _repository;

  /// Lists the tenant's contacts, optionally within a category or facility,
  /// filtered by a free-text [query] and sorted for display.
  Future<List<DirectoryContact>> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    ContactCategory? category,
    String? facilityId,
    String query = '',
    bool includeArchived = false,
    int limit = 300,
  }) async {
    policy.require(NodexPermissions.contactsRead);
    final List<DirectoryContact> contacts = await _repository.listContacts(
      tenantId,
      category: category,
      facilityId: facilityId,
      includeArchived: includeArchived,
      limit: limit,
    );
    final List<DirectoryContact> matches =
        contacts
            .where(
              (DirectoryContact contact) => contactMatchesQuery(contact, query),
            )
            .toList(growable: false)
          ..sort(compareContacts);
    return matches;
  }
}
