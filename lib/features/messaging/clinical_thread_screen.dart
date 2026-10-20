/// One clinical discussion (Module 43).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/messaging/clinical_message.dart';
import 'package:nodex_hms/features/messaging/messaging_screen.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// One discussion, with the composer at the bottom.
class ClinicalThreadScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ClinicalThreadScreen({required this.threadId, super.key});

  /// The thread being read.
  final String threadId;

  @override
  ConsumerState<ClinicalThreadScreen> createState() =>
      _ClinicalThreadScreenState();
}

class _ClinicalThreadScreenState extends ConsumerState<ClinicalThreadScreen> {
  final TextEditingController _body = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String body = _body.text.trim();
    if (body.isEmpty) return;
    final ClinicalThread? thread = await ref
        .watch(messagingRepositoryProvider)
        .getThread(widget.threadId);
    final String? userId = ref.read(sessionProvider).user?.userId;
    final String? tenantId = ref.read(sessionProvider).tenantId;
    if (thread == null || userId == null || tenantId == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(sendMessageUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            thread: thread,
            tenantId: tenantId,
            senderId: userId,
            body: body,
          );
      _body.clear();
      ref.invalidate(threadMessagesProvider(widget.threadId));
    } on NodexError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ClinicalMessage>> messages = ref.watch(
      threadMessagesProvider(widget.threadId),
    );
    final String? userId = ref.watch(sessionProvider).user?.userId;
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Discussion')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace _) => Center(
                child: Text(
                  error is NodexError
                      ? error.message
                      : 'The discussion is unavailable on this device.',
                ),
              ),
              data: (List<ClinicalMessage> values) => values.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet.',
                        style: theme.textTheme.bodyLarge,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: values.length,
                      itemBuilder: (BuildContext context, int index) {
                        final ClinicalMessage message = values[index];
                        final bool mine = message.senderId == userId;
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(maxWidth: 320),
                            decoration: BoxDecoration(
                              color: mine
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (message.isUrgent)
                                  Text(
                                    'Urgent',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                Text(message.body),
                                if (message.createdAt != null)
                                  Text(
                                    message.createdAt!
                                        .toLocal()
                                        .toIso8601String()
                                        .substring(11, 16),
                                    style: theme.textTheme.labelSmall,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _body,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Write a message…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: const Text('Send'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
