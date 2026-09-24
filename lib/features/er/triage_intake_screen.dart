/// Triage intake form (Module 05).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/er/er.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Collects a new ER triage assessment for [patientId].
class TriageIntakeScreen extends ConsumerStatefulWidget {
  const TriageIntakeScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<TriageIntakeScreen> createState() => _TriageIntakeScreenState();
}

class _TriageIntakeScreenState extends ConsumerState<TriageIntakeScreen> {
  final TextEditingController _complaintController = TextEditingController();
  TriageAcuity _acuity = TriageAcuity.esi3;
  TriageDisposition _disposition = TriageDisposition.admit;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _complaintController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = ref.read(sessionProvider);
    final tenantId = session.tenantId;
    final assessedBy = session.user?.userId;
    if (tenantId == null || assessedBy == null) {
      setState(() => _error = 'Session is not ready.');
      return;
    }
    if (_complaintController.text.trim().isEmpty) {
      setState(() => _error = 'Chief complaint is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(recordTriageUseCaseProvider)(
        policy: session.authorization,
        tenantId: tenantId,
        patientId: widget.patientId,
        assessedBy: assessedBy,
        acuity: _acuity,
        chiefComplaint: _complaintController.text.trim(),
        disposition: _disposition,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on NodexError catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Triage could not be recorded.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record triage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_error != null) ...<Widget>[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _complaintController,
            decoration: const InputDecoration(
              labelText: 'Chief complaint',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TriageAcuity>(
            initialValue: _acuity,
            decoration: const InputDecoration(
              labelText: 'Acuity',
              border: OutlineInputBorder(),
            ),
            items: TriageAcuity.values
                .map(
                  (TriageAcuity value) => DropdownMenuItem<TriageAcuity>(
                    value: value,
                    child: Text(value.label),
                  ),
                )
                .toList(),
            onChanged: (TriageAcuity? value) {
              if (value != null) {
                setState(() => _acuity = value);
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TriageDisposition>(
            initialValue: _disposition,
            decoration: const InputDecoration(
              labelText: 'Disposition',
              border: OutlineInputBorder(),
            ),
            items: TriageDisposition.values
                .map(
                  (TriageDisposition value) =>
                      DropdownMenuItem<TriageDisposition>(
                        value: value,
                        child: Text(value.label),
                      ),
                )
                .toList(),
            onChanged: (TriageDisposition? value) {
              if (value != null) {
                setState(() => _disposition = value);
              }
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Record triage'),
          ),
        ],
      ),
    );
  }
}
