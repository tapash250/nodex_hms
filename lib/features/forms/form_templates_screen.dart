/// Clinical forms (Module 47).
///
/// The screen lists the forms that are in force and opens the runner for one
/// of them. Nothing here knows what a form is for: the template says which
/// fields to ask, the engine says how to ask them, and the answers are
/// recorded against the patient the clinician is working on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/forms/form_template.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The forms a clinician may fill in.
final formTemplatesProvider = FutureProvider.autoDispose<List<FormTemplate>>((
  Ref ref,
) async {
  return ref
      .watch(listFormTemplatesUseCaseProvider)
      .call(policy: ref.watch(sessionProvider).authorization);
});

/// The list of published clinical forms.
class FormTemplatesScreen extends ConsumerWidget {
  /// Creates the screen.
  const FormTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FormTemplate>> templates = ref.watch(
      formTemplatesProvider,
    );
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Clinical forms')),
      body: templates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Text(
            error is NodexError ? error.message : 'Forms are unavailable.',
          ),
        ),
        data: (List<FormTemplate> values) => values.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No form templates are published for this tenant.',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: values.length,
                itemBuilder: (BuildContext context, int index) {
                  final FormTemplate template = values[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.assignment_outlined),
                      title: Text(template.title),
                      subtitle: Text(
                        template.description ??
                            '${template.schema.fields.length} questions',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/forms/${template.id}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
