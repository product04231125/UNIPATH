import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/api/student_api_models.dart';
import 'package:university_path_frontend/features/api/student_catalog_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

const owner = '00000000-0000-4000-8000-000000000001';
const recordId = '00000000-0000-4000-8000-000000000002';
const clientId = '00000000-0000-4000-8000-000000000003';

class Gateway implements ApiGateway {
  final requests = <(String, String, Map<String, Object?>?)>[];
  Map<String, dynamic> response = {};
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

Map<String, dynamic> course() => {
  'id': recordId,
  'owner_id': owner,
  'version': 1,
  'client_id': clientId,
  'created_at': '2026-10-19T00:00:00Z',
  'updated_at': '2026-10-19T00:00:00Z',
  'origin': 'personal',
  'official': false,
  'title': '합성 수강',
  'detail': '',
  'term': '2026-1',
  'category': '전공',
  'credits': '3.125',
  'completion': 'recorded',
};

void main() {
  test('typed creation preserves decimal precision and does not send ownership or versions', () async {
    final gateway = Gateway()..response = course();
    final api = StudentApi(gateway, ownerId: owner);
    final result = await api.create(
      StudentResources.courseRecords,
      const StudentCourseRecordCreate(
        title: '합성 수강',
        term: '2026-1',
        category: '전공',
        credits: '3.125',
        completion: 'recorded',
        clientId: clientId,
      ),
    );
    final (method, path, body) = gateway.requests.single;
    expect((method, path), ('POST', 'me/course-records'));
    expect(body!['credits'], '3.125');
    expect(body['client_id'], clientId);
    expect(body.keys, isNot(contains('owner_id')));
    expect(body.keys, isNot(contains('version')));
    expect(result.data.credits, '3.125');
    expect(result.id, recordId);
  });

  test('PATCH preserves omitted fields and explicit null without sending a full record', () async {
    final gateway = Gateway()
      ..response = {
        ...course(),
        'title': '합성 자격',
        'earned_on': null,
        'version': 2,
      };
    final api = StudentApi(gateway, ownerId: owner);
    final result = await api.patch(
      StudentResources.credentialRecords,
      recordId,
      expectedVersion: 1,
      changes: {'earned_on': null},
    );
    expect(gateway.requests.single.$3, {
      'expected_version': 1,
      'earned_on': null,
    });
    expect(result.data.earnedOn, isNull);
    await expectLater(
      api.patch(
        StudentResources.credentialRecords,
        recordId,
        expectedVersion: 2,
        changes: {'owner_id': clientId},
      ),
      throwsArgumentError,
    );
    expect(gateway.requests.length, 1);
  });

  test('cursor pages retain identity and reject responses for another account or official origin', () async {
    final gateway = Gateway()
      ..response = {
        'items': [course()],
        'next_cursor': recordId,
      };
    final api = StudentApi(gateway, ownerId: owner);
    final page = await api.list(
      StudentResources.courseRecords,
      cursor: clientId,
      limit: 2,
    );
    expect(page.nextCursor, recordId);
    expect(Uri.parse(gateway.requests.single.$2).queryParameters, {
      'limit': '2',
      'cursor': clientId,
    });
    gateway.response = {
      'items': [
        {...course(), 'owner_id': clientId},
      ],
      'next_cursor': null,
    };
    await expectLater(
      api.list(StudentResources.courseRecords),
      throwsFormatException,
    );
    gateway.response = {
      'items': [
        {...course(), 'official': true},
      ],
      'next_cursor': null,
    };
    await expectLater(
      api.list(StudentResources.courseRecords),
      throwsFormatException,
    );
  });

  test('structured references keep order and event instants preserve the same moment', () {
    const document = StudentApplicationDocumentCreate(
      title: '합성 초안',
      target: '합성 지원처',
      role: '개발',
      documentType: '자기소개서',
      sources: [
        StudentRecordReference(kind: 'experience', recordId: recordId),
        StudentRecordReference(kind: 'achievement', recordId: clientId),
      ],
    );
    expect(document.toJson()['sources'], [
      {'kind': 'experience', 'record_id': recordId},
      {'kind': 'achievement', 'record_id': clientId},
    ]);
    final event = StudentEventCreate.fromJson({
      'title': '합성 일정',
      'starts_at': '2026-10-19T00:00:00+09:00',
      'ends_at': '2026-10-19T01:00:00+09:00',
      'time_zone': 'Asia/Seoul',
      'category': 'academic',
    });
    expect(event.toJson()['starts_at'], '2026-10-18T15:00:00.000Z');
    expect(event.timeZone, 'Asia/Seoul');
  });

  test(
    'catalog uses read-only typed DTOs and explicit context/date filters',
    () async {
      final gateway = Gateway()
        ..response = {
          'items': [
            {
              'id': recordId,
              'version': 1,
              'name': '합성 과목',
              'institution_id': owner,
              'code': 'CS1',
              'credits': '3.5',
            },
          ],
          'next_cursor': null,
        };
      final page = await StudentCatalogApi(gateway).list(
        StudentCatalogResources.courses,
        institutionId: owner,
        curriculumId: clientId,
        asOf: '2026-10-19',
      );
      expect(page.items.single.credits, '3.5');
      final request = gateway.requests.single;
      expect(request.$1, 'GET');
      expect(Uri.parse(request.$2).queryParameters['curriculum_id'], clientId);
      expect(Uri.parse(request.$2).queryParameters['as_of'], '2026-10-19');
      expect(request.$3, isNull);
    },
  );
}
