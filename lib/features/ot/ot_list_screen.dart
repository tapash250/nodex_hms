/// Operation theatre schedule and case history (Module 19).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/ot/ot.dart';
import 'package:nodex_hms/features/ot/ot_controller.dart';

/// Renders a local timestamp for schedule rows.
String otStamp(DateTime value) {
  final DateTime local = value.toLocal();
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

/// Operation theatre booking board.
class OtListScreen extends StatelessWidget {
  /// Creates the operation theatre list screen.
  const OtListScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Operation theatre'),
        bottom: const TabBar(
          tabs: <Widget>[
            Tab(text: 'Schedule'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: const TabBarView(children: <Widget>[_ScheduleTab(), _HistoryTab()]),
    ),
  );
}

class _ScheduleTab extends ConsumerWidget {
  const _ScheduleTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<OtBooking>> bookings = ref.watch(otBookingsProvider);
    return bookings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace _) => _OtListError(error: error),
      data: (List<OtBooking> list) {
        final List<OtBooking> upcoming = list
            .where(
              (OtBooking booking) =>
                  booking.status == OtBookingStatus.scheduled ||
                  booking.status == OtBookingStatus.inProgress,
            )
            .toList(growable: false);
        if (upcoming.isEmpty) {
          return const _Empty(message: 'No upcoming theatre cases.');
        }
        return ListView(
          children: <Widget>[
            for (final OtBooking booking in upcoming)
              _BookingTile(booking: booking),
          ],
        );
      },
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<OtBooking>> bookings = ref.watch(otBookingsProvider);
    return bookings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace _) => _OtListError(error: error),
      data: (List<OtBooking> list) {
        final List<OtBooking> history = list
            .where((OtBooking booking) => booking.isTerminal)
            .toList(growable: false);
        if (history.isEmpty) {
          return const _Empty(message: 'No case history yet.');
        }
        return ListView(
          children: <Widget>[
            for (final OtBooking booking in history)
              _BookingTile(booking: booking),
          ],
        );
      },
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking});

  final OtBooking booking;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      leading: Icon(switch (booking.status) {
        OtBookingStatus.scheduled => Icons.event_outlined,
        OtBookingStatus.inProgress => Icons.play_circle_outline,
        OtBookingStatus.completed => Icons.check_circle_outline,
        OtBookingStatus.cancelled => Icons.cancel_outlined,
      }),
      title: Text(booking.procedureName),
      subtitle: Text(
        '${booking.theatreRoom} · ${otStamp(booking.scheduledStart)}',
      ),
      trailing: Text(
        booking.priority.label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: switch (booking.priority) {
            OtPriority.routine => null,
            OtPriority.urgent => theme.colorScheme.tertiary,
            OtPriority.emergency => theme.colorScheme.error,
          },
        ),
      ),
      onTap: () => context.push('/ot/bookings/${booking.id}'),
    );
  }
}

class _OtListError extends StatelessWidget {
  const _OtListError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        error is NodexError
            ? (error as NodexError).message
            : 'Could not load theatre bookings.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
