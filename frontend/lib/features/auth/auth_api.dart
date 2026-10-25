import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_role.dart';
import 'account_security_gateway.dart';
import 'auth_http_stub.dart' if (dart.library.js_interop) 'auth_http_web.dart';
import 'record_files_gateway.dart';
import '../api/school_signup_models.dart';

class SchoolSignupResult {
  const SchoolSignupResult(this.identity, this.signup);
  final AuthIdentity identity;
  final SchoolAdminSignupView signup;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.status, this.fields = const []});
  final String message;
  final int? status;
  final List<String> fields;
}

class AuthIdentity {
  AuthIdentity.fromJson(Map<String, dynamic> value)
    : id = value['user']['id'] as String,
      email = value['user']['email'] as String,
      displayName = value['user']['display_name'] as String,
      version = value['user']['version'] as int,
      role = switch (value['user']['role']) {
        'user' => AppRole.user,
        'school_admin' => AppRole.schoolAdmin,
        'super_admin' => AppRole.superAdmin,
        _ => throw const FormatException('Unknown server role'),
      },
      expiresAt = DateTime.parse(value['session_expires_at'] as String),
      scopes = List<Map<String, dynamic>>.from(value['admin_scopes'] as List) {
    if (value['user']['account_status'] != 'active' ||
        !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) {
      throw const FormatException('Inactive or invalid server identity');
    }
  }
  final String id, email, displayName;
  final int version;
  final AppRole role;
  final DateTime expiresAt;
  final List<Map<String, dynamic>> scopes;
}

abstract class AuthGateway {
  Future<AuthIdentity> authenticate({
    required String email,
    required String password,
    String? displayName,
  });
  Future<AuthIdentity?> me();
  Future<void> logout();
  Future<List<Map<String, dynamic>>> institutions();
  void close();
}

abstract class ApiGateway {
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]);
}

/// Browser: HttpOnly cookie. Native: opaque token in this process only.
class AuthApi implements AuthGateway, ApiGateway {
  AuthApi({http.Client? client, Uri? baseUrl, bool? cookieMode})
    : _client = client ?? createAuthHttpClient(),
      _base =
          baseUrl ??
          Uri.parse(
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://localhost:8010',
            ),
          ),
      _cookieMode = cookieMode ?? kIsWeb;
  final http.Client _client;
  final Uri _base;
  final bool _cookieMode;
  String? _token;
  String? _ownerId;
  int _sessionEpoch = 0;

  /// Pin a workspace to this login. Server checks the owner as well, including
  /// cookies changed by a different browser tab before our next session poll.
  ApiGateway forOwner(String ownerId) {
    if (_ownerId != ownerId) {
      throw const AuthFailure('다시 로그인해 주세요.', status: 403);
    }
    return _OwnerGateway(this, ownerId, _sessionEpoch);
  }

  AccountSecurityGateway securityForOwner(String ownerId) {
    if (_ownerId != ownerId) throw const AuthFailure('다시 로그인해 주세요.');
    return _OwnedAccountSecurity(this, ownerId, _sessionEpoch);
  }

  RecordFilesGateway recordFilesForOwner(String ownerId) {
    if (_ownerId != ownerId) throw const AuthFailure('다시 로그인해 주세요.');
    return _OwnedRecordFiles(this, ownerId, _sessionEpoch);
  }

  Future<http.Response> _recordFileRequest(
    String ownerId,
    int epoch,
    String method,
    String path, [
    Uint8List? bytes,
    Map<String, Object?>? metadata,
  ]) async {
    void checkOwner() {
      if (!_ownsSession(ownerId, epoch)) {
        throw const AuthFailure('계정이 변경되었습니다. 다시 로그인해 주세요.', status: 403);
      }
    }

    checkOwner();
    final uri = Uri.parse(path);
    final allowed = method == 'POST'
        ? uri.path == 'me/official-record-sources'
        : RegExp(r'^(me|admin)/official-record-sources/[0-9a-fA-F-]{36}/file$')
              .hasMatch(uri.path);
    if (uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        uri.hasQuery ||
        !allowed) {
      throw const AuthFailure('올바른 자료 경로를 확인해 주세요.');
    }
    if (bytes != null && bytes.length > 2 * 1024 * 1024) {
      throw const AuthFailure('PDF는 최대 2 MiB까지 제출할 수 있습니다.', status: 413);
    }
    try {
      final request = http.Request(method, _base.resolve('/api/v1/$path'));
      request.headers['X-Unipath-Owner'] = ownerId;
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
      if (bytes != null) {
        if (metadata == null) throw const AuthFailure('자료 정보를 확인해 주세요.');
        final encoded = base64Url.encode(utf8.encode(jsonEncode(metadata)));
        if (encoded.length > 4096) {
          throw const AuthFailure('자료 정보가 너무 큽니다.', status: 422);
        }
        request.headers['X-Unipath-Source-Metadata'] = encoded;
        request.headers['Content-Type'] = 'application/pdf';
        request.bodyBytes = Uint8List.fromList(bytes);
      }
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      checkOwner();
      if (response.statusCode != (method == 'POST' ? 201 : 200)) {
        throw AuthFailure(switch (response.statusCode) {
          401 => '다시 로그인해 주세요.',
          403 => '이 자료에 접근할 권한이 없습니다.',
          404 => '제출 자료를 찾을 수 없습니다.',
          409 => '다른 변경이 있습니다. 제출 자료를 다시 확인해 주세요.',
          413 => 'PDF는 최대 2 MiB까지 제출할 수 있습니다.',
          415 => 'PDF 원본 파일을 선택해 주세요.',
          422 => '파일과 제출 정보를 확인해 주세요.',
          429 => '시도 횟수가 많습니다. 잠시 후 다시 시도해 주세요.',
          _ => '자료 응답을 확인하지 못했습니다. 다시 확인해 주세요.',
        }, status: response.statusCode);
      }
      final type = response.headers['content-type']?.split(';').first;
      if (type !=
              (method == 'POST'
                  ? 'application/json'
                  : 'application/octet-stream') ||
          response.bodyBytes.length > 2 * 1024 * 1024) {
        throw const AuthFailure('자료 응답 형식을 확인하지 못했습니다.');
      }
      return response;
    } on AuthFailure {
      rethrow;
    } catch (_) {
      checkOwner();
      throw const AuthFailure('자료 전송 결과를 확인하지 못했습니다. 제출 목록을 확인해 주세요.');
    }
  }

  bool _ownsSession(String ownerId, int epoch) =>
      _ownerId == ownerId && _sessionEpoch == epoch;
  void _forgetExpectedSession(String ownerId, int epoch) {
    if (!_ownsSession(ownerId, epoch)) return;
    _token = null;
    _sessionEpoch++;
    _setOwner(null);
  }

  Future<void> _endOwnedSessions(
    String ownerId,
    int epoch,
    String path,
    Map<String, Object?>? body,
  ) async {
    if (!_ownsSession(ownerId, epoch)) {
      throw const AuthFailure('계정이 변경되었습니다. 로그인 상태를 다시 확인해 주세요.', status: 403);
    }
    try {
      // A successful operation revokes this very session. Unlike ordinary
      // requests, a concurrent me() observing that revocation is expected.
      final result = await _request('POST', path, body, ownerId);
      if (result != null) throw const AuthFailure('요청 완료 응답을 확인하지 못했습니다.');
      if (!_ownsSession(ownerId, epoch) && _ownerId != null) {
        throw const AuthFailure('계정이 변경되었습니다. 새 계정의 세션은 유지합니다.', status: 403);
      }
      _forgetExpectedSession(ownerId, epoch);
    } on AuthFailure catch (error) {
      if (!_ownsSession(ownerId, epoch) && _ownerId != null) {
        throw const AuthFailure('계정이 변경되었습니다. 새 계정의 세션은 유지합니다.', status: 403);
      }
      if (error.status == 401) _forgetExpectedSession(ownerId, epoch);
      rethrow;
    }
  }

  Future<AccountSessionStatus> _checkOwnedSession(
    String ownerId,
    int epoch,
  ) async {
    if (!_ownsSession(ownerId, epoch)) {
      return _ownerId == null
          ? AccountSessionStatus.expired
          : AccountSessionStatus.changed;
    }
    try {
      final value = AuthIdentity.fromJson(
        (await _request('GET', 'auth/me', null, ownerId))!,
      );
      if (!_ownsSession(ownerId, epoch)) {
        return _ownerId == null
            ? AccountSessionStatus.expired
            : AccountSessionStatus.changed;
      }
      if (value.id != ownerId) return AccountSessionStatus.changed;
      return AccountSessionStatus.active;
    } on AuthFailure catch (error) {
      if (!_ownsSession(ownerId, epoch) && _ownerId != null) {
        return AccountSessionStatus.changed;
      }
      if (error.status == 401) {
        _forgetExpectedSession(ownerId, epoch);
        return AccountSessionStatus.expired;
      }
      if (error.status == 403) return AccountSessionStatus.changed;
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _ownedRequest(
    String ownerId,
    int epoch,
    String method,
    String path,
    Map<String, Object?>? body,
  ) async {
    void check() {
      if (_ownerId != ownerId || epoch != _sessionEpoch) {
        throw const AuthFailure('계정이 변경되었습니다. 다시 로그인해 주세요.', status: 403);
      }
    }

    check();
    final result = await _request(method, path, body, ownerId);
    check();
    return result;
  }

  void _setOwner(String? value) {
    if (_ownerId != value) _sessionEpoch++;
    _ownerId = value;
  }

  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) => _request(method, path, body);

  Future<Map<String, dynamic>?> _request(
    String method,
    String path, [
    Map<String, Object?>? body,
    String? expectedOwner,
  ]) async {
    try {
      final request = http.Request(method, _base.resolve('/api/v1/$path'));
      request.headers['Content-Type'] = 'application/json';
      if (expectedOwner != null) {
        request.headers['X-Unipath-Owner'] = expectedOwner;
      }
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
      if (body != null) request.body = jsonEncode(body);
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) {
        final fields = <String>[];
        if (response.statusCode == 422) {
          try {
            final error = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
            fields.addAll(
              (error['error']['field_errors'] as List).map(
                (f) => f['field'] as String,
              ),
            );
          } catch (_) {
            /* Retain a safe fallback for an invalid error body. */
          }
        }
        throw AuthFailure(
          switch (response.statusCode) {
            401 => '이메일·비밀번호를 확인하거나 다시 로그인해 주세요.',
            403 => '이 작업을 수행할 권한이 없습니다.',
            409 => '이미 등록되었거나 다른 변경이 있습니다. 입력을 확인해 주세요.',
            422 => '입력값의 형식과 길이를 확인해 주세요.',
            429 => '시도 횟수가 많습니다. 잠시 후 다시 시도해 주세요.',
            _ => '서버에서 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.',
          },
          status: response.statusCode,
          fields: fields,
        );
      }
      if (response.statusCode == 204) return null;
      return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      );
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('서버에 연결하지 못했습니다. 연결을 확인하고 다시 시도해 주세요.');
    }
  }

  @override
  Future<AuthIdentity> authenticate({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = (await _request(
      'POST',
      displayName == null ? 'auth/login' : 'auth/register',
      {
        'email': email.trim(),
        'password': password,
        if (displayName != null) 'display_name': displayName.trim(),
        'session_mode': _cookieMode ? 'cookie' : 'bearer',
      },
    ))!;
    return _acceptAuthentication(response);
  }

  Future<SchoolSignupResult> registerSchoolAdmin({
    required String email,
    required String password,
    required String displayName,
    required SchoolAdminSignupDetails details,
  }) async {
    final epoch = _sessionEpoch;
    final response = (await _request('POST', 'auth/school-admin-signups', {
      ...details.toJson(),
      'email': email.trim(),
      'password': password,
      'display_name': displayName.trim(),
      'session_mode': _cookieMode ? 'cookie' : 'bearer',
    }))!;
    if (epoch != _sessionEpoch) {
      throw const AuthFailure('로그인 상태가 변경되었습니다. 신청 이력을 확인해 주세요.');
    }
    try {
      final signup = SchoolAdminSignupView.fromJson(
        Map<String, dynamic>.from(response['signup'] as Map),
      );
      final identity = AuthIdentity.fromJson(response);
      if (signup.applicantId != identity.id ||
          signup.clientId != details.clientId) {
        throw const FormatException('Signup receipt mismatch');
      }
      return SchoolSignupResult(_acceptAuthentication(response), signup);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('가입 접수 응답을 확인하지 못했습니다. 같은 입력으로 다시 확인해 주세요.');
    }
  }

  AuthIdentity _acceptAuthentication(Map<String, dynamic> response) {
    try {
      final identity = AuthIdentity.fromJson(response);
      if (!_cookieMode) {
        final token = response['access_token'];
        if (token is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
          throw const FormatException('Invalid session token');
        }
        _token = token;
      }
      _sessionEpoch++;
      _setOwner(identity.id);
      return identity;
    } catch (_) {
      throw const AuthFailure('로그인 응답을 확인하지 못했습니다. 다시 시도해 주세요.');
    }
  }

  @override
  Future<AuthIdentity?> me() async {
    final requestedToken = _token;
    final epoch = _sessionEpoch;
    if (!_cookieMode && _token == null) return null;
    try {
      final identity = AuthIdentity.fromJson(
        (await _request('GET', 'auth/me'))!,
      );
      if (epoch == _sessionEpoch) _setOwner(identity.id);
      return identity;
    } on AuthFailure catch (error) {
      if (error.status != 401) rethrow;
      if (_token == requestedToken && epoch == _sessionEpoch) {
        _token = null;
        _setOwner(null);
      }
      return null;
    } catch (_) {
      throw const AuthFailure('계정 정보를 확인하지 못했습니다. 다시 시도해 주세요.');
    }
  }

  @override
  Future<void> logout() async {
    final epoch = _sessionEpoch;
    try {
      await _request('POST', 'auth/logout');
    } on AuthFailure catch (error) {
      if (error.status != 401) rethrow;
    }
    if (epoch == _sessionEpoch) {
      _token = null;
      _sessionEpoch++;
      _setOwner(null);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> institutions() async {
    try {
      final rows = <Map<String, dynamic>>[];
      final seen = <String>{};
      String? cursor;
      do {
        final parameters = <String, String>{'limit': '100'};
        if (cursor != null) {
          parameters['cursor'] = cursor;
        }
        final path = Uri(
          path: 'admin/institutions',
          queryParameters: parameters,
        ).toString();
        final response = (await _request('GET', path))!;
        rows.addAll(List<Map<String, dynamic>>.from(response['items'] as List));
        cursor = response['next_cursor'] as String?;
        if (cursor != null && !seen.add(cursor)) {
          throw const FormatException('Repeated cursor');
        }
      } while (cursor != null);
      return rows;
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('학교 목록을 확인하지 못했습니다. 다시 조회해 주세요.');
    }
  }

  @override
  void close() {
    _token = null;
    _sessionEpoch++;
    _setOwner(null);
    _client.close();
  }
}

class _OwnerGateway implements ApiGateway {
  const _OwnerGateway(this.auth, this.ownerId, this.epoch);
  final AuthApi auth;
  final String ownerId;
  final int epoch;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) => auth._ownedRequest(ownerId, epoch, method, path, body);
}

class _OwnedRecordFiles implements RecordFilesGateway {
  const _OwnedRecordFiles(this.auth, this.ownerId, this.epoch);
  final AuthApi auth;
  final String ownerId;
  final int epoch;
  @override
  Future<Map<String, dynamic>> upload(
    String path,
    Uint8List bytes, {
    required Map<String, Object?> metadata,
  }) async {
    try {
      final response = await auth._recordFileRequest(
        ownerId,
        epoch,
        'POST',
        path,
        bytes,
        metadata,
      );
      return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      );
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('자료 등록 응답을 확인하지 못했습니다. 제출 목록을 확인해 주세요.');
    }
  }

  @override
  Future<Uint8List> download(String path) async =>
      (await auth._recordFileRequest(ownerId, epoch, 'GET', path)).bodyBytes;
}

class _OwnedAccountSecurity implements AccountSecurityGateway {
  const _OwnedAccountSecurity(this.auth, this.ownerId, this.epoch);
  final AuthApi auth;
  final String ownerId;
  final int epoch;
  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) => auth._endOwnedSessions(ownerId, epoch, 'auth/change-password', {
    'old_password': oldPassword,
    'new_password': newPassword,
  });
  @override
  Future<void> logoutAll() =>
      auth._endOwnedSessions(ownerId, epoch, 'auth/logout-all', null);
  @override
  Future<AccountSessionStatus> checkSession() =>
      auth._checkOwnedSession(ownerId, epoch);
}
