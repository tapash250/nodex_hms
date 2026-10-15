/// Doctor & specialist directory (Module 08).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/roster/practitioner.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Practitioner directory surface.
class PractitionerDirectoryScreen extends ConsumerStatefulWidget {
  /// Creates the directory.
  const PractitionerDirectoryScreen({super.key});

  @override
  ConsumerState<PractitionerDirectoryScreen> createState() =>
      _PractitionerDirectoryScreenState();
}

class _PractitionerDirectoryScreenState
    extends ConsumerState<PractitionerDirectoryScreen> {
  List<PractitionerProfile> _profiles = const <PractitionerProfile>[];
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
      final profiles = await ref
          .read(searchPractitionersUseCaseProvider)
          .call(policy: session.authorization, tenantId: tenantId);
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Doctor directory')),
        body: Center(child: Text(_error!)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor directory')),
      body: _profiles.isEmpty
          ? const Center(child: Text('No practitioners registered yet.'))
          : ListView.builder(
              itemCount: _profiles.length,
              itemBuilder: (BuildContext context, int index) {
                final PractitionerProfile profile = _profiles[index];
                return ListTile(
                  leading: const Icon(Icons.person_outlined),
                  title: Text(profile.specialty),
                  subtitle: Text(
                    profile.subSpecialty ??
                        profile.credentials ??
                        profile.userId,
                  ),
                  trailing: Icon(
                    profile.acceptingReferrals
                        ? Icons.check_circle_outline
                        : Icons.block,
                  ),
                );
              },
            ),
    );
  }
}
