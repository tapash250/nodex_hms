/// Radiology order detail and workflow actions (Module 18).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/radiology/radiology.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/radiology/radiology_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Detail screen for one imaging order.
class ImagingOrderScreen extends ConsumerWidget {
  /// Creates the screen.
  const ImagingOrderScreen({required this.orderId, super.key});

  /// Local order id.
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ImagingOrderDetail> detail = ref.watch(
      imagingOrderDetailProvider(orderId),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Imaging order')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _RadiologyError(
          error: error,
          onRetry: () => ref.invalidate(imagingOrderDetailProvider(orderId)),
        ),
        data: (ImagingOrderDetail value) => _ImagingOrderBody(value: value),
      ),
    );
  }
}

class _ImagingOrderBody extends ConsumerWidget {
  const _ImagingOrderBody({required this.value});

  final ImagingOrderDetail value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final ImagingOrder order = value.order;
    final bool canOrder = session.authorization.can(
      NodexPermissions.imagingOrderWrite,
    );
    final bool canRecord = session.authorization.can(
      NodexPermissions.imagingStudyRecord,
    );
    final bool canEnter = session.authorization.can(
      NodexPermissions.imagingReportEnter,
    );
    final bool canVerify = session.authorization.can(
      NodexPermissions.imagingReportVerify,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(order.orderCode, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _Fact(label: 'Modality', value: order.modality.label),
                _Fact(label: 'Body region', value: order.bodyRegion),
                _Fact(label: 'Priority', value: order.priority.label),
                _Fact(label: 'Status', value: order.status.label),
                if (order.clinicalIndication != null)
                  _Fact(label: 'Indication', value: order.clinicalIndication!),
                if (order.cancelledReason != null)
                  _Fact(label: 'Cancelled', value: order.cancelledReason!),
              ],
            ),
          ),
        ),
        if (canOrder && !order.isTerminal)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel order'),
              onPressed: () => _cancel(context, ref),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(child: Text('Study', style: theme.textTheme.titleMedium)),
            if (canRecord && value.study == null && !order.isTerminal)
              TextButton.icon(
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Record'),
                onPressed: () => _showStudySheet(context, ref),
              ),
          ],
        ),
        if (value.study == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No study recorded yet.'),
            ),
          )
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(value.study!.studyUid),
              subtitle: Text(
                '${value.study!.modality.label} · '
                '${value.study!.bodyRegion}',
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(child: Text('Report', style: theme.textTheme.titleMedium)),
            if (canEnter &&
                value.report == null &&
                value.study != null &&
                !order.isTerminal)
              TextButton.icon(
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Draft'),
                onPressed: () => _showReportSheet(context, ref),
              ),
          ],
        ),
        if (value.report == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No report filed yet.'),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        value.report!.isVerified
                            ? Icons.verified_outlined
                            : Icons.pending_outlined,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          value.report!.status.label,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (canVerify && value.report!.isDraft)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Revise report',
                          onPressed: () => _showReportSheet(
                            context,
                            ref,
                            report: value.report!,
                          ),
                        ),
                      if (canVerify && value.report!.isDraft)
                        IconButton(
                          icon: const Icon(Icons.check_circle),
                          tooltip: 'Verify report',
                          onPressed: () => _verify(context, ref),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Findings', style: theme.textTheme.labelMedium),
                  Text(value.report!.findings),
                  const SizedBox(height: 8),
                  Text('Impression', style: theme.textTheme.labelMedium),
                  Text(value.report!.impression),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _CancelSheet(),
    );
    if (reason == null) return;
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(cancelImagingOrderUseCaseProvider)
          .call(
            policy: session.authorization,
            original: value.order,
            reason: reason,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _showStudySheet(BuildContext context, WidgetRef ref) async {
    final _StudyDraft? draft = await showModalBottomSheet<_StudyDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _StudySheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(recordImagingStudyUseCaseProvider)
          .call(
            policy: session.authorization,
            order: value.order,
            studyUid: draft.studyUid,
            performedBy: userId,
            acquisitionNotes: draft.notes,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _showReportSheet(
    BuildContext context,
    WidgetRef ref, {
    ImagingReport? report,
  }) async {
    final _ReportDraft? draft = await showModalBottomSheet<_ReportDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _ReportSheet(initial: report),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    try {
      if (report == null) {
        final String? userId = session.user?.userId;
        if (userId == null) return;
        await ref
            .read(enterImagingReportUseCaseProvider)
            .call(
              policy: session.authorization,
              order: value.order,
              findings: draft.findings,
              impression: draft.impression,
              enteredBy: userId,
            );
      } else {
        await ref
            .read(reviseImagingReportUseCaseProvider)
            .call(
              policy: session.authorization,
              report: report,
              findings: draft.findings,
              impression: draft.impression,
            );
      }
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null || value.report == null) return;
    try {
      await ref
          .read(verifyImagingReportUseCaseProvider)
          .call(
            policy: session.authorization,
            report: value.report!,
            verifierId: userId,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  void _invalidate(WidgetRef ref) {
    final String orderId = value.order.id;
    ref.invalidate(imagingOrderDetailProvider(orderId));
    ref.invalidate(imagingOrdersForPatientProvider(value.order.patientId));
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: Text(label)),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}

class _StudyDraft {
  const _StudyDraft({required this.studyUid, this.notes});
  final String studyUid;
  final String? notes;
}

class _StudySheet extends StatefulWidget {
  const _StudySheet();
  @override
  State<_StudySheet> createState() => _StudySheetState();
}

class _StudySheetState extends State<_StudySheet> {
  final TextEditingController _uid = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  @override
  void dispose() {
    _uid.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Record study acquisition',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _uid,
            decoration: const InputDecoration(
              labelText: 'Study identifier (PACS/DICOM UID) *',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Acquisition notes (optional)',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_uid.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                _StudyDraft(
                  studyUid: _uid.text.trim(),
                  notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                ),
              );
            },
            child: const Text('Record study'),
          ),
        ],
      ),
    );
  }
}

class _ReportDraft {
  const _ReportDraft({required this.findings, required this.impression});
  final String findings;
  final String impression;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({this.initial});
  final ImagingReport? initial;
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  late final TextEditingController _findings;
  late final TextEditingController _impression;

  @override
  void initState() {
    super.initState();
    _findings = TextEditingController(text: widget.initial?.findings ?? '');
    _impression = TextEditingController(text: widget.initial?.impression ?? '');
  }

  @override
  void dispose() {
    _findings.dispose();
    _impression.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bool revising = widget.initial != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            revising ? 'Revise imaging report' : 'Draft imaging report',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _findings,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Findings *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _impression,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Impression *'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_findings.text.trim().isEmpty ||
                  _impression.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                _ReportDraft(
                  findings: _findings.text.trim(),
                  impression: _impression.text.trim(),
                ),
              );
            },
            child: Text(revising ? 'Save revision' : 'Save draft'),
          ),
        ],
      ),
    );
  }
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet();
  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final TextEditingController _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Cancel imaging order',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Cancellation reason *',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_reason.text.trim().isEmpty) return;
              Navigator.pop(context, _reason.text.trim());
            },
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
  }
}

class _RadiologyError extends StatelessWidget {
  const _RadiologyError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          error is NodexError
              ? (error as NodexError).message
              : 'Imaging order unavailable',
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
