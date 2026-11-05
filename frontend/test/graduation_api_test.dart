import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/api/graduation_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

import 'support/auth_fixture.dart';

const auditId = '00000000-0000-4000-8000-000000000003';
const context = GraduationContext(
  institutionId: otherId,
  departmentId: otherId,
  curriculumId: otherId,
  admissionYear: 2026,
  track: 'single_major',
);
Map<String, dynamic> auditJson() => {
  'id': auditId,
  'owner_id': userId,
  'client_id': auditId,
  'version': 1,
  'context': context.toJson(),
  'evaluated_on': '2026-10-21',
  'created_at': '2026-10-21T00:00:00Z',
  'official': true,
  'label': '학교 검토 자료 기준 졸업요건 감사',
  'status': 'satisfied',
  'reason': 'all_requirements_met',
  'catalog_complete': true,
  'eligible_as_of': true,
  'catalog_review_id': otherId,
  'catalog_review_version': 1,
  'catalog_digest': 'a' * 64,
  'criteria': [],
  'records': [],
  'record_evidence': [],
  'results': [
    {
      'rule_set_id': otherId,
      'rule_set_version': 2,
      'rule_id': auditId,
      'title': '합성 요건',
      'status': 'satisfied',
      'reason': 'threshold_met',
      'current': '3.500001',
      'required': '3',
      'deficit': '0',
      'missing_course_ids': [],
      'uncertain_course_ids': [],
      'evidence_record_ids': [otherId],
    },
  ],
  'issues': [],
  'current_usable': true,
  'current_issues': [],
};
http.Response json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<void> login(AuthApi auth) => auth.authenticate(
  email: 'synthetic@example.test',
  password: 'synthetic long password',
);

void main() {
  test('historical eligibility is retained separately from current usability and exact amounts', () {
    final data = auditJson()..['current_usable'] = false;
    data['current_issues'] = [
      {'kind': 'records', 'reason': 'approved_records_changed'},
    ];
    final result = GraduationAuditView.fromJson(data);
    expect(result.eligibleAsOf, true);
    expect(result.currentUsable, false);
    expect(result.evaluatedOn, '2026-10-21');
    expect(result.results.single.current, '3.500001');
    expect(result.currentIssues.single.reason, 'approved_records_changed');
    expect(
      () => GraduationAuditView.fromJson({...data, 'official': false}),
      throwsFormatException,
    );
  });

  test('audit creation sends only reviewed context, date and stable replay key once', () async {
    final calls = <http.Request>[];
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return json({...identityJson(), 'access_token': token});
        }
        calls.add(request);
        expect(request.headers['X-Unipath-Owner'], userId);
        expect(request.headers['Authorization'], 'Bearer $token');
        return json(auditJson());
      }),
    );
    addTearDown(auth.close);
    await login(auth);
    final api = GraduationApi.forOwner(auth, userId);
    final request = GraduationAuditCreate(
      context: context,
      asOf: '2026-10-21',
      clientId: auditId,
    );
    final result = await api.create(request);
    expect(result.eligibleAsOf, true);
    expect(calls, hasLength(1));
    expect(calls.single.url.path, '/api/v1/me/graduation-audits');
    expect(jsonDecode(calls.single.body), request.toJson());
    expect(jsonDecode(calls.single.body).keys.toSet(), {
      'context',
      'as_of',
      'client_id',
    });
  });

  test('owner, date, scope, ID and eligibility mismatches cannot be displayed as the requested result', () async {
    var response = auditJson();
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return json({...identityJson(), 'access_token': token});
        }
        return json(response);
      }),
    );
    addTearDown(auth.close);
    await login(auth);
    final api = GraduationApi.forOwner(auth, userId);
    response = {...auditJson(), 'owner_id': otherId};
    await expectLater(api.get(auditId), throwsA(isA<AuthFailure>()));
    response = {...auditJson(), 'id': otherId};
    await expectLater(api.get(auditId), throwsFormatException);
    response = {...auditJson(), 'eligible_as_of': false};
    await expectLater(api.get(auditId), throwsFormatException);
    response = {...auditJson(), 'evaluated_on': '2026-10-20'};
    await expectLater(
      api.create(
        const GraduationAuditCreate(
          context: context,
          asOf: '2026-10-21',
          clientId: auditId,
        ),
      ),
      throwsFormatException,
    );
    response = {
      'items': [
        {...auditJson(), 'owner_id': otherId},
      ],
      'next_cursor': null,
    };
    await expectLater(api.list(), throwsA(isA<AuthFailure>()));
  });

  for (final cookie in [false, true]) {
    for (final sameOwner in [false, true]) {
      test(
        'audit result and capability cannot cross login cookie=$cookie sameOwner=$sameOwner',
        () async {
          final started = Completer<void>();
          final pending = Completer<http.Response>();
          var logins = 0;
          var reads = 0;
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
              reads++;
              started.complete();
              return pending.future;
            }),
          );
          addTearDown(auth.close);
          await login(auth);
          final api = GraduationApi.forOwner(auth, userId);
          final failure = expectLater(
            api.get(auditId),
            throwsA(isA<AuthFailure>()),
          );
          await started.future;
          await login(auth);
          pending.complete(json(auditJson()));
          await failure;
          await expectLater(api.list(), throwsA(isA<AuthFailure>()));
          expect(reads, 1);
        },
      );
    }
  }
}
