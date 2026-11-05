import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/api/student_api_models.dart';
import 'package:university_path_frontend/features/auth/account_security_gateway.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

// Disposable synthetic loopback API only; no real operator credentials.
// flutter test test/server_account_security_http_test.dart \
// --dart-define=SECURITY_TEST_BASE_URL=http://localhost:8057
const password = 'synthetic initial security password 2026';
const replacement = '  합성 변경 비밀번호 문장 2026  ';

class LoseSecurityResponse extends http.BaseClient {
  final inner = http.Client();
  bool lose = true;
  int changes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (request.method == 'POST' &&
        request.url.path.endsWith('/change-password')) {
      changes++;
      if (lose) {
        lose = false;
        await response.stream.drain<void>();
        throw http.ClientException('Synthetic lost committed response');
      }
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  const base = String.fromEnvironment('SECURITY_TEST_BASE_URL');
  AuthApi api({http.Client? client}) {
    final uri = Uri.parse(base);
    expect(uri.scheme, 'http');
    expect(['localhost', '127.0.0.1'], contains(uri.host));
    final auth = AuthApi(baseUrl: uri, cookieMode: false, client: client);
    addTearDown(auth.close);
    return auth;
  }

  Future<(String, String)> register(AuthApi auth) async {
    final email = 'account-security-${PersonalRecord.newId()}@example.test';
    final user = await auth.authenticate(
      email: email,
      password: password,
      displayName: '합성 보안 HTTP 검증',
    );
    return (email, user.id);
  }

  Future<String> course(AuthApi auth, String owner) async =>
      (await StudentApi(auth.forOwner(owner), ownerId: owner).create(
        StudentResources.courseRecords,
        const StudentCourseRecordCreate(
          title: '합성 보존 수강',
          term: '2026-2',
          category: '전공',
          credits: '3',
          completion: 'recorded',
        ),
      )).id;
  test('real password change revokes every native session and preserves personal records with exact raw password', () async {
    final first = api(), second = api(), verifier = api();
    final (email, owner) = await register(first);
    await second.authenticate(email: email, password: password);
    expect((await second.me())!.id, owner);
    final id = await course(first, owner);
    final gateway = first.securityForOwner(owner);
    await expectLater(
      gateway.changePassword(
        oldPassword: 'synthetic wrong old password',
        newPassword: replacement,
      ),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'wrong old', 422)),
    );
    expect(await gateway.checkSession(), AccountSessionStatus.active);
    expect((await second.me())!.id, owner);
    await gateway.changePassword(
      oldPassword: password,
      newPassword: replacement,
    );
    expect(await first.me(), isNull);
    expect(await second.me(), isNull);
    await expectLater(
      verifier.authenticate(email: email, password: password),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'old rejected', 401)),
    );
    final current = await verifier.authenticate(
      email: email,
      password: replacement,
    );
    expect(current.id, owner);
    final saved = await StudentApi(
      verifier.forOwner(owner),
      ownerId: owner,
    ).get(StudentResources.courseRecords, id);
    expect(saved.data.title, '합성 보존 수강');
    expect(saved.version, 1);
    await expectLater(
      gateway.logoutAll(),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'old gateway', 403)),
    );
    expect((await verifier.me())!.id, owner);
    await verifier.logout();
  }, skip: base.isEmpty);
  test('real all-device logout revokes both sessions without changing password or deleting records', () async {
    final first = api(), second = api(), verifier = api();
    final (email, owner) = await register(first);
    await second.authenticate(email: email, password: password);
    final id = await course(first, owner);
    await first.securityForOwner(owner).logoutAll();
    expect(await first.me(), isNull);
    expect(await second.me(), isNull);
    await verifier.authenticate(email: email, password: password);
    expect(
      (await StudentApi(
        verifier.forOwner(owner),
        ownerId: owner,
      ).get(StudentResources.courseRecords, id)).version,
      1,
    );
    await verifier.logout();
  }, skip: base.isEmpty);
  test('real committed response loss is only reported as expired until user verifies the new password', () async {
    final transport = LoseSecurityResponse();
    final first = api(client: transport), second = api(), verifier = api();
    final (email, owner) = await register(first);
    await second.authenticate(email: email, password: password);
    final gateway = first.securityForOwner(owner);
    await expectLater(
      gateway.changePassword(oldPassword: password, newPassword: replacement),
      throwsA(isA<AuthFailure>()),
    );
    expect(transport.changes, 1);
    expect(await gateway.checkSession(), AccountSessionStatus.expired);
    expect(transport.changes, 1);
    expect(await second.me(), isNull);
    await expectLater(
      verifier.authenticate(email: email, password: password),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'old rejected', 401)),
    );
    expect(
      (await verifier.authenticate(email: email, password: replacement)).id,
      owner,
    );
    await verifier.logout();
  }, skip: base.isEmpty);
  test('real newer account is not logged out or modified by an old security capability', () async {
    final current = api(), oldDevice = api();
    final (emailA, ownerA) = await register(current);
    await oldDevice.authenticate(email: emailA, password: password);
    final old = current.securityForOwner(ownerA);
    final (_, ownerB) = await register(current);
    expect(ownerB, isNot(ownerA));
    await expectLater(
      old.logoutAll(),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'stale', 403)),
    );
    await expectLater(
      old.changePassword(oldPassword: password, newPassword: replacement),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'stale', 403)),
    );
    expect((await current.me())!.id, ownerB);
    expect((await oldDevice.me())!.id, ownerA);
    await current.logout();
    await oldDevice.logout();
  }, skip: base.isEmpty);
}
