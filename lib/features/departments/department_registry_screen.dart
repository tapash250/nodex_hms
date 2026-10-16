/// Clinical departments registry (Module 12).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/departments/department.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Department registry surface.
class DepartmentRegistryScreen extends ConsumerStatefulWidget {
  /// Creates the registry.
  const DepartmentRegistryScreen({super.key});

  @override
  ConsumerState<DepartmentRegistryScreen> createState() =>
      _DepartmentRegistryScreenState();
}

class _DepartmentRegistryScreenState
    extends ConsumerState<DepartmentRegistryScreen> {
  List<Department> _departments = const <Department>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
      final List<Department> departments = await ref
          .read(listDepartmentsUseCaseProvider)
          .call(policy: session.authorization, tenantId: tenantId);
      if (!mounted) return;
      setState(() {
        _departments = departments;
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

  Future<void> _register() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    if (tenantId == null || facilities.isEmpty) {
      return;
    }
    final String facilityId = facilities.first;
    final ({String code, String name, String? specialty})? entry =
        await showDialog<({String code, String name, String? specialty})>(
          context: context,
          builder: (BuildContext context) => const _DepartmentFormDialog(),
        );
    if (entry == null) {
      return;
    }
    try {
      await ref
          .read(registerDepartmentUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            facilityId: facilityId,
            code: entry.code,
            displayName: entry.name,
            specialty: entry.specialty,
          );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Departments')),
        body: Center(child: Text(_error!)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Departments')),
      floatingActionButton: FloatingActionButton(
        onPressed: _register,
        tooltip: 'Register department',
        child: const Icon(Icons.add),
      ),
      body: _departments.isEmpty
          ? const Center(child: Text('No departments registered yet.'))
          : ListView.builder(
              itemCount: _departments.length,
              itemBuilder: (BuildContext context, int index) {
                final Department department = _departments[index];
                return ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(department.displayName),
                  subtitle: Text(
                    <String>[
                      department.code,
                      if (department.specialty case final String specialty)
                        specialty,
                    ].join(' · '),
                  ),
                  trailing: Text(department.status.wireValue),
                );
              },
            ),
    );
  }
}

class _DepartmentFormDialog extends StatefulWidget {
  const _DepartmentFormDialog();

  @override
  State<_DepartmentFormDialog> createState() => _DepartmentFormDialogState();
}

class _DepartmentFormDialogState extends State<_DepartmentFormDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _specialty = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _specialty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Register department'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _code,
          decoration: const InputDecoration(labelText: 'Code'),
        ),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _specialty,
          decoration: const InputDecoration(labelText: 'Specialty (optional)'),
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final String specialty = _specialty.text.trim();
          Navigator.of(context).pop((
            code: _code.text,
            name: _name.text,
            specialty: specialty.isEmpty ? null : specialty,
          ));
        },
        child: const Text('Register'),
      ),
    ],
  );
}
