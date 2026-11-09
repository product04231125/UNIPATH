import '../auth/auth_api.dart';

/// Transport for administrator academic data only; no student capability.
class AcademicWorkspaceApi {
  const AcademicWorkspaceApi(this.transport);
  factory AcademicWorkspaceApi.forOwner(ApiGateway api, String ownerId) =>
      AcademicWorkspaceApi(api is AuthApi ? api.forOwner(ownerId) : api);
  final ApiGateway transport;
  static const path = 'admin/academic';

  Future<List<Map<String, dynamic>>> _pages(
    String resource,
    String school, {
    Map<String, String> filters = const {},
  }) async {
    final rows = <Map<String, dynamic>>[];
    final cursors = <String>{};
    String? cursor;
    do {
      final query = Uri(
        queryParameters: {
          'institution_id': school,
          'limit': '100',
          'cursor': ?cursor,
          ...filters,
        },
      ).query;
      final result = (await transport.request(
        'GET',
        '$path/$resource?$query',
      ))!;
      final batch = List<Map<String, dynamic>>.from(result['items'] as List);
      if (batch.any((row) => row['institution_id'] != school)) {
        throw const FormatException('School classification scope mismatch');
      }
      rows.addAll(batch);
      cursor = result['next_cursor'] as String?;
      if (cursor != null && !cursors.add(cursor)) {
        throw const FormatException('Repeated academic page cursor');
      }
    } while (cursor != null);
    return rows;
  }

  Future<List<Map<String, dynamic>>> classifications(String school) =>
      _pages('classification-revisions', school);
  Future<List<Map<String, dynamic>>> tracks(String school) =>
      _pages('study-tracks', school);

  Future<Map<String, dynamic>> classification(String id, String school) async {
    final row = (await transport.request(
      'GET',
      '$path/classification-revisions/$id',
    ))!;
    if (row['id'] != id || row['institution_id'] != school) {
      throw const FormatException('Classification identity mismatch');
    }
    return row;
  }

  Future<Map<String, dynamic>> create(Map<String, Object?> body) async =>
      (await transport.request(
        'POST',
        '$path/classification-revisions',
        body,
      ))!;
  Future<Map<String, dynamic>> save(
    String id,
    Map<String, Object?> body,
  ) async => (await transport.request(
    'PUT',
    '$path/classification-revisions/$id',
    body,
  ))!;
  Future<Map<String, dynamic>> preview(String id, int version) async =>
      (await transport.request(
        'POST',
        '$path/classification-revisions/$id/preview-publication',
        {'expected_version': version},
      ))!;
  Future<Map<String, dynamic>> publish(
    String id,
    Map<String, Object?> body,
  ) async => (await transport.request(
    'POST',
    '$path/classification-revisions/$id/publish',
    body,
  ))!;
  Future<Map<String, dynamic>> createTrack(Map<String, Object?> body) async =>
      (await transport.request('POST', '$path/study-tracks', body))!;
  Future<Map<String, dynamic>> updateTrack(
    String id,
    Map<String, Object?> body,
  ) async =>
      (await transport.request('PATCH', '$path/study-tracks/$id', body))!;

  Future<List<Map<String, dynamic>>> curricula(String school) =>
      _pages('curriculum-revisions', school);
  Future<Map<String, dynamic>> curriculum(String id, String school) async {
    final result = (await transport.request(
      'GET',
      '$path/curriculum-revisions/$id',
    ))!;
    if (result['id'] != id || result['institution_id'] != school) {
      throw const FormatException('Curriculum identity mismatch');
    }
    return result;
  }

  Future<Map<String, dynamic>> createCurriculum(
    Map<String, Object?> body,
  ) async =>
      (await transport.request('POST', '$path/curriculum-revisions', body))!;
  Future<Map<String, dynamic>> saveCurriculum(
    String id,
    Map<String, Object?> body,
  ) async =>
      (await transport.request('PUT', '$path/curriculum-revisions/$id', body))!;
  Future<Map<String, dynamic>> addCourse(
    String id,
    Map<String, Object?> body,
  ) async => (await transport.request(
    'POST',
    '$path/curriculum-revisions/$id/course-entries',
    body,
  ))!;
  Future<Map<String, dynamic>> previewCurriculum(
    String id,
    int version,
  ) async => (await transport.request(
    'POST',
    '$path/curriculum-revisions/$id/preview-publication',
    {'expected_version': version},
  ))!;
  Future<Map<String, dynamic>> publishCurriculum(
    String id,
    Map<String, Object?> body,
  ) async => (await transport.request(
    'POST',
    '$path/curriculum-revisions/$id/publish',
    body,
  ))!;
  Future<Map<String, dynamic>> copyCurriculum(
    String id,
    Map<String, Object?> body,
  ) async => (await transport.request(
    'POST',
    '$path/curriculum-revisions/$id/drafts',
    body,
  ))!;

  Future<List<Map<String, dynamic>>> requirements(String school, String kind) =>
      _pages('requirement-revisions', school, filters: {'kind': kind});
  Future<Map<String, dynamic>> requirement(String id, String school) async {
    final result = (await transport.request(
      'GET',
      '$path/requirement-revisions/$id',
    ))!;
    if (result['id'] != id || result['institution_id'] != school) {
      throw const FormatException('Requirement identity mismatch');
    }
    return result;
  }

  Future<Map<String, dynamic>> previewRequirement(
    String id,
    int version,
  ) async => (await transport.request(
    'POST',
    '$path/requirement-revisions/$id/preview-publication',
    {'expected_version': version},
  ))!;
}
