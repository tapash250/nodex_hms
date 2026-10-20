/// Handing the device over (Module 52).
///
/// Two clinicians share a device on a ward. The quick switch asks for the
/// outgoing clinician's PIN, and on a match the incoming one signs in as
/// themselves. The PIN is never the only thing that changes: the session is
/// locked and the next sign-in is a full one, so a PIN on its own grants
/// nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/core/security/pin_store.dart';

/// The PIN store.
final pinStoreProvider = Provider<PinStore>((Ref ref) => const PinStore());

/// Asks for a PIN and reports whether it matched.
///
/// Returns null when the clinician backs out.
Future<bool?> askForPin(BuildContext context, WidgetRef ref) async {
  final TextEditingController controller = TextEditingController();
  String? error;
  bool checking = false;
  try {
    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Enter your PIN',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'The session stays locked until the next clinician signs in.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  errorText: error,
                  counterText: '',
                ),
                onSubmitted: (String value) async {
                  setState(() => checking = true);
                  final bool matched = await ref
                      .read(pinStoreProvider)
                      .verify(value);
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext, matched);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: checking
                        ? null
                        : () => Navigator.pop(sheetContext),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: checking
                        ? null
                        : () async {
                            setState(() => checking = true);
                            final bool matched = await ref
                                .read(pinStoreProvider)
                                .verify(controller.text);
                            if (!sheetContext.mounted) return;
                            Navigator.pop(sheetContext, matched);
                          },
                    child: const Text('Unlock'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}
