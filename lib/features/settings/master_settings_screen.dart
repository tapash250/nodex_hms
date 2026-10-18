/// Master Settings & AI Configuration Hub (Module 39).
///
/// Five tabs, one per clause of the scope: the hospital's configuration, its
/// branding, its department tree, its tariff masters and its AI routing
/// profiles. Everything shown here is configuration, so nothing is edited in
/// place: a settings profile and a branding asset are superseded, a department
/// is archived, a tariff and a routing profile are retired. What is in force
/// today has to stay explainable tomorrow, which is why the versions are listed
/// rather than hidden.
///
/// Every change on this screen goes through `_stepUp` first. The specification
/// asks for Multi-Factor Authentication on configuration changes, and a screen
/// that asked for a code and then ignored the answer would be theatre: the
/// assertion the verifier returns is what the use case demands, and the use
/// case refuses without one.
///
/// Nothing here is computed twice. The contrast of a branding pair, the depth
/// of a department, the tax on a tariff and whether a tariff is live are read
/// from the domain, not re-derived beside it, so the screen and the invoice
/// cannot disagree about what a service costs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/security/second_factor.dart';
import 'package:nodex_hms/domain/settings/settings.dart';
import 'package:nodex_hms/domain/settings/settings_use_cases.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The master settings and AI configuration hub.
class MasterSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MasterSettingsScreen({super.key});

  @override
  ConsumerState<MasterSettingsScreen> createState() =>
      _MasterSettingsScreenState();
}

class _MasterSettingsScreenState extends ConsumerState<MasterSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  MasterSettingsBoard? _board;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) {
      setState(() {
        _error = 'Session is not ready.';
        _loading = false;
      });
      return;
    }
    try {
      final MasterSettingsBoard board = await ref
          .read(readMasterSettingsUseCaseProvider)
          .board(tenantId: tenantId, policy: session.authorization);
      if (!mounted) {
        return;
      }
      setState(() {
        _board = board;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _snack(error.toString());
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? get _userId => ref.read(sessionProvider).user?.userId;

  String? get _facilityId {
    final Set<String> facilities =
        ref.read(sessionProvider).snapshot?.facilityIds ?? const <String>{};
    return facilities.isEmpty ? null : facilities.first;
  }

  /// Asks for a second factor and returns the assertion, or null.
  ///
  /// The code never reaches a use case: it is handed to the verifier, and what
  /// comes back is evidence with an identity, a purpose and an expiry.
  Future<SecondFactorAssertion?> _stepUp(String purpose) async {
    final String? tenantId = ref.read(sessionProvider).tenantId;
    final String? userId = _userId;
    if (tenantId == null || userId == null) {
      return null;
    }
    final String? code = await _askCode(purpose);
    if (code == null) {
      return null;
    }
    final SecondFactorAssertion? assertion = await ref
        .read(secondFactorVerifierProvider)
        .verify(
          tenantId: tenantId,
          userId: userId,
          purpose: purpose,
          code: code,
        );
    if (assertion == null) {
      _snack('That second factor was refused.');
    }
    return assertion;
  }

  Future<String?> _askCode(String purpose) async {
    final TextEditingController controller = TextEditingController();
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Prove it is you'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('This change belongs to $purpose.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Six-digit code',
                counterText: '',
              ),
              maxLength: 6,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    final String value = controller.text.trim();
    controller.dispose();
    return accepted == true && value.isNotEmpty ? value : null;
  }

  Future<String?> _askValue({
    required String title,
    required String label,
    required String confirm,
  }) async {
    final TextEditingController controller = TextEditingController();
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(labelText: label),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    final String value = controller.text.trim();
    controller.dispose();
    if (accepted != true || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<Map<String, String>?> _askFields({
    required String title,
    required List<_FieldSpec> fields,
    String confirm = 'Save',
  }) async {
    final Map<String, String>? values = await showDialog<Map<String, String>>(
      context: context,
      builder: (BuildContext context) =>
          _FieldsDialog(title: title, fields: fields, confirm: confirm),
    );
    return values;
  }

  // ---------------------------------------------------------------- settings

  Future<void> _draftProfile() async {
    final String? tenantId = ref.read(sessionProvider).tenantId;
    final String? userId = _userId;
    if (tenantId == null || userId == null) {
      return;
    }
    final Map<String, String>? fields = await _askFields(
      title: 'New configuration version',
      confirm: 'Draft',
      fields: const <_FieldSpec>[
        _FieldSpec('hospital_name', 'Hospital name'),
        _FieldSpec('timezone', 'Timezone (IANA)', initial: 'Asia/Kolkata'),
        _FieldSpec('default_locale', 'Locale', initial: 'en-IN'),
        _FieldSpec(
          'date_format',
          'Date format',
          initial: 'dd-mm-yyyy',
          choices: <String, String>{
            'Day-month-year': 'dd-mm-yyyy',
            'Month-day-year': 'mm-dd-yyyy',
            'Year-month-day': 'yyyy-mm-dd',
          },
        ),
        _FieldSpec('currency_code', 'Currency', initial: 'INR'),
        _FieldSpec(
          'currency_minor_units',
          'Currency decimals',
          initial: '2',
          numeric: true,
        ),
        _FieldSpec(
          'fiscal_year_start_month',
          'Fiscal year opens (month)',
          initial: '4',
          numeric: true,
        ),
        _FieldSpec(
          'appointment_slot_minutes',
          'Appointment slot (minutes)',
          initial: '15',
          numeric: true,
        ),
        _FieldSpec(
          'session_idle_minutes',
          'Session idle lock (minutes)',
          initial: '15',
          numeric: true,
        ),
        _FieldSpec(
          'require_two_factor',
          'Demand a second factor',
          initial: 'true',
          choices: <String, String>{'Yes': 'true', 'No': 'false'},
        ),
        _FieldSpec(
          'scope',
          'Scope',
          initial: 'hospital',
          choices: <String, String>{
            'Hospital-wide': 'hospital',
            'This facility': 'facility',
          },
        ),
      ],
    );
    if (fields == null) {
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeConfigure,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(draftSettingsProfileUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            tenantId: tenantId,
            hospitalName: fields['hospital_name'] ?? '',
            createdBy: userId,
            timezone: fields['timezone'] ?? 'UTC',
            defaultLocale: fields['default_locale'] ?? 'en',
            dateFormat: DateFormatStyle.fromWire(
              fields['date_format'] ?? 'dd-mm-yyyy',
            ),
            currencyCode: fields['currency_code'] ?? 'INR',
            currencyMinorUnits: _int(fields['currency_minor_units'], 2),
            fiscalYearStartMonth: _int(fields['fiscal_year_start_month'], 4),
            appointmentSlotMinutes: _int(
              fields['appointment_slot_minutes'],
              15,
            ),
            sessionIdleMinutes: _int(fields['session_idle_minutes'], 15),
            requireTwoFactor: fields['require_two_factor'] == 'true',
            facilityId: fields['scope'] == 'facility' ? _facilityId : null,
          );
    });
  }

  Future<void> _activateProfile(SettingsProfile profile) async {
    final String? userId = _userId;
    if (userId == null) {
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeConfigure,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(activateSettingsProfileUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            profile: profile,
            activatedBy: userId,
          );
    });
  }

  // ---------------------------------------------------------------- branding

  Future<void> _draftBranding() async {
    final String? tenantId = ref.read(sessionProvider).tenantId;
    final String? userId = _userId;
    if (tenantId == null || userId == null) {
      return;
    }
    final Map<String, String>? fields = await _askFields(
      title: 'New branding proposal',
      confirm: 'Draft',
      fields: const <_FieldSpec>[
        _FieldSpec(
          'asset_kind',
          'Kind',
          initial: 'logo',
          choices: <String, String>{
            'Logo': 'logo',
            'Letterhead': 'letterhead',
            'Favicon': 'favicon',
            'Watermark': 'watermark',
          },
        ),
        _FieldSpec('label', 'Label', initial: 'Hospital mark'),
        _FieldSpec('primary_color', 'Primary colour', initial: '#0B5FFF'),
        _FieldSpec('secondary_color', 'Secondary colour', initial: '#FFFFFF'),
        _FieldSpec('storage_path', 'Storage path'),
        _FieldSpec('checksum', 'File digest'),
        _FieldSpec('mime_type', 'Media type', initial: 'image/svg+xml'),
        _FieldSpec('byte_size', 'Size in bytes', numeric: true),
      ],
    );
    if (fields == null) {
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeBranding,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(draftBrandingAssetUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            tenantId: tenantId,
            kind: BrandingAssetKind.fromWire(fields['asset_kind'] ?? 'logo'),
            label: fields['label'] ?? '',
            primaryColor: fields['primary_color'] ?? '#000000',
            secondaryColor: fields['secondary_color'] ?? '#FFFFFF',
            createdBy: userId,
            storagePath: _nullIfBlank(fields['storage_path']),
            checksum: _nullIfBlank(fields['checksum']),
            mimeType: _nullIfBlank(fields['mime_type']),
            byteSize: int.tryParse(fields['byte_size'] ?? ''),
            facilityId: _facilityId,
          );
    });
  }

  Future<void> _publishBranding(BrandingAsset asset) async {
    final String? userId = _userId;
    if (userId == null) {
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeBranding,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(publishBrandingAssetUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            asset: asset,
            activatedBy: userId,
          );
    });
  }

  // ------------------------------------------------------------- departments

  Future<void> _defineDepartment() async {
    final String? tenantId = ref.read(sessionProvider).tenantId;
    final String? userId = _userId;
    final MasterSettingsBoard? board = _board;
    if (tenantId == null || userId == null) {
      return;
    }
    final Map<String, String> parents = <String, String>{
      'At the top': '',
      for (final DepartmentNode node in board?.activeDepartments ?? const [])
        board?.pathOf(node.id) ?? node.code: node.id,
    };
    final Map<String, String>? fields = await _askFields(
      title: 'Add a department',
      confirm: 'Add',
      fields: <_FieldSpec>[
        const _FieldSpec('code', 'Code'),
        const _FieldSpec('name', 'Name'),
        const _FieldSpec(
          'kind',
          'Kind',
          initial: 'clinical',
          choices: <String, String>{
            'Clinical': 'clinical',
            'Diagnostic': 'diagnostic',
            'Therapeutic': 'therapeutic',
            'Support': 'support',
            'Administrative': 'administrative',
          },
        ),
        _FieldSpec('parent_id', 'Sits under', choices: parents),
        const _FieldSpec('cost_centre', 'Cost centre'),
        const _FieldSpec(
          'is_billable',
          'Billed',
          initial: 'false',
          choices: <String, String>{'Yes': 'true', 'No': 'false'},
        ),
        const _FieldSpec(
          'sort_order',
          'Sort order',
          initial: '0',
          numeric: true,
        ),
      ],
    );
    if (fields == null) {
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeConfigure,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(defineDepartmentUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            tenantId: tenantId,
            code: fields['code'] ?? '',
            name: fields['name'] ?? '',
            createdBy: userId,
            kind: DepartmentKind.fromWire(fields['kind'] ?? 'clinical'),
            parentId: _nullIfBlank(fields['parent_id']),
            facilityId: _facilityId,
            costCentre: _nullIfBlank(fields['cost_centre']),
            isBillable: fields['is_billable'] == 'true',
            sortOrder: _int(fields['sort_order'], 0),
          );
    });
  }

  Future<void> _archiveDepartment(DepartmentNode department) async {
    final String? userId = _userId;
    if (userId == null) {
      return;
    }
    final String? reason = await _askValue(
      title: 'Close the department',
      label: 'Why',
      confirm: 'Close',
    );
    if (reason == null) {
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeConfigure,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(closeDepartmentUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            department: department,
            reason: reason,
            userId: userId,
          );
    });
  }

  // ----------------------------------------------------------------- tariffs

  Future<void> _setTariff() async {
    final String? tenantId = ref.read(sessionProvider).tenantId;
    final String? userId = _userId;
    final MasterSettingsBoard? board = _board;
    if (tenantId == null || userId == null) {
      return;
    }
    final Map<String, String> departments = <String, String>{
      'Nobody yet': '',
      for (final DepartmentNode node in board?.activeDepartments ?? const [])
        board?.pathOf(node.id) ?? node.code: node.id,
    };
    final Map<String, String>? fields = await _askFields(
      title: 'Price a service',
      confirm: 'Draft',
      fields: <_FieldSpec>[
        const _FieldSpec('code', 'Code'),
        const _FieldSpec('service_name', 'Service name'),
        const _FieldSpec(
          'category',
          'Category',
          initial: 'consultation',
          choices: <String, String>{
            'Consultation': 'consultation',
            'Procedure': 'procedure',
            'Investigation': 'investigation',
            'Room': 'room',
            'Pharmacy': 'pharmacy',
            'Consumable': 'consumable',
            'Package': 'package',
          },
        ),
        _FieldSpec('department_id', 'Department', choices: departments),
        const _FieldSpec('currency_code', 'Currency', initial: 'INR'),
        const _FieldSpec(
          'amount_minor',
          'Amount in minor units',
          numeric: true,
        ),
        const _FieldSpec(
          'tax_rate_bps',
          'Tax in basis points',
          initial: '0',
          numeric: true,
        ),
        const _FieldSpec(
          'insurance_capable',
          'Insurer may be billed',
          initial: 'true',
          choices: <String, String>{'Yes': 'true', 'No': 'false'},
        ),
        const _FieldSpec(
          'effective_from',
          'Applies from (YYYY-MM-DD)',
          initial: '2026-04-01',
        ),
        const _FieldSpec('effective_to', 'Applies to (YYYY-MM-DD)'),
      ],
    );
    if (fields == null) {
      return;
    }
    final DateTime? from = _date(fields['effective_from']);
    if (from == null) {
      _snack('A start date is required.');
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeTariff,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(setTariffUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            tenantId: tenantId,
            code: fields['code'] ?? '',
            serviceName: fields['service_name'] ?? '',
            effectiveFrom: from,
            createdBy: userId,
            category: TariffCategory.fromWire(
              fields['category'] ?? 'consultation',
            ),
            amountMinor: _int(fields['amount_minor'], 0),
            taxRateBps: _int(fields['tax_rate_bps'], 0),
            insuranceCapable: fields['insurance_capable'] == 'true',
            currencyCode: fields['currency_code'] ?? 'INR',
            effectiveTo: _date(fields['effective_to']),
            departmentId: _nullIfBlank(fields['department_id']),
            facilityId: _facilityId,
          );
    });
  }

  Future<void> _approveTariff(BillingTariff tariff) async {
    final String? userId = _userId;
    if (userId == null) {
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeTariff,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(approveTariffUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            tariff: tariff,
            approvedBy: userId,
          );
    });
  }

  Future<void> _retireTariff(BillingTariff tariff) async {
    final String? userId = _userId;
    if (userId == null) {
      return;
    }
    final String? reason = await _askValue(
      title: 'Retire the tariff',
      label: 'Why',
      confirm: 'Retire',
    );
    if (reason == null) {
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeTariff,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(retireTariffUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            tariff: tariff,
            reason: reason,
            userId: userId,
          );
    });
  }

  // -------------------------------------------------------------- ai routing

  Future<void> _defineRoutingProfile() async {
    final String? tenantId = ref.read(sessionProvider).tenantId;
    final String? userId = _userId;
    if (tenantId == null || userId == null) {
      return;
    }
    final Map<String, String>? fields = await _askFields(
      title: 'Propose a routing profile',
      confirm: 'Draft',
      fields: const <_FieldSpec>[
        _FieldSpec('profile_code', 'Profile code', initial: 'scribe-standard'),
        _FieldSpec('display_name', 'Display name', initial: 'Scribe standard'),
        _FieldSpec(
          'task_kind',
          'Task',
          initial: 'scribe',
          choices: <String, String>{
            'Ambient scribe': 'scribe',
            'Clinical coding': 'coding',
            'Triage support': 'triage',
            'Summarisation': 'summarisation',
            'Translation': 'translation',
            'Imaging support': 'imaging',
          },
        ),
        _FieldSpec(
          'primary_model_key',
          'Primary model key',
          initial: 'stub_clinical_note_v1',
        ),
        _FieldSpec('fallback_model_key', 'Fallback model key'),
        _FieldSpec(
          'temperature_bps',
          'Temperature in basis points',
          initial: '2000',
          numeric: true,
        ),
        _FieldSpec(
          'max_output_tokens',
          'Most it may emit (tokens)',
          initial: '1024',
          numeric: true,
        ),
        _FieldSpec(
          'data_residency',
          'Data residency',
          initial: 'in_country',
          choices: <String, String>{
            'In country': 'in_country',
            'In region': 'regional',
            'Global': 'global',
          },
        ),
        _FieldSpec(
          'redact_phi',
          'Redact before sending',
          initial: 'true',
          choices: <String, String>{'Yes': 'true', 'No': 'false'},
        ),
      ],
    );
    if (fields == null) {
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeAiRouting,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(defineRoutingProfileUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            tenantId: tenantId,
            profileCode: fields['profile_code'] ?? '',
            displayName: fields['display_name'] ?? '',
            primaryModelKey: fields['primary_model_key'] ?? '',
            createdBy: userId,
            taskKind: AiTaskKind.fromWire(fields['task_kind'] ?? 'scribe'),
            fallbackModelKey: _nullIfBlank(fields['fallback_model_key']),
            temperatureBps: _int(fields['temperature_bps'], 2000),
            maxOutputTokens: _int(fields['max_output_tokens'], 1024),
            dataResidency: AiDataResidency.fromWire(
              fields['data_residency'] ?? 'in_country',
            ),
            redactPhi: fields['redact_phi'] == 'true',
            facilityId: _facilityId,
          );
    });
  }

  Future<void> _activateRouting(AiRoutingProfile profile) async {
    final String? userId = _userId;
    if (userId == null) {
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeAiRouting,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(activateRoutingProfileUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            profile: profile,
            activatedBy: userId,
          );
    });
  }

  Future<void> _retireRouting(AiRoutingProfile profile) async {
    final String? userId = _userId;
    if (userId == null) {
      return;
    }
    final String? reason = await _askValue(
      title: 'Retire the routing profile',
      label: 'Why',
      confirm: 'Retire',
    );
    if (reason == null) {
      return;
    }
    final SecondFactorAssertion? assertion = await _stepUp(
      settingsPurposeAiRouting,
    );
    if (assertion == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(retireRoutingProfileUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            secondFactor: assertion,
            profile: profile,
            reason: reason,
            userId: userId,
          );
    });
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final MasterSettingsBoard? board = _board;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Master settings'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const <Widget>[
            Tab(text: 'Configuration', icon: Icon(Icons.public_outlined)),
            Tab(text: 'Branding', icon: Icon(Icons.palette_outlined)),
            Tab(text: 'Departments', icon: Icon(Icons.account_tree_outlined)),
            Tab(text: 'Tariffs', icon: Icon(Icons.receipt_long_outlined)),
            Tab(text: 'AI routing', icon: Icon(Icons.alt_route_outlined)),
          ],
        ),
      ),
      body: _body(board),
    );
  }

  Widget _body(MasterSettingsBoard? board) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final String? error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error, textAlign: TextAlign.center),
        ),
      );
    }
    if (board == null) {
      return const Center(child: Text('Nothing to show.'));
    }
    return TabBarView(
      controller: _tabs,
      children: <Widget>[
        _configurationTab(board),
        _brandingTab(board),
        _departmentsTab(board),
        _tariffsTab(board),
        _routingTab(board),
      ],
    );
  }

  Widget _configurationTab(MasterSettingsBoard board) {
    final SettingsProfile? active = board.configurationFor();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(active?.hospitalName ?? 'No configuration in force'),
              subtitle: Text(
                active == null
                    ? 'Every device is rendering by its own defaults.'
                    : <String>[
                        'Version ${active.version}',
                        active.isHospitalWide
                            ? 'Hospital-wide'
                            : 'One facility',
                        '${active.timezone} · ${active.defaultLocale}',
                        '${active.currencyCode} to ${active.currencyMinorUnits} decimals',
                        'Fiscal year opens in month ${active.fiscalYearStartMonth}',
                        '${active.appointmentSlotMinutes}-minute slots',
                        'Locks after ${active.sessionIdleMinutes} idle minutes',
                        active.requireTwoFactor
                            ? 'Second factor demanded'
                            : 'Second factor not demanded',
                      ].join('\n'),
              ),
              isThreeLine: true,
            ),
          ),
          if (board.departmentsWithoutCostCentre.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.report_outlined),
                title: Text(
                  '${board.departmentsWithoutCostCentre.length} departments '
                  'with no cost centre',
                ),
                subtitle: Text(
                  board.departmentsWithoutCostCentre
                      .map((DepartmentNode node) => node.code)
                      .join(', '),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text('Versions', style: Theme.of(context).textTheme.titleMedium),
          for (final SettingsProfile profile in board.historyFor())
            ListTile(
              leading: Icon(
                profile.isActive
                    ? Icons.radio_button_checked
                    : Icons.history_outlined,
              ),
              title: Text('v${profile.version} · ${profile.hospitalName}'),
              subtitle: Text(
                '${profile.status.label} · '
                '${profile.isHospitalWide ? 'hospital-wide' : 'one facility'}',
              ),
              trailing: profile.isDraft || profile.isActive
                  ? TextButton(
                      onPressed: profile.isActive
                          ? null
                          : () => _activateProfile(profile),
                      child: const Text('Put in force'),
                    )
                  : null,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _draftProfile,
        icon: const Icon(Icons.add),
        label: const Text('New version'),
      ),
    );
  }

  Widget _brandingTab(MasterSettingsBoard board) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          for (final BrandingAssetKind kind in BrandingAssetKind.values)
            Card(
              child: ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(kind.label),
                subtitle: Text(switch (board.brandingFor(kind: kind)) {
                  final BrandingAsset asset => <String>[
                    asset.label,
                    '${asset.primaryColor} on ${asset.secondaryColor}',
                    'Contrast ${asset.contrastRatio.toStringAsFixed(1)}:1${brandingContrastIsReadable(asset) ? '' : ' — hard to read'}',
                    asset.hasFile ? 'File held' : 'No file uploaded yet',
                  ].join('\n'),
                  _ => 'Nothing in use.',
                }),
                isThreeLine: true,
              ),
            ),
          if (board.unreadableBranding.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.contrast_outlined),
                title: const Text('Colours that cannot be told apart'),
                subtitle: Text(
                  board.unreadableBranding
                      .map((BrandingAsset asset) => asset.label)
                      .join(', '),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text('Proposals', style: Theme.of(context).textTheme.titleMedium),
          for (final BrandingAsset asset in board.assets)
            ListTile(
              leading: const Icon(Icons.drafts_outlined),
              title: Text('${asset.kind.label} · ${asset.label}'),
              subtitle: Text(asset.status.label),
              trailing: asset.isDraft || asset.isActive
                  ? TextButton(
                      onPressed: asset.isActive
                          ? null
                          : () => _publishBranding(asset),
                      child: const Text('Put in use'),
                    )
                  : null,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _draftBranding,
        icon: const Icon(Icons.upload_outlined),
        label: const Text('New artwork'),
      ),
    );
  }

  Widget _departmentsTab(MasterSettingsBoard board) {
    Widget branch(DepartmentNode node, int depth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(left: depth * 16),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(
                node.isTerminal
                    ? Icons.folder_off_outlined
                    : Icons.folder_outlined,
              ),
              title: Text('${node.code} · ${node.name}'),
              subtitle: Text(
                <String>[
                  node.kind.label,
                  node.hasCostCentre
                      ? 'Cost centre ${node.costCentre}'
                      : 'No cost centre',
                  if (node.isBillable) 'Billed',
                  'Level ${board.levelOf(node.id)}',
                  board.pathOf(node.id),
                ].join(' · '),
              ),
              isThreeLine: true,
              trailing: node.isActive
                  ? TextButton(
                      onPressed: () => _archiveDepartment(node),
                      child: const Text('Close'),
                    )
                  : Text(node.status.label),
            ),
          ),
          for (final DepartmentNode child in board.childrenOf(node.id))
            branch(child, depth + 1),
        ],
      );
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          for (final DepartmentNode root in board.roots) branch(root, 0),
          const SizedBox(height: 8),
          Text('Closed', style: Theme.of(context).textTheme.titleMedium),
          for (final DepartmentNode node in board.departments)
            if (node.isTerminal)
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: Text('${node.code} · ${node.name}'),
                subtitle: Text(node.archiveReason ?? 'Closed'),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _defineDepartment,
        icon: const Icon(Icons.add),
        label: const Text('Add department'),
      ),
    );
  }

  Widget _tariffsTab(MasterSettingsBoard board) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (board.tariffsAwaitingApproval.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.pending_actions_outlined),
                title: Text(
                  '${board.tariffsAwaitingApproval.length} waiting on an '
                  'approver',
                ),
              ),
            ),
          for (final BillingTariff tariff in board.tariffs)
            ListTile(
              leading: Icon(
                tariffIsLive(tariff, at: board.asOf)
                    ? Icons.check_circle_outline
                    : Icons.history_outlined,
              ),
              title: Text('${tariff.code} · ${tariff.serviceName}'),
              subtitle: Text(
                <String>[
                  tariff.category.label,
                  'Net ${_money(board, tariff.amountMinor, tariff.currencyCode)}',
                  'Tax ${tariff.taxRatePercent.toStringAsFixed(2)}%',
                  'Gross ${_money(board, tariff.grossMinor, tariff.currencyCode)}',
                  _windowLabel(tariff),
                  tariff.status.label,
                ].join(' · '),
              ),
              isThreeLine: true,
              trailing: switch (tariff.status) {
                TariffStatus.draft => TextButton(
                  onPressed: () => _approveTariff(tariff),
                  child: const Text('Approve'),
                ),
                TariffStatus.active => TextButton(
                  onPressed: () => _retireTariff(tariff),
                  child: const Text('Retire'),
                ),
                TariffStatus.retired => null,
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _setTariff,
        icon: const Icon(Icons.add),
        label: const Text('Price a service'),
      ),
    );
  }

  Widget _routingTab(MasterSettingsBoard board) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          for (final AiTaskKind kind in AiTaskKind.values)
            ListTile(
              leading: const Icon(Icons.alt_route_outlined),
              title: Text(kind.label),
              subtitle: Text(switch (board.routingFor(taskKind: kind)) {
                final AiRoutingProfile profile => <String>[
                  profile.profileCode,
                  'Model ${profile.primaryModelKey}',
                  profile.hasFallback
                      ? 'Fallback ${profile.fallbackModelKey}'
                      : 'No fallback',
                  'Temperature ${profile.temperature.toStringAsFixed(2)}',
                  'Up to ${profile.maxOutputTokens} tokens',
                  profile.dataResidency.label,
                  profile.redactPhi ? 'Redacted' : 'Not redacted',
                ].join(' · '),
                _ => 'Nothing routing this task.',
              }),
              isThreeLine: true,
            ),
          if (board.routingProfilesWithoutFallback.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: const Text('Routing without a fallback'),
                subtitle: Text(
                  board.routingProfilesWithoutFallback
                      .map((AiRoutingProfile profile) => profile.profileCode)
                      .join(', '),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text('Profiles', style: Theme.of(context).textTheme.titleMedium),
          for (final AiRoutingProfile profile in board.routingProfiles)
            ListTile(
              leading: const Icon(Icons.memory_outlined),
              title: Text('${profile.profileCode} · ${profile.displayName}'),
              subtitle: Text(
                '${profile.status.label} · ${profile.taskKind.label}',
              ),
              trailing: switch (profile.status) {
                RoutingProfileStatus.draft => TextButton(
                  onPressed: () => _activateRouting(profile),
                  child: const Text('Put to work'),
                ),
                RoutingProfileStatus.active => TextButton(
                  onPressed: () => _retireRouting(profile),
                  child: const Text('Retire'),
                ),
                RoutingProfileStatus.retired => null,
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _defineRoutingProfile,
        icon: const Icon(Icons.add),
        label: const Text('Propose a profile'),
      ),
    );
  }
}

/// One field in a prompted form.
final class _FieldSpec {
  const _FieldSpec(
    this.key,
    this.label, {
    this.initial = '',
    this.choices,
    this.numeric = false,
  });

  /// Identifier the answer is filed under.
  final String key;

  /// What the field is called.
  final String label;

  /// The value the field opens with.
  final String initial;

  /// The options, when the field is a choice. Keys are labels, values wire values.
  final Map<String, String>? choices;

  /// Whether the keyboard should be numeric.
  final bool numeric;
}

/// Prompts for a set of fields and returns the answers.
class _FieldsDialog extends StatefulWidget {
  const _FieldsDialog({
    required this.title,
    required this.fields,
    required this.confirm,
  });

  final String title;
  final List<_FieldSpec> fields;
  final String confirm;

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{
        for (final _FieldSpec field in widget.fields)
          field.key: TextEditingController(text: field.initial),
      };
  late final Map<String, String> _choices = <String, String>{
    for (final _FieldSpec field in widget.fields)
      field.key: field.initial.isEmpty
          ? (field.choices?.values.first ?? '')
          : field.initial,
  };

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final _FieldSpec field in widget.fields)
              if (field.choices case final Map<String, String> options)
                DropdownButtonFormField<String>(
                  initialValue: _choices[field.key],
                  decoration: InputDecoration(labelText: field.label),
                  items: <DropdownMenuItem<String>>[
                    for (final MapEntry<String, String> entry
                        in options.entries)
                      DropdownMenuItem<String>(
                        value: entry.value,
                        child: Text(entry.key),
                      ),
                  ],
                  onChanged: (String? value) => setState(() {
                    _choices[field.key] = value ?? '';
                  }),
                )
              else
                TextField(
                  controller: _controllers[field.key],
                  keyboardType: field.numeric
                      ? TextInputType.number
                      : TextInputType.text,
                  decoration: InputDecoration(labelText: field.label),
                ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final Map<String, String> answers = <String, String>{
              for (final _FieldSpec field in widget.fields)
                field.key: field.choices == null
                    ? (_controllers[field.key]?.text.trim() ?? '')
                    : (_choices[field.key] ?? ''),
            };
            Navigator.of(context).pop(answers);
          },
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

String _windowLabel(BillingTariff tariff) {
  final DateTime? to = tariff.effectiveTo;
  return to == null
      ? 'From ${_formatDate(tariff.effectiveFrom)}'
      : '${_formatDate(tariff.effectiveFrom)} to ${_formatDate(to)}';
}

String _money(MasterSettingsBoard board, int minorUnits, String currencyCode) {
  final SettingsProfile? profile = board.configurationFor();
  if (profile != null) {
    return profile.formatMoney(minorUnits);
  }
  return '$currencyCode ${(minorUnits / 100).toStringAsFixed(2)}';
}

String _formatDate(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

int _int(String? value, int fallback) => int.tryParse(value ?? '') ?? fallback;

String? _nullIfBlank(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Parses a `YYYY-MM-DD` field into UTC midnight, or null.
///
/// The parts are read directly rather than through `DateTime.parse`, so a device
/// west of UTC does not turn the first of the month into the last day of the one
/// before.
DateTime? _date(String? value) {
  if (value == null) {
    return null;
  }
  final List<String> parts = value.trim().split('-');
  if (parts.length != 3) {
    return null;
  }
  final int? year = int.tryParse(parts[0]);
  final int? month = int.tryParse(parts[1]);
  final int? day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return null;
  }
  return DateTime.utc(year, month, day);
}
