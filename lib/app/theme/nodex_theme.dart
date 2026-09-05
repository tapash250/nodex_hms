/// Material 3 clinical theme.
///
/// Two requirements from the specification shape this file: a high-contrast light
/// mode suitable for bright ward and daylight conditions, and an OLED-friendly
/// dark mode for night shifts. Touch targets are held at 48dp minimum throughout,
/// because clinical use includes gloved hands and moving trolleys.
///
/// Clinical severity colours are defined once here rather than per-widget, so
/// urgency reads identically on every surface.
library;

import 'package:flutter/material.dart';

/// Clinical urgency levels used by alerts, triage bands and status chips.
enum ClinicalSeverity {
  /// Routine informational state.
  info,

  /// Stable but noteworthy.
  low,

  /// Requires attention within the shift.
  moderate,

  /// Requires prompt attention.
  high,

  /// Immediate, life-critical attention.
  critical,
}

/// Severity colour roles resolved against the active [ColorScheme].
@immutable
final class ClinicalSeverityColors
    extends ThemeExtension<ClinicalSeverityColors> {
  /// Creates a severity palette.
  const ClinicalSeverityColors({
    required this.info,
    required this.low,
    required this.moderate,
    required this.high,
    required this.critical,
    required this.onSeverity,
  });

  /// Informational.
  final Color info;

  /// Low urgency.
  final Color low;

  /// Moderate urgency.
  final Color moderate;

  /// High urgency.
  final Color high;

  /// Critical urgency.
  final Color critical;

  /// Foreground colour for text drawn on a severity fill.
  final Color onSeverity;

  /// Returns the fill colour for [severity].
  Color colorFor(ClinicalSeverity severity) => switch (severity) {
    ClinicalSeverity.info => info,
    ClinicalSeverity.low => low,
    ClinicalSeverity.moderate => moderate,
    ClinicalSeverity.high => high,
    ClinicalSeverity.critical => critical,
  };

  @override
  ClinicalSeverityColors copyWith({
    Color? info,
    Color? low,
    Color? moderate,
    Color? high,
    Color? critical,
    Color? onSeverity,
  }) => ClinicalSeverityColors(
    info: info ?? this.info,
    low: low ?? this.low,
    moderate: moderate ?? this.moderate,
    high: high ?? this.high,
    critical: critical ?? this.critical,
    onSeverity: onSeverity ?? this.onSeverity,
  );

  @override
  ClinicalSeverityColors lerp(
    ThemeExtension<ClinicalSeverityColors>? other,
    double t,
  ) {
    if (other is! ClinicalSeverityColors) {
      return this;
    }
    return ClinicalSeverityColors(
      info: Color.lerp(info, other.info, t)!,
      low: Color.lerp(low, other.low, t)!,
      moderate: Color.lerp(moderate, other.moderate, t)!,
      high: Color.lerp(high, other.high, t)!,
      critical: Color.lerp(critical, other.critical, t)!,
      onSeverity: Color.lerp(onSeverity, other.onSeverity, t)!,
    );
  }
}

/// Builds the NODEX light and dark themes.
abstract final class NodexTheme {
  /// Brand seed colour: a clinical teal that reads as medical without tipping
  /// into the alarm palette reserved for severity.
  static const Color seedColor = Color(0xFF00696E);

  /// Minimum interactive dimension, per the specification's 48dp requirement.
  static const double minimumTouchTarget = 48;

  /// The light theme, tuned for high contrast in bright clinical environments.
  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      // High contrast rather than the default: ward lighting and daylight glare
      // wash out low-contrast surfaces.
      contrastLevel: 0.5,
    );
    return _base(scheme).copyWith(
      extensions: <ThemeExtension<Object?>>[
        const ClinicalSeverityColors(
          info: Color(0xFF00639B),
          low: Color(0xFF1B6C33),
          moderate: Color(0xFF8A5100),
          high: Color(0xFFB3261E),
          critical: Color(0xFF8C0009),
          onSeverity: Colors.white,
        ),
      ],
    );
  }

  /// The dark theme. Uses true black surfaces to reduce OLED power draw during
  /// night shifts and to avoid glare in darkened wards.
  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      contrastLevel: 0.3,
    ).copyWith(surface: const Color(0xFF000000));

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFF000000),
      extensions: <ThemeExtension<Object?>>[
        const ClinicalSeverityColors(
          info: Color(0xFF8ECDFF),
          low: Color(0xFF7FDA92),
          moderate: Color(0xFFFFB95C),
          high: Color(0xFFFFB4AB),
          critical: Color(0xFFFF897D),
          onSeverity: Color(0xFF1A1C1E),
        ),
      ],
    );
  }

  static ThemeData _base(ColorScheme scheme) => ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 2,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, minimumTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 24),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, minimumTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 24),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, minimumTouchTarget),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(minimumTouchTarget, minimumTouchTarget),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      // Errors on clinical forms must be readable at a glance, not truncated.
      errorMaxLines: 3,
      helperMaxLines: 3,
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
    cardTheme: const CardThemeData(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: const NavigationBarThemeData(height: 72),
    dividerTheme: const DividerThemeData(space: 1, thickness: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
