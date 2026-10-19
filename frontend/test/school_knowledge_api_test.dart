import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/school_knowledge_api.dart';
import 'package:university_path_frontend/features/api/school_knowledge_models.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

const institution = '00000000-0000-4000-8000-000000000001';
const department = '00000000-0000-4000-8000-000000000002';
const document = '00000000-0000-4000-8000-000000000003';
const chunk = '00000000-0000-4000-8000-000000000004';
const scope = SchoolKnowledgeContext(
  institutionId: institution,
  departmentId: department,
  admissionYear: 2026,
  track: 'single_major',
);

class Gateway implements ApiGateway {
  Map<String, dynamic> response = {};
  final requests = <(String, String, Map<String, Object?>?)>[];
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    requests.add((method, path, body));
    return response;
  }
}

Map<String, dynamic> evidence({
  String status = 'evidence_found',
  String url = 'https://school.example.invalid/rules',
}) => {
  'query_id': document,
  'status': status,
  'reason': 'approved_sources_found',
  'sources': [
    {
      'chunk_id': chunk,
      'document_id': document,
      'title': '합성 공식 규정',
      'source_url': url,
      'page': 1,
      'excerpt': '합성 검색 발췌',
    },
  ],
  'missing_fields': [],
};

Map<String, dynamic> header() => {
  'id': document,
  'institution_id': institution,
  'department_id': department,
  'curriculum_id': null,
  'name': '합성 추출 초안',
  'source_document_id': document,
  'source_document_version': 2,
  'version': 3,
  'status': 'draft',
  'document_hash': 'a' * 64,
  'page_count': 2,
  'extractor_version': 'synthetic-v2',
  'source_checked_on': '2026-10-19',
  'created_at': '2026-10-19T00:00:00Z',
  'updated_at': '2026-10-19T00:00:00Z',
  'approved_by': null,
  'approved_at': null,
  'review_note': '',
  'revoked_by': null,
  'revoked_at': null,
  'revocation_reason': '',
};

void main() {
  test(
    'catalogue search sends explicit IDs and parses source-only evidence',
    () async {
      final gateway = Gateway()..response = evidence();
      final result = await SchoolKnowledgeApi(gateway).search(
        const SchoolKnowledgeSearch(question: '합성 봉사 조건은?', context: scope),
      );
      final (method, path, body) = gateway.requests.single;
      expect((method, path), ('POST', 'me/school-searches'));
      final context = body!['context'] as Map;
      expect(context['institution_id'], institution);
      expect(context.containsKey('institution'), isFalse);
      expect(body.containsKey('owner_id'), isFalse);
      expect(result.sources.single.page, 1);
      expect(result.sources.single.excerpt, '합성 검색 발췌');
    },
  );

  test(
    'query preserves missing-generator state without fabricating an answer',
    () async {
      final gateway = Gateway()
        ..response = {
          'query_id': document,
          'status': 'failed',
          'reason': 'answer_generator_not_configured',
          'answer': null,
          'citations': [],
          'missing_fields': [],
        };
      final result = await SchoolKnowledgeApi(gateway).query(
        const SchoolKnowledgeQuery(question: '합성 봉사 조건은?', context: scope),
      );
      expect(result.status, AssistantStatus.failed);
      expect(result.answer, isNull);
      expect(gateway.requests.single.$2, 'me/school-queries');
    },
  );

  test(
    'admin blank-page and approval requests preserve explicit review inputs',
    () async {
      final gateway = Gateway()
        ..response = {
          'knowledge_document_id': document,
          'version': 3,
          'page': 2,
          'page_hash': 'b' * 64,
          'is_blank': true,
          'parts': [],
        };
      final api = SchoolKnowledgeAdminApi(gateway);
      final page = await api.replacePage(
        document,
        2,
        const SchoolKnowledgePageReplace(
          expectedVersion: 2,
          isBlank: true,
          parts: [],
        ),
      );
      expect(page.isBlank, isTrue);
      expect(page.parts, isEmpty);
      expect(gateway.requests.last.$1, 'PUT');
      expect(gateway.requests.last.$3!['parts'], isEmpty);
      gateway.response = header();
      final result = await api.approve(
        document,
        SchoolKnowledgeApprove(
          expectedVersion: 3,
          reviewedDocumentHash: 'a' * 64,
          sourceVerified: false,
          applicabilityVerified: true,
          extractionVerified: true,
          completeDocumentVerified: true,
          reviewNote: '합성 검토 요청',
        ),
      );
      expect(gateway.requests.last.$3!['source_verified'], isFalse);
      expect(result.sourceCheckedOn, '2026-10-19');
      expect(result.status, 'draft');
    },
  );

  test(
    'unconfirmed search results and unsafe source URLs are rejected',
    () async {
      final gateway = Gateway();
      final api = SchoolKnowledgeApi(gateway);
      for (final invalid in [
        evidence(status: 'insufficient_evidence'),
        evidence(url: 'javascript:alert(1)'),
        evidence(url: 'https://user:secret@example.invalid'),
      ]) {
        gateway.response = invalid;
        await expectLater(
          api.search(
            const SchoolKnowledgeSearch(question: '합성 봉사 조건은?', context: scope),
          ),
          throwsFormatException,
        );
      }
    },
  );
}
