/// Chart geometry (Module 49).
///
/// The engine draws vectors, not pixels of pre-rendered images, so a chart can
/// be redrawn at any size, on any device, without a bitmap. These are the
/// shared pieces: a scale that maps a value onto a fraction of the plot, a
/// point, and a band such as a reference interval.
library;

import 'package:flutter/material.dart';

/// A linear mapping from data values onto a fraction of the plot area.
///
/// The scale knows nothing about pixels: the painter decides what a fraction
/// means, which keeps the arithmetic testable without a screen.
@immutable
final class ChartScale {
  /// Declares a scale.
  const ChartScale({required this.min, required this.max});

  /// Lowest value on the scale.
  final double min;

  /// Highest value on the scale.
  final double max;

  /// The distance between the ends of the scale.
  double get span => max - min;

  /// Where [value] sits on the scale, as a fraction from 0 to 1.
  ///
  /// A scale whose ends are the same value has no distance to divide by, so it
  /// answers "the middle" rather than dividing by zero.
  double fraction(num value) {
    if (span == 0) return 0.5;
    return ((value - min) / span).clamp(0.0, 1.0);
  }

  /// A scale that covers [values] with a little air above and below.
  ///
  /// A series that touches both ends of its scale is a series whose trend is
  /// invisible, so the scale is padded unless the caller says otherwise.
  static ChartScale covering(Iterable<num> values, {double padding = 0.12}) {
    if (values.isEmpty) return const ChartScale(min: 0, max: 1);
    double low = double.infinity;
    double high = double.negativeInfinity;
    for (final num value in values) {
      if (value < low) low = value.toDouble();
      if (value > high) high = value.toDouble();
    }
    if (low == high) {
      low -= 1;
      high += 1;
    }
    final double pad = (high - low) * padding;
    return ChartScale(min: low - pad, max: high + pad);
  }
}

/// One point of a series.
@immutable
final class ChartPoint {
  /// Declares a point.
  const ChartPoint(this.x, this.y, {this.label});

  /// Materializes a point from a value, with the horizontal position implicit.
  factory ChartPoint.indexed(int index, num value, {String? label}) =>
      ChartPoint(index.toDouble(), value.toDouble(), label: label);

  /// Position along the horizontal axis.
  final double x;

  /// Position along the value axis.
  final double y;

  /// Optional caption, used for the axis label.
  final String? label;
}

/// A shaded range on the value axis.
///
/// A reference interval is the common case: the band says "this is what normal
/// looks like", so a point outside it is visible without being read against a
/// number.
@immutable
final class ChartBand {
  /// Declares a band.
  const ChartBand({required this.from, required this.to, this.label});

  /// Lower edge of the band.
  final double from;

  /// Upper edge of the band.
  final double to;

  /// Optional caption.
  final String? label;

  /// Whether [value] lies inside the band.
  bool contains(num value) => value >= from && value <= to;
}
