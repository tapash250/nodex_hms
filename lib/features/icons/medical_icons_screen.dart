/// The medical icon gallery (Module 51).
///
/// Every symbol in the repository, with the name it is known by. A screen that
/// needs a symbol looks it up here, and the gallery is where the two stay in
/// step: an icon without a name is an icon nobody can find.
library;

import 'package:flutter/material.dart';
import 'package:nodex_hms/app/icons/medical_icons.dart';

/// Renders the medical icon repository.
class MedicalIconsScreen extends StatelessWidget {
  /// Creates the gallery.
  const MedicalIconsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MapEntry<String, IconData>> entries =
        MedicalIcons.registry.entries.toList(growable: false)..sort(
          (MapEntry<String, IconData> a, MapEntry<String, IconData> b) =>
              a.key.compareTo(b.key),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Medical icons')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            '${MedicalIcons.length} symbols. Each one is a constant, so a build '
            'that draws four of them ships four: the icon tree-shaker can see '
            'which constants the app actually reaches.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              for (final MapEntry<String, IconData> entry in entries)
                SizedBox(
                  width: 96,
                  child: Column(
                    children: <Widget>[
                      Icon(entry.value, size: 28),
                      const SizedBox(height: 4),
                      Text(
                        entry.key,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
