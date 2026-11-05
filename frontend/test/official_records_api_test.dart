import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/api/official_records_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

import 'support/auth_fixture.dart';

const batchId = '00000000-0000-4000-8000-000000000003';
Map<String, dynamic> dataJson(String kind) => {
  'kind': kind,
  'coverage': 'complete',
  'page_count': 2,
  'records_as_of': '2026-01-01',
  'context': {
    'department_id': otherId,
    'admission_year': 2026,
    'track': 'single_major',
  },
  'records': [
    {
      'client_id': batchId,
      'source_page': 2,
      ...switch (kind) {
        'academics' => {
          'course_id': otherId,
          'expected_course_version': 3,
          'completion_status': 'completed',
          'earned_credits': '3.500001',
          'original_grade': 'A+',
          'grade_points': null,
          'grade_scale': null,
        },
        'volunteers' => {'approval_status': 'pending', 'approved_hours': null},
        'certificates' => {
          'certificate_id': otherId,
          'expected_certificate_version': 7,
          'approval_status': 'approved',
          'validity_known': false,
          'expires_on': null,
        },
        'theses' => {
          'thesis_type': 'capstone',
          'approval_status': 'approved',
          'is_completed': null,
        },
        _ => <String, Object?>{},
      },
    },
  ],
};
Map<String, dynamic> batchJson({String owner = userId}) => {
  'id': batchId,
  'owner_id': owner,
  'source_id': otherId,
  'source_version': 2,
  'source_sha256': 'a' * 64,
  'institution_id': otherId,
  'client_id': batchId,
  'kind': 'academics',
  'status': 'approved',
  'version': 2,
  'context': dataJson('academics')['context'],
  'coverage': 'complete',
  'page_count': 2,
  'records_as_of': '2026-01-01',
  'record_count': 1,
  'usable_for_audit': true,
  'issues': [],
  'graduation_eligible': false,
  'created_at': '2026-10-21T00:00:00Z',
  'updated_at': '2026-10-21T00:00:00Z',
  'data': dataJson('academics'),
  'references': [],
};
http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<void> login(AuthApi auth) => auth.authenticate(
  email: 'synthetic@example.test',
  password: 'synthetic long password',
);

void main() {
  test('four closed record kinds preserve decimals, pages, unknowns and reviewed context', () {
    for (final kind in ['academics', 'volunteers', 'certificates', 'theses']) {
      final data = SchoolRecordData.fromJson(dataJson(kind));
      expect(data.kind, kind);
      final wire = data.toJson();
      expect(wire['records_as_of'], '2026-01-01');
      final record = (wire['records'] as List).single as Map;
      expect(record['source_page'], 2);
      if (kind == 'academics') {
        expect(record['earned_credits'], '3.500001');
        expect(record['original_grade'], 'A+');
        expect(record['grade_points'], isNull);
      } else if (kind == 'volunteers') {
        expect(record['approved_hours'], isNull);
      } else if (kind == 'certificates') {
        expect(record['validity_known'], false);
        expect(record['expires_on'], isNull);
      } else {
        expect(record['is_completed'], isNull);
      }
      final empty = SchoolRecordData.fromJson({
        ...dataJson(kind),
        'records': [],
      });
      expect(empty.toJson()['records'], isEmpty);
    }
    expect(
      () => SchoolRecordData.fromJson({'kind': 'student_assertion'}),
      throwsFormatException,
    );
    expect(
      () => SchoolRecordBatchView.fromJson({
        ...batchJson(),
        'graduation_eligible': true,
      }),
      throwsFormatException,
    );
  });

  test('staff sends exact draft, review flags, source digest and explicit predecessor once', () async {
    final calls = <http.Request>[];
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return json({
            ...identityJson(role: 'super_admin'),
            'access_token': token,
          });
        }
        calls.add(request);
        expect(request.headers['X-Unipath-Owner'], userId);
        expect(request.headers['Authorization'], 'Bearer $token');
        return json(batchJson(owner: otherId));
      }),
    );
    addTearDown(auth.close);
    await login(auth);
    final api = OfficialRecordsApi.forOwner(auth, userId, admin: true);
    final draft = SchoolRecordBatchCreate(
      sourceId: otherId,
      expectedSourceVersion: 2,
      clientId: batchId,
      data: SchoolRecordData.fromJson(dataJson('academics')),
    );
    await api.create(draft);
    final approval = SchoolRecordBatchApprove(
      expectedVersion: 2,
      expectedSourceSha256: 'a' * 64,
      recordsReviewed: true,
      contextReviewed: true,
      coverageReviewed: true,
      replacesBatchId: otherId,
      expectedReplacedVersion: 7,
    );
    await api.approve(batchId, approval);
    expect(calls, hasLength(2));
    expect(jsonDecode(calls.first.body), draft.toJson());
    expect(jsonDecode(calls.last.body), approval.toJson());
    expect(
      calls.last.url.path,
      '/api/v1/admin/official-record-batches/$batchId/approve',
    );
    expect(jsonDecode(calls.last.body).containsKey('owner_id'), isFalse);
  });

  test('owner history rejects mismatched owner, identifier, events and review attempts', () async {
    Map<String, dynamic> response = batchJson();
    var reads = 0;
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return json({...identityJson(), 'access_token': token});
        }
        reads++;
        expect(request.method, 'GET');
        return json(response);
      }),
    );
    addTearDown(auth.close);
    await login(auth);
    final api = OfficialRecordsApi.forOwner(auth, userId);
    expect((await api.get(batchId)).graduationEligible, false);
    response = batchJson(owner: otherId);
    await expectLater(api.get(batchId), throwsA(isA<AuthFailure>()));
    response = {...batchJson(), 'id': otherId};
    await expectLater(api.get(batchId), throwsFormatException);
    response = {
      'items': [batchJson(owner: otherId)],
      'next_cursor': null,
    };
    await expectLater(api.list(), throwsA(isA<AuthFailure>()));
    response = {
      'items': [
        {
          'id': batchId,
          'batch_id': otherId,
          'actor_id': null,
          'version': 1,
          'action': 'created',
          'reason': '',
          'occurred_at': '2026-10-21T00:00:00Z',
        },
      ],
    };
    await expectLater(api.events(batchId), throwsFormatException);
    await expectLater(
      api.revoke(
        batchId,
        const SchoolRecordBatchRevoke(expectedVersion: 2, reason: '합성'),
      ),
      throwsStateError,
    );
    expect(reads, 5);
  });

  for (final cookie in [false, true]) {
    for (final sameOwner in [false, true]) {
      test(
        'stale record response is discarded across cookie=$cookie sameOwner=$sameOwner',
        () async {
          final started = Completer<void>();
          final pending = Completer<http.Response>();
          var logins = 0;
          var calls = 0;
          final auth = AuthApi(
            cookieMode: cookie,
            client: MockClient((request) async {
              if (request.url.path.endsWith('/login')) {
                logins++;
                return json({
                  ...identityJson(
                    id: logins == 1 || sameOwner ? userId : otherId,
                  ),
                  'access_token': token,
                });
              }
              calls++;
              started.complete();
              return pending.future;
            }),
          );
          addTearDown(auth.close);
          await login(auth);
          final api = OfficialRecordsApi.forOwner(auth, userId);
          final failure = expectLater(
            api.get(batchId),
            throwsA(isA<AuthFailure>()),
          );
          await started.future;
          await login(auth);
          pending.complete(json(batchJson()));
          await failure;
          await expectLater(api.list(), throwsA(isA<AuthFailure>()));
          expect(calls, 1);
        },
      );
    }
  }
}
