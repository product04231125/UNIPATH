import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_role.dart';
import 'auth_http_stub.dart' if (dart.library.js_interop) 'auth_http_web.dart';

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
    if (_ownerId != ownerId) throw const AuthFailure('다시 로그인해 주세요.');
    return _OwnerGateway(this, ownerId, _sessionEpoch);
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
        throw const AuthFailure('계정이 변경되었습니다. 다시 로그인해 주세요.');
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
