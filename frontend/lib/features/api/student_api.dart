import '../auth/auth_api.dart';
import 'student_api_models.dart';

/// Typed personal contract adapter. Live planning uses an owner-bound gateway;
/// other personal screens retain their local repositories until connected.
class StudentResource<T extends StudentPayload> {
  const StudentResource(this.path, this.decode);
  final String path;
  final T Function(Map<String, dynamic>) decode;
}

class StudentResources {
  static final events = StudentResource('events', StudentEventCreate.fromJson);
  static final courseRecords = StudentResource(
    'course-records',
    StudentCourseRecordCreate.fromJson,
  );
  static final activityRecords = StudentResource(
    'activity-records',
    StudentActivityRecordCreate.fromJson,
  );
  static final experienceRecords = StudentResource(
    'experience-records',
    StudentExperienceRecordCreate.fromJson,
  );
  static final credentialRecords = StudentResource(
    'credential-records',
    StudentCredentialRecordCreate.fromJson,
  );
  static final achievementRecords = StudentResource(
    'achievement-records',
    StudentAchievementRecordCreate.fromJson,
  );
  static final personalCurricula = StudentResource(
    'personal-curricula',
    StudentPersonalCurriculumCreate.fromJson,
  );
  static final curriculumCourses = StudentResource(
    'personal-curriculum-courses',
    StudentPersonalCurriculumCourseCreate.fromJson,
  );
  static final graduationRules = StudentResource(
    'personal-graduation-rules',
    StudentPersonalGraduationRuleCreate.fromJson,
  );
  static final compositions = StudentResource(
    'portfolio-compositions',
    StudentPortfolioCompositionCreate.fromJson,
  );
  static final applicationDocuments = StudentResource(
    'application-documents',
    StudentApplicationDocumentCreate.fromJson,
  );
}

class StudentRecord<T extends StudentPayload> {
  StudentRecord.fromJson(
    Map<String, dynamic> value,
    StudentResource<T> resource,
  ) : id = value['id'] as String,
      ownerId = value['owner_id'] as String,
      version = value['version'] as int,
      createdAt = DateTime.parse(value['created_at'] as String),
      updatedAt = DateTime.parse(value['updated_at'] as String),
      data = resource.decode(value) {
    if (value['origin'] != 'personal' || value['official'] != false) {
      throw const FormatException('Expected a personal record');
    }
  }
  final String id, ownerId;
  final int version;
  final DateTime createdAt, updatedAt;
  final T data;
}

class StudentPage<T extends StudentPayload> {
  StudentPage(List<StudentRecord<T>> items, this.nextCursor)
    : items = List.unmodifiable(items);
  final List<StudentRecord<T>> items;
  final String? nextCursor;
}

/// Construct for one authenticated identity; discard on account change/logout.
/// No local writes, implicit imports, caches, or token storage are performed.
class StudentApi {
  const StudentApi(this.api, {required this.ownerId});
  final ApiGateway api;
  final String ownerId;

  StudentRecord<T> _record<T extends StudentPayload>(
    StudentResource<T> resource,
    Map<String, dynamic> value,
  ) {
    final result = StudentRecord.fromJson(value, resource);
    if (result.ownerId != ownerId) {
      throw const FormatException('Unexpected account in personal response');
    }
    return result;
  }

  Future<StudentPage<T>> list<T extends StudentPayload>(
    StudentResource<T> resource, {
    String? cursor,
    String? clientId,
    String? curriculumId,
    String? query,
    DateTime? startsBefore,
    DateTime? endsAfter,
    int limit = 100,
  }) async {
    final parameters = <String, String>{
      'limit': '$limit',
      'cursor': ?cursor,
      'client_id': ?clientId,
      'curriculum_id': ?curriculumId,
      'query': ?query,
      'starts_before': ?startsBefore?.toUtc().toIso8601String(),
      'ends_after': ?endsAfter?.toUtc().toIso8601String(),
    };
    final data = (await api.request(
      'GET',
      'me/${resource.path}?${Uri(queryParameters: parameters).query}',
    ))!;
    return StudentPage(
      (data['items'] as List)
          .map(
            (item) => _record(resource, Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      data['next_cursor'] as String?,
    );
  }

  Future<StudentRecord<T>> get<T extends StudentPayload>(
    StudentResource<T> resource,
    String id,
  ) async =>
      _record(resource, (await api.request('GET', 'me/${resource.path}/$id'))!);

  Future<StudentRecord<T>> create<T extends StudentPayload>(
    StudentResource<T> resource,
    T payload,
  ) async => _record(
    resource,
    (await api.request('POST', 'me/${resource.path}', payload.toJson()))!,
  );

  Future<StudentRecord<T>> patch<T extends StudentPayload>(
    StudentResource<T> resource,
    String id, {
    required int expectedVersion,
    required Map<String, Object?> changes,
  }) async {
    _checkChanges(changes);
    return _record(
      resource,
      (await api.request('PATCH', 'me/${resource.path}/$id', {
        ...changes,
        'expected_version': expectedVersion,
      }))!,
    );
  }

  Future<void> remove<T extends StudentPayload>(
    StudentResource<T> resource,
    String id, {
    required int expectedVersion,
  }) async {
    await api.request(
      'DELETE',
      'me/${resource.path}/$id?expected_version=$expectedVersion',
    );
  }

  Future<StudentProfileView> profile() async {
    final result = StudentProfileView.fromJson(
      (await api.request('GET', 'me/planning-profile'))!,
    );
    if (result.ownerId != ownerId || result.official) {
      throw const FormatException('Unexpected personal profile');
    }
    return result;
  }

  Future<StudentProfileView> patchProfile({
    required int expectedVersion,
    required Map<String, Object?> changes,
  }) async {
    _checkChanges(changes);
    final result = StudentProfileView.fromJson(
      (await api.request('PATCH', 'me/planning-profile', {
        ...changes,
        'expected_version': expectedVersion,
      }))!,
    );
    if (result.ownerId != ownerId || result.official) {
      throw const FormatException('Unexpected personal profile');
    }
    return result;
  }

  void _checkChanges(Map<String, Object?> changes) {
    if (changes.keys.any(
      const {
        'id',
        'owner_id',
        'client_id',
        'version',
        'created_at',
        'updated_at',
        'origin',
        'official',
        'expected_version',
      }.contains,
    )) {
      throw ArgumentError(
        'Pass only editable fields; expectedVersion is separate',
      );
    }
  }
}
