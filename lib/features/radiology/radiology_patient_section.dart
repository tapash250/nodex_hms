/// Imaging order section embedded in the patient detail screen (Module 18).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/radiology/radiology.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/radiology/radiology_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Shows imaging orders and the order creation entry point for a patient.
class RadiologyPatientSection extends ConsumerWidget {
  /// Creates the section.
  const RadiologyPatientSection({required this.patientId, super.key});

  /// Patient identifier.
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ImagingOrder>> orders = ref.watch(
      imagingOrdersForPatientProvider(patientId),
    );
    final SessionState session = ref.watch(sessionProvider);
    final bool canOrder = session.authorization.can(
      NodexPermissions.imagingOrderWrite,
    );
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Radiology', style: theme.textTheme.titleMedium),
            ),
            if (canOrder)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Order'),
                onPressed: () => _showOrderSheet(context, ref),
              ),
          ],
        ),
        orders.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (Object error, StackTrace _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error is NodexError
                    ? error.message
                    : 'Imaging history unavailable.',
              ),
            ),
          ),
          data: (List<ImagingOrder> values) => values.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No imaging orders recorded.'),
                  ),
                )
              : Column(
                  children: values
                      .map(
                        (ImagingOrder order) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              order.priority.isStat
                                  ? Icons.priority_high
                                  : Icons.image_outlined,
                            ),
                            title: Text(order.orderCode),
                            subtitle: Text(
                              '${order.modality.label} · '
                              '${order.bodyRegion} · '
                              '${order.priority.label} · '
                              '${order.status.label}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go(
                              '/patients/$patientId/imaging/${order.id}',
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }

  Future<void> _showOrderSheet(BuildContext context, WidgetRef ref) async {
    final _OrderDraft? draft = await showModalBottomSheet<_OrderDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _OrderSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;
    try {
      final ImagingOrder order = await ref
          .read(orderImagingUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: patientId,
            orderedBy: userId,
            orderCode: draft.orderCode,
            modality: draft.modality,
            bodyRegion: draft.bodyRegion,
            priority: draft.priority,
            clinicalIndication: draft.indication,
          );
      ref.invalidate(imagingOrdersForPatientProvider(patientId));
      if (context.mounted) {
        context.go('/patients/$patientId/imaging/${order.id}');
      }
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _OrderDraft {
  const _OrderDraft({
    required this.orderCode,
    required this.modality,
    required this.bodyRegion,
    required this.priority,
    this.indication,
  });
  final String orderCode;
  final ImagingModality modality;
  final String bodyRegion;
  final ImagingPriority priority;
  final String? indication;
}

class _OrderSheet extends StatefulWidget {
  const _OrderSheet();
  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  final TextEditingController _orderCode = TextEditingController();
  final TextEditingController _bodyRegion = TextEditingController();
  final TextEditingController _indication = TextEditingController();
  ImagingModality _modality = ImagingModality.xray;
  ImagingPriority _priority = ImagingPriority.routine;

  @override
  void dispose() {
    _orderCode.dispose();
    _bodyRegion.dispose();
    _indication.dispose();
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
            'Create imaging order',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _orderCode,
            decoration: const InputDecoration(labelText: 'Order code *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<ImagingModality>(
                  initialValue: _modality,
                  decoration: const InputDecoration(labelText: 'Modality *'),
                  items: ImagingModality.values
                      .map(
                        (ImagingModality m) =>
                            DropdownMenuItem<ImagingModality>(
                              value: m,
                              child: Text(m.label),
                            ),
                      )
                      .toList(growable: false),
                  onChanged: (ImagingModality? value) {
                    if (value != null) setState(() => _modality = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<ImagingPriority>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: ImagingPriority.values
                      .map(
                        (ImagingPriority p) =>
                            DropdownMenuItem<ImagingPriority>(
                              value: p,
                              child: Text(p.label),
                            ),
                      )
                      .toList(growable: false),
                  onChanged: (ImagingPriority? value) {
                    if (value != null) setState(() => _priority = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyRegion,
            decoration: const InputDecoration(labelText: 'Body region *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _indication,
            decoration: const InputDecoration(
              labelText: 'Clinical indication (optional)',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_orderCode.text.trim().isEmpty ||
                  _bodyRegion.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                _OrderDraft(
                  orderCode: _orderCode.text.trim(),
                  modality: _modality,
                  bodyRegion: _bodyRegion.text.trim(),
                  priority: _priority,
                  indication: _indication.text.trim().isEmpty
                      ? null
                      : _indication.text.trim(),
                ),
              );
            },
            child: const Text('Create order'),
          ),
        ],
      ),
    );
  }
}
