/// Global search (Module 54).
///
/// One search box for the whole application, reachable from anywhere with
/// Ctrl+K or "/". It searches the patients the device already holds, so it
/// works on a ward with no signal — which is the point of having it on a
/// hotkey rather than three taps away.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The keys that open the search.
abstract final class GlobalSearchShortcuts {
  /// The shortcut definitions.
  ///
  /// Control-K on a desktop keyboard, Command-K on a laptop, and "/" on a
  /// tablet with no keyboard attached. The three are the same action.
  static Map<ShortcutActivator, VoidCallback> bindings({
    required VoidCallback onOpen,
  }) => <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.keyK, control: true): onOpen,
    const SingleActivator(LogicalKeyboardKey.keyK, meta: true): onOpen,
    const SingleActivator(LogicalKeyboardKey.slash): onOpen,
  };
}

/// The patients the search found.
final globalSearchProvider = FutureProvider.autoDispose
    .family<List<Patient>, String>((Ref ref, String query) async {
      final String? tenantId = ref.watch(sessionProvider).tenantId;
      if (tenantId == null || query.trim().isEmpty) {
        return const <Patient>[];
      }
      return ref
          .watch(patientRepositoryProvider)
          .searchPatients(tenantId: tenantId, query: query, limit: 25);
    });

/// The global search screen.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final TextEditingController _query = TextEditingController();
  String _term = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Patient>> results = ref.watch(
      globalSearchProvider(_term),
    );
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Name, record number or phone',
                border: OutlineInputBorder(),
              ),
              onChanged: (String value) => setState(() => _term = value),
            ),
          ),
          Expanded(
            child: results.when(
              loading: () => const LinearProgressIndicator(),
              error: (Object error, StackTrace _) => Center(
                child: Text(
                  error is NodexError
                      ? error.message
                      : 'The search index is unavailable on this device.',
                ),
              ),
              data: (List<Patient> values) {
                if (_term.trim().isEmpty) {
                  return Center(
                    child: Text(
                      'Type a name, a record number or a phone number.',
                      style: theme.textTheme.bodyLarge,
                    ),
                  );
                }
                if (values.isEmpty) {
                  return Center(
                    child: Text(
                      'No patient matches "$_term" on this device.',
                      style: theme.textTheme.bodyLarge,
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: values.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Patient patient = values[index];
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(patient.displayName),
                      subtitle: Text(
                        '${patient.mrn} · ${patient.gender.wireValue}',
                      ),
                      onTap: () => context.go('/patients/${patient.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
