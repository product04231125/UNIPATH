import '../auth/auth_api.dart';
import 'student_api.dart';
import 'student_api_models.dart';

class StudentCatalogResources {
  static final institutions = StudentResource(
    'institutions',
    StudentInstitutionView.fromJson,
  );
  static final departments = StudentResource(
    'departments',
    StudentDepartmentPublicView.fromJson,
  );
  static final curricula = StudentResource(
    'curricula',
    StudentCurriculumPublicView.fromJson,
  );
  static final courses = StudentResource(
    'courses',
    StudentCoursePublicView.fromJson,
  );
  static final curriculumCourses = StudentResource(
    'curriculum-courses',
    StudentCurriculumCoursePublicView.fromJson,
  );
  static final ruleSets = StudentResource(
    'rule-sets',
    StudentRuleSetPublicView.fromJson,
  );
  static final rules = StudentResource('rules', StudentRulePublicView.fromJson);
  static final documents = StudentResource(
    'documents',
    StudentDocumentPublicView.fromJson,
  );
}

class StudentCatalogPage<T extends StudentPayload> {
  StudentCatalogPage(List<T> items, this.nextCursor)
    : items = List.unmodifiable(items);
  final List<T> items;
  final String? nextCursor;
}

/// Read-only catalog contract adapter, using the common authenticated transport.
class StudentCatalogApi {
  const StudentCatalogApi(this.api);
  final ApiGateway api;

  Future<StudentCatalogPage<T>> list<T extends StudentPayload>(
    StudentResource<T> resource, {
    String? institutionId,
    String? departmentId,
    String? curriculumId,
    String? ruleSetId,
    String? asOf,
    String? cursor,
    String? query,
    int limit = 100,
  }) async {
    final parameters = <String, String>{
      'limit': '$limit',
      'institution_id': ?institutionId,
      'department_id': ?departmentId,
      'curriculum_id': ?curriculumId,
      'rule_set_id': ?ruleSetId,
      'as_of': ?asOf,
      'cursor': ?cursor,
      'query': ?query,
    };
    final response = (await api.request(
      'GET',
      'catalog/${resource.path}?${Uri(queryParameters: parameters).query}',
    ))!;
    return StudentCatalogPage(
      (response['items'] as List)
          .map(
            (value) => resource.decode(Map<String, dynamic>.from(value as Map)),
          )
          .toList(),
      response['next_cursor'] as String?,
    );
  }

  Future<T> get<T extends StudentPayload>(
    StudentResource<T> resource,
    String id, {
    String? asOf,
  }) async {
    final query = asOf == null
        ? ''
        : '?${Uri(queryParameters: {'as_of': asOf}).query}';
    return resource.decode(
      (await api.request('GET', 'catalog/${resource.path}/$id$query'))!,
    );
  }
}
