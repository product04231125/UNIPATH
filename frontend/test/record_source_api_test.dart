import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/api/record_source_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

import 'support/auth_fixture.dart';

const sourceId = '00000000-0000-4000-8000-000000000003';
final pdf = Uint8List.fromList(utf8.encode('%PDF-1.7\n% SYNTHETIC\n%%EOF\n'));
Map<String, Object?> sourceJson() => {
  'id': sourceId,
  'owner_id': userId,
  'client_id': sourceId,
  'institution_id': otherId,
  'department_id': null,
  'curriculum_id': null,
  'document_kind': 'transcript',
  'issued_on': '2026-01-01',
  'filename': '합성 성적.pdf',
  'sha256': 'a' * 64,
  'byte_count': pdf.length,
  'status': 'submitted',
  'version': 1,
  'created_at': '2026-10-21T00:00:00Z',
  'updated_at': '2026-10-21T00:00:00Z',
  'graduation_eligible': false,
};
http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
RecordSourceUpload uploadMetadata({bool consent = true}) => RecordSourceUpload(
  clientId: sourceId,
  institutionId: otherId,
  documentKind: RecordSourceKind.transcript,
  issuedOn: '2026-01-01',
  filename: '합성 성적.pdf',
  reviewConsentConfirmed: consent,
);

Future<void> login(AuthApi auth) => auth.authenticate(
  email: 'synthetic@example.test',
  password: 'synthetic long password',
);

void main() {
  test('native upload transmits exact PDF, explicit consent, stable client ID and captured owner', () async {
    final calls = <http.Request>[];
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        calls.add(request);
        if (request.url.path.endsWith('/login')) {
          return json({...identityJson(), 'access_token': token});
        }
        expect(request.headers['X-Unipath-Owner'], userId);
        expect(request.headers['Authorization'], 'Bearer $token');
        if (request.method == 'POST') {
          expect(request.headers['content-type'], 'application/pdf');
          expect(request.bodyBytes, pdf);
          expect(request.url.hasQuery, isFalse);
          final metadata = jsonDecode(
            utf8.decode(
              base64Url.decode(request.headers['X-Unipath-Source-Metadata']!),
            ),
          ) as Map;
          expect(metadata['filename'], '합성 성적.pdf');
          expect(metadata['review_consent_confirmed'], true);
          expect(metadata['client_id'], sourceId);
          expect(metadata.containsKey('owner_id'), isFalse);
          return json(sourceJson(), 201);
        }
        if (request.url.path.endsWith('/file')) {
          return http.Response.bytes(
            pdf,
            200,
            headers: {'content-type': 'application/octet-stream'},
          );
        }
        return json({
          'items': [sourceJson()],
          'next_cursor': null,
        });
      }),
    );
    addTearDown(auth.close);
    await login(auth);
    final api = RecordSourceApi.forOwner(auth, userId);
    final uploaded = await api.upload(uploadMetadata(), pdf);
    expect(uploaded.status, RecordSourceStatus.submitted);
    expect(uploaded.graduationEligible, isFalse);
    expect(await api.download(sourceId), pdf);
    expect(
      (await api.list(status: RecordSourceStatus.submitted)).items.single.id,
      sourceId,
    );
    expect(
      calls.where((r) => r.method == 'POST' && !r.url.path.endsWith('/login')),
      hasLength(1),
    );
  });

  for (final cookie in [false, true]) {
    for (final sameOwner in [false, true]) {
      test(
        'late file response and stale capability cannot cross a ${cookie ? 'cookie' : 'native'} ${sameOwner ? 'same-owner relogin' : 'account change'}',
        () async {
          final started = Completer<void>();
          final pending = Completer<http.Response>();
          var logins = 0;
          var uploads = 0;
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
              uploads++;
              if (cookie) {
                expect(request.headers.containsKey('Authorization'), isFalse);
              }
              expect(request.headers['X-Unipath-Owner'], userId);
              started.complete();
              return pending.future;
            }),
          );
          addTearDown(auth.close);
          await login(auth);
          final files = auth.recordFilesForOwner(userId);
          final attempt = files.upload(
            'me/official-record-sources',
            pdf,
            metadata: uploadMetadata().toJson(),
          );
          final failure = expectLater(
            attempt,
            throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 403)),
          );
          await started.future;
          await login(auth);
          pending.complete(json(sourceJson(), 201));
          await failure;
          await expectLater(
            files.download('me/official-record-sources/$sourceId/file'),
            throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 403)),
          );
          expect(uploads, 1);
          expect(
            () => auth.recordFilesForOwner(sameOwner ? userId : otherId),
            returnsNormally,
          );
        },
      );
    }
  }

  test(
    'file capability blocks foreign paths and oversize bodies before sending',
    () async {
      var count = 0;
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          count++;
          return json({...identityJson(), 'access_token': token});
        }),
      );
      addTearDown(auth.close);
      await login(auth);
      final files = auth.recordFilesForOwner(userId);
      for (final path in [
        'https://example.invalid/file',
        '../auth/logout',
        'me/official-record-sources/../file',
      ]) {
        await expectLater(files.download(path), throwsA(isA<AuthFailure>()));
      }
      await expectLater(
        files.upload(
          'me/official-record-sources',
          Uint8List(2 * 1024 * 1024 + 1),
          metadata: uploadMetadata().toJson(),
        ),
        throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 413)),
      );
      expect(count, 1);
    },
  );

  test('explicit consent and both reviewer attestations are mandatory without implicit network writes', () async {
    var count = 0;
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        count++;
        return json({...identityJson(), 'access_token': token});
      }),
    );
    addTearDown(auth.close);
    await login(auth);
    final owner = RecordSourceApi.forOwner(auth, userId);
    await expectLater(
      owner.upload(uploadMetadata(consent: false), pdf),
      throwsFormatException,
    );
    final admin = RecordSourceApi.forOwner(auth, userId, admin: true);
    expect(
      () => admin.verify(
        sourceId,
        expectedVersion: 1,
        expectedSha256: 'a' * 64,
        schoolIssuedConfirmed: true,
        subjectIdentityConfirmed: false,
      ),
      throwsFormatException,
    );
    expect(count, 1);
  });

  test('server errors do not expose private response bodies and never retry uploads', () async {
    var uploads = 0;
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return json({...identityJson(), 'access_token': token});
        }
        uploads++;
        return json({'private': 'SYNTHETIC PRIVATE FILE CONTENT'}, 403);
      }),
    );
    addTearDown(auth.close);
    await login(auth);
    await expectLater(
      auth
          .recordFilesForOwner(userId)
          .upload(
            'me/official-record-sources',
            pdf,
            metadata: uploadMetadata().toJson(),
          ),
      throwsA(
        isA<AuthFailure>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.message, 'message', isNot(contains('PRIVATE'))),
      ),
    );
    expect(uploads, 1);
  });

  test('unknown states and graduation eligibility cannot silently become valid source metadata', () {
    for (final change in [
      {'status': 'published'},
      {'graduation_eligible': true},
      {'sha256': 'bad'},
    ]) {
      expect(
        () => RecordSource.fromJson({...sourceJson(), ...change}),
        throwsA(anything),
      );
    }
    final source = RecordSource.fromJson({
      ...sourceJson(),
      'status': 'verified',
    });
    expect(source.status, RecordSourceStatus.verified);
    expect(source.graduationEligible, isFalse);
  });

  test(
    'owner source adapter rejects metadata returned for another account',
    () async {
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return json({...identityJson(), 'access_token': token});
          }
          if (request.url.path.endsWith(sourceId)) {
            return json({...sourceJson(), 'owner_id': otherId});
          }
          return json({
            'items': [
              {...sourceJson(), 'owner_id': otherId},
            ],
            'next_cursor': null,
          });
        }),
      );
      addTearDown(auth.close);
      await login(auth);
      final api = RecordSourceApi.forOwner(auth, userId);
      for (final response in [() => api.get(sourceId), () => api.list()]) {
        await expectLater(
          response(),
          throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 403)),
        );
      }
    },
  );

  test('malformed upload response exposes no file text and triggers no implicit retry', () async {
    var count = 0;
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return json({...identityJson(), 'access_token': token});
        }
        count++;
        return http.Response(
          'SYNTHETIC PRIVATE PDF TEXT',
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(auth.close);
    await login(auth);
    await expectLater(
      auth
          .recordFilesForOwner(userId)
          .upload(
            'me/official-record-sources',
            pdf,
            metadata: uploadMetadata().toJson(),
          ),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.message,
          'safe error',
          isNot(contains('PRIVATE')),
        ),
      ),
    );
    expect(count, 1);
  });
}
