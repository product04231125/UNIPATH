import '../auth/auth_api.dart';
import 'school_signup_models.dart';

export 'school_signup_models.dart';

class SchoolSignupApi {
  SchoolSignupApi.forOwner(AuthApi auth, this.ownerId)
    : _api = auth.forOwner(ownerId);
  final ApiGateway _api;
  final String ownerId;
  static const _own = 'me/school-admin-signups';
  static const _admin = 'admin/school-admin-signups';

  SchoolAdminSignupView _decode(Map<String, dynamic> value, {String? id}) {
    final row = SchoolAdminSignupView.fromJson(value);
    if (row.applicantId != ownerId) {
      throw const AuthFailure('신청 계정이 변경되었습니다.', status: 403);
    }
    if (id != null && row.id != id) {
      throw const FormatException('Signup identifier mismatch');
    }
    return row;
  }

  Future<SchoolAdminSignupList> ownList({
    String? cursor,
    String? status,
  }) async {
    final query = Uri(queryParameters: {'cursor': ?cursor, 'status': ?status})
        .query;
    final result = SchoolAdminSignupList.fromJson(
      (await _api.request('GET', '$_own?$query'))!,
    );
    for (final row in result.items) {
      if (row.applicantId != ownerId) {
        throw const AuthFailure('신청 계정이 변경되었습니다.', status: 403);
      }
    }
    return result;
  }

  Future<SchoolAdminSignupView> submit(SchoolAdminSignupDetails body) async {
    final result = _decode((await _api.request('POST', _own, body.toJson()))!);
    if (result.clientId != body.clientId) {
      throw const FormatException('Signup replay key mismatch');
    }
    return result;
  }

  Future<SchoolAdminSignupView> cancel(String id, int version) async => _decode(
    (await _api.request('POST', '$_own/$id/cancel', {
      'expected_version': version,
    }))!,
    id: id,
  );

  Future<SchoolAdminSignupReviewList> reviews({
    String? cursor,
    String? status,
  }) async {
    final query = Uri(queryParameters: {'cursor': ?cursor, 'status': ?status})
        .query;
    return SchoolAdminSignupReviewList.fromJson(
      (await _api.request('GET', '$_admin?$query'))!,
    );
  }

  Future<SchoolAdminSignupReviewView> review(String id) async {
    final row = SchoolAdminSignupReviewView.fromJson(
      (await _api.request('GET', '$_admin/$id'))!,
    );
    if (row.id != id || row.applicantId != row.applicant.id) {
      throw const FormatException('Signup review mismatch');
    }
    return row;
  }

  Future<SchoolAdminSignupReviewView> approve(
    String id,
    SchoolAdminSignupApprove body,
  ) async => SchoolAdminSignupReviewView.fromJson(
    (await _api.request('POST', '$_admin/$id/approve', body.toJson()))!,
  );

  Future<SchoolAdminSignupReviewView> reject(
    String id,
    int version,
    String note,
  ) async => SchoolAdminSignupReviewView.fromJson(
    (await _api.request('POST', '$_admin/$id/reject', {
      'expected_version': version,
      'review_note': note,
    }))!,
  );

  Future<Map<String, dynamic>> institution(String id) async =>
      (await _api.request('GET', 'admin/institutions/$id'))!;

  Future<List<Map<String, dynamic>>> institutions() async {
    final rows = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final query = Uri(queryParameters: {'limit': '100', 'cursor': ?cursor})
          .query;
      final page = (await _api.request('GET', 'admin/institutions?$query'))!;
      rows.addAll(
        (page['items'] as List).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      cursor = page['next_cursor'] as String?;
    } while (cursor != null);
    return rows;
  }
}
