import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/academic_guidance_models.dart';
import 'package:university_path_frontend/features/api/guidance_api.dart';
import 'package:university_path_frontend/features/api/job_analysis_models.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

class CapturingGateway extends ApiGateway {
  final calls = <(String, String, Map<String, Object?>?)>[];
  Map<String, dynamic> response = {};
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    calls.add((method, path, body));
    return response;
  }
}

void main() {
  test(
    'node uses server ID and audit query, invalid ID sends no request',
    () async {
      final gateway = CapturingGateway()
        ..response = {
          'schema_version': 'academic-click-v3',
          'node_id': 'calendar:2026:11',
          'state': 'ready',
          'reason': 'calendar_snapshot',
          'message': '안내',
          'cards': [],
          'warnings': [],
          'buttons': [],
        };
      final api = GuidanceApi(gateway);
      await api.node('calendar:2026:11', auditId: 'audit-id');
      expect(
        gateway.calls.single.$2,
        'me/academic-guidance/nodes/calendar:2026:11?audit_id=audit-id',
      );
      await expectLater(api.node('../other'), throwsFormatException);
      expect(gateway.calls.length, 1);
    },
  );
  test(
    'job analysis sends selected version and consent without school IDs',
    () async {
      final gateway = CapturingGateway()
        ..response = {
          'analysis_id': 'analysis',
          'status': 'not_configured',
          'reason': 'analyzer_not_configured',
          'official': false,
          'comparisons': [],
          'missing_fields': [],
        };
      await GuidanceApi(gateway).analyze(
        const JobAnalysisRequest(
          postingText: '공고 본문',
          externalProcessingConsent: true,
          records: [
            PersonalEvidenceSelection(
              kind: 'experience',
              recordId: 'record',
              expectedVersion: 3,
            ),
          ],
        ),
      );
      expect(gateway.calls.single.$2, 'me/job-analyses');
      expect(gateway.calls.single.$3, {
        'posting_text': '공고 본문',
        'external_processing_consent': true,
        'records': [
          {'kind': 'experience', 'record_id': 'record', 'expected_version': 3},
        ],
      });
    },
  );
  test(
    'personalized sends registered IDs and separates evidence-only payload',
    () async {
      final gateway = CapturingGateway()
        ..response = {
          'query_id': 'query',
          'status': 'evidence_only',
          'reason': 'generator_not_configured',
          'official': false,
          'school': {
            'query_id': 'school',
            'status': 'insufficient_evidence',
            'reason': 'no_approved_matching_evidence',
          },
          'personal': {'records': [], 'official': false},
        };
      final response = await GuidanceApi(gateway).personalized(
        const PersonalizedGuidanceRequest(
          question: '질문',
          context: GuidanceSchoolContext(
            institutionId: 'school',
            departmentId: 'department',
          ),
          externalProcessingConsent: true,
        ),
      );
      expect(gateway.calls.single.$2, 'me/personalized-guidance');
      expect(
        (gateway.calls.single.$3!['context'] as Map)['institution_id'],
        'school',
      );
      expect(gateway.calls.single.$3!['external_processing_consent'], true);
      expect(response.answer, isNull);
      expect(response.personal.records, isEmpty);
    },
  );
}
