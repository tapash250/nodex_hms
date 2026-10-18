/// Reports & Operational Analytics Warehouse entities (Module 38).
///
/// Specification scope: "Hospital-wide analytics: morbidity reports, department
/// productivity, pharmacy burn rate, and financial balance sheets." with the
/// performance clause "offloaded from operational tables to read-replicas with
/// materialized rolling rollups."
///
/// The warehouse stores conclusions, not facts. An encounter, a dispense and an
/// invoice live in the modules that own them; what lives here is what those
/// modules add up to over a period, and the record of who asked. A rollup must
/// stay readable when the operational rows behind it have been corrected, because
/// the number the board was shown is itself a fact worth keeping.
///
/// The facts a stored copy would let drift are derived instead. What period a
/// grain covers is [analyticsPeriodEnd] and [analyticsPeriodStartFor], so "monthly"
/// means one thing on every device. A ratio is [rollupRatio], a balance sheet's
/// bottom line is [rollupNetPosition], and whether a figure has gone out of date
/// is [isRollupStale] against the clock rather than a flag somebody has to
/// remember to set. What a run's own record cannot say until it is read is
/// [isRunStalled] and [runDurationSeconds].
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// What a report is about.
enum ReportCategory {
  /// Illness in the population the hospital serves.
  morbidity('morbidity'),

  /// What a department produced.
  productivity('productivity'),

  /// What the pharmacy consumed and dispensed.
  pharmacy('pharmacy'),

  /// Money in and money out.
  financial('financial'),

  /// Anything else operational the hospital measures.
  operational('operational');

  const ReportCategory(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ReportCategory.morbidity => 'Morbidity',
    ReportCategory.productivity => 'Department productivity',
    ReportCategory.pharmacy => 'Pharmacy',
    ReportCategory.financial => 'Financial',
    ReportCategory.operational => 'Operational',
  };

  /// Parses a stored value.
  static ReportCategory fromWire(String value) =>
      ReportCategory.values.firstWhere(
        (ReportCategory value_) => value_.wireValue == value,
        orElse: () => ReportCategory.operational,
      );
}

/// The operational module a rollup draws on.
enum AnalyticsSource {
  /// Clinical encounters and diagnoses.
  encounters('encounters'),

  /// Dispensing and stock movement.
  pharmacy('pharmacy'),

  /// Invoices, payments and claims.
  billing('billing'),

  /// Shifts, duties and attendance.
  workforce('workforce'),

  /// Stock, assets and consumables.
  inventory('inventory'),

  /// Orders and results.
  laboratory('laboratory'),

  /// More than one of the above.
  mixed('mixed');

  const AnalyticsSource(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    AnalyticsSource.encounters => 'Clinical encounters',
    AnalyticsSource.pharmacy => 'Pharmacy',
    AnalyticsSource.billing => 'Billing',
    AnalyticsSource.workforce => 'Workforce',
    AnalyticsSource.inventory => 'Inventory',
    AnalyticsSource.laboratory => 'Laboratory',
    AnalyticsSource.mixed => 'Several sources',
  };

  /// Parses a stored value.
  static AnalyticsSource fromWire(String value) =>
      AnalyticsSource.values.firstWhere(
        (AnalyticsSource value_) => value_.wireValue == value,
        orElse: () => AnalyticsSource.mixed,
      );
}

/// How wide a rolling period is.
enum AnalyticsGrain {
  /// One day.
  day('day'),

  /// Seven days, Monday to Sunday.
  week('week'),

  /// A calendar month.
  month('month'),

  /// A calendar quarter.
  quarter('quarter'),

  /// A calendar year.
  year('year');

  const AnalyticsGrain(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    AnalyticsGrain.day => 'Daily',
    AnalyticsGrain.week => 'Weekly',
    AnalyticsGrain.month => 'Monthly',
    AnalyticsGrain.quarter => 'Quarterly',
    AnalyticsGrain.year => 'Yearly',
  };

  /// Parses a stored value.
  static AnalyticsGrain fromWire(String value) =>
      AnalyticsGrain.values.firstWhere(
        (AnalyticsGrain value_) => value_.wireValue == value,
        orElse: () => AnalyticsGrain.month,
      );

  /// Roughly how many days a period of this grain covers.
  int get approximateDays => switch (this) {
    AnalyticsGrain.day => 1,
    AnalyticsGrain.week => 7,
    AnalyticsGrain.month => 30,
    AnalyticsGrain.quarter => 91,
    AnalyticsGrain.year => 365,
  };
}

/// The last day of the period of [grain] that starts on [periodStart].
///
/// Weeks start on Monday, and months, quarters and years are the calendar
/// periods a hospital already reports in, so "the March figures" means the same
/// thing here as it does in the board pack.
DateTime analyticsPeriodEnd({
  required AnalyticsGrain grain,
  required DateTime periodStart,
}) {
  final DateTime start = DateTime.utc(
    periodStart.toUtc().year,
    periodStart.toUtc().month,
    periodStart.toUtc().day,
  );
  final DateTime end = switch (grain) {
    AnalyticsGrain.day => start,
    AnalyticsGrain.week => start.add(const Duration(days: 6)),
    AnalyticsGrain.month => DateTime.utc(start.year, start.month + 1, 0),
    AnalyticsGrain.quarter => DateTime.utc(
      start.year,
      ((start.month - 1) ~/ 3) * 3 + 3,
      _lastDayOfMonth(start.year, ((start.month - 1) ~/ 3) * 3 + 3),
    ),
    AnalyticsGrain.year => DateTime.utc(start.year, 12, 31),
  };
  return DateTime.utc(end.year, end.month, end.day);
}

/// The first day of the period of [grain] that contains [at].
///
/// This is what makes a rollup "rolling": a figure materialised at any moment in
/// March lands on the same period every device agrees is March.
DateTime analyticsPeriodStartFor({
  required AnalyticsGrain grain,
  required DateTime at,
}) {
  final DateTime moment = at.toUtc();
  final DateTime day = DateTime.utc(moment.year, moment.month, moment.day);
  return switch (grain) {
    AnalyticsGrain.day => day,
    AnalyticsGrain.week => day.subtract(Duration(days: day.weekday - 1)),
    AnalyticsGrain.month => DateTime.utc(day.year, day.month),
    AnalyticsGrain.quarter => DateTime.utc(
      day.year,
      ((day.month - 1) ~/ 3) * 3 + 1,
    ),
    AnalyticsGrain.year => DateTime.utc(day.year),
  };
}

/// Lifecycle status of a report definition.
enum ReportDefinitionStatus {
  /// Being written; the only stage whose contract may change.
  draft('draft'),

  /// Available to run; the query contract is frozen.
  published('published'),

  /// Withdrawn; terminal, and kept so a past run still resolves to its definition.
  retired('retired');

  const ReportDefinitionStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ReportDefinitionStatus.draft => 'Draft',
    ReportDefinitionStatus.published => 'Published',
    ReportDefinitionStatus.retired => 'Retired',
  };

  /// Parses a stored value.
  static ReportDefinitionStatus fromWire(String value) =>
      ReportDefinitionStatus.values.firstWhere(
        (ReportDefinitionStatus value_) => value_.wireValue == value,
        orElse: () => ReportDefinitionStatus.draft,
      );

  /// Whether the definition may be run.
  bool get isRunnable => this == ReportDefinitionStatus.published;

  /// Whether the definition is settled.
  bool get isTerminal => this == ReportDefinitionStatus.retired;
}

/// Whether a definition may move from [from] to [to].
bool definitionCanTransition(
  ReportDefinitionStatus from,
  ReportDefinitionStatus to,
) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    ReportDefinitionStatus.draft => to == ReportDefinitionStatus.published,
    ReportDefinitionStatus.published => to == ReportDefinitionStatus.retired,
    ReportDefinitionStatus.retired => false,
  };
}

/// Lifecycle status of a materialised rollup.
enum RollupStatus {
  /// The current figure for its period.
  materialised('materialised'),

  /// Replaced by a later materialisation of the same period.
  superseded('superseded'),

  /// Withdrawn, with a reason; terminal.
  voided('voided');

  const RollupStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    RollupStatus.materialised => 'Current',
    RollupStatus.superseded => 'Superseded',
    RollupStatus.voided => 'Withdrawn',
  };

  /// Parses a stored value.
  static RollupStatus fromWire(String value) => RollupStatus.values.firstWhere(
    (RollupStatus value_) => value_.wireValue == value,
    orElse: () => RollupStatus.materialised,
  );

  /// Whether the rollup is the current figure for its period.
  bool get isCurrent => this == RollupStatus.materialised;

  /// Whether the rollup is settled.
  bool get isTerminal => !isCurrent;
}

/// Lifecycle status of a report run.
enum ReportRunStatus {
  /// Asked for, not started.
  queued('queued'),

  /// Reading.
  running('running'),

  /// Finished with rows; terminal.
  succeeded('succeeded'),

  /// Finished without rows, with a reason; terminal.
  failed('failed'),

  /// Abandoned before it finished, with a reason; terminal.
  cancelled('cancelled');

  const ReportRunStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ReportRunStatus.queued => 'Queued',
    ReportRunStatus.running => 'Running',
    ReportRunStatus.succeeded => 'Succeeded',
    ReportRunStatus.failed => 'Failed',
    ReportRunStatus.cancelled => 'Cancelled',
  };

  /// Parses a stored value.
  static ReportRunStatus fromWire(String value) =>
      ReportRunStatus.values.firstWhere(
        (ReportRunStatus value_) => value_.wireValue == value,
        orElse: () => ReportRunStatus.queued,
      );

  /// Whether the run is settled.
  bool get isTerminal => switch (this) {
    ReportRunStatus.succeeded ||
    ReportRunStatus.failed ||
    ReportRunStatus.cancelled => true,
    ReportRunStatus.queued || ReportRunStatus.running => false,
  };

  /// Whether the run is still to be worked.
  bool get isLive => !isTerminal;
}

/// Whether a run may move from [from] to [to].
bool reportRunCanTransition(ReportRunStatus from, ReportRunStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    ReportRunStatus.queued =>
      to == ReportRunStatus.running || to == ReportRunStatus.cancelled,
    ReportRunStatus.running =>
      to == ReportRunStatus.succeeded ||
          to == ReportRunStatus.failed ||
          to == ReportRunStatus.cancelled,
    ReportRunStatus.succeeded ||
    ReportRunStatus.failed ||
    ReportRunStatus.cancelled => false,
  };
}

/// Which side of the warehouse answered a run.
enum RollupServedFrom {
  /// The rolling rollup, which is the point of materialising one.
  rollup('rollup'),

  /// A query sent through to the read replica.
  replica('replica');

  const RollupServedFrom(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    RollupServedFrom.rollup => 'Rolling rollup',
    RollupServedFrom.replica => 'Read replica',
  };

  /// Parses a stored value.
  static RollupServedFrom? fromWire(String? value) => value == null
      ? null
      : RollupServedFrom.values.firstWhere(
          (RollupServedFrom value_) => value_.wireValue == value,
          orElse: () => RollupServedFrom.replica,
        );
}

/// The format a report leaves in.
enum ExportFormat {
  /// Comma-separated values.
  csv('csv'),

  /// A printable document.
  pdf('pdf'),

  /// A spreadsheet.
  xlsx('xlsx'),

  /// Machine-readable rows.
  json('json');

  const ExportFormat(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ExportFormat.csv => 'CSV',
    ExportFormat.pdf => 'PDF',
    ExportFormat.xlsx => 'Spreadsheet',
    ExportFormat.json => 'JSON',
  };

  /// Parses a stored value.
  static ExportFormat fromWire(String value) => ExportFormat.values.firstWhere(
    (ExportFormat value_) => value_.wireValue == value,
    orElse: () => ExportFormat.csv,
  );
}

/// Where a report artefact went.
enum ExportDestination {
  /// Taken off the device by the person who asked.
  download('download'),

  /// Sent by email.
  email('email'),

  /// Left behind a short-lived link.
  secureLink('secure_link'),

  /// Printed.
  print('print');

  const ExportDestination(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ExportDestination.download => 'Downloaded',
    ExportDestination.email => 'Emailed',
    ExportDestination.secureLink => 'Shared by link',
    ExportDestination.print => 'Printed',
  };

  /// Parses a stored value.
  static ExportDestination fromWire(String value) =>
      ExportDestination.values.firstWhere(
        (ExportDestination value_) => value_.wireValue == value,
        orElse: () => ExportDestination.download,
      );
}

/// What the hospital can report.
@immutable
final class ReportDefinition {
  /// Creates a report definition.
  const ReportDefinition({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.displayName,
    required this.category,
    required this.primarySource,
    required this.grain,
    required this.retentionDays,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.facilityId,
    this.description,
    this.publishedAt,
    this.publishedBy,
    this.retiredAt,
    this.createdAt,
  });

  /// Validates and builds a new draft definition row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String code,
    required String displayName,
    required String createdBy,
    ReportCategory category = ReportCategory.operational,
    AnalyticsSource primarySource = AnalyticsSource.mixed,
    AnalyticsGrain grain = AnalyticsGrain.month,
    int retentionDays = 3650,
    String? facilityId,
    String? description,
    String definitionId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (code.trim().isEmpty) {
      fieldErrors['code'] = 'A report code is required.';
    }
    if (displayName.trim().isEmpty) {
      fieldErrors['display_name'] = 'A report name is required.';
    }
    if (retentionDays < 30 || retentionDays > 36500) {
      fieldErrors['retention_days'] = 'A retention period is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Report definition failed validation.',
        fieldErrors: fieldErrors,
        code: 'report_definition_invalid',
      );
    }
    final String stamp = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (definitionId.isNotEmpty) 'id': definitionId,
      'tenant_id': tenantId,
      'facility_id': _trimmed(facilityId),
      'code': code.trim(),
      'display_name': displayName.trim(),
      'description': _trimmed(description),
      'category': category.wireValue,
      'primary_source': primarySource.wireValue,
      'grain': grain.wireValue,
      'retention_days': retentionDays,
      'status': ReportDefinitionStatus.draft.wireValue,
      'published_at': null,
      'published_by': null,
      'retired_at': null,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a definition from a local row.
  factory ReportDefinition.fromRow(Map<String, Object?> row) =>
      ReportDefinition(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        code: row['code']! as String,
        displayName: row['display_name']! as String,
        category: ReportCategory.fromWire(
          (row['category'] as String?) ?? ReportCategory.operational.wireValue,
        ),
        primarySource: AnalyticsSource.fromWire(
          (row['primary_source'] as String?) ?? AnalyticsSource.mixed.wireValue,
        ),
        grain: AnalyticsGrain.fromWire(
          (row['grain'] as String?) ?? AnalyticsGrain.month.wireValue,
        ),
        retentionDays: _asInt(row['retention_days']),
        status: ReportDefinitionStatus.fromWire(
          (row['status'] as String?) ?? ReportDefinitionStatus.draft.wireValue,
        ),
        createdBy: row['created_by']! as String,
        updatedAt: _parse(row['updated_at']),
        facilityId: row['facility_id'] as String?,
        description: row['description'] as String?,
        publishedAt: _parseNullable(row['published_at']),
        publishedBy: row['published_by'] as String?,
        retiredAt: _parseNullable(row['retired_at']),
        createdAt: _parseNullable(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The code the rest of the hospital names the figure by.
  final String code;

  /// Display name.
  final String displayName;

  /// What the report is about.
  final ReportCategory category;

  /// The operational module the rollup draws on.
  final AnalyticsSource primarySource;

  /// How wide a rolling period is.
  final AnalyticsGrain grain;

  /// How long a rollup of this report is kept, in days.
  final int retentionDays;

  /// Lifecycle status.
  final ReportDefinitionStatus status;

  /// Who raised it.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The facility it is scoped to, or null for hospital-wide.
  final String? facilityId;

  /// What it is for.
  final String? description;

  /// When it was published, UTC.
  final DateTime? publishedAt;

  /// Who published it.
  final String? publishedBy;

  /// When it was retired, UTC.
  final DateTime? retiredAt;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// Whether the report is hospital-wide rather than one facility's.
  bool get isHospitalWide => facilityId == null;

  /// Whether the definition may be run.
  bool get isRunnable => status.isRunnable;

  /// Whether the definition is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the definition still has to be worked.
  bool get isLive => !isTerminal;
}

/// The change set that publishes a definition.
Map<String, Object?> definitionPublishChanges({
  required String publishedBy,
  DateTime? at,
}) {
  if (publishedBy.trim().isEmpty) {
    throw const ValidationError(
      message: 'Report definition failed validation.',
      fieldErrors: <String, String>{'published_by': 'A publisher is required.'},
      code: 'report_definition_publisher_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ReportDefinitionStatus.published.wireValue,
    'published_at': now,
    'published_by': publishedBy.trim(),
    'updated_at': now,
  };
}

/// The change set that retires a definition.
Map<String, Object?> definitionRetireChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ReportDefinitionStatus.retired.wireValue,
    'retired_at': now,
    'updated_at': now,
  };
}

/// One materialised rolling rollup.
@immutable
final class AnalyticsRollup {
  /// Creates a rollup.
  const AnalyticsRollup({
    required this.id,
    required this.tenantId,
    required this.definitionId,
    required this.grain,
    required this.periodStart,
    required this.periodEnd,
    required this.rowCount,
    required this.numerator,
    required this.denominator,
    required this.incomeMinor,
    required this.expenditureMinor,
    required this.status,
    required this.materialisedAt,
    required this.createdBy,
    required this.updatedAt,
    this.facilityId,
    this.materialisedBy,
    this.supersededAt,
    this.supersedeNote,
    this.voidedAt,
    this.voidReason,
    this.createdAt,
  });

  /// Validates and builds a new materialised rollup row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String definitionId,
    required DateTime periodStart,
    required String createdBy,
    AnalyticsGrain grain = AnalyticsGrain.month,
    DateTime? periodEnd,
    String? facilityId,
    int rowCount = 0,
    int numerator = 0,
    int denominator = 0,
    int incomeMinor = 0,
    int expenditureMinor = 0,
    String? materialisedBy,
    DateTime? materialisedAt,
    String rollupId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (definitionId.isEmpty) {
      fieldErrors['definition_id'] = 'A report definition is required.';
    }
    if (rowCount < 0) {
      fieldErrors['row_count'] = 'A row count cannot be negative.';
    }
    if (denominator < 0) {
      fieldErrors['denominator'] = 'A denominator cannot be negative.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    final DateTime start = DateTime.utc(
      periodStart.toUtc().year,
      periodStart.toUtc().month,
      periodStart.toUtc().day,
    );
    final DateTime end = periodEnd == null
        ? analyticsPeriodEnd(grain: grain, periodStart: start)
        : DateTime.utc(
            periodEnd.toUtc().year,
            periodEnd.toUtc().month,
            periodEnd.toUtc().day,
          );
    if (end.isBefore(start)) {
      fieldErrors['period_end'] = 'The period must end after it starts.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Analytics rollup failed validation.',
        fieldErrors: fieldErrors,
        code: 'analytics_rollup_invalid',
      );
    }
    final DateTime at = (materialisedAt ?? DateTime.now()).toUtc();
    final String stamp = at.toIso8601String();
    return <String, Object?>{
      if (rollupId.isNotEmpty) 'id': rollupId,
      'tenant_id': tenantId,
      'definition_id': definitionId,
      'facility_id': _trimmed(facilityId),
      'grain': grain.wireValue,
      'period_start': _formatDate(start),
      'period_end': _formatDate(end),
      'row_count': rowCount,
      'numerator': numerator,
      'denominator': denominator,
      'income_minor': incomeMinor,
      'expenditure_minor': expenditureMinor,
      'materialised_at': stamp,
      'materialised_by': materialisedBy,
      'status': RollupStatus.materialised.wireValue,
      'superseded_at': null,
      'supersede_note': null,
      'voided_at': null,
      'void_reason': null,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a rollup from a local row.
  factory AnalyticsRollup.fromRow(Map<String, Object?> row) => AnalyticsRollup(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    definitionId: row['definition_id']! as String,
    grain: AnalyticsGrain.fromWire(
      (row['grain'] as String?) ?? AnalyticsGrain.month.wireValue,
    ),
    periodStart: _parseDate(row['period_start']),
    periodEnd: _parseDate(row['period_end']),
    rowCount: _asInt(row['row_count']),
    numerator: _asInt(row['numerator']),
    denominator: _asInt(row['denominator']),
    incomeMinor: _asInt(row['income_minor']),
    expenditureMinor: _asInt(row['expenditure_minor']),
    status: RollupStatus.fromWire(
      (row['status'] as String?) ?? RollupStatus.materialised.wireValue,
    ),
    materialisedAt: _parse(row['materialised_at']),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    facilityId: row['facility_id'] as String?,
    materialisedBy: row['materialised_by'] as String?,
    supersededAt: _parseNullable(row['superseded_at']),
    supersedeNote: row['supersede_note'] as String?,
    voidedAt: _parseNullable(row['voided_at']),
    voidReason: row['void_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The definition this is a figure for.
  final String definitionId;

  /// How wide the period is.
  final AnalyticsGrain grain;

  /// First day of the period, UTC midnight.
  final DateTime periodStart;

  /// Last day of the period, UTC midnight.
  final DateTime periodEnd;

  /// How many operational rows the period added up to.
  final int rowCount;

  /// The numerator of whatever ratio the report defines.
  final int numerator;

  /// The denominator of whatever ratio the report defines.
  final int denominator;

  /// Money in, in minor units.
  final int incomeMinor;

  /// Money out, in minor units.
  final int expenditureMinor;

  /// Lifecycle status.
  final RollupStatus status;

  /// When it was materialised, UTC.
  final DateTime materialisedAt;

  /// Who raised the row.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The facility it is scoped to, or null for hospital-wide.
  final String? facilityId;

  /// Who materialised it.
  final String? materialisedBy;

  /// When it was superseded, UTC.
  final DateTime? supersededAt;

  /// Why it was superseded.
  final String? supersedeNote;

  /// When it was withdrawn, UTC.
  final DateTime? voidedAt;

  /// Why it was withdrawn.
  final String? voidReason;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// The moment the period stops being covered, exclusive, UTC.
  DateTime get windowEnd => periodEnd.add(const Duration(days: 1));

  /// Whether the rollup is the current figure for its period.
  bool get isCurrent => status.isCurrent;

  /// Whether the rollup is settled.
  bool get isTerminal => status.isTerminal;

  /// The ratio the two terms describe, as a percentage.
  ///
  /// Null when there is nothing to divide by: a rate over an empty denominator is
  /// not zero, it is unknown, and showing a zero would be a claim.
  double? get ratio => rollupRatio(this);

  /// The bottom line of the two sides, in minor units.
  int get netPosition => rollupNetPosition(this);

  /// Whether the period made more than it spent.
  bool get isSurplus => netPosition > 0;

  /// Whether the period spent more than it made.
  bool get isDeficit => netPosition < 0;
}

/// The ratio a rollup's two terms describe, as a percentage, or null.
double? rollupRatio(AnalyticsRollup rollup) => rollup.denominator <= 0
    ? null
    : rollup.numerator / rollup.denominator * 100;

/// The bottom line of a rollup's two sides, in minor units.
int rollupNetPosition(AnalyticsRollup rollup) =>
    rollup.incomeMinor - rollup.expenditureMinor;

/// The percentage change from one period to the next, or null.
///
/// Null when the earlier period was zero: a rise from nothing has no percentage,
/// and inventing one would be the most misleading number on the page.
double? growthRate({required int current, required int previous}) =>
    previous == 0 ? null : (current - previous) / previous * 100;

/// Whether a rollup has gone out of date against its own period.
///
/// A figure is stale once its period has been closed a while ago: a March rollup
/// read in June is stale even though it is the current row for March, because the
/// question a reader has in June is what April and May did.
bool isRollupStale({
  required AnalyticsRollup rollup,
  required DateTime now,
  Duration maxAge = const Duration(days: 1),
}) => now.toUtc().isAfter(rollup.windowEnd.add(maxAge));

/// Whether a rollup's period covers a requested range.
bool isRollupCovering({
  required AnalyticsRollup rollup,
  required DateTime from,
  required DateTime to,
}) =>
    !rollup.periodStart.isAfter(from.toUtc()) &&
    !rollup.periodEnd.isBefore(to.toUtc());

/// The newest rollup for a definition and grain, or null.
///
/// Superseded and withdrawn figures are skipped: they are kept to explain a
/// number that was published, not to be read as the number.
AnalyticsRollup? latestRollupFor({
  required String definitionId,
  required AnalyticsGrain grain,
  required Iterable<AnalyticsRollup> rollups,
}) {
  AnalyticsRollup? newest;
  for (final AnalyticsRollup rollup in rollups) {
    if (rollup.definitionId != definitionId ||
        rollup.grain != grain ||
        !rollup.isCurrent) {
      continue;
    }
    if (newest == null || rollup.periodStart.isAfter(newest.periodStart)) {
      newest = rollup;
    }
  }
  return newest;
}

/// The change set that supersedes a rollup with a later materialisation.
Map<String, Object?> rollupSupersedeChanges({String? note, DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': RollupStatus.superseded.wireValue,
    'superseded_at': now,
    'supersede_note': _trimmed(note),
    'updated_at': now,
  };
}

/// The change set that withdraws a rollup.
Map<String, Object?> rollupVoidChanges({required String reason, DateTime? at}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Analytics rollup failed validation.',
      fieldErrors: <String, String>{'void_reason': 'A reason is required.'},
      code: 'analytics_rollup_void_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': RollupStatus.voided.wireValue,
    'voided_at': now,
    'void_reason': reason.trim(),
    'updated_at': now,
  };
}

/// One execution of a report definition.
@immutable
final class ReportRun {
  /// Creates a report run.
  const ReportRun({
    required this.id,
    required this.tenantId,
    required this.definitionId,
    required this.runNumber,
    required this.grain,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    required this.requestedBy,
    required this.createdBy,
    required this.updatedAt,
    this.facilityId,
    this.filterNote,
    this.servedFrom,
    this.rowCount,
    this.startedAt,
    this.finishedAt,
    this.failureReason,
    this.cancelledAt,
    this.cancelReason,
    this.createdAt,
  });

  /// Validates and builds a new queued run row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String definitionId,
    required String runNumber,
    required String requestedBy,
    required String createdBy,
    required DateTime periodStart,
    AnalyticsGrain grain = AnalyticsGrain.month,
    DateTime? periodEnd,
    String? facilityId,
    String? filterNote,
    String runId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (definitionId.isEmpty) {
      fieldErrors['definition_id'] = 'A report definition is required.';
    }
    if (runNumber.trim().isEmpty) {
      fieldErrors['run_number'] = 'A run number is required.';
    }
    if (requestedBy.isEmpty) {
      fieldErrors['requested_by'] = 'Who asked for it is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    final DateTime start = DateTime.utc(
      periodStart.toUtc().year,
      periodStart.toUtc().month,
      periodStart.toUtc().day,
    );
    final DateTime end = periodEnd == null
        ? analyticsPeriodEnd(grain: grain, periodStart: start)
        : DateTime.utc(
            periodEnd.toUtc().year,
            periodEnd.toUtc().month,
            periodEnd.toUtc().day,
          );
    if (end.isBefore(start)) {
      fieldErrors['period_end'] = 'The period must end after it starts.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Report run failed validation.',
        fieldErrors: fieldErrors,
        code: 'report_run_invalid',
      );
    }
    final String stamp = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (runId.isNotEmpty) 'id': runId,
      'tenant_id': tenantId,
      'definition_id': definitionId,
      'facility_id': _trimmed(facilityId),
      'run_number': runNumber.trim(),
      'grain': grain.wireValue,
      'period_start': _formatDate(start),
      'period_end': _formatDate(end),
      'filter_note': _trimmed(filterNote),
      'status': ReportRunStatus.queued.wireValue,
      'served_from': null,
      'row_count': null,
      'requested_by': requestedBy,
      'started_at': null,
      'finished_at': null,
      'failure_reason': null,
      'cancelled_at': null,
      'cancel_reason': null,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a run from a local row.
  factory ReportRun.fromRow(Map<String, Object?> row) => ReportRun(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    definitionId: row['definition_id']! as String,
    runNumber: row['run_number']! as String,
    grain: AnalyticsGrain.fromWire(
      (row['grain'] as String?) ?? AnalyticsGrain.month.wireValue,
    ),
    periodStart: _parseDate(row['period_start']),
    periodEnd: _parseDate(row['period_end']),
    status: ReportRunStatus.fromWire(
      (row['status'] as String?) ?? ReportRunStatus.queued.wireValue,
    ),
    requestedBy: row['requested_by']! as String,
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    facilityId: row['facility_id'] as String?,
    filterNote: row['filter_note'] as String?,
    servedFrom: RollupServedFrom.fromWire(row['served_from'] as String?),
    rowCount: row['row_count'] as int?,
    startedAt: _parseNullable(row['started_at']),
    finishedAt: _parseNullable(row['finished_at']),
    failureReason: row['failure_reason'] as String?,
    cancelledAt: _parseNullable(row['cancelled_at']),
    cancelReason: row['cancel_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The definition being executed.
  final String definitionId;

  /// The warehouse's run number.
  final String runNumber;

  /// How wide the period is.
  final AnalyticsGrain grain;

  /// First day of the period, UTC midnight.
  final DateTime periodStart;

  /// Last day of the period, UTC midnight.
  final DateTime periodEnd;

  /// Lifecycle status.
  final ReportRunStatus status;

  /// Who asked for the report.
  final String requestedBy;

  /// Who raised the row.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The facility it is scoped to, or null for hospital-wide.
  final String? facilityId;

  /// The filter the requester applied.
  final String? filterNote;

  /// Which side of the warehouse answered.
  final RollupServedFrom? servedFrom;

  /// How many rows the run produced.
  final int? rowCount;

  /// When the run started, UTC.
  final DateTime? startedAt;

  /// When the run stopped, UTC.
  final DateTime? finishedAt;

  /// Why the run failed.
  final String? failureReason;

  /// When the run was abandoned, UTC.
  final DateTime? cancelledAt;

  /// Why the run was abandoned.
  final String? cancelReason;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// Whether the run is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the run still has to be worked.
  bool get isLive => status.isLive;

  /// Whether the run produced rows.
  bool get succeeded => status == ReportRunStatus.succeeded;

  /// Whether the rolling rollup answered.
  bool get servedFromRollup => servedFrom == RollupServedFrom.rollup;

  /// How long the run took, in seconds, once it has a start and a finish.
  int? get durationSeconds => runDurationSeconds(this);
}

/// How long a run took, in whole seconds, or null while it is unfinished.
int? runDurationSeconds(ReportRun run) {
  final DateTime? started = run.startedAt;
  final DateTime? finished = run.finishedAt;
  if (started == null || finished == null) {
    return null;
  }
  final int seconds = finished.difference(started).inSeconds;
  return seconds < 0 ? 0 : seconds;
}

/// Whether a run has been running longer than it should.
///
/// A queued run is not stalled: nothing has started, so nothing has hung.
bool isRunStalled({
  required ReportRun run,
  required DateTime now,
  Duration threshold = const Duration(minutes: 15),
}) {
  final DateTime? started = run.startedAt;
  if (run.status != ReportRunStatus.running || started == null) {
    return false;
  }
  return now.toUtc().isAfter(started.add(threshold));
}

/// The change set that starts a run.
Map<String, Object?> runStartChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ReportRunStatus.running.wireValue,
    'started_at': now,
    'updated_at': now,
  };
}

/// The change set that finishes a run with rows.
Map<String, Object?> runSucceedChanges({
  required RollupServedFrom servedFrom,
  required int rowCount,
  DateTime? at,
}) {
  if (rowCount < 0) {
    throw const ValidationError(
      message: 'Report run failed validation.',
      fieldErrors: <String, String>{
        'row_count': 'A row count cannot be negative.',
      },
      code: 'report_run_row_count_invalid',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ReportRunStatus.succeeded.wireValue,
    'served_from': servedFrom.wireValue,
    'row_count': rowCount,
    'finished_at': now,
    'updated_at': now,
  };
}

/// The change set that finishes a run without rows.
Map<String, Object?> runFailChanges({required String reason, DateTime? at}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Report run failed validation.',
      fieldErrors: <String, String>{'failure_reason': 'A reason is required.'},
      code: 'report_run_failure_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ReportRunStatus.failed.wireValue,
    'failure_reason': reason.trim(),
    'finished_at': now,
    'updated_at': now,
  };
}

/// The change set that abandons a run.
Map<String, Object?> runCancelChanges({required String reason, DateTime? at}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Report run failed validation.',
      fieldErrors: <String, String>{'cancel_reason': 'A reason is required.'},
      code: 'report_run_cancel_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ReportRunStatus.cancelled.wireValue,
    'cancel_reason': reason.trim(),
    'cancelled_at': now,
    'updated_at': now,
  };
}

/// One artefact that left the warehouse.
@immutable
final class AnalyticsExport {
  /// Creates an export record.
  const AnalyticsExport({
    required this.id,
    required this.tenantId,
    required this.runId,
    required this.artifactLabel,
    required this.format,
    required this.destination,
    required this.exportedAt,
    required this.exportedBy,
    this.byteSize,
    this.checksum,
    this.note,
    this.createdAt,
  });

  /// Validates and builds an export row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String runId,
    required String artifactLabel,
    required String exportedBy,
    ExportFormat format = ExportFormat.csv,
    ExportDestination destination = ExportDestination.download,
    int? byteSize,
    String? checksum,
    String? note,
    DateTime? exportedAt,
    String exportId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (runId.isEmpty) {
      fieldErrors['run_id'] = 'The report run is required.';
    }
    if (artifactLabel.trim().isEmpty) {
      fieldErrors['artifact_label'] = 'A file name is required.';
    }
    if (exportedBy.isEmpty) {
      fieldErrors['exported_by'] = 'Who took it is required.';
    }
    if (byteSize != null && byteSize < 0) {
      fieldErrors['byte_size'] = 'A size cannot be negative.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Analytics export failed validation.',
        fieldErrors: fieldErrors,
        code: 'analytics_export_invalid',
      );
    }
    final DateTime at = (exportedAt ?? DateTime.now()).toUtc();
    return <String, Object?>{
      if (exportId.isNotEmpty) 'id': exportId,
      'tenant_id': tenantId,
      'run_id': runId,
      'artifact_label': artifactLabel.trim(),
      'format': format.wireValue,
      'destination': destination.wireValue,
      'byte_size': byteSize,
      'checksum': _trimmed(checksum),
      'note': _trimmed(note),
      'exported_at': at.toIso8601String(),
      'exported_by': exportedBy,
      'created_at': at.toIso8601String(),
    };
  }

  /// Materializes an export from a local row.
  factory AnalyticsExport.fromRow(Map<String, Object?> row) => AnalyticsExport(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    runId: row['run_id']! as String,
    artifactLabel: row['artifact_label']! as String,
    format: ExportFormat.fromWire(
      (row['format'] as String?) ?? ExportFormat.csv.wireValue,
    ),
    destination: ExportDestination.fromWire(
      (row['destination'] as String?) ?? ExportDestination.download.wireValue,
    ),
    exportedAt: _parse(row['exported_at']),
    exportedBy: row['exported_by']! as String,
    byteSize: row['byte_size'] as int?,
    checksum: row['checksum'] as String?,
    note: row['note'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The run the artefact came from.
  final String runId;

  /// The file name.
  final String artifactLabel;

  /// The format it left in.
  final ExportFormat format;

  /// Where it went.
  final ExportDestination destination;

  /// When it left, UTC.
  final DateTime exportedAt;

  /// Who took it.
  final String exportedBy;

  /// How large it was, in bytes.
  final int? byteSize;

  /// A digest of the artefact, when the warehouse produced one.
  final String? checksum;

  /// Why it was taken.
  final String? note;

  /// When the row was raised, UTC.
  final DateTime? createdAt;
}

String? _trimmed(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _formatDate(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

/// Parses a date-only column into UTC midnight.
///
/// The parts are read directly rather than through `DateTime.parse`, because a
/// date-only string parses as local midnight and a device west of UTC would then
/// report the previous month's rollup.
DateTime _parseDate(Object? value) {
  if (value is String) {
    final List<String> parts = value.split('-');
    if (parts.length == 3) {
      final int? year = int.tryParse(parts[0]);
      final int? month = int.tryParse(parts[1]);
      final int? day = int.tryParse(parts[2]);
      if (year != null && month != null && day != null) {
        return DateTime.utc(year, month, day);
      }
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

int _lastDayOfMonth(int year, int month) =>
    DateTime.utc(year, month + 1, 0).day;

DateTime _parse(Object? value) => value is String
    ? DateTime.parse(value).toUtc()
    : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _parseNullable(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.parse(value);
  }
  return 0;
}
