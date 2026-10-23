import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/api/admin_application_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

import 'support/auth_fixture.dart';

const applicationId = '00000000-0000-4000-8000-000000000003';
Map<String, dynamic> applicationJson() => {
  'id': applicationId,
  'applicant_id': userId,
  'institution_id': otherId,
  'institution_name': '합성대',
  'client_id': applicationId,
  'position': '합성 담당자',
  'contact_email': 'staff@example.test',
  'reason': '합성 신청',
  'status': 'pending',
  'version': 1,
  'created_at': '2026-10-23T00:00:00Z',
  'updated_at': '2026-10-23T00:00:00Z',
  'reviewed_by': null,
  'reviewed_at': null,
  'review_note': '',
  'identity_verified': false,
  'affiliation_verified': false,
  'granted_scope_id': null,
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
  test(
    'submission uses typed fields, stable retry key and owner-bound transport',
    () async {
      final calls = <http.Request>[];
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return json({...identityJson(), 'access_token': token});
          }
          calls.add(request);
          expect(request.headers['X-Unipath-Owner'], userId);
          return json(applicationJson());
        }),
      );
      addTearDown(auth.close);
      await login(auth);
      final api = SchoolAdminApplicationsApi.forOwner(auth, userId);
      const body = SchoolAdminApplicationCreate(
        institutionId: otherId,
        clientId: applicationId,
        position: '합성 담당자',
        contactEmail: 'staff@example.test',
        reason: '합성 신청',
      );
      final result = await api.submit(body);
      expect(result.status, 'pending');
      expect(calls.single.url.path, '/api/v1/me/school-admin-applications');
      expect(jsonDecode(calls.single.body), body.toJson());
      expect(result.grantedScopeId, isNull);
    },
  );

  test(
    'another account response or mismatched application ID is rejected',
    () async {
      var response = {...applicationJson(), 'applicant_id': otherId};
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
      final api = SchoolAdminApplicationsApi.forOwner(auth, userId);
      await expectLater(api.get(applicationId), throwsA(isA<AuthFailure>()));
      response = {...applicationJson(), 'id': otherId};
      await expectLater(api.get(applicationId), throwsFormatException);
    },
  );

  test(
    'a delayed response cannot cross a new login with the same account',
    () async {
      final waiting = Completer<void>();
      final response = Completer<http.Response>();
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return json({...identityJson(), 'access_token': token});
          }
          waiting.complete();
          return response.future;
        }),
      );
      addTearDown(auth.close);
      await login(auth);
      final api = SchoolAdminApplicationsApi.forOwner(auth, userId);
      final pending = expectLater(
        api.get(applicationId),
        throwsA(isA<AuthFailure>()),
      );
      await waiting.future;
      await login(auth);
      response.complete(json(applicationJson()));
      await pending;
      await expectLater(api.get(applicationId), throwsA(isA<AuthFailure>()));
    },
  );

  test('unknown states cannot be presented as a valid application', () {
    expect(
      () => SchoolAdminApplicationView.fromJson({
        ...applicationJson(),
        'status': 'granted',
      }),
      throwsFormatException,
    );
  });
}
