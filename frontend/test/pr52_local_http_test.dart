import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/academic_guidance_models.dart';
import 'package:university_path_frontend/features/api/guidance_api.dart';
import 'package:university_path_frontend/features/api/job_analysis_models.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/guidance_asset_gateway.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';

import 'support/auth_fixture.dart';

const schoolId = '10000000-0000-4000-8000-000000000001';
const departmentId = '10000000-0000-4000-8000-000000000002';
const recordId = '10000000-0000-4000-8000-000000000003';
const queryId = '10000000-0000-4000-8000-000000000004';
const chunkId = '10000000-0000-4000-8000-000000000005';
const documentId = '10000000-0000-4000-8000-000000000006';

/// A loopback-only synthetic HTTP fixture, not the deployed FastAPI service.
void main() {
  test('PR52 local HTTP preserves authentication contract fields and logout isolation', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final assetId = 'a' * 64;
    server.listen((request) async {
      final path = request.uri.path;
      final text = await utf8.decoder.bind(request).join();
      final body = text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>;
      request.response.headers.contentType = ContentType.json;
      Object? response;
      if (path == '/api/v1/auth/login') {
        response = {...identityJson(), 'access_token': token};
      } else {
        expect(request.headers.value('Authorization'), 'Bearer $token');
        if (!path.endsWith('/logout')) {
          expect(request.headers.value('X-Unipath-Owner'), userId);
        }
        paths.add(path);
        switch (path) {
          case '/api/v1/me/school-queries':
            expect(body['context'], {
              'institution_id': schoolId,
              'department_id': departmentId,
              'curriculum_id': null,
              'admission_year': 2026,
              'track': 'single_major',
            });
            expect(body.containsKey('external_processing_consent'), false);
            response = {
              'query_id': queryId,
              'status': 'insufficient_evidence',
              'reason': 'no_approved_matching_evidence',
              'answer': null,
              'citations': [],
              'missing_fields': [],
            };
          case '/api/v1/me/personalized-guidance':
            expect(body['external_processing_consent'], true);
            expect(body['records'], [
              {
                'kind': 'activity',
                'record_id': recordId,
                'expected_version': 2,
              },
            ]);
            response = {
              'query_id': queryId,
              'status': 'evidence_only',
              'reason': 'generator_not_configured',
              'official': false,
              'school': {
                'query_id': queryId,
                'status': 'evidence_found',
                'reason': 'approved_sources_found',
                'sources': [
                  {
                    'chunk_id': chunkId,
                    'document_id': documentId,
                    'title': '합성 학교 안내',
                    'source_url': 'https://example.invalid/source',
                    'page': 1,
                    'excerpt': '학교 안내 문장',
                  },
                ],
              },
              'personal': {
                'records': [
                  {
                    'kind': 'activity',
                    'record_id': recordId,
                    'version': 2,
                    'origin': 'personal',
                    'official': false,
                    'title': '합성 활동',
                    'text': '합성 봉사 기록',
                    'truncated': false,
                  },
                ],
                'official': false,
              },
            };
          case '/api/v1/me/job-analyses':
            expect(body['external_processing_consent'], true);
            expect(body.containsKey('context'), false);
            response = {
              'analysis_id': queryId,
              'status': 'not_configured',
              'reason': 'analyzer_not_configured',
              'official': false,
              'comparisons': [],
              'missing_fields': [],
            };
          case '/api/v1/me/academic-guidance/nodes/home':
            response = {
              'schema_version': 'academic-click-v3',
              'node_id': 'home',
              'state': 'ready',
              'reason': 'menu',
              'message': '메뉴',
              'cards': [],
              'warnings': [],
              'buttons': [],
            };
          case '/api/v1/auth/logout':
            request.response.statusCode = 204;
          default:
            if (path == '/api/v1/me/academic-guidance/assets/$assetId') {
              request.response.headers.contentType = ContentType(
                'application',
                'pdf',
              );
              request.response.add(utf8.encode('%PDF-1.4'));
              await request.response.close();
              return;
            }
            request.response.statusCode = 404;
            response = {
              'error': {'request_id': 'fixture-404', 'field_errors': []},
            };
        }
      }
      if (response != null) request.response.write(jsonEncode(response));
      await request.response.close();
    });
    final auth = AuthApi(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      cookieMode: false,
    );
    try {
      await auth.authenticate(
        email: 'synthetic@example.test',
        password: 'synthetic test password',
      );
      final owned = auth.forOwner(userId),
          guidance = GuidanceApi(owned, ownerId: userId);
      final school = RegisteredAssistantApi(owned);
      final result = await school.query(
        '봉사 조건',
        const SchoolQueryContext(
          institutionId: schoolId,
          departmentId: departmentId,
          admissionYear: 2026,
          track: 'single_major',
        ),
      );
      expect(result.status, AssistantStatus.insufficientEvidence);
      expect(
        (await guidance.personalized(
          const PersonalizedGuidanceRequest(
            question: '질문',
            context: GuidanceSchoolContext(
              institutionId: schoolId,
              departmentId: departmentId,
            ),
            records: [
              GuidanceRecordSelection(
                kind: 'activity',
                recordId: recordId,
                expectedVersion: 2,
              ),
            ],
            externalProcessingConsent: true,
          ),
        )).status,
        'evidence_only',
      );
      expect(
        (await guidance.analyze(
          const JobAnalysisRequest(
            postingText: '합성 공고',
            externalProcessingConsent: true,
          ),
        )).status,
        'not_configured',
      );
      expect((await guidance.node('home')).nodeId, 'home');
      expect(
        (await (owned as GuidanceAssetGateway).guidanceAsset(assetId))
            .contentType,
        'application/pdf',
      );
      await auth.logout();
      final previous = paths.length;
      await expectLater(guidance.node('home'), throwsA(isA<AuthFailure>()));
      expect(paths.length, previous);
    } finally {
      auth.close();
      await server.close(force: true);
    }
  });
}
