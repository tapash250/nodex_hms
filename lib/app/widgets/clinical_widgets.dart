/// Reusable clinical widget library (Module 45).
///
/// A widget that renders a clinical fact carries two obligations: it must say
/// the same thing every time it appears, and it must say it in a way a clinician
/// can act on. These components therefore keep their meaning in one place —
/// a bed status maps to a tone here and nowhere else — and they refuse to
/// guess: a sparkline with one point draws a point, not an invented trend.
library;

import 'package:flutter/material.dart';
import 'package:nodex_hms/domain/beds/bed.dart';

/// How serious a widget's subject is.
///
/// The tone is semantic rather than chromatic: callers pick `critical` and the
/// theme decides what critical looks like. That is what lets a ward board and a
/// laboratory queue agree on what red means.
enum ClinicalTone {
  /// No judgement; ordinary information.
  neutral,

  /// Informative, neither good nor bad.
  info,

  /// Nominal: nothing to do.
  success,

  /// Needs attention before the next round.
  warning,

  /// Needs attention now.
  critical;

  /// The container colour for this tone under [scheme].
  Color background(ColorScheme scheme) => switch (this) {
    ClinicalTone.neutral => scheme.surfaceContainerHighest,
    ClinicalTone.info => scheme.primaryContainer,
    ClinicalTone.success => scheme.secondaryContainer,
    ClinicalTone.warning => scheme.tertiaryContainer,
    ClinicalTone.critical => scheme.errorContainer,
  };

  /// The foreground colour for this tone under [scheme].
  Color foreground(ColorScheme scheme) => switch (this) {
    ClinicalTone.neutral => scheme.onSurfaceVariant,
    ClinicalTone.info => scheme.onPrimaryContainer,
    ClinicalTone.success => scheme.onSecondaryContainer,
    ClinicalTone.warning => scheme.onTertiaryContainer,
    ClinicalTone.critical => scheme.onErrorContainer,
  };
}

/// A pill that states a status in words and tone.
///
/// The label is always rendered: colour alone is not a clinical signal, and a
/// ward board read under theatre lighting is not a colour-sorting exercise.
class ClinicalStatusBadge extends StatelessWidget {
  /// Creates a badge.
  const ClinicalStatusBadge({
    required this.label,
    this.tone = ClinicalTone.neutral,
    this.icon,
    super.key,
  });

  /// The words shown.
  final String label;

  /// How serious the status is.
  final ClinicalTone tone;

  /// Optional leading icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.background(scheme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: tone.foreground(scheme)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: tone.foreground(scheme),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// A badge for a bed's occupancy state.
///
/// The mapping lives here so every ward surface — census, floor map, transfer
/// picker — reads the same word for the same row.
class BedStatusBadge extends StatelessWidget {
  /// Creates a bed badge.
  const BedStatusBadge({required this.status, this.compact = false, super.key});

  /// The bed state.
  final BedStatus status;

  /// Whether to omit the icon, for dense tables.
  final bool compact;

  /// The tone a bed state carries.
  ///
  /// The bed registry only knows two states, because occupancy is derived from
  /// the active assignment rather than stored: a bed is available or it is out
  /// of service. A caller that knows more — a board showing a bed being cleaned
  /// or blocked for infection control — passes its own tone to
  /// [ClinicalStatusBadge] instead of pretending the registry said so.
  static ClinicalTone toneFor(BedStatus status) => switch (status) {
    BedStatus.available => ClinicalTone.success,
    BedStatus.maintenance => ClinicalTone.critical,
  };

  /// The words a bed state carries.
  static String labelFor(BedStatus status) => switch (status) {
    BedStatus.available => 'Available',
    BedStatus.maintenance => 'Out of service',
  };

  @override
  Widget build(BuildContext context) => ClinicalStatusBadge(
    label: labelFor(status),
    tone: toneFor(status),
    icon: compact ? null : _iconFor(status),
  );

  static IconData _iconFor(BedStatus status) => switch (status) {
    BedStatus.available => Icons.check_circle_outline,
    BedStatus.maintenance => Icons.build_outlined,
  };
}

/// A number with its unit and, when it matters, where it sits against a range.
class ClinicalMetricTile extends StatelessWidget {
  /// Creates a metric tile.
  const ClinicalMetricTile({
    required this.label,
    required this.value,
    this.unit,
    this.referenceLow,
    this.referenceHigh,
    this.previous,
    super.key,
  });

  /// What is being measured.
  final String label;

  /// The measured value.
  final num value;

  /// Unit of measure.
  final String? unit;

  /// Bottom of the reference range, when one exists.
  final num? referenceLow;

  /// Top of the reference range, when one exists.
  final num? referenceHigh;

  /// The previous reading, used for the trend arrow.
  final num? previous;

  /// Whether the value sits outside its reference range.
  bool get isOutOfRange {
    final num? low = referenceLow;
    final num? high = referenceHigh;
    if (low != null && value < low) return true;
    if (high != null && value > high) return true;
    return false;
  }

  /// Whether the value moved away from the range since [previous].
  bool get isWorsening {
    final num? prior = previous;
    if (prior == null || !isOutOfRange) return false;
    final num? high = referenceHigh;
    if (high != null && value > high) return value > prior;
    final num? low = referenceLow;
    if (low != null && value < low) return value < prior;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? colour = isOutOfRange ? theme.colorScheme.error : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Text(
            '${_format(value)}${unit == null ? '' : ' $unit'}',
            style: theme.textTheme.titleMedium?.copyWith(color: colour),
          ),
          if (previous != null) ...<Widget>[
            const SizedBox(width: 6),
            Icon(
              value == previous
                  ? Icons.trending_flat
                  : value > previous!
                  ? Icons.trending_up
                  : Icons.trending_down,
              size: 16,
              color: isWorsening ? theme.colorScheme.error : null,
            ),
          ],
          if (isOutOfRange) ...<Widget>[
            const SizedBox(width: 6),
            Text(
              referenceHigh != null && value > referenceHigh!
                  ? 'above range'
                  : 'below range',
              style: theme.textTheme.bodySmall?.copyWith(color: colour),
            ),
          ],
        ],
      ),
    );
  }

  static String _format(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}

/// A sparkline of a clinical series.
///
/// The widget draws what it was given. One point is a dot, two points are a
/// line, and no point is an explicit "no data" state — the alternative is a
/// flat line that reads as a stable patient.
class VitalSparkline extends StatelessWidget {
  /// Creates a sparkline.
  const VitalSparkline({
    required this.values,
    this.label,
    this.unit,
    this.referenceLow,
    this.referenceHigh,
    this.width = 120,
    this.height = 32,
    this.tone = ClinicalTone.info,
    super.key,
  });

  /// Readings, oldest first.
  final List<num> values;

  /// What the series measures, used for the accessibility label.
  final String? label;

  /// Unit of measure.
  final String? unit;

  /// Bottom of the reference range.
  final num? referenceLow;

  /// Top of the reference range.
  final num? referenceHigh;

  /// Drawn width.
  final double width;

  /// Drawn height.
  final double height;

  /// Colour family, overridden to critical when the last point is out of range.
  final ClinicalTone tone;

  /// Whether the most recent reading is outside the reference range.
  bool get lastIsOutOfRange {
    if (values.isEmpty) return false;
    final num last = values.last;
    if (referenceLow != null && last < referenceLow!) return true;
    if (referenceHigh != null && last > referenceHigh!) return true;
    return false;
  }

  /// The sentence a screen reader reads instead of the drawing.
  String get semanticLabel {
    final String subject = label ?? 'Series';
    if (values.isEmpty) return '$subject: no readings';
    final String unitPart = unit == null ? '' : ' $unit';
    final String rangePart = lastIsOutOfRange
        ? ', outside the reference range'
        : '';
    return '$subject: ${values.length} readings, latest '
        '${values.last}$unitPart$rangePart';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ClinicalTone effective = lastIsOutOfRange
        ? ClinicalTone.critical
        : tone;
    if (values.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: Text(
            'No data',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: VitalSparklinePainter(
            values: values,
            lineColor: effective.foreground(scheme),
            bandColor: effective.background(scheme).withValues(alpha: 0.5),
            referenceLow: referenceLow,
            referenceHigh: referenceHigh,
            hasReferenceBand: referenceLow != null && referenceHigh != null,
          ),
        ),
      ),
    );
  }
}

/// Paints a sparkline inside its reference band.
class VitalSparklinePainter extends CustomPainter {
  /// Creates the painter.
  const VitalSparklinePainter({
    required this.values,
    required this.lineColor,
    required this.bandColor,
    this.referenceLow,
    this.referenceHigh,
    this.hasReferenceBand = false,
  });

  /// Readings, oldest first.
  final List<num> values;

  /// Stroke colour.
  final Color lineColor;

  /// Reference band fill.
  final Color bandColor;

  /// Bottom of the reference range.
  final num? referenceLow;

  /// Top of the reference range.
  final num? referenceHigh;

  /// Whether a band can be drawn.
  final bool hasReferenceBand;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    // The vertical extent always includes the reference band when there is one:
    // a series that never leaves its range still has to show where the range
    // is, or the line means nothing.
    num low = values.reduce((num a, num b) => a < b ? a : b);
    num high = values.reduce((num a, num b) => a > b ? a : b);
    if (hasReferenceBand) {
      low = low < referenceLow! ? low : referenceLow!;
      high = high > referenceHigh! ? high : referenceHigh!;
    }
    final num span = high - low;
    final double drawable = size.height - 2;

    double y(num value) {
      if (span == 0) return size.height / 2;
      final double fraction = (value - low) / span;
      return size.height - 1 - fraction * drawable;
    }

    if (hasReferenceBand) {
      final Rect band = Rect.fromLTRB(
        0,
        y(referenceHigh!),
        size.width,
        y(referenceLow!),
      );
      canvas.drawRect(band, Paint()..color = bandColor);
    }

    final Paint stroke = Paint()
      ..color = lineColor
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (values.length == 1) {
      canvas.drawCircle(
        Offset(size.width / 2, y(values.first)),
        2.2,
        Paint()..color = lineColor,
      );
      return;
    }

    final double step = size.width / (values.length - 1);
    final Path path = Path()..moveTo(0, y(values.first));
    for (int i = 1; i < values.length; i++) {
      path.lineTo(step * i, y(values[i]));
    }
    canvas.drawPath(path, stroke);

    canvas.drawCircle(
      Offset(size.width, y(values.last)),
      2.4,
      Paint()..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(VitalSparklinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.bandColor != bandColor ||
      oldDelegate.referenceLow != referenceLow ||
      oldDelegate.referenceHigh != referenceHigh ||
      oldDelegate.hasReferenceBand != hasReferenceBand;
}

/// The Glasgow Coma Scale, as three sliders and a total.
///
/// The total is computed from the components and never typed: a GCS total that
/// disagrees with its parts is a documentation error waiting to reach a handover.
/// The bands are the clinical ones — 8 or less is severe, 9 to 12 moderate,
/// 13 or more mild — and the widget states the band rather than leaving the
/// reader to recall the thresholds.
class GcsCalculator extends StatefulWidget {
  /// Creates the calculator.
  const GcsCalculator({
    this.eye = 4,
    this.verbal = 5,
    this.motor = 6,
    this.enabled = true,
    this.onChanged,
    super.key,
  });

  /// Eye response 1–4.
  final int eye;

  /// Verbal response 1–5.
  final int verbal;

  /// Motor response 1–6.
  final int motor;

  /// Whether the sliders accept input.
  final bool enabled;

  /// Called with the three components whenever any of them changes.
  final void Function(int eye, int verbal, int motor)? onChanged;

  /// The lowest possible total.
  static const int minimumTotal = 3;

  /// The highest possible total.
  static const int maximumTotal = 15;

  /// The clinical band a total falls in.
  static String bandFor(int total) {
    if (total <= 8) return 'Severe';
    if (total <= 12) return 'Moderate';
    return 'Mild';
  }

  /// The tone a total carries.
  static ClinicalTone toneFor(int total) {
    if (total <= 8) return ClinicalTone.critical;
    if (total <= 12) return ClinicalTone.warning;
    return ClinicalTone.success;
  }

  @override
  State<GcsCalculator> createState() => _GcsCalculatorState();
}

class _GcsCalculatorState extends State<GcsCalculator> {
  late int _eye = widget.eye.clamp(1, 4);
  late int _verbal = widget.verbal.clamp(1, 5);
  late int _motor = widget.motor.clamp(1, 6);

  /// The computed total.
  int get total => _eye + _verbal + _motor;

  @override
  void didUpdateWidget(GcsCalculator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eye != widget.eye) _eye = widget.eye.clamp(1, 4);
    if (oldWidget.verbal != widget.verbal) _verbal = widget.verbal.clamp(1, 5);
    if (oldWidget.motor != widget.motor) _motor = widget.motor.clamp(1, 6);
  }

  void _update({int? eye, int? verbal, int? motor}) {
    setState(() {
      _eye = eye ?? _eye;
      _verbal = verbal ?? _verbal;
      _motor = motor ?? _motor;
    });
    widget.onChanged?.call(_eye, _verbal, _motor);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('GCS', style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            ClinicalStatusBadge(
              label:
                  '${total.toString()} · '
                  '${GcsCalculator.bandFor(total)}',
              tone: GcsCalculator.toneFor(total),
            ),
          ],
        ),
        _GcsSlider(
          label: 'Eye',
          value: _eye,
          labels: const <String>['None', 'To pain', 'To speech', 'Spontaneous'],
          enabled: widget.enabled,
          onChanged: (int value) => _update(eye: value),
        ),
        _GcsSlider(
          label: 'Verbal',
          value: _verbal,
          labels: const <String>[
            'None',
            'Sounds',
            'Words',
            'Confused',
            'Oriented',
          ],
          enabled: widget.enabled,
          onChanged: (int value) => _update(verbal: value),
        ),
        _GcsSlider(
          label: 'Motor',
          value: _motor,
          labels: const <String>[
            'None',
            'Extension',
            'Flexion',
            'Withdrawal',
            'Localizes',
            'Obeys',
          ],
          enabled: widget.enabled,
          onChanged: (int value) => _update(motor: value),
        ),
      ],
    );
  }
}

class _GcsSlider extends StatelessWidget {
  const _GcsSlider({
    required this.label,
    required this.value,
    required this.labels,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<String> labels;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      SizedBox(width: 64, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.toDouble(),
          min: 1,
          max: labels.length.toDouble(),
          divisions: labels.length - 1,
          label: '${labels[value - 1]} ($value)',
          onChanged: enabled ? (double raw) => onChanged(raw.round()) : null,
        ),
      ),
      SizedBox(
        width: 104,
        child: Text(
          labels[value - 1],
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
