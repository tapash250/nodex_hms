/// Meal plan detail, authoring and approval (Module 21).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/nutrition/nutrition.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/nutrition/nutrition_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Detail screen for one meal plan.
class MealPlanScreen extends ConsumerWidget {
  /// Creates the screen.
  const MealPlanScreen({required this.planId, super.key});

  /// Local plan id.
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MealPlanDetail> detail = ref.watch(
      mealPlanDetailProvider(planId),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Meal plan')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _NutritionError(
          error: error,
          onRetry: () => ref.invalidate(mealPlanDetailProvider(planId)),
        ),
        data: (MealPlanDetail value) => _MealPlanBody(value: value),
      ),
    );
  }
}

class _MealPlanBody extends ConsumerWidget {
  const _MealPlanBody({required this.value});

  final MealPlanDetail value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final DietMealPlan plan = value.plan;
    final bool canAuthor = session.authorization.can(
      NodexPermissions.dietPlanWrite,
    );
    final bool canApprove = session.authorization.can(
      NodexPermissions.dietPlanApprove,
    );
    final bool complete = value.days.length == dietCycleDays;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(plan.name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _Fact(label: 'Source', value: plan.planSource.label),
                _Fact(label: 'Cycle', value: '${plan.cycleDays} days'),
                _Fact(label: 'Status', value: plan.status.label),
                _Fact(
                  label: 'Days planned',
                  value: '${value.days.length} of $dietCycleDays',
                ),
                if (value.assessment != null)
                  _Fact(
                    label: 'Diagnosis',
                    value: value.assessment!.nutritionDiagnosis,
                  ),
                if (plan.rejectionReason != null)
                  _Fact(label: 'Rejected', value: plan.rejectionReason!),
                if (plan.isApproved && plan.approvedAt != null)
                  _Fact(
                    label: 'Approved',
                    value: _formatWhen(plan.approvedAt!),
                  ),
              ],
            ),
          ),
        ),
        if (canAuthor && plan.isDraft)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_task),
              label: const Text('Add day'),
              onPressed: () => _showDaySheet(context, ref),
            ),
          ),
        if (canApprove && plan.isDraft) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Approve'),
                  onPressed: complete ? () => _approve(context, ref) : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Reject'),
                  onPressed: () => _reject(context, ref),
                ),
              ),
            ],
          ),
          if (!complete)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'A plan can be approved only once all seven days are planned.',
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text('Daily menu', style: theme.textTheme.titleMedium),
        if (value.days.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No days planned yet.'),
            ),
          )
        else
          ...value.days.map(
            (DietMealPlanDay day) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Day ${day.dayNumber}',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text('${day.caloriesKcal} kcal'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _Fact(label: 'Breakfast', value: day.breakfast),
                    _Fact(label: 'Lunch', value: day.lunch),
                    _Fact(label: 'Dinner', value: day.dinner),
                    if (day.snacks != null)
                      _Fact(label: 'Snacks', value: day.snacks!),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showDaySheet(BuildContext context, WidgetRef ref) async {
    final _DayDraft? draft = await showModalBottomSheet<_DayDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _DaySheet(
        usedDays: value.days.map((DietMealPlanDay d) => d.dayNumber).toSet(),
      ),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(addDietMealPlanDayUseCaseProvider)
          .call(
            policy: session.authorization,
            plan: value.plan,
            dayNumber: draft.dayNumber,
            breakfast: draft.breakfast,
            lunch: draft.lunch,
            dinner: draft.dinner,
            caloriesKcal: draft.caloriesKcal,
            snacks: draft.snacks,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(approveDietMealPlanUseCaseProvider)
          .call(
            policy: session.authorization,
            plan: value.plan,
            approvedBy: userId,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _ReasonSheet(),
    );
    if (reason == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(rejectDietMealPlanUseCaseProvider)
          .call(
            policy: session.authorization,
            plan: value.plan,
            rejectedBy: userId,
            reason: reason,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  void _invalidate(WidgetRef ref) {
    ref.invalidate(mealPlanDetailProvider(value.plan.id));
    ref.invalidate(dietPlansForPatientProvider(value.plan.patientId));
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatWhen(DateTime when) {
    final DateTime local = when.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: Text(label)),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}

class _DayDraft {
  const _DayDraft({
    required this.dayNumber,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    required this.caloriesKcal,
    this.snacks,
  });
  final int dayNumber;
  final String breakfast;
  final String lunch;
  final String dinner;
  final int caloriesKcal;
  final String? snacks;
}

class _DaySheet extends StatefulWidget {
  const _DaySheet({required this.usedDays});
  final Set<int> usedDays;
  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  final TextEditingController _breakfast = TextEditingController();
  final TextEditingController _lunch = TextEditingController();
  final TextEditingController _dinner = TextEditingController();
  final TextEditingController _snacks = TextEditingController();
  final TextEditingController _calories = TextEditingController(text: '2000');
  int _day = 1;

  @override
  void initState() {
    super.initState();
    for (int candidate = 1; candidate <= dietCycleDays; candidate++) {
      if (!widget.usedDays.contains(candidate)) {
        _day = candidate;
        return;
      }
    }
  }

  @override
  void dispose() {
    _breakfast.dispose();
    _lunch.dispose();
    _dinner.dispose();
    _snacks.dispose();
    _calories.dispose();
    super.dispose();
  }

  List<int> get _freeDays => <int>[
    for (int i = 1; i <= dietCycleDays; i++)
      if (!widget.usedDays.contains(i)) i,
  ];

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final List<int> options = _freeDays;
    if (options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('All seven days are already planned.'),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Plan a day',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: options.contains(_day) ? _day : options.first,
            decoration: const InputDecoration(labelText: 'Day *'),
            items: options
                .map(
                  (int day) => DropdownMenuItem<int>(
                    value: day,
                    child: Text('Day $day'),
                  ),
                )
                .toList(growable: false),
            onChanged: (int? value) {
              if (value != null) setState(() => _day = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _breakfast,
            decoration: const InputDecoration(labelText: 'Breakfast *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lunch,
            decoration: const InputDecoration(labelText: 'Lunch *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dinner,
            decoration: const InputDecoration(labelText: 'Dinner *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _snacks,
            decoration: const InputDecoration(labelText: 'Snacks (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _calories,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Daily calories *'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final int? calories = int.tryParse(_calories.text.trim());
              if (_breakfast.text.trim().isEmpty ||
                  _lunch.text.trim().isEmpty ||
                  _dinner.text.trim().isEmpty ||
                  calories == null) {
                return;
              }
              Navigator.pop(
                context,
                _DayDraft(
                  dayNumber: _day,
                  breakfast: _breakfast.text.trim(),
                  lunch: _lunch.text.trim(),
                  dinner: _dinner.text.trim(),
                  caloriesKcal: calories,
                  snacks: _snacks.text.trim().isEmpty
                      ? null
                      : _snacks.text.trim(),
                ),
              );
            },
            child: const Text('Add day'),
          ),
        ],
      ),
    );
  }
}

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet();
  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final TextEditingController _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
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
            'Reject meal plan',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Rejection reason *'),
            autofocus: true,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_reason.text.trim().isEmpty) return;
              Navigator.pop(context, _reason.text.trim());
            },
            child: const Text('Reject plan'),
          ),
        ],
      ),
    );
  }
}

class _NutritionError extends StatelessWidget {
  const _NutritionError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          error is NodexError
              ? (error as NodexError).message
              : 'Meal plan unavailable',
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
