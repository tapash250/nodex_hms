/// Clinical widget library gallery (Module 45).
///
/// The gallery exists so the components can be reviewed where they are used:
/// every state a badge, a metric tile or a sparkline can be in is rendered
/// side by side, including the states that are easy to forget — no readings,
/// a single reading, and a series that left its reference range.
library;

import 'package:flutter/material.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';
import 'package:nodex_hms/domain/beds/bed.dart';

/// Renders every component in the shared clinical widget library.
class WidgetsLibraryScreen extends StatefulWidget {
  /// Creates the gallery.
  const WidgetsLibraryScreen({super.key});

  @override
  State<WidgetsLibraryScreen> createState() => _WidgetsLibraryScreenState();
}

class _WidgetsLibraryScreenState extends State<WidgetsLibraryScreen> {
  int _eye = 4;
  int _verbal = 5;
  int _motor = 6;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Clinical widgets')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Status badges', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final BedStatus status in BedStatus.values)
                BedStatusBadge(status: status),
              const ClinicalStatusBadge(
                label: 'Isolation',
                tone: ClinicalTone.warning,
                icon: Icons.warning_amber_outlined,
              ),
              const ClinicalStatusBadge(
                label: 'Critical result',
                tone: ClinicalTone.critical,
                icon: Icons.priority_high,
              ),
              const ClinicalStatusBadge(label: 'Routine'),
            ],
          ),
          const SizedBox(height: 24),
          Text('Metric tiles', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ClinicalMetricTile(
                    label: 'Heart rate',
                    value: 88,
                    unit: 'bpm',
                    referenceLow: 60,
                    referenceHigh: 100,
                    previous: 96,
                  ),
                  ClinicalMetricTile(
                    label: 'SpO₂',
                    value: 91,
                    unit: '%',
                    referenceLow: 94,
                    referenceHigh: 100,
                    previous: 93,
                  ),
                  ClinicalMetricTile(
                    label: 'Temperature',
                    value: 36.8,
                    unit: '°C',
                    referenceLow: 36.1,
                    referenceHigh: 37.2,
                  ),
                  ClinicalMetricTile(
                    label: 'GCS',
                    value: 7,
                    referenceLow: 13,
                    referenceHigh: 15,
                    previous: 9,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Sparklines', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _GalleryRow(
                    caption: 'In range',
                    child: VitalSparkline(
                      values: <num>[72, 76, 81, 78, 74, 70],
                      label: 'Heart rate',
                      unit: 'bpm',
                      referenceLow: 60,
                      referenceHigh: 100,
                    ),
                  ),
                  _GalleryRow(
                    caption: 'Left the range',
                    child: VitalSparkline(
                      values: <num>[96, 94, 92, 89, 87],
                      label: 'SpO₂',
                      unit: '%',
                      referenceLow: 94,
                      referenceHigh: 100,
                    ),
                  ),
                  _GalleryRow(
                    caption: 'One reading',
                    child: VitalSparkline(
                      values: <num>[37.4],
                      label: 'Temperature',
                      unit: '°C',
                    ),
                  ),
                  _GalleryRow(
                    caption: 'No readings',
                    child: VitalSparkline(values: <num>[], label: 'Pulse'),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'The screen reader sentence for a series replaces the '
                      'drawing: "Heart rate: 6 readings, latest 70 bpm".',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('GCS calculator', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GcsCalculator(
                eye: _eye,
                verbal: _verbal,
                motor: _motor,
                onChanged: (int eye, int verbal, int motor) => setState(() {
                  _eye = eye;
                  _verbal = verbal;
                  _motor = motor;
                }),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Tones', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ClinicalTone tone in ClinicalTone.values)
                ClinicalStatusBadge(label: tone.name, tone: tone),
            ],
          ),
        ],
      ),
    );
  }
}

class _GalleryRow extends StatelessWidget {
  const _GalleryRow({required this.caption, required this.child});

  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: <Widget>[
        SizedBox(width: 120, child: Text(caption)),
        child,
      ],
    ),
  );
}
