/// Working boards, service requests and the private scratchpad (Module 44).
///
/// The board is a board: cards in lanes, moved by tapping, so the state of a
/// ward's work is visible without asking anybody. The scratchpad is the
/// clinician's own page of notes, and it never leaves the device — the screen
/// says so where the notes are, because a note that looks like a ward record
/// is a note somebody will quote in a handover.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/productivity/work_item.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The board key this screen shows.
const String nodexDefaultBoardKey = 'ward.handover';

/// The cards on the board.
final workBoardProvider = FutureProvider.autoDispose
    .family<List<WorkItem>, String>((Ref ref, String boardKey) async {
      return ref
          .watch(readBoardUseCaseProvider)
          .call(
            policy: ref.watch(sessionProvider).authorization,
            boardKey: boardKey,
          );
    });

/// The service requests.
final itTicketsProvider = FutureProvider.autoDispose<List<ItTicket>>((
  Ref ref,
) async {
  return ref
      .watch(readTicketsUseCaseProvider)
      .call(policy: ref.watch(sessionProvider).authorization);
});

/// The clinician's own notes.
final scratchpadProvider = FutureProvider.autoDispose<String?>((Ref ref) async {
  return ref.watch(readScratchpadUseCaseProvider).call();
});

/// The productivity workspace.
class ProductivityScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ProductivityScreen({super.key});

  @override
  ConsumerState<ProductivityScreen> createState() => _ProductivityScreenState();
}

class _ProductivityScreenState extends ConsumerState<ProductivityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Work'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: 'Board'),
            Tab(text: 'Tickets'),
            Tab(text: 'Scratchpad'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const <Widget>[_BoardTab(), _TicketsTab(), _ScratchpadTab()],
      ),
    );
  }
}

class _BoardTab extends ConsumerWidget {
  const _BoardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WorkItem>> cards = ref.watch(
      workBoardProvider(nodexDefaultBoardKey),
    );
    final SessionState session = ref.watch(sessionProvider);
    final bool canManage = session.authorization.can(
      NodexPermissions.workItemsManage,
    );
    final ThemeData theme = Theme.of(context);

    return cards.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace _) => Center(
        child: Text(
          error is NodexError ? error.message : 'The board is unavailable.',
        ),
      ),
      data: (List<WorkItem> values) {
        if (values.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Nothing is on the board. A card appears here when somebody '
                'raises a piece of work.',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            for (final WorkLane lane in WorkLane.values)
              _Lane(
                lane: lane,
                cards: values
                    .where((WorkItem card) => card.lane == lane)
                    .toList(growable: false),
                canManage: canManage,
              ),
          ],
        );
      },
    );
  }
}

class _Lane extends ConsumerWidget {
  const _Lane({
    required this.lane,
    required this.cards,
    required this.canManage,
  });

  final WorkLane lane;
  final List<WorkItem> cards;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            children: <Widget>[
              Text(lane.label, style: theme.textTheme.titleSmall),
              const SizedBox(width: 8),
              Text('${cards.length}', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        for (final WorkItem card in cards)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(card.title),
              subtitle: Text(
                <String>[
                  card.priority.wireValue,
                  if (card.dueAt != null)
                    'due ${card.dueAt!.toLocal().toIso8601String()}',
                ].join(' · '),
              ),
              trailing: canManage && card.lane != WorkLane.done
                  ? PopupMenuButton<WorkLane>(
                      tooltip: 'Move the card',
                      onSelected: (WorkLane to) =>
                          _move(context, ref, card, to),
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<WorkLane>>[
                            for (final WorkLane target in WorkLane.values)
                              if (target != card.lane)
                                PopupMenuItem<WorkLane>(
                                  value: target,
                                  child: Text(target.label),
                                ),
                          ],
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    WorkItem card,
    WorkLane to,
  ) async {
    try {
      await ref
          .read(moveWorkItemUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            item: card,
            lane: to,
          );
      ref.invalidate(workBoardProvider(nodexDefaultBoardKey));
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _TicketsTab extends ConsumerWidget {
  const _TicketsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ItTicket>> tickets = ref.watch(itTicketsProvider);
    final SessionState session = ref.watch(sessionProvider);
    final bool canManage = session.authorization.can(
      NodexPermissions.ticketsManage,
    );
    final ThemeData theme = Theme.of(context);

    return tickets.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace _) => Center(
        child: Text(
          error is NodexError ? error.message : 'Tickets are unavailable.',
        ),
      ),
      data: (List<ItTicket> values) => values.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No service requests have been raised.',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: values.length,
              itemBuilder: (BuildContext context, int index) {
                final ItTicket ticket = values[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      ticket.isClosed
                          ? Icons.check_circle_outline
                          : Icons.build_outlined,
                    ),
                    title: Text('${ticket.ticketCode} · ${ticket.title}'),
                    subtitle: Text(
                      <String>[
                        ticket.category,
                        ticket.priority,
                        ticket.status,
                        if (ticket.resolutionNote != null)
                          ticket.resolutionNote!,
                      ].join(' · '),
                    ),
                    trailing: canManage && !ticket.isClosed
                        ? TextButton(
                            onPressed: () => _resolve(context, ref, ticket),
                            child: const Text('Resolve'),
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    ItTicket ticket,
  ) async {
    final String? note = await _ask(context, 'What was done?', 'Resolve');
    if (note == null || !context.mounted) return;
    try {
      await ref
          .read(resolveTicketUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            ticket: ticket,
            note: note,
          );
      ref.invalidate(itTicketsProvider);
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _ScratchpadTab extends ConsumerStatefulWidget {
  const _ScratchpadTab();

  @override
  ConsumerState<_ScratchpadTab> createState() => _ScratchpadTabState();
}

class _ScratchpadTabState extends ConsumerState<_ScratchpadTab> {
  final TextEditingController _note = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<String?> note = ref.watch(scratchpadProvider);
    final ThemeData theme = Theme.of(context);
    note.whenData((String? value) {
      if (!_loaded) {
        _loaded = true;
        _note.text = value ?? '';
      }
    });
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Your notes stay on this device. They are not hospital records and '
            'they are never uploaded.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _note,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Notes to self…',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(writeScratchpadUseCaseProvider)
                  .call(note: _note.text);
              ref.invalidate(scratchpadProvider);
            },
            child: const Text('Save notes'),
          ),
        ],
      ),
    );
  }
}

Future<String?> _ask(BuildContext context, String label, String confirm) async {
  final TextEditingController controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              final String value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, value);
            },
            child: Text(confirm),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}
