import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/job_analysis_models.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';

void main() {
  test('job request preserves explicit record selection and version', () {
    final request = {
      'posting_text': '필수: Python 개발 경험',
      'records': [
        {
          'kind': 'experience',
          'record_id': '59579706-6788-48c2-82ad-6af17570a394',
          'expected_version': 2,
        },
      ],
    };
    expect(JobAnalysisRequest.fromJson(request).toJson(), request);
  });

  test(
    'unconfigured analysis stays explicit and unknown status is rejected',
    () {
      final response = {
        'analysis_id': '59579706-6788-48c2-82ad-6af17570a394',
        'status': 'not_configured',
        'reason': 'analyzer_not_configured',
        'official': false,
        'comparisons': <Object?>[],
        'missing_fields': <String>[],
      };
      final result = JobAnalysisResponse.fromJson(response);
      expect(result.toJson(), response);
      expect(result.official, isFalse);
      expect(
        () => JobAnalysisResponse.fromJson({...response, 'status': 'success'}),
        throwsFormatException,
      );
    },
  );

  test('assistant serialization preserves source applicability', () {
    final applicability = {
      'institution_id': '59579706-6788-48c2-82ad-6af17570a394',
      'department_id': null,
      'curriculum_id': null,
      'source_version': 2,
      'knowledge_document_id': 'e1834ed9-080a-4b3b-a181-a4b165b5aa4f',
      'knowledge_version': 3,
      'effective_from': '2026-03-01',
      'effective_to': null,
      'source_checked_on': '2026-10-31',
      'admission_years': [2026],
      'tracks': ['single_major'],
    };
    final result = AssistantResult.fromJson({
      'query_id': '59579706-6788-48c2-82ad-6af17570a394',
      'status': 'grounded',
      'reason': 'generated_from_evidence',
      'answer': '합성 근거 설명',
      'missing_fields': <String>[],
      'citations': [
        {
          'chunk_id': '59579706-6788-48c2-82ad-6af17570a394',
          'document_id': 'e1834ed9-080a-4b3b-a181-a4b165b5aa4f',
          'title': '합성 규정',
          'source_url': 'https://school.example.invalid/rules',
          'page': 1,
          'excerpt': '합성 원문',
          'applicability': applicability,
        },
      ],
    });
    expect(
      (result.toJson()['citations'] as List).first['applicability'],
      applicability,
    );
  });
}
