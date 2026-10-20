/// Clinical messaging (Module 43).
///
/// A thread list and a conversation. The list shows only the discussions the
/// signed-in clinician is part of, and the screen says so rather than
/// implying that there is nothing else: a clinician who cannot see a thread
/// may believe nobody discussed the case.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/messaging/clinical_message.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The threads the signed-in clinician takes part in.
final clinicalThreadsProvider = FutureProvider.autoDispose
    .family<List<ClinicalThread>, String>((Ref ref, String userId) async {
      return ref
          .watch(listThreadsUseCaseProvider)
          .call(
            policy: ref.watch(sessionProvider).authorization,
            userId: userId,
          );
    });

/// The messages in a thread.
final threadMessagesProvider = FutureProvider.autoDispose
    .family<List<ClinicalMessage>, String>((Ref ref, String threadId) async {
      final ClinicalThread? thread = await ref
          .watch(messagingRepositoryProvider)
          .getThread(threadId);
      if (thread == null) {
        throw const PersistenceError(
          message: 'This discussion is not available on this device.',
          code: 'clinical_thread_not_found_locally',
        );
      }
      return ref
          .watch(listMessagesUseCaseProvider)
          .call(
            policy: ref.watch(sessionProvider).authorization,
            thread: thread,
            userId: ref.watch(sessionProvider).user?.userId ?? '',
          );
    });

/// The list of clinical discussions.
class MessagingScreen extends ConsumerWidget {
  /// Creates the screen.
  const MessagingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? userId = ref.watch(sessionProvider).user?.userId;
    final ThemeData theme = Theme.of(context);

    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Session is not ready.')));
    }

    final AsyncValue<List<ClinicalThread>> threads = ref.watch(
      clinicalThreadsProvider(userId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: threads.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Text(
            error is NodexError
                ? error.message
                : 'Discussions are unavailable on this device.',
          ),
        ),
        data: (List<ClinicalThread> values) => values.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'You are not part of any clinical discussion. A discussion '
                    'you are asked into appears here.',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: values.length,
                itemBuilder: (BuildContext context, int index) {
                  final ClinicalThread thread = values[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.forum_outlined),
                      title: Text(thread.subject),
                      subtitle: Text(
                        '${thread.participants.length} participant(s)'
                        '${thread.patientId != null ? ' · patient linked' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/messages/${thread.id}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
