/// Bio-medical waste management (Module 30).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/waste/waste.dart';
import 'package:nodex_hms/domain/waste/waste_use_cases.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The bio-medical waste board: the category catalogue, the generation logs,
/// the barcoded disposal certificates and the derived compliance gap.
class WasteManagementScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const WasteManagementScreen({super.key});

  @override
  ConsumerState<WasteManagementScreen> createState() =>
      _WasteManagementScreenState();
}

class _WasteManagementScreenState extends ConsumerState<WasteManagementScreen> {
  List<WasteCategory> _categories = const <WasteCategory>[];
  Map<String, WasteCategory> _byId = const <String, WasteCategory>{};
  List<WasteGenerationLog> _logs = const <WasteGenerationLog>[];
  List<DisposalCertificate> _certificates = const <DisposalCertificate>[];
  List<WasteCategoryCompliance> _compliance = const <WasteCategoryCompliance>[];
  final DateTime _from = _monthStart();
  final DateTime _to = _tomorrow();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
      final ReadWasteUseCase read = ref.read(readWasteUseCaseProvider);
      final List<WasteCategory> categories = await read.categories(
        policy: session.authorization,
        tenantId: tenantId,
        includeInactive: true,
      );
      final List<WasteGenerationLog> logs = await read.generationLogs(
        policy: session.authorization,
        tenantId: tenantId,
      );
      final List<DisposalCertificate> certificates = await read.certificates(
        policy: session.authorization,
        tenantId: tenantId,
        includeVoided: true,
      );
      final List<WasteCategoryCompliance> compliance = await read.compliance(
        policy: session.authorization,
        tenantId: tenantId,
        from: _from,
        to: _to,
      );
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _byId = <String, WasteCategory>{
          for (final WasteCategory category in categories)
            category.id: category,
        };
        _logs = logs;
        _certificates = certificates;
        _compliance = compliance;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  List<WasteCategory> get _activeCategories => _categories
      .where((WasteCategory category) => category.isActive)
      .toList(growable: false);

  String _name(String categoryId) =>
      _byId[categoryId]?.name ?? 'Unknown category';

  Future<void> _addCategory() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) return;
    final _CategoryFormResult? result = await showDialog<_CategoryFormResult>(
      context: context,
      builder: (BuildContext context) => const _CategoryFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(registerWasteCategoryUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            createdBy: userId,
            code: result.code,
            name: result.name,
            colour: result.colour,
            hazardClass: result.hazardClass,
            requiresTreatment: result.requiresTreatment,
            treatmentMethod: result.treatmentMethod,
            retentionDays: result.retentionDays,
            isActive: true,
          );
    });
  }

  Future<void> _editCategory(WasteCategory category) async {
    final session = ref.read(sessionProvider);
    final _CategoryFormResult? result = await showDialog<_CategoryFormResult>(
      context: context,
      builder: (BuildContext context) =>
          _CategoryFormDialog(category: category),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(updateWasteCategoryUseCaseProvider)
          .call(
            policy: session.authorization,
            category: category,
            code: result.code,
            name: result.name,
            colour: result.colour,
            hazardClass: result.hazardClass,
            requiresTreatment: result.requiresTreatment,
            treatmentMethod: result.treatmentMethod,
            retentionDays: result.retentionDays,
            isActive: result.isActive,
          );
    });
  }

  Future<void> _toggleCategory(WasteCategory category) async {
    final session = ref.read(sessionProvider);
    await _run(() async {
      await ref
          .read(updateWasteCategoryUseCaseProvider)
          .call(
            policy: session.authorization,
            category: category,
            code: category.code,
            name: category.name,
            isActive: !category.isActive,
          );
    });
  }

  Future<void> _logGeneration() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    final String? facilityId = facilities.isEmpty ? null : facilities.first;
    if (tenantId == null || userId == null || facilityId == null) return;
    if (_activeCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a waste category first.')),
      );
      return;
    }
    final _GenerationFormResult? result =
        await showDialog<_GenerationFormResult>(
          context: context,
          builder: (BuildContext context) =>
              _GenerationFormDialog(categories: _activeCategories),
        );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(logWasteGenerationUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            facilityId: facilityId,
            categoryId: result.categoryId,
            loggedBy: userId,
            weightGrams: result.weightGrams,
            containerCount: result.containerCount,
            locationLabel: result.locationLabel,
            notes: result.notes,
          );
    });
  }

  Future<void> _issueCertificate() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    final String? facilityId = facilities.isEmpty ? null : facilities.first;
    if (tenantId == null || userId == null || facilityId == null) return;
    if (_activeCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a waste category first.')),
      );
      return;
    }
    final _CertificateFormResult? result =
        await showDialog<_CertificateFormResult>(
          context: context,
          builder: (BuildContext context) =>
              _CertificateFormDialog(categories: _activeCategories),
        );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(issueWasteCertificateUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            facilityId: facilityId,
            categoryId: result.categoryId,
            issuedBy: userId,
            certificateNo: result.certificateNo,
            barcode: result.barcode,
            disposalVendor: result.disposalVendor,
            method: result.method,
            disposedAt: result.disposedAt,
            weightGrams: result.weightGrams,
            vendorLicence: result.vendorLicence,
            manifestReference: result.manifestReference,
          );
    });
  }

  Future<void> _voidCertificate(DisposalCertificate certificate) async {
    final session = ref.read(sessionProvider);
    final TextEditingController controller = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Void certificate'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    await _run(() async {
      await ref
          .read(voidWasteCertificateUseCaseProvider)
          .call(
            policy: session.authorization,
            certificate: certificate,
            reason: reason,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Biomedical waste')),
        body: Center(child: Text(_error!)),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Biomedical waste'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Generation'),
              Tab(text: 'Certificates'),
              Tab(text: 'Compliance'),
              Tab(text: 'Categories'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _generationTab(),
            _certificateTab(),
            _complianceTab(),
            _categoryTab(),
          ],
        ),
      ),
    );
  }

  Widget _generationTab() {
    return Stack(
      children: <Widget>[
        if (_logs.isEmpty)
          const Center(child: Text('No waste generated in this window.'))
        else
          ListView.builder(
            itemCount: _logs.length,
            itemBuilder: (BuildContext context, int index) {
              final WasteGenerationLog log = _logs[index];
              return ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: _colourOf(_byId[log.categoryId]),
                ),
                title: Text(
                  '${_name(log.categoryId)} · ${_formatWeight(log.weightGrams)}',
                ),
                subtitle: Text(
                  <String>[
                    _containers(log.containerCount),
                    if (log.locationLabel case final String place) place,
                    _formatDate(log.loggedAt),
                    if (log.notes case final String note) note,
                  ].join(' · '),
                ),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _logGeneration,
            tooltip: 'Log waste generated',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _certificateTab() {
    return Stack(
      children: <Widget>[
        if (_certificates.isEmpty)
          const Center(child: Text('No disposal certificates.'))
        else
          ListView.builder(
            itemCount: _certificates.length,
            itemBuilder: (BuildContext context, int index) {
              final DisposalCertificate certificate = _certificates[index];
              return ListTile(
                leading: Icon(
                  certificate.isLive
                      ? Icons.verified_outlined
                      : Icons.block_outlined,
                  color: certificate.isLive
                      ? null
                      : Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '${certificate.certificateNo} · '
                  '${_name(certificate.categoryId)}',
                ),
                subtitle: Text(
                  <String>[
                    certificate.status.label,
                    certificate.method.label,
                    _formatWeight(certificate.weightGrams),
                    certificate.disposalVendor,
                    _formatDate(certificate.disposedAt),
                    if (certificate.voidReason case final String reason)
                      'void: $reason',
                  ].join(' · '),
                ),
                onTap: certificate.isLive
                    ? () => _voidCertificate(certificate)
                    : null,
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _issueCertificate,
            tooltip: 'Issue disposal certificate',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _complianceTab() {
    return Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.event_outlined),
          title: const Text('Window'),
          subtitle: Text(
            '${_formatDate(_from)} to ${_formatDate(_to.subtract(const Duration(days: 1)))}',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _load,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _compliance.isEmpty
              ? const Center(child: Text('No waste streams to assess.'))
              : ListView.builder(
                  itemCount: _compliance.length,
                  itemBuilder: (BuildContext context, int index) {
                    final WasteCategoryCompliance entry = _compliance[index];
                    return ListTile(
                      leading: Icon(
                        entry.isCompliant
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: entry.isCompliant
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        '${entry.category.code} · ${entry.category.name}',
                      ),
                      subtitle: Text(
                        'Generated ${_formatWeight(entry.generatedGrams)} · '
                        'Certificated '
                        '${_formatWeight(entry.certificatedGrams)}',
                      ),
                      trailing: Text(
                        entry.isCompliant
                            ? 'Balanced'
                            : '${_formatWeight(entry.gapGrams)} open',
                        style: entry.isCompliant
                            ? null
                            : TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _categoryTab() {
    return Stack(
      children: <Widget>[
        if (_categories.isEmpty)
          const Center(child: Text('No waste categories defined.'))
        else
          ListView.builder(
            itemCount: _categories.length,
            itemBuilder: (BuildContext context, int index) {
              final WasteCategory category = _categories[index];
              return ListTile(
                leading: Icon(
                  Icons.circle,
                  color: _colourOf(category),
                  size: 16,
                ),
                title: Text('${category.code} · ${category.name}'),
                subtitle: Text(
                  <String>[
                    category.colour.label,
                    category.hazardClass.label,
                    if (category.requiresTreatment)
                      category.treatmentMethod ?? 'Treatment required',
                    if (!category.isActive) 'Not in use',
                  ].join(' · '),
                ),
                onTap: () => _editCategory(category),
                trailing: Switch(
                  value: category.isActive,
                  onChanged: (bool _) => _toggleCategory(category),
                ),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _addCategory,
            tooltip: 'Add waste category',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

Color? _colourOf(WasteCategory? category) => switch (category?.colour) {
  WasteColour.yellow => const Color(0xFFF9A825),
  WasteColour.red => const Color(0xFFC62828),
  WasteColour.white => const Color(0xFF9E9E9E),
  WasteColour.blue => const Color(0xFF1565C0),
  WasteColour.black => const Color(0xFF212121),
  WasteColour.green => const Color(0xFF2E7D32),
  WasteColour.other || null => null,
};

DateTime _monthStart() {
  final DateTime now = DateTime.now().toUtc();
  return DateTime.utc(now.year, now.month);
}

DateTime _tomorrow() => DateTime.now().toUtc().add(const Duration(days: 1));

String _formatDate(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

String _formatWeight(int grams) =>
    grams >= 1000 ? '${(grams / 1000).toStringAsFixed(2)} kg' : '$grams g';

String _containers(int count) =>
    count == 1 ? '1 container' : '$count containers';

class _CategoryFormResult {
  const _CategoryFormResult({
    required this.code,
    required this.name,
    required this.colour,
    required this.hazardClass,
    required this.requiresTreatment,
    required this.isActive,
    this.treatmentMethod,
    this.retentionDays,
  });

  final String code;
  final String name;
  final WasteColour colour;
  final WasteHazardClass hazardClass;
  final bool requiresTreatment;
  final bool isActive;
  final String? treatmentMethod;
  final int? retentionDays;
}

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({this.category});

  final WasteCategory? category;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  late final TextEditingController _code = TextEditingController(
    text: widget.category?.code ?? '',
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.category?.name ?? '',
  );
  late final TextEditingController _treatment = TextEditingController(
    text: widget.category?.treatmentMethod ?? '',
  );
  late final TextEditingController _retention = TextEditingController(
    text: widget.category?.retentionDays?.toString() ?? '',
  );
  late WasteColour _colour = widget.category?.colour ?? WasteColour.yellow;
  late WasteHazardClass _hazardClass =
      widget.category?.hazardClass ?? WasteHazardClass.infectious;
  late bool _requiresTreatment = widget.category?.requiresTreatment ?? true;
  late bool _isActive = widget.category?.isActive ?? true;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _code,
      _name,
      _treatment,
      _retention,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.category == null ? 'Add waste category' : 'Edit category',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Code'),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          DropdownButtonFormField<WasteColour>(
            initialValue: _colour,
            decoration: const InputDecoration(labelText: 'Colour'),
            items: <DropdownMenuItem<WasteColour>>[
              for (final WasteColour colour in WasteColour.values)
                DropdownMenuItem<WasteColour>(
                  value: colour,
                  child: Text(colour.label),
                ),
            ],
            onChanged: (WasteColour? value) {
              if (value != null) setState(() => _colour = value);
            },
          ),
          DropdownButtonFormField<WasteHazardClass>(
            initialValue: _hazardClass,
            decoration: const InputDecoration(labelText: 'Hazard class'),
            items: <DropdownMenuItem<WasteHazardClass>>[
              for (final WasteHazardClass hazard in WasteHazardClass.values)
                DropdownMenuItem<WasteHazardClass>(
                  value: hazard,
                  child: Text(hazard.label),
                ),
            ],
            onChanged: (WasteHazardClass? value) {
              if (value != null) setState(() => _hazardClass = value);
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _requiresTreatment,
            title: const Text('Requires treatment'),
            onChanged: (bool? value) =>
                setState(() => _requiresTreatment = value ?? false),
          ),
          TextField(
            controller: _treatment,
            decoration: const InputDecoration(labelText: 'Treatment method'),
          ),
          TextField(
            controller: _retention,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Retention (days)'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _isActive,
            title: const Text('In use'),
            onChanged: (bool? value) =>
                setState(() => _isActive = value ?? false),
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
        onPressed: () => Navigator.of(context).pop(
          _CategoryFormResult(
            code: _code.text.trim(),
            name: _name.text.trim(),
            colour: _colour,
            hazardClass: _hazardClass,
            requiresTreatment: _requiresTreatment,
            isActive: _isActive,
            treatmentMethod: _nullIfEmpty(_treatment),
            retentionDays: int.tryParse(_retention.text.trim()),
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}

class _GenerationFormResult {
  const _GenerationFormResult({
    required this.categoryId,
    required this.weightGrams,
    required this.containerCount,
    this.locationLabel,
    this.notes,
  });

  final String categoryId;
  final int weightGrams;
  final int containerCount;
  final String? locationLabel;
  final String? notes;
}

class _GenerationFormDialog extends StatefulWidget {
  const _GenerationFormDialog({required this.categories});

  final List<WasteCategory> categories;

  @override
  State<_GenerationFormDialog> createState() => _GenerationFormDialogState();
}

class _GenerationFormDialogState extends State<_GenerationFormDialog> {
  late String _categoryId = widget.categories.first.id;
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _containers = TextEditingController(text: '1');
  final TextEditingController _location = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _weight,
      _containers,
      _location,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Log waste generated'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Waste category'),
            items: <DropdownMenuItem<String>>[
              for (final WasteCategory category in widget.categories)
                DropdownMenuItem<String>(
                  value: category.id,
                  child: Text('${category.code} · ${category.name}'),
                ),
            ],
            onChanged: (String? value) {
              if (value != null) setState(() => _categoryId = value);
            },
          ),
          TextField(
            controller: _weight,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Weight (grams)'),
          ),
          TextField(
            controller: _containers,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Containers'),
          ),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Location (ward, room)',
            ),
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
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
        onPressed: () => Navigator.of(context).pop(
          _GenerationFormResult(
            categoryId: _categoryId,
            weightGrams: int.tryParse(_weight.text.trim()) ?? 0,
            containerCount: int.tryParse(_containers.text.trim()) ?? 1,
            locationLabel: _nullIfEmpty(_location),
            notes: _nullIfEmpty(_notes),
          ),
        ),
        child: const Text('Log'),
      ),
    ],
  );
}

class _CertificateFormResult {
  const _CertificateFormResult({
    required this.categoryId,
    required this.certificateNo,
    required this.barcode,
    required this.disposalVendor,
    required this.method,
    required this.disposedAt,
    required this.weightGrams,
    this.vendorLicence,
    this.manifestReference,
  });

  final String categoryId;
  final String certificateNo;
  final String barcode;
  final String disposalVendor;
  final DisposalMethod method;
  final DateTime disposedAt;
  final int weightGrams;
  final String? vendorLicence;
  final String? manifestReference;
}

class _CertificateFormDialog extends StatefulWidget {
  const _CertificateFormDialog({required this.categories});

  final List<WasteCategory> categories;

  @override
  State<_CertificateFormDialog> createState() => _CertificateFormDialogState();
}

class _CertificateFormDialogState extends State<_CertificateFormDialog> {
  late String _categoryId = widget.categories.first.id;
  final TextEditingController _number = TextEditingController();
  final TextEditingController _barcode = TextEditingController();
  final TextEditingController _vendor = TextEditingController();
  final TextEditingController _licence = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _manifest = TextEditingController();
  DisposalMethod _method = DisposalMethod.incineration;
  DateTime _disposedAt = DateTime.now().toUtc();

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _number,
      _barcode,
      _vendor,
      _licence,
      _weight,
      _manifest,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _disposedAt,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null) return;
    setState(() {
      _disposedAt = DateTime.utc(picked.year, picked.month, picked.day);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Issue disposal certificate'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Waste category'),
            items: <DropdownMenuItem<String>>[
              for (final WasteCategory category in widget.categories)
                DropdownMenuItem<String>(
                  value: category.id,
                  child: Text('${category.code} · ${category.name}'),
                ),
            ],
            onChanged: (String? value) {
              if (value != null) setState(() => _categoryId = value);
            },
          ),
          TextField(
            controller: _number,
            decoration: const InputDecoration(labelText: 'Certificate number'),
          ),
          TextField(
            controller: _barcode,
            decoration: const InputDecoration(labelText: 'Barcode'),
          ),
          TextField(
            controller: _vendor,
            decoration: const InputDecoration(labelText: 'Disposal vendor'),
          ),
          TextField(
            controller: _licence,
            decoration: const InputDecoration(labelText: 'Vendor licence'),
          ),
          DropdownButtonFormField<DisposalMethod>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Method'),
            items: <DropdownMenuItem<DisposalMethod>>[
              for (final DisposalMethod method in DisposalMethod.values)
                DropdownMenuItem<DisposalMethod>(
                  value: method,
                  child: Text(method.label),
                ),
            ],
            onChanged: (DisposalMethod? value) {
              if (value != null) setState(() => _method = value);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Disposed on'),
            subtitle: Text(_formatDate(_disposedAt)),
            onTap: _pickDate,
          ),
          TextField(
            controller: _weight,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Weight (grams)'),
          ),
          TextField(
            controller: _manifest,
            decoration: const InputDecoration(labelText: 'Manifest reference'),
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
        onPressed: () => Navigator.of(context).pop(
          _CertificateFormResult(
            categoryId: _categoryId,
            certificateNo: _number.text.trim(),
            barcode: _barcode.text.trim(),
            disposalVendor: _vendor.text.trim(),
            method: _method,
            disposedAt: _disposedAt,
            weightGrams: int.tryParse(_weight.text.trim()) ?? 0,
            vendorLicence: _nullIfEmpty(_licence),
            manifestReference: _nullIfEmpty(_manifest),
          ),
        ),
        child: const Text('Issue'),
      ),
    ],
  );
}
