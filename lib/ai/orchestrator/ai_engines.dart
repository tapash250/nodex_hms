/// NODEX AI engine catalogue.
///
/// Engine keys are stable contract identifiers referenced by routing policies,
/// audit records and clinical workflow code. Model and provider identifiers never
/// appear here: a workflow asks for an engine, and the deployment profile decides
/// which approved model serves it.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/ai/contracts/ai_contracts.dart';

/// Declared requirements of one AI engine.
///
/// These are the minimums a candidate must satisfy. Failover may not place a task
/// on a model that fails any of them.
@immutable
final class AiEngineDefinition {
  /// Declares an engine.
  const AiEngineDefinition({
    required this.engineKey,
    required this.displayName,
    required this.purpose,
    required this.modality,
    required this.riskLevel,
    required this.privacyClass,
    required this.requiresStructuredOutput,
    required this.requiresHumanReview,
    required this.responseSchemaKey,
    this.mayAbstain = true,
  });

  /// Stable engine identifier, for example `ai_triage_advisory`.
  final String engineKey;

  /// Human-readable name for governance surfaces.
  final String displayName;

  /// What the engine is for, recorded as intended use.
  final String purpose;

  /// Input modality.
  final Modality modality;

  /// Clinical risk tier of the engine's output.
  final ClinicalRiskLevel riskLevel;

  /// Most sensitive data class the engine processes.
  final DataPrivacyClass privacyClass;

  /// Whether responses must validate against [responseSchemaKey].
  final bool requiresStructuredOutput;

  /// Whether output requires human review before any clinical use.
  final bool requiresHumanReview;

  /// Identifier of the engine's response schema.
  final String responseSchemaKey;

  /// Whether the engine may return an abstention instead of an answer.
  ///
  /// Abstention is mandatory for extraction engines: when a critical field
  /// cannot be read confidently the model must decline rather than guess.
  final bool mayAbstain;
}

/// The engines defined by the specification.
abstract final class AiEngines {
  /// Structured clinical note generation from dictation or draft text.
  static const String clinicalNotesScribe = 'ai_clinical_notes_scribe';

  /// Emergency triage acuity advisory.
  static const String triageAdvisory = 'ai_triage_advisory';

  /// Laboratory report interpretation support.
  static const String labReportInterpreter = 'ai_lab_report_interpreter';

  /// Clinical document extraction from photographed documents.
  static const String clinicalDocumentExtraction =
      'ai_clinical_document_extraction';

  /// Discharge summary drafting.
  static const String dischargeSummary = 'ai_discharge_summary';

  /// Medication interaction advisory.
  static const String medicationInteraction = 'ai_medication_interaction';

  /// Diet plan generation for dietitian approval.
  static const String dietPlanGeneration = 'ai_diet_plan_generation';

  /// Executive and operational insight generation.
  static const String operationalInsights = 'ai_operational_insights';

  static const Map<String, AiEngineDefinition>
  _definitions = <String, AiEngineDefinition>{
    clinicalNotesScribe: AiEngineDefinition(
      engineKey: clinicalNotesScribe,
      displayName: 'AI Clinical Notes Scribe',
      purpose:
          'Converts clinician dictation or draft text into a structured '
          'SOAP note for review. Never authors a finalized note.',
      modality: Modality.multimodal,
      riskLevel: ClinicalRiskLevel.elevated,
      privacyClass: DataPrivacyClass.phiPermitted,
      requiresStructuredOutput: true,
      requiresHumanReview: true,
      responseSchemaKey: 'clinical_note_v1',
    ),
    triageAdvisory: AiEngineDefinition(
      engineKey: triageAdvisory,
      displayName: 'AI Triage Advisory',
      purpose:
          'Suggests an emergency severity index band with red flags. '
          'Advisory only; acuity assignment remains a clinician decision.',
      modality: Modality.text,
      riskLevel: ClinicalRiskLevel.high,
      privacyClass: DataPrivacyClass.phiPermitted,
      requiresStructuredOutput: true,
      requiresHumanReview: true,
      responseSchemaKey: 'triage_advisory_v1',
    ),
    labReportInterpreter: AiEngineDefinition(
      engineKey: labReportInterpreter,
      displayName: 'AI Lab Report Interpreter',
      purpose:
          'Summarises laboratory results and flags values outside '
          'reference ranges. Does not release or verify results.',
      modality: Modality.text,
      riskLevel: ClinicalRiskLevel.elevated,
      privacyClass: DataPrivacyClass.phiPermitted,
      requiresStructuredOutput: true,
      requiresHumanReview: true,
      responseSchemaKey: 'lab_interpretation_v1',
    ),
    clinicalDocumentExtraction: AiEngineDefinition(
      engineKey: clinicalDocumentExtraction,
      displayName: 'Clinical Document Extraction',
      purpose:
          'Extracts structured fields from photographed prescriptions, '
          'diagnostic slips, laboratory reports and ECG printouts. '
          'Extraction is not diagnostic interpretation.',
      modality: Modality.image,
      riskLevel: ClinicalRiskLevel.high,
      // The designated edge vision model runs on-device, so document images
      // never leave the device unless a separately validated cloud vision
      // model is explicitly enabled in the deployment profile.
      privacyClass: DataPrivacyClass.onDeviceOnly,
      requiresStructuredOutput: true,
      requiresHumanReview: true,
      responseSchemaKey: 'document_extraction_v1',
    ),
    dischargeSummary: AiEngineDefinition(
      engineKey: dischargeSummary,
      displayName: 'AI Discharge Summary',
      purpose:
          'Drafts a discharge summary from the encounter record for '
          'clinician review. Does not finalize discharge.',
      modality: Modality.text,
      riskLevel: ClinicalRiskLevel.elevated,
      privacyClass: DataPrivacyClass.phiPermitted,
      requiresStructuredOutput: true,
      requiresHumanReview: true,
      responseSchemaKey: 'discharge_summary_v1',
    ),
    medicationInteraction: AiEngineDefinition(
      engineKey: medicationInteraction,
      displayName: 'AI Medication Interaction Advisory',
      purpose:
          'Supplements the deterministic interaction rule engine with '
          'narrative context. The rule engine remains authoritative.',
      modality: Modality.text,
      riskLevel: ClinicalRiskLevel.high,
      privacyClass: DataPrivacyClass.deIdentified,
      requiresStructuredOutput: true,
      requiresHumanReview: true,
      responseSchemaKey: 'medication_interaction_v1',
    ),
    dietPlanGeneration: AiEngineDefinition(
      engineKey: dietPlanGeneration,
      displayName: 'AI Diet Plan Generation',
      purpose:
          'Generates a candidate seven-day diet plan for dietitian '
          'approval.',
      modality: Modality.text,
      riskLevel: ClinicalRiskLevel.standard,
      privacyClass: DataPrivacyClass.deIdentified,
      requiresStructuredOutput: true,
      requiresHumanReview: true,
      responseSchemaKey: 'diet_plan_v1',
    ),
    operationalInsights: AiEngineDefinition(
      engineKey: operationalInsights,
      displayName: 'AI Operational Insights',
      purpose:
          'Summarises aggregate operational metrics for executive '
          'dashboards. Operates on aggregates, never on patient records.',
      modality: Modality.text,
      riskLevel: ClinicalRiskLevel.low,
      privacyClass: DataPrivacyClass.deIdentified,
      requiresStructuredOutput: true,
      // Aggregate operational commentary carries no clinical decision, so it
      // is the one engine that does not gate on clinician review.
      requiresHumanReview: false,
      responseSchemaKey: 'operational_insight_v1',
    ),
  };

  /// All declared engines, keyed by engine key.
  static Map<String, AiEngineDefinition> get definitions =>
      Map<String, AiEngineDefinition>.unmodifiable(_definitions);

  /// Every declared engine key.
  static Iterable<String> get engineKeys => _definitions.keys;

  /// Returns the definition for [engineKey], or null when undeclared.
  static AiEngineDefinition? definitionOf(String engineKey) =>
      _definitions[engineKey];
}
