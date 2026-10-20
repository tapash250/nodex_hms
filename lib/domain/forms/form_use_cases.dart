/// Form use cases (Module 47).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/forms/form_repository.dart';
import 'package:nodex_hms/domain/forms/form_template.dart';
import 'package:nodex_hms/domain/forms/icd10.dart';

/// Lists the forms a clinician may fill in.
final class ListFormTemplatesUseCase {
  /// Creates the use case.
  const ListFormTemplatesUseCase({required this._repository});

  final FormRepository _repository;

  /// Reads the published templates.
  Future<List<FormTemplate>> call({required AuthorizationPolicy policy}) async {
    policy.require(NodexPermissions.formsRead);
    return _repository.listTemplates();
  }
}

/// Searches the ICD-10 catalogue.
final class SearchIcd10UseCase {
  /// Creates the use case.
  const SearchIcd10UseCase({required this._repository});

  final FormRepository _repository;

  /// Searches the codes held on the device.
  Future<List<Icd10Code>> call({
    required AuthorizationPolicy policy,
    required String query,
    int limit = 20,
  }) async {
    policy.require(NodexPermissions.formsRead);
    final List<Icd10Code> codes = await _repository.listIcd10Codes();
    return searchIcd10(codes, query, limit: limit);
  }
}

/// Records a filled form.
///
/// The answers are validated against the template before the response is
/// written, so a form that was left half-finished never reaches the record.
final class SubmitFormResponseUseCase {
  /// Creates the use case.
  const SubmitFormResponseUseCase({required this._repository});

  final FormRepository _repository;

  /// Records the response, returning its local id.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required FormTemplate template,
    required String submittedBy,
    required Map<String, Object?> values,
    String? patientId,
    String? encounterId,
  }) async {
    policy.require(NodexPermissions.formsSubmit);
    if (!template.isFillable) {
      throw const ValidationError(
        message: 'Only a published form can be filled in.',
        code: 'form_template_not_published',
      );
    }
    return _repository.submitResponse(
      buildResponseRow(
        tenantId: tenantId,
        template: template,
        submittedBy: submittedBy,
        values: values,
        patientId: patientId,
        encounterId: encounterId,
      ),
    );
  }
}

/// Lists the forms recorded for a patient.
final class ListFormResponsesUseCase {
  /// Creates the use case.
  const ListFormResponsesUseCase({required this._repository});

  final FormRepository _repository;

  /// Reads the responses.
  Future<List<FormResponse>> call({
    required AuthorizationPolicy policy,
    required String patientId,
  }) async {
    policy.require(NodexPermissions.formsRead);
    return _repository.listResponses(patientId);
  }
}
