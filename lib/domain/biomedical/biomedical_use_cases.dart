/// Biomedical assets & calibration use cases (Module 29).
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/biomedical/biomedical.dart';
import 'package:nodex_hms/domain/biomedical/biomedical_repository.dart';

/// Registers a serialized instrument.
final class RegisterAssetUseCase {
  /// Creates the use case.
  RegisterAssetUseCase({required this._repository});

  final BiomedicalRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String createdBy,
    required String facilityId,
    required String assetTag,
    required String name,
    String? departmentId,
    String? category,
    String? manufacturer,
    String? modelNo,
    String? serialNo,
    AssetCriticality criticality = AssetCriticality.medium,
    AssetStatus status = AssetStatus.inService,
    DateTime? commissionedOn,
    DateTime? warrantyUntil,
    String? notes,
    String assetId = '',
  }) async {
    policy.require(NodexPermissions.biomedicalManage);
    return _repository.registerAsset(
      BiomedicalAsset.registerRow(
        tenantId: tenantId,
        createdBy: createdBy,
        facilityId: facilityId,
        assetTag: assetTag,
        name: name,
        departmentId: departmentId,
        category: category,
        manufacturer: manufacturer,
        modelNo: modelNo,
        serialNo: serialNo,
        criticality: criticality,
        status: status,
        commissionedOn: commissionedOn,
        warrantyUntil: warrantyUntil,
        notes: notes,
        assetId: assetId,
      ),
    );
  }
}

/// Updates an asset. A decommissioned asset is a retained, frozen record.
final class UpdateAssetUseCase {
  /// Creates the use case.
  UpdateAssetUseCase({required this._repository});

  final BiomedicalRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required BiomedicalAsset asset,
    required String facilityId,
    required String assetTag,
    required String name,
    String? departmentId,
    String? category,
    String? manufacturer,
    String? modelNo,
    String? serialNo,
    AssetCriticality? criticality,
    AssetStatus? status,
    DateTime? commissionedOn,
    DateTime? warrantyUntil,
    String? notes,
  }) async {
    policy.require(NodexPermissions.biomedicalManage);
    if (!asset.isEditable) {
      throw const AuthorizationError(
        message:
            'A decommissioned asset is retained as a historical record and '
            'cannot be edited.',
        code: 'biomedical_asset_immutable',
      );
    }
    await _repository.updateAsset(
      asset.id,
      biomedicalAssetChanges(
        facilityId: facilityId,
        assetTag: assetTag,
        name: name,
        departmentId: departmentId,
        category: category,
        manufacturer: manufacturer,
        modelNo: modelNo,
        serialNo: serialNo,
        criticality: criticality,
        status: status,
        commissionedOn: commissionedOn,
        warrantyUntil: warrantyUntil,
        notes: notes,
      ),
    );
  }
}

/// Moves an asset between the live lifecycle states.
final class SetAssetStatusUseCase {
  /// Creates the use case.
  SetAssetStatusUseCase({required this._repository});

  final BiomedicalRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required BiomedicalAsset asset,
    required AssetStatus status,
  }) async {
    policy.require(NodexPermissions.biomedicalManage);
    if (asset.status.isDecommissioned) {
      throw const AuthorizationError(
        message: 'A decommissioned asset cannot change status.',
        code: 'biomedical_asset_immutable',
      );
    }
    if (status.isDecommissioned) {
      throw const ValidationError(
        message: 'Asset status change failed validation.',
        fieldErrors: <String, String>{
          'status': 'Use decommission to retire an asset.',
        },
        code: 'biomedical_status_invalid',
      );
    }
    await _repository.updateAsset(
      asset.id,
      biomedicalAssetStatusChanges(status),
    );
  }
}

/// Decommissions an asset. The row is retained because tickets and service
/// records name it.
///
/// An asset with an open breakdown ticket may not be retired — the same rule
/// the database enforces, checked here so the answer is immediate offline.
final class DecommissionAssetUseCase {
  /// Creates the use case.
  DecommissionAssetUseCase({required this._repository});

  final BiomedicalRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required BiomedicalAsset asset,
  }) async {
    policy.require(NodexPermissions.biomedicalManage);
    if (asset.status.isDecommissioned) {
      throw const AuthorizationError(
        message: 'This asset is already decommissioned.',
        code: 'biomedical_asset_already_decommissioned',
      );
    }
    final List<BreakdownTicket> tickets = await _repository.listTickets(
      asset.tenantId,
      assetId: asset.id,
    );
    if (tickets.any((BreakdownTicket ticket) => ticket.isLive)) {
      throw const ValidationError(
        message: 'Asset retirement failed validation.',
        fieldErrors: <String, String>{
          'asset_id': 'Close the open breakdown ticket before decommissioning.',
        },
        code: 'biomedical_asset_open_ticket',
      );
    }
    await _repository.updateAsset(
      asset.id,
      biomedicalAssetDecommissionChanges(),
    );
  }
}

/// Raises a breakdown ticket against an instrument.
final class RaiseBreakdownUseCase {
  /// Creates the use case.
  RaiseBreakdownUseCase({required this._repository});

  final BiomedicalRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String createdBy,
    required String assetId,
    required String facilityId,
    required String reportedBy,
    required String symptom,
    TicketPriority priority = TicketPriority.medium,
    String ticketId = '',
  }) async {
    policy.require(NodexPermissions.biomedicalMaintain);
    final BiomedicalAsset? asset = await _repository.assetById(assetId);
    if (asset == null) {
      throw const ValidationError(
        message: 'Breakdown ticket failed validation.',
        fieldErrors: <String, String>{
          'asset_id': 'That instrument is not in the registry.',
        },
        code: 'biomedical_asset_missing',
      );
    }
    if (asset.status.isDecommissioned) {
      throw const ValidationError(
        message: 'Breakdown ticket failed validation.',
        fieldErrors: <String, String>{
          'asset_id': 'A decommissioned asset cannot fail in service.',
        },
        code: 'biomedical_asset_decommissioned',
      );
    }
    return _repository.registerTicket(
      BreakdownTicket.registerRow(
        tenantId: tenantId,
        createdBy: createdBy,
        assetId: assetId,
        facilityId: facilityId,
        reportedBy: reportedBy,
        symptom: symptom,
        priority: priority,
        ticketId: ticketId,
      ),
    );
  }
}

/// Advances a breakdown ticket one stage.
///
/// The stage order is the same rule the database enforces. Moving a ticket into
/// repair takes the instrument out of service, and resolving it returns the
/// instrument to service if it was under repair — the lifecycle follows the
/// work order.
final class AdvanceBreakdownUseCase {
  /// Creates the use case.
  AdvanceBreakdownUseCase({required this._repository});

  final BiomedicalRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required BreakdownTicket ticket,
    required TicketStatus to,
    String? resolutionNotes,
    String? cancellationReason,
  }) async {
    policy.require(NodexPermissions.biomedicalMaintain);
    if (!breakdownCanAdvance(ticket.status, to)) {
      throw ValidationError(
        message: 'Breakdown ticket failed validation.',
        fieldErrors: <String, String>{
          'status':
              'A ${ticket.status.label.toLowerCase()} ticket cannot move to '
              '${to.label.toLowerCase()}.',
        },
        code: 'biomedical_ticket_transition_invalid',
      );
    }
    if (to == TicketStatus.resolved &&
        (resolutionNotes == null || resolutionNotes.trim().isEmpty)) {
      throw const ValidationError(
        message: 'Breakdown ticket failed validation.',
        fieldErrors: <String, String>{
          'resolution_notes': 'Describe how the fault was resolved.',
        },
        code: 'biomedical_ticket_resolution_required',
      );
    }
    await _repository.updateTicket(
      ticket.id,
      ticketTransitionChanges(
        to: to,
        resolutionNotes: resolutionNotes,
        cancellationReason: cancellationReason,
      ),
    );
    final BiomedicalAsset? asset = await _repository.assetById(ticket.assetId);
    if (asset == null || asset.status.isDecommissioned) {
      return;
    }
    if (to == TicketStatus.inRepair &&
        asset.status != AssetStatus.underRepair) {
      await _repository.updateAsset(
        asset.id,
        biomedicalAssetStatusChanges(AssetStatus.underRepair),
      );
    } else if (to == TicketStatus.resolved &&
        asset.status == AssetStatus.underRepair) {
      await _repository.updateAsset(
        asset.id,
        biomedicalAssetStatusChanges(AssetStatus.inService),
      );
    }
  }
}

/// Records an append-only service event: a calibration, preventive service,
/// repair, safety test or inspection.
final class RecordMaintenanceUseCase {
  /// Creates the use case.
  RecordMaintenanceUseCase({required this._repository});

  final BiomedicalRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String assetId,
    required MaintenanceKind kind,
    required MaintenanceResult result,
    DateTime? performedAt,
    String? ticketId,
    String? performedBy,
    String? provider,
    DateTime? nextDueAt,
    String? reference,
    String? notes,
    String recordId = '',
  }) async {
    policy.require(NodexPermissions.biomedicalMaintain);
    final BiomedicalAsset? asset = await _repository.assetById(assetId);
    if (asset == null) {
      throw const ValidationError(
        message: 'Service record failed validation.',
        fieldErrors: <String, String>{
          'asset_id': 'That instrument is not in the registry.',
        },
        code: 'biomedical_asset_missing',
      );
    }
    return _repository.registerMaintenanceRecord(
      MaintenanceRecord.registerRow(
        tenantId: tenantId,
        assetId: assetId,
        kind: kind,
        result: result,
        performedAt: performedAt,
        ticketId: ticketId,
        performedBy: performedBy,
        provider: provider,
        nextDueAt: nextDueAt,
        reference: reference,
        notes: notes,
        recordId: recordId,
      ),
    );
  }
}

/// A board row: the instrument with its latest service and derived calibration
/// state.
@immutable
final class AssetBoardEntry {
  /// Creates a board row.
  const AssetBoardEntry({
    required this.asset,
    required this.lastService,
    required this.dueState,
    required this.openTicketCount,
  });

  /// The instrument.
  final BiomedicalAsset asset;

  /// The most recent service event, when any.
  final MaintenanceRecord? lastService;

  /// The derived calibration-due state.
  final CalibrationDueState dueState;

  /// How many breakdown tickets are still live.
  final int openTicketCount;
}

/// Reads the biomedical board and service history.
final class ReadBiomedicalUseCase {
  /// Creates the use case.
  ReadBiomedicalUseCase({required this._repository});

  final BiomedicalRepository _repository;

  /// The instruments for the tenant, excluding decommissioned unless
  /// [includeDecommissioned].
  Future<List<BiomedicalAsset>> assets({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? facilityId,
    String? departmentId,
    bool includeDecommissioned = false,
  }) async {
    policy.require(NodexPermissions.biomedicalRead);
    final List<BiomedicalAsset> items = await _repository.listAssets(
      tenantId,
      facilityId: facilityId,
      departmentId: departmentId,
    );
    return items
        .where(
          (BiomedicalAsset asset) =>
              includeDecommissioned || !asset.status.isDecommissioned,
        )
        .toList(growable: false);
  }

  /// Breakdown tickets, optionally for one asset, newest first.
  Future<List<BreakdownTicket>> tickets({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? assetId,
    bool liveOnly = false,
  }) async {
    policy.require(NodexPermissions.biomedicalRead);
    final List<BreakdownTicket> tickets = await _repository.listTickets(
      tenantId,
      assetId: assetId,
    );
    final List<BreakdownTicket> filtered =
        tickets
            .where((BreakdownTicket ticket) => !liveOnly || ticket.isLive)
            .toList(growable: false)
          ..sort(
            (BreakdownTicket a, BreakdownTicket b) =>
                b.reportedAt.compareTo(a.reportedAt),
          );
    return filtered;
  }

  /// The append-only service history for an asset, newest first.
  Future<List<MaintenanceRecord>> maintenanceHistory({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String assetId,
  }) async {
    policy.require(NodexPermissions.biomedicalRead);
    final List<MaintenanceRecord> records = await _repository
        .listMaintenanceRecords(tenantId, assetId: assetId);
    return records.toList(growable: false)..sort(
      (MaintenanceRecord a, MaintenanceRecord b) =>
          b.performedAt.compareTo(a.performedAt),
    );
  }

  /// The board: each instrument with its latest service, derived calibration
  /// state and open-ticket count, most urgent first.
  Future<List<AssetBoardEntry>> board({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? facilityId,
    DateTime? now,
  }) async {
    policy.require(NodexPermissions.biomedicalRead);
    final DateTime asOf = (now ?? DateTime.now().toUtc()).toUtc();
    final List<BiomedicalAsset> assets = await this.assets(
      policy: policy,
      tenantId: tenantId,
      facilityId: facilityId,
    );
    final List<BreakdownTicket> tickets = await _repository.listTickets(
      tenantId,
    );
    final List<MaintenanceRecord> records = await _repository
        .listMaintenanceRecords(tenantId);

    final List<AssetBoardEntry> board = <AssetBoardEntry>[];
    for (final BiomedicalAsset asset in assets) {
      MaintenanceRecord? lastService;
      DateTime? nextDue;
      DateTime? nextDueFrom;
      for (final MaintenanceRecord record in records) {
        if (record.assetId != asset.id) {
          continue;
        }
        if (lastService == null ||
            record.performedAt.isAfter(lastService.performedAt)) {
          lastService = record;
        }
        if (record.nextDueAt != null &&
            (nextDueFrom == null || record.performedAt.isAfter(nextDueFrom))) {
          nextDue = record.nextDueAt;
          nextDueFrom = record.performedAt;
        }
      }
      final int openTickets = tickets
          .where(
            (BreakdownTicket ticket) =>
                ticket.assetId == asset.id && ticket.isLive,
          )
          .length;
      board.add(
        AssetBoardEntry(
          asset: asset,
          lastService: lastService,
          dueState: calibrationDueState(nextDueAt: nextDue, now: asOf),
          openTicketCount: openTickets,
        ),
      );
    }
    board.sort((AssetBoardEntry a, AssetBoardEntry b) {
      final int severity = _dueSeverity(b.dueState) - _dueSeverity(a.dueState);
      if (severity != 0) {
        return severity;
      }
      return a.asset.assetTag.compareTo(b.asset.assetTag);
    });
    return board;
  }
}

int _dueSeverity(CalibrationDueState state) => switch (state) {
  CalibrationDueState.overdue => 3,
  CalibrationDueState.dueSoon => 2,
  CalibrationDueState.current => 1,
  CalibrationDueState.notScheduled => 0,
};
