import '../auth/auth_api.dart';
import 'admin_application_models.dart';

export 'admin_application_models.dart';

String _query(
  String? status,
  String? institutionId,
  String? cursor,
  int limit,
) => Uri(
  queryParameters: {
    'status': ?status,
    'institution_id': ?institutionId,
    'cursor': ?cursor,
    'limit': '$limit',
  },
).query;

/// A capability belongs to one login, including requests awaiting a response.
class SchoolAdminApplicationsApi {
  SchoolAdminApplicationsApi.forOwner(AuthApi auth, this.ownerId)
    : _api = auth.forOwner(ownerId);
  final ApiGateway _api;
  final String ownerId;
  static const _path = 'me/school-admin-applications';

  SchoolAdminApplicationView _decode(Map<String, dynamic> value, {String? id}) {
    final result = SchoolAdminApplicationView.fromJson(value);
    if (result.applicantId != ownerId) {
      throw const AuthFailure('신청 계정을 확인하지 못했습니다.', status: 403);
    }
    if (id != null && result.id != id) {
      throw const FormatException('Application identifier mismatch');
    }
    return result;
  }

  Future<SchoolAdminApplicationView> submit(
    SchoolAdminApplicationCreate request,
  ) async {
    final result = _decode(
      (await _api.request('POST', _path, request.toJson()))!,
    );
    if (result.clientId != request.clientId ||
        result.institutionId != request.institutionId) {
      throw const FormatException('Application request mismatch');
    }
    return result;
  }

  Future<SchoolAdminApplicationView> get(String id) async =>
      _decode((await _api.request('GET', '$_path/$id'))!, id: id);

  Future<SchoolAdminApplicationList> list({
    String? status,
    String? institutionId,
    String? cursor,
    int limit = 30,
  }) async {
    final result = SchoolAdminApplicationList.fromJson(
      (await _api.request(
        'GET',
        '$_path?${_query(status, institutionId, cursor, limit)}',
      ))!,
    );
    for (final item in result.items) {
      if (item.applicantId != ownerId) {
        throw const AuthFailure('신청 계정을 확인하지 못했습니다.', status: 403);
      }
    }
    return result;
  }

  Future<SchoolAdminApplicationView> cancel(
    String id,
    int expectedVersion,
  ) async => _decode(
    (await _api.request(
      'POST',
      '$_path/$id/cancel',
      SchoolAdminApplicationCancel(expectedVersion: expectedVersion).toJson(),
    ))!,
    id: id,
  );
}

/// Review is independently restricted to super administrators by the server.
class SchoolAdminApplicationReviewsApi {
  SchoolAdminApplicationReviewsApi.forOwner(AuthApi auth, String ownerId)
    : _api = auth.forOwner(ownerId);
  final ApiGateway _api;
  static const _path = 'admin/school-admin-applications';

  SchoolAdminApplicationReviewView _decode(
    Map<String, dynamic> value,
    String id,
  ) {
    final result = SchoolAdminApplicationReviewView.fromJson(value);
    if (result.id != id || result.applicant.id != result.applicantId) {
      throw const FormatException('Application review identifier mismatch');
    }
    return result;
  }

  Future<SchoolAdminApplicationReviewView> get(String id) async =>
      _decode((await _api.request('GET', '$_path/$id'))!, id);

  Future<SchoolAdminApplicationReviewList> list({
    String? status,
    String? institutionId,
    String? cursor,
    int limit = 30,
  }) async {
    final result = SchoolAdminApplicationReviewList.fromJson(
      (await _api.request(
        'GET',
        '$_path?${_query(status, institutionId, cursor, limit)}',
      ))!,
    );
    for (final item in result.items) {
      if (item.applicant.id != item.applicantId) {
        throw const FormatException('Application applicant mismatch');
      }
    }
    return result;
  }

  Future<SchoolAdminApplicationReviewView> approve(
    String id,
    SchoolAdminApplicationApprove request,
  ) async {
    if (!request.identityVerified || !request.affiliationVerified) {
      throw ArgumentError(
        'Review identity and school affiliation before approval',
      );
    }
    return _decode(
      (await _api.request('POST', '$_path/$id/approve', request.toJson()))!,
      id,
    );
  }

  Future<SchoolAdminApplicationReviewView> reject(
    String id,
    SchoolAdminApplicationReject request,
  ) async => _decode(
    (await _api.request('POST', '$_path/$id/reject', request.toJson()))!,
    id,
  );
}
