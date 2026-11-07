import '../auth/auth_api.dart';
import 'academic_guidance_models.dart';
import 'job_analysis_models.dart';

/// Uses the same owner-bound gateway as profile/record operations.
class GuidanceApi {
  const GuidanceApi(this.api);
  final ApiGateway api;

  Future<AcademicGuidance> node(String id, {String? auditId}) async {
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,200}$').hasMatch(id)) {
      throw const FormatException('Invalid guidance node');
    }
    final query = auditId == null
        ? ''
        : '?${Uri(queryParameters: {'audit_id': auditId}).query}';
    return AcademicGuidance.fromJson(
      (await api.request('GET', 'me/academic-guidance/nodes/$id$query'))!,
    );
  }

  Future<PersonalizedGuidanceResponse> personalized(
    PersonalizedGuidanceRequest value,
  ) async => PersonalizedGuidanceResponse.fromJson(
    (await api.request('POST', 'me/personalized-guidance', value.toJson()))!,
  );

  Future<JobAnalysisResponse> analyze(JobAnalysisRequest value) async =>
      JobAnalysisResponse.fromJson(
        (await api.request('POST', 'me/job-analyses', value.toJson()))!,
      );
}
