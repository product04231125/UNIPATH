import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../auth/auth_api.dart';
import 'academic_workspace_api.dart';

/// A confirmed rejection is editable; an uncertain response retains the exact retry body.
class AcademicWriteController extends ChangeNotifier {
  AcademicWriteController(this.api, this.school);
  final AcademicWorkspaceApi api;
  final String school;
  bool busy = false, _disposed = false;
  String? error;
  List<String> fields = [];
  String? _method, _path;
  Map<String, Object?>? _body;
  bool get uncertain => _body != null;
  String? fieldError(String field) =>
      fields.any((path) {
        final normalized = path.replaceFirst(RegExp(r'^body\.'), '');
        return normalized == field || normalized.startsWith('$field.');
      })
      ? '이 입력 내용을 확인하세요.'
      : null;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>?> send(
    String method,
    String path,
    Map<String, Object?> body,
  ) async {
    if (busy || uncertain || _disposed) return null;
    _method = method;
    _path = path;
    _body = Map<String, Object?>.from(jsonDecode(jsonEncode(body)) as Map);
    return retry();
  }

  Future<Map<String, dynamic>?> retry() async {
    if (busy || _body == null || _disposed) return null;
    busy = true;
    error = null;
    fields = [];
    _changed();
    try {
      final result = await api.transport.request(_method!, _path!, _body);
      if (_disposed) return null;
      if (result == null || result['institution_id'] != school) {
        throw const FormatException('Academic response scope mismatch');
      }
      _body = null;
      return result;
    } catch (failure) {
      if (_disposed) return null;
      error = failure is AuthFailure
          ? failure.message
          : '저장 결과를 확인하지 못했습니다. 작성 내용은 유지됩니다.';
      if (failure is AuthFailure) {
        fields = failure.fields;
        if (const [400, 401, 403, 404, 409, 422].contains(failure.status)) {
          _body = null;
        }
      }
      return null;
    } finally {
      busy = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
