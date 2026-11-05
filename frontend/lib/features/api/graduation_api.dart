import '../auth/auth_api.dart';
import 'graduation_models.dart';

export 'graduation_models.dart';

bool _sameContext(GraduationContext a, GraduationContext b) =>
    a.institutionId == b.institutionId &&
    a.departmentId == b.departmentId &&
    a.curriculumId == b.curriculumId &&
    a.admissionYear == b.admissionYear &&
    a.track == b.track;

class GraduationApi {
  const GraduationApi._(this.api, this.ownerId);
  factory GraduationApi.forOwner(AuthApi auth, String ownerId) =>
      GraduationApi._(auth.forOwner(ownerId), ownerId);
  final ApiGateway api;
  final String ownerId;
  static const _path = 'me/graduation-audits';

  Future<GraduationAuditView> create(GraduationAuditCreate request) async {
    final result = _decode(
      (await api.request('POST', _path, request.toJson()))!,
    );
    if (result.clientId != request.clientId ||
        result.evaluatedOn != request.asOf ||
        !_sameContext(result.context, request.context)) {
      throw const FormatException('Graduation audit request mismatch');
    }
    return result;
  }

  Future<GraduationAuditView> get(String id) async =>
      _decode((await api.request('GET', '$_path/$id'))!, id: id);

  Future<GraduationAuditList> list({
    String? institutionId,
    String? cursor,
    int limit = 20,
  }) async {
    final query = Uri(
      queryParameters: {
        'institution_id': ?institutionId,
        'cursor': ?cursor,
        'limit': '$limit',
      },
    ).query;
    final result = GraduationAuditList.fromJson(
      (await api.request('GET', '$_path?$query'))!,
    );
    for (final row in result.items) {
      _owner(row.ownerId);
    }
    return result;
  }

  void _owner(String id) {
    if (id != ownerId) {
      throw const AuthFailure('졸업요건 감사의 계정을 확인하지 못했습니다.', status: 403);
    }
  }

  GraduationAuditView _decode(Map<String, dynamic> value, {String? id}) {
    final result = GraduationAuditView.fromJson(value);
    _owner(result.ownerId);
    if (id != null && result.id != id) {
      throw const FormatException('Graduation audit identifier mismatch');
    }
    if (result.eligibleAsOf !=
            (result.status == 'satisfied' && result.catalogComplete) ||
        result.currentUsable != result.currentIssues.isEmpty) {
      throw const FormatException('Inconsistent graduation audit state');
    }
    return result;
  }
}

/// The server rechecks the current school scope on every operation.
class GraduationCatalogApi {
  const GraduationCatalogApi._(this.api);
  factory GraduationCatalogApi.forOwner(AuthApi auth, String ownerId) =>
      GraduationCatalogApi._(auth.forOwner(ownerId));
  final ApiGateway api;
  static const _path = 'admin/graduation-catalog-reviews';

  Future<CatalogPreview> preview(GraduationContext context, String on) async {
    final query = Uri(
      queryParameters: {
        ...context.toJson().map((k, v) => MapEntry(k, '$v')),
        'as_of': on,
      },
    ).query;
    final result = CatalogPreview.fromJson(
      (await api.request('GET', '$_path/preview?$query'))!,
    );
    if (!_sameContext(result.context, context) || result.asOf != on) {
      throw const FormatException('Catalogue preview context/date mismatch');
    }
    return result;
  }

  Future<CatalogReviewView> create(CatalogReviewCreate request) async {
    if (!request.allRequirementsReviewed ||
        !request.allLevelsReviewed ||
        !request.sourcesReviewed) {
      throw const FormatException(
        'Explicit complete catalogue review required',
      );
    }
    final result = CatalogReviewView.fromJson(
      (await api.request('POST', _path, request.toJson()))!,
    );
    if (result.clientId != request.clientId ||
        result.snapshotDigest != request.expectedCatalogDigest ||
        result.asOf != request.asOf ||
        !_sameContext(result.context, request.context)) {
      throw const FormatException('Catalogue review creation mismatch');
    }
    return result;
  }

  Future<CatalogReviewView> get(String id) async =>
      _decode((await api.request('GET', '$_path/$id'))!, id);

  Future<CatalogReviewList> list({
    String? institutionId,
    String? status,
    String? cursor,
    int limit = 20,
  }) async {
    final query = Uri(
      queryParameters: {
        'institution_id': ?institutionId,
        'status': ?status,
        'cursor': ?cursor,
        'limit': '$limit',
      },
    ).query;
    return CatalogReviewList.fromJson(
      (await api.request('GET', '$_path?$query'))!,
    );
  }

  Future<CatalogReviewView> revoke(
    String id,
    CatalogReviewRevoke request,
  ) async => _decode(
    (await api.request('POST', '$_path/$id/revoke', request.toJson()))!,
    id,
  );

  Future<CatalogReviewEvents> events(String id) async {
    final events = CatalogReviewEvents.fromJson(
      (await api.request('GET', '$_path/$id/events'))!,
    );
    if (events.items.any((e) => e.reviewId != id)) {
      throw const FormatException('Catalogue review event mismatch');
    }
    return events;
  }

  CatalogReviewView _decode(Map<String, dynamic> json, String id) {
    final value = CatalogReviewView.fromJson(json);
    if (value.id != id) {
      throw const FormatException('Catalogue review identifier mismatch');
    }
    return value;
  }
}
