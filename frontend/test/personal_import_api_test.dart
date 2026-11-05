import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/personal_import_api.dart';
import 'package:university_path_frontend/features/api/personal_import_models.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

const owner = '00000000-0000-4000-8000-000000000001';
const importId = '00000000-0000-4000-8000-000000000002';
const localId = '00000000-0000-4000-8000-000000000003';
const serverId = '00000000-0000-4000-8000-000000000004';

class Gateway implements ApiGateway {
  Map<String, dynamic> response = receipt();
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

Map<String, dynamic> receipt({bool replayed = false}) => {
  'import_id': importId,
  'owner_id': owner,
  'committed_at': '2026-10-19T00:00:00Z',
  'record_count': 1,
  'profile_version_at_import': null,
  'replayed': replayed,
  'origin': 'personal',
  'official': false,
  'mappings': [
    {
      'resource': 'course-records',
      'client_id': localId,
      'record_id': serverId,
      'version_at_import': 1,
      'outcome': 'created',
    },
  ],
};

void main() {
  test(
    'import requires matching owner and explicit consent before transport',
    () async {
      final gateway = Gateway();
      final api = PersonalImportApi(gateway, ownerId: owner);
      for (final request in [
        const PersonalImportRequest(
          importId: importId,
          sourceOwnerId: owner,
          consentConfirmed: false,
        ),
        const PersonalImportRequest(
          importId: importId,
          sourceOwnerId: localId,
          consentConfirmed: true,
        ),
      ]) {
        await expectLater(api.create(request), throwsArgumentError);
      }
      expect(gateway.requests, isEmpty);
    },
  );

  test(
    'typed request uses local reference aliases and keeps source order',
    () async {
      final gateway = Gateway();
      final request = PersonalImportRequest(
        importId: importId,
        sourceOwnerId: owner,
        consentConfirmed: true,
        courseRecords: const [
          PersonalImportCourseRecord(
            clientId: localId,
            title: '합성 과목',
            term: '2026-1',
            category: '전공',
            credits: '3.500',
          ),
        ],
        personalCurriculumCourses: const [
          PersonalImportCurriculumCourse(
            clientId: localId,
            title: '합성 개인 과목',
            curriculumClientId: localId,
            courseRecordClientId: localId,
            category: '전공',
            credits: '3.500',
            required: true,
          ),
        ],
        portfolioCompositions: const [
          PersonalImportComposition(
            clientId: localId,
            title: '합성 구성',
            sources: [
              PersonalImportRecordReference(
                kind: 'achievement',
                clientId: serverId,
              ),
              PersonalImportRecordReference(
                kind: 'achievement',
                clientId: localId,
              ),
            ],
          ),
        ],
      );
      final result = await PersonalImportApi(
        gateway,
        ownerId: owner,
      ).create(request);
      final (method, path, body) = gateway.requests.single;
      expect((method, path), ('POST', 'me/personal-imports'));
      expect(body!['source_owner_id'], owner);
      expect(body.containsKey('owner_id'), isFalse);
      final link = (body['personal_curriculum_courses'] as List).single as Map;
      expect(link['curriculum_client_id'], localId);
      expect(link.containsKey('curriculum_id'), isFalse);
      final sources =
          ((body['portfolio_compositions'] as List).single as Map)['sources']
              as List;
      expect(sources.map((source) => (source as Map)['client_id']), [
        serverId,
        localId,
      ]);
      expect(result.mappings.single.recordId, serverId);
      expect(result.mappings.single.versionAtImport, 1);
      expect(result.official, isFalse);
    },
  );

  test(
    'receipt lookup retains historical mapping without changing local data',
    () async {
      final gateway = Gateway()..response = receipt(replayed: true);
      final result = await PersonalImportApi(
        gateway,
        ownerId: owner,
      ).get(importId);
      expect(gateway.requests.single.$1, 'GET');
      expect(gateway.requests.single.$2, 'me/personal-imports/$importId');
      expect(gateway.requests.single.$3, isNull);
      expect(result.replayed, isTrue);
      expect(result.mappings.single.recordId, serverId);
    },
  );

  test(
    'other owner, false official flags, duplicate or incomplete receipts fail',
    () async {
      final gateway = Gateway();
      final api = PersonalImportApi(gateway, ownerId: owner);
      for (final invalid in [
        {...receipt(), 'owner_id': localId},
        {...receipt(), 'import_id': localId},
        {...receipt(), 'official': true},
        {...receipt(), 'record_count': 0},
        {
          ...receipt(),
          'record_count': 2,
          'mappings': [
            ...(receipt()['mappings'] as List),
            ...(receipt()['mappings'] as List),
          ],
        },
        {...receipt(), 'record_count': 0, 'mappings': []},
      ]) {
        gateway.response = invalid;
        await expectLater(api.get(importId), throwsFormatException);
      }
    },
  );

  test('profile initialization receipt can have zero records', () async {
    final gateway = Gateway()
      ..response = {
        ...receipt(),
        'record_count': 0,
        'mappings': [],
        'profile_version_at_import': 1,
      };
    final result = await PersonalImportApi(
      gateway,
      ownerId: owner,
    ).get(importId);
    expect(result.recordCount, 0);
    expect(result.profileVersionAtImport, 1);
  });

  test('event transport preserves explicit instant and display timezone', () {
    final event = PersonalImportEvent(
      clientId: localId,
      title: '합성 일정',
      startsAt: DateTime.parse('2026-10-19T10:00:00+09:00'),
      endsAt: DateTime.parse('2026-10-19T11:00:00+09:00'),
      timeZone: 'Asia/Seoul',
      category: 'personal',
    );
    final value = event.toJson();
    expect(value['starts_at'], '2026-10-19T01:00:00.000Z');
    expect(value['time_zone'], 'Asia/Seoul');
    expect(
      PersonalImportEvent.fromJson(Map<String, dynamic>.from(value)).startsAt,
      event.startsAt,
    );
  });
}
