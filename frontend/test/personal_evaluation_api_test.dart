import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/personal_evaluation_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

const ownerId = '00000000-0000-4000-8000-000000000001';
const curriculumId = '00000000-0000-4000-8000-000000000002';
const ruleId = '00000000-0000-4000-8000-000000000003';
const resultId = '00000000-0000-4000-8000-000000000004';

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

Map<String, dynamic> summary() => {
  'id': resultId,
  'owner_id': ownerId,
  'client_id': null,
  'version': 1,
  'curriculum_id': curriculumId,
  'curriculum_version': 1,
  'curriculum_title': '합성 과정',
  'created_at': '2026-10-19T00:00:00Z',
  'evaluated_on': '2026-10-19',
  'official': false,
  'label': PersonalEvaluationSummary.personalLabel,
  'status': 'needs_review',
  'reason': 'record_data_needs_review',
};

Map<String, dynamic> detail() => {
  ...summary(),
  'results': [
    {
      'rule_id': ruleId,
      'rule_version': 1,
      'title': '합성 기준',
      'status': 'needs_review',
      'reason': 'explicit_condition_required',
      'current': null,
      'required': null,
      'deficit': null,
      'missing_course_ids': [],
      'uncertain_course_ids': [],
      'evidence_record_ids': [],
      'condition': null,
    },
  ],
  'source_versions': [
    {'kind': 'personal-curricula', 'record_id': curriculumId, 'version': 1},
  ],
};

void main() {
  test('calculation request has explicit typed criteria and no official/owner override', () async {
    final gateway = Gateway()..response = detail();
    final result = await PersonalEvaluationApi(gateway, ownerId: ownerId)
        .create(
          const PersonalEvaluationRequest(
            curriculumId: curriculumId,
            expectedCurriculumVersion: 1,
            clientId: resultId,
            asOf: '2026-10-19',
            calculations: [
              PersonalRuleCalculation(
                ruleId: ruleId,
                expectedVersion: 1,
                condition: PersonalCreditCondition(minimum: '3.125'),
              ),
            ],
          ),
        );
    final (method, path, body) = gateway.requests.single;
    expect((method, path), ('POST', 'me/personal-evaluations'));
    expect(body!['client_id'], resultId);
    expect(body['owner_id'], isNull);
    expect(body.containsKey('official'), isFalse);
    final calculation = (body['calculations'] as List).single as Map;
    expect((calculation['condition'] as Map)['minimum'], '3.125');
    expect(result.status, PersonalEvaluationStatus.needsReview);
    expect(result.results.single.current, isNull);
    expect(result.results.single.condition, isNull);
    expect(result.label, PersonalEvaluationSummary.personalLabel);
  });

  test('five condition variants roundtrip source selections and explicit observations', () {
    const conditions = <PersonalCondition>[
      PersonalCreditCondition(minimum: '10', courseRecordIds: [ruleId]),
      PersonalCourseCondition(
        courses: [
          PersonalRequiredCourse(
            curriculumCourseId: ruleId,
            minimumGradePoints: '3',
            comparisonGradeScale: '4.5',
          ),
        ],
        grades: [
          PersonalGradeObservation(
            courseRecordId: resultId,
            points: '3.2',
            scale: '4.5',
          ),
        ],
      ),
      PersonalVolunteerCondition(minimum: '10', activityIds: [ruleId]),
      PersonalCertificateCondition(
        certificates: [PersonalCertificateObservation(credentialId: ruleId)],
      ),
      PersonalThesisCondition(
        thesisType: 'capstone',
        records: [PersonalThesisObservation(achievementId: ruleId)],
      ),
    ];
    for (final value in conditions) {
      expect(
        PersonalCondition.fromJson(value.toJson()).toJson(),
        value.toJson(),
      );
    }
    expect(
      (conditions[3].toJson()['certificates'] as List).single['validity_known'],
      isFalse,
    );
    expect(
      (conditions[4].toJson()['records'] as List).single['approval'],
      'needs_review',
    );
  });

  test('another owner or official-looking result is rejected', () async {
    final gateway = Gateway()..response = {...detail(), 'owner_id': ruleId};
    final api = PersonalEvaluationApi(gateway, ownerId: ownerId);
    await expectLater(api.get(resultId), throwsFormatException);
    gateway.response = {...detail(), 'official': true};
    await expectLater(api.get(resultId), throwsFormatException);
    gateway.response = {...detail(), 'label': '공식 졸업 가능'};
    await expectLater(api.get(resultId), throwsFormatException);
  });

  test('history reads lightweight summaries and deletion carries the known version', () async {
    final gateway = Gateway()
      ..response = {
        'items': [summary()],
        'next_cursor': resultId,
      };
    final api = PersonalEvaluationApi(gateway, ownerId: ownerId);
    final page = await api.list(curriculumId: curriculumId, limit: 2);
    expect(page.items.single.curriculumTitle, '합성 과정');
    expect(page.nextCursor, resultId);
    expect(
      Uri.parse(gateway.requests.single.$2).queryParameters['curriculum_id'],
      curriculumId,
    );
    await api.remove(resultId, expectedVersion: 1);
    expect(gateway.requests.last, (
      'DELETE',
      'me/personal-evaluations/$resultId?expected_version=1',
      null,
    ));
  });
}
