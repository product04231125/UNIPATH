import '../assistant/assistant_api.dart';
import '../auth/auth_api.dart';
import 'school_knowledge_models.dart';

/// Explicit catalogue selection; no local-profile upload, approval or AI fallback.
class SchoolKnowledgeApi {
  const SchoolKnowledgeApi(this.api);
  final ApiGateway api;

  Future<SchoolKnowledgeSearchResponse> search(
    SchoolKnowledgeSearch request,
  ) async {
    final result = SchoolKnowledgeSearchResponse.fromJson(
      (await api.request('POST', 'me/school-searches', request.toJson()))!,
    );
    if (!{
          'evidence_found',
          'insufficient_evidence',
          'needs_user_input',
          'failed',
        }.contains(result.status) ||
        result.sources.isNotEmpty != (result.status == 'evidence_found')) {
      throw const FormatException('Invalid approved-source search result');
    }
    for (final source in result.sources) {
      final uri = Uri.parse(source.sourceUrl);
      if (!{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          source.page < 1) {
        throw const FormatException('Invalid approved source citation');
      }
    }
    return result;
  }

  Future<AssistantResult> query(SchoolKnowledgeQuery request) async {
    return AssistantResult.fromJson(
      (await api.request('POST', 'me/school-queries', request.toJson()))!,
    );
  }
}

/// Uses the current shared authentication session; server scope checks are mandatory.
class SchoolKnowledgeAdminApi {
  const SchoolKnowledgeAdminApi(this.api);
  final ApiGateway api;
  static const _path = 'admin/knowledge-revisions';

  Future<SchoolKnowledgeList> list({
    String? institutionId,
    String? sourceDocumentId,
    String? status,
    String? cursor,
    int limit = 100,
  }) async {
    final query = Uri(
      queryParameters: {
        'institution_id': ?institutionId,
        'source_document_id': ?sourceDocumentId,
        'status': ?status,
        'cursor': ?cursor,
        'limit': '$limit',
      },
    ).query;
    return SchoolKnowledgeList.fromJson(
      (await api.request('GET', '$_path?$query'))!,
    );
  }

  Future<SchoolKnowledgeView> get(String id) async =>
      SchoolKnowledgeView.fromJson((await api.request('GET', '$_path/$id'))!);

  Future<SchoolKnowledgeView> create(SchoolKnowledgeCreate request) async =>
      SchoolKnowledgeView.fromJson(
        (await api.request('POST', _path, request.toJson()))!,
      );

  Future<SchoolKnowledgePageList> pages(
    String id, {
    int? cursor,
    int limit = 100,
  }) async {
    final query = Uri(
      queryParameters: {'cursor': ?cursor?.toString(), 'limit': '$limit'},
    ).query;
    return SchoolKnowledgePageList.fromJson(
      (await api.request('GET', '$_path/$id/pages?$query'))!,
    );
  }

  Future<SchoolKnowledgePageView> page(String id, int page) async =>
      SchoolKnowledgePageView.fromJson(
        (await api.request('GET', '$_path/$id/pages/$page'))!,
      );

  Future<SchoolKnowledgePageView> replacePage(
    String id,
    int page,
    SchoolKnowledgePageReplace request,
  ) async => SchoolKnowledgePageView.fromJson(
    (await api.request('PUT', '$_path/$id/pages/$page', request.toJson()))!,
  );

  Future<void> removePage(
    String id,
    int page, {
    required int expectedVersion,
  }) async {
    await api.request(
      'DELETE',
      '$_path/$id/pages/$page?expected_version=$expectedVersion',
    );
  }

  Future<SchoolKnowledgeView> approve(
    String id,
    SchoolKnowledgeApprove request,
  ) async => SchoolKnowledgeView.fromJson(
    (await api.request('POST', '$_path/$id/approve', request.toJson()))!,
  );

  Future<SchoolKnowledgeView> revoke(
    String id,
    SchoolKnowledgeRevoke request,
  ) async => SchoolKnowledgeView.fromJson(
    (await api.request('POST', '$_path/$id/revoke', request.toJson()))!,
  );

  Future<void> removeDraft(String id, {required int expectedVersion}) async {
    await api.request('DELETE', '$_path/$id?expected_version=$expectedVersion');
  }
}
