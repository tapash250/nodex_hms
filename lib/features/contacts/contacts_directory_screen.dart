/// Hospital contacts directory (Module 42).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/contacts/contact.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The hospital contacts directory surface.
class ContactsDirectoryScreen extends ConsumerStatefulWidget {
  /// Creates the directory screen.
  const ContactsDirectoryScreen({super.key});

  @override
  ConsumerState<ContactsDirectoryScreen> createState() =>
      _ContactsDirectoryScreenState();
}

class _ContactsDirectoryScreenState
    extends ConsumerState<ContactsDirectoryScreen> {
  final TextEditingController _search = TextEditingController();
  List<DirectoryContact> _contacts = const <DirectoryContact>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) {
      setState(() {
        _error = 'Session is not ready.';
        _loading = false;
      });
      return;
    }
    try {
      final List<DirectoryContact> contacts = await ref
          .read(listContactsUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            query: _search.text,
          );
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openForm({DirectoryContact? existing}) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) return;
    final _ContactFormResult? result = await showDialog<_ContactFormResult>(
      context: context,
      builder: (BuildContext context) => _ContactFormDialog(existing: existing),
    );
    if (result == null) return;
    try {
      if (existing == null) {
        await ref
            .read(registerContactUseCaseProvider)
            .call(
              policy: session.authorization,
              tenantId: tenantId,
              createdBy: userId,
              name: result.name,
              phonePrimary: result.phonePrimary,
              category: result.category,
              contactRole: result.contactRole,
              organisation: result.organisation,
              phoneSecondary: result.phoneSecondary,
              extension: result.extension,
              email: result.email,
              notes: result.notes,
              isEmergency: result.isEmergency,
              available24_7: result.available24_7,
              displayOrder: result.displayOrder,
            );
      } else {
        await ref
            .read(updateContactUseCaseProvider)
            .call(
              policy: session.authorization,
              contact: existing,
              name: result.name,
              phonePrimary: result.phonePrimary,
              category: result.category,
              contactRole: result.contactRole,
              organisation: result.organisation,
              phoneSecondary: result.phoneSecondary,
              extension: result.extension,
              email: result.email,
              notes: result.notes,
              isEmergency: result.isEmergency,
              available24_7: result.available24_7,
              displayOrder: result.displayOrder,
            );
      }
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _archive(DirectoryContact contact) async {
    final session = ref.read(sessionProvider);
    try {
      await ref
          .read(archiveContactUseCaseProvider)
          .call(policy: session.authorization, contact: contact);
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showContact(DirectoryContact contact) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              leading: Icon(
                contact.isEmergency ? Icons.emergency : Icons.contact_phone,
              ),
              title: Text(contact.name),
              subtitle: Text(
                <String>[
                  contact.category.label,
                  if (contact.contactRole case final String role) role,
                  if (contact.organisation case final String org) org,
                ].join(' · '),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.call),
              title: Text(contact.phonePrimary),
              subtitle: contact.phoneSecondary == null
                  ? null
                  : Text(contact.phoneSecondary!),
            ),
            if (contact.extension case final String extension)
              ListTile(
                leading: const Icon(Icons.dialpad),
                title: Text('Ext $extension'),
              ),
            if (contact.email case final String email)
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(email),
              ),
            if (contact.notes case final String notes)
              ListTile(leading: const Icon(Icons.notes), title: Text(notes)),
            if (contact.isEditable)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
            if (contact.isEditable)
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Archive'),
                onTap: () => Navigator.of(context).pop('archive'),
              ),
          ],
        ),
      ),
    );
    if (action == 'edit') {
      await _openForm(existing: contact);
    } else if (action == 'archive') {
      await _archive(contact);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contacts')),
        body: Center(child: Text(_error!)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        tooltip: 'Add contact',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, role, number',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _contacts.isEmpty
                ? const Center(child: Text('No contacts found.'))
                : ListView.builder(
                    itemCount: _contacts.length,
                    itemBuilder: (BuildContext context, int index) {
                      final DirectoryContact contact = _contacts[index];
                      return ListTile(
                        leading: Icon(
                          contact.isEmergency
                              ? Icons.emergency
                              : Icons.contact_phone_outlined,
                          color: contact.isEmergency
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                        title: Text(contact.name),
                        subtitle: Text(
                          <String>[
                            contact.category.label,
                            if (contact.extension case final String extension)
                              'ext $extension',
                            if (contact.organisation case final String org) org,
                          ].join(' · '),
                        ),
                        trailing: Text(contact.phonePrimary),
                        onTap: () => _showContact(contact),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The editable fields of a contact form.
class _ContactFormResult {
  const _ContactFormResult({
    required this.name,
    required this.phonePrimary,
    required this.category,
    required this.isEmergency,
    required this.available24_7,
    required this.displayOrder,
    this.contactRole,
    this.organisation,
    this.phoneSecondary,
    this.extension,
    this.email,
    this.notes,
  });

  final String name;
  final String phonePrimary;
  final ContactCategory category;
  final bool isEmergency;
  final bool available24_7;
  final int displayOrder;
  final String? contactRole;
  final String? organisation;
  final String? phoneSecondary;
  final String? extension;
  final String? email;
  final String? notes;
}

class _ContactFormDialog extends StatefulWidget {
  const _ContactFormDialog({this.existing});

  final DirectoryContact? existing;

  @override
  State<_ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends State<_ContactFormDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name,
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.existing?.phonePrimary,
  );
  late final TextEditingController _secondary = TextEditingController(
    text: widget.existing?.phoneSecondary,
  );
  late final TextEditingController _extension = TextEditingController(
    text: widget.existing?.extension,
  );
  late final TextEditingController _role = TextEditingController(
    text: widget.existing?.contactRole,
  );
  late final TextEditingController _organisation = TextEditingController(
    text: widget.existing?.organisation,
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.existing?.email,
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.existing?.notes,
  );
  late ContactCategory _category =
      widget.existing?.category ?? ContactCategory.support;
  late bool _isEmergency = widget.existing?.isEmergency ?? false;
  late bool _available24_7 = widget.existing?.available24_7 ?? false;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _name,
      _phone,
      _secondary,
      _extension,
      _role,
      _organisation,
      _email,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Add contact' : 'Edit contact'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          DropdownButtonFormField<ContactCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: <DropdownMenuItem<ContactCategory>>[
              for (final ContactCategory category in ContactCategory.values)
                DropdownMenuItem<ContactCategory>(
                  value: category,
                  child: Text(category.label),
                ),
            ],
            onChanged: (ContactCategory? value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Primary phone'),
          ),
          TextField(
            controller: _secondary,
            decoration: const InputDecoration(labelText: 'Secondary phone'),
          ),
          TextField(
            controller: _extension,
            decoration: const InputDecoration(labelText: 'Extension'),
          ),
          TextField(
            controller: _role,
            decoration: const InputDecoration(labelText: 'Role'),
          ),
          TextField(
            controller: _organisation,
            decoration: const InputDecoration(labelText: 'Organisation'),
          ),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Emergency contact'),
            value: _isEmergency,
            onChanged: (bool value) => setState(() => _isEmergency = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Available 24/7'),
            value: _available24_7,
            onChanged: (bool value) => setState(() => _available24_7 = value),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _ContactFormResult(
            name: _name.text.trim(),
            phonePrimary: _phone.text.trim(),
            category: _category,
            isEmergency: _isEmergency,
            available24_7: _available24_7,
            displayOrder: widget.existing?.displayOrder ?? 100,
            contactRole: _nullIfEmpty(_role),
            organisation: _nullIfEmpty(_organisation),
            phoneSecondary: _nullIfEmpty(_secondary),
            extension: _nullIfEmpty(_extension),
            email: _nullIfEmpty(_email),
            notes: _nullIfEmpty(_notes),
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}
