import 'package:university_path_frontend/features/auth/auth_api.dart';

const userId = '00000000-0000-4000-8000-000000000001';
const otherId = '00000000-0000-4000-8000-000000000002';
const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Map<String, Object?> identityJson({String role = 'user'}) => {
  'user': {
    'id': userId,
    'email': 'synthetic@example.test',
    'display_name': '합성 학생',
    'role': role,
    'account_status': 'active',
    'version': 1,
  },
  'admin_scopes': <Map<String, Object?>>[],
  'permission_version': 1,
  'session_expires_at': '2030-01-01T00:00:00Z',
};

class FakeAuth implements AuthGateway {
  FakeAuth({this.role = 'user'});
  final String role;
  bool signedIn = false;
  int logouts = 0;
  @override
  Future<AuthIdentity> authenticate({
    required String email,
    required String password,
    String? displayName,
  }) async {
    signedIn = true;
    return AuthIdentity.fromJson(
      Map<String, dynamic>.from(identityJson(role: role)),
    );
  }

  @override
  Future<AuthIdentity?> me() async => signedIn
      ? AuthIdentity.fromJson(
          Map<String, dynamic>.from(identityJson(role: role)),
        )
      : null;
  @override
  Future<void> logout() async {
    logouts++;
    signedIn = false;
  }

  @override
  Future<List<Map<String, dynamic>>> institutions() async => [
    {'id': otherId, 'name': '서버 합성 학교'},
  ];
  @override
  void close() {}
}
