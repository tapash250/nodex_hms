/// Nutrition section embedded in the patient detail screen (Module 21).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/nutrition/nutrition.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/nutrition/nutrition_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Shows nutrition assessments and meal plans for a patient.
class NutritionPatientSection extends ConsumerWidget {
  /// Creates the section.
  const NutritionPatientSection({required this.patientId, super.key});

  /// Patient identifier.
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<DietAssessment>> assessments = ref.watch(
      dietAssessmentsForPatientProvider(patientId),
    );
    final AsyncValue<List<DietMealPlan>> plans = ref.watch(
      dietPlansForPatientProvider(patientId),
    );
    final SessionState session = ref.watch(sessionProvider);
    final bool canAssess = session.authorization.can(
      NodexPermissions.dietAssessmentWrite,
    );
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Nutrition', style: theme.textTheme.titleMedium),
            ),
            if (canAssess)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Assess'),
                onPressed: () => _showAssessmentSheet(context, ref),
              ),
          ],
        ),
        assessments.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (Object error, StackTrace _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error is NodexError
                    ? error.message
                    : 'Nutrition history unavailable.',
              ),
            ),
          ),
          data: (List<DietAssessment> values) => values.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No nutrition assessments recorded.'),
                  ),
                )
              : Column(
                  children: values
                      .map(
                        (DietAssessment assessment) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              assessment.isFinalized
                                  ? Icons.verified_outlined
                                  : Icons.edit_note_outlined,
                            ),
                            title: Text(assessment.nutritionDiagnosis),
                            subtitle: Text(
                              '${assessment.assessmentType.label} · '
                              '${assessment.status.label}',
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 8),
        plans.when(
          loading: () => const SizedBox.shrink(),
          error: (Object error, StackTrace _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error is NodexError ? error.message : 'Meal plans unavailable.',
              ),
            ),
          ),
          data: (List<DietMealPlan> values) => values.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No meal plans authored yet.'),
                  ),
                )
              : Column(
                  children: values
                      .map(
                        (DietMealPlan plan) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              plan.isApproved
                                  ? Icons.restaurant_menu
                                  : plan.planSource.isAiGenerated
                                  ? Icons.auto_awesome_outlined
                                  : Icons.edit_note_outlined,
                            ),
                            title: Text(plan.name),
                            subtitle: Text(
                              '${plan.planSource.label} · '
                              '${plan.cycleDays}-day · '
                              '${plan.status.label}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go(
                              '/patients/$patientId/nutrition/${plan.id}',
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }

  Future<void> _showAssessmentSheet(BuildContext context, WidgetRef ref) async {
    final _AssessmentDraft? draft =
        await showModalBottomSheet<_AssessmentDraft>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext context) => const _AssessmentSheet(),
        );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;
    try {
      final DietAssessment assessment = await ref
          .read(recordDietAssessmentUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: patientId,
            assessedBy: userId,
            assessmentType: draft.assessmentType,
            nutritionDiagnosis: draft.nutritionDiagnosis,
            weightKg: draft.weightKg,
            heightCm: draft.heightCm,
            restrictions: draft.restrictions,
          );
      ref.invalidate(dietAssessmentsForPatientProvider(patientId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Assessment ${assessment.status.label.toLowerCase()}',
            ),
          ),
        );
      }
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _AssessmentDraft {
  const _AssessmentDraft({
    required this.assessmentType,
    required this.nutritionDiagnosis,
    this.weightKg,
    this.heightCm,
    this.restrictions,
  });
  final DietAssessmentType assessmentType;
  final String nutritionDiagnosis;
  final double? weightKg;
  final double? heightCm;
  final String? restrictions;
}

class _AssessmentSheet extends StatefulWidget {
  const _AssessmentSheet();
  @override
  State<_AssessmentSheet> createState() => _AssessmentSheetState();
}

class _AssessmentSheetState extends State<_AssessmentSheet> {
  final TextEditingController _diagnosis = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _height = TextEditingController();
  final TextEditingController _restrictions = TextEditingController();
  DietAssessmentType _type = DietAssessmentType.initial;

  @override
  void dispose() {
    _diagnosis.dispose();
    _weight.dispose();
    _height.dispose();
    _restrictions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Record nutrition assessment',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<DietAssessmentType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Assessment type *'),
            items: DietAssessmentType.values
                .map(
                  (DietAssessmentType type) =>
                      DropdownMenuItem<DietAssessmentType>(
                        value: type,
                        child: Text(type.label),
                      ),
                )
                .toList(growable: false),
            onChanged: (DietAssessmentType? value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _diagnosis,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Nutrition diagnosis *',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Weight kg'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _height,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Height cm'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _restrictions,
            decoration: const InputDecoration(
              labelText: 'Dietary restrictions (optional)',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_diagnosis.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                _AssessmentDraft(
                  assessmentType: _type,
                  nutritionDiagnosis: _diagnosis.text.trim(),
                  weightKg: double.tryParse(_weight.text.trim()),
                  heightCm: double.tryParse(_height.text.trim()),
                  restrictions: _restrictions.text.trim().isEmpty
                      ? null
                      : _restrictions.text.trim(),
                ),
              );
            },
            child: const Text('Save assessment'),
          ),
        ],
      ),
    );
  }
}
