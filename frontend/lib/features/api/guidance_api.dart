import '../auth/auth_api.dart';
import 'academic_guidance_models.dart';
import 'job_analysis_models.dart';
import 'graduation_models.dart';
import '../auth/guidance_asset_gateway.dart';

/// Uses the same owner-bound gateway as profile/record operations.
class GuidanceApi {
  const GuidanceApi(this.api, {this.ownerId});
  final ApiGateway api;
  final String? ownerId;
  Future<GuidanceAsset> asset(String id) {
    final gateway = api;
    if (gateway is! GuidanceAssetGateway) {
      throw const AuthFailure('안내 원문 연결을 확인해 주세요.');
    }
    return (gateway as GuidanceAssetGateway).guidanceAsset(id);
  }

  Future<List<GraduationAuditHeader>> audits(String institutionId) async {
    if (ownerId == null) throw const AuthFailure('감사 이력의 로그인 계정을 확인해 주세요.');
    final result = <GraduationAuditHeader>[];
    String? cursor;
    final seen = <String>{};
    do {
      final query = Uri(
        queryParameters: {
          'institution_id': institutionId,
          'limit': '20',
          'cursor': ?cursor,
        },
      ).query;
      final page = GraduationAuditList.fromJson(
        (await api.request('GET', 'me/graduation-audits?$query'))!,
      );
      if (page.items.any((r) => r.ownerId != ownerId)) {
        throw const AuthFailure('감사 이력의 계정을 확인하지 못했습니다.', status: 403);
      }
      result.addAll(page.items);
      cursor = page.nextCursor;
      if (cursor != null && !seen.add(cursor)) {
        throw const FormatException('Repeated audit cursor');
      }
    } while (cursor != null);
    return result;
  }

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
