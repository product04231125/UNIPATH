import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/admin/remote_admin_repository.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/records/course/course_pick_options.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

import 'support/auth_fixture.dart';

import 'package:university_path_frontend/features/admin/admin_course_registration.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';

class FailingLinkRepository extends FakeAdminRepository {
  bool failLink = true;
  int courseSaves = 0;
  @override
  Future<void> save(String actorId, AdminRecord record) async {
    if (record.kind == AdminKind.curriculumCourse && failLink)
      throw StateError('link offline');
    if (record.kind == AdminKind.course) courseSaves++;
    await super.save(actorId, record);
  }
}

class LostResponseRepository extends FakeAdminRepository {
  LostResponseRepository(this.failKind);
  final AdminKind failKind;
  bool lose = true;
  int saves = 0;
  @override
  Future<void> save(String actorId, AdminRecord record) async {
    saves++;
    await super.save(actorId, record);
    if (lose && record.kind == failKind) {
      lose = false;
      throw Exception('response lost');
    }
  }
}

class CourseContractGateway implements ApiGateway {
  final rows = <String, List<Map<String, dynamic>>>{};
  final writes = <(String, Map<String, Object?>)>[];
  int sequence = 20;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final uri = Uri.parse(path);
    final resource = uri.pathSegments[1];
    if (method == 'GET') {
      var items = rows[resource] ?? <Map<String, dynamic>>[];
      if (uri.pathSegments.first == 'catalog') {
        items = items
            .where(
              (r) =>
                  r['institution_id'] == uri.queryParameters['institution_id'],
            )
            .toList();
        if (resource == 'courses' &&
            uri.queryParameters['curriculum_id'] != null) {
          final linked = (rows['curriculum-courses'] ?? [])
              .where(
                (r) =>
                    r['curriculum_id'] == uri.queryParameters['curriculum_id'],
              )
              .map((r) => r['course_id'])
              .toSet();
          items = items.where((r) => linked.contains(r['id'])).toList();
        }
      }
      return {'items': items, 'next_cursor': null};
    }
    writes.add((path, Map.of(body!)));
    final id =
        '00000000-0000-4000-8000-${(++sequence).toString().padLeft(12, '0')}';
    final saved = <String, dynamic>{...body, 'id': id, 'version': 1};
    (rows[resource] ??= []).add(saved);
    return saved;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('remote course and link writes produce a student candidate in the selected curriculum', () async {
    final auth = FakeAuth(role: 'super_admin')..signedIn = true;
    final gateway = CourseContractGateway();
    final repo = RemoteAdminRepository(
      (await auth.me())!,
      auth: auth,
      api: gateway,
    );
    addTearDown(repo.dispose);
    final course = await AdminCourseRegistration().save(
      repository: repo,
      actorId: userId,
      courseValues: {
        'name': '프로그래밍',
        'code': 'CS101',
        'credits': '1.125',
        'institutionId': 'school',
      },
      curriculumId: 'curriculum',
      category: 'major',
      requiredCourse: 'true',
    );
    expect(gateway.writes[0].$1, 'admin/courses');
    expect(gateway.writes[0].$2.keys.toSet(), {
      'name',
      'institution_id',
      'code',
      'credits',
    });
    expect(gateway.writes[1].$1, 'admin/curriculum-courses');
    expect(gateway.writes[1].$2['course_id'], course.id);
    expect(gateway.writes[1].$2['required'], true);
    final candidates = await loadCoursePickOptions(
      courseRepository: PersonalRecordRepository(PersonalRecordKind.course),
      studentApi: StudentApi(gateway, ownerId: userId),
      institutionId: 'school',
      curriculumId: 'curriculum',
    );
    expect(candidates.single.id, 'catalog:${course.id}');
    expect(
      candidates.single.curriculumCourseId,
      gateway.rows['curriculum-courses']!.single['id'],
    );
    expect(candidates.single.category, 'major');
    expect(candidates.single.requiredCourse, true);
    expect(candidates.single.credits, '1.125');
    expect(
      await loadCoursePickOptions(
        courseRepository: PersonalRecordRepository(PersonalRecordKind.course),
        studentApi: StudentApi(gateway, ownerId: userId),
        institutionId: 'school',
        curriculumId: 'other',
      ),
      isEmpty,
    );
  });
  test(
    'uncertain course result never automatically posts another course',
    () async {
      final repo = LostResponseRepository(AdminKind.course);
      addTearDown(repo.dispose);
      final coordinator = AdminCourseRegistration();
      Future<AdminRecord> save() => coordinator.save(
        repository: repo,
        actorId: 'super-admin',
        courseValues: {
          'name': '과목',
          'code': 'C1',
          'credits': '3',
          'institutionId': 'school-a',
        },
        curriculumId: 'school-a-curr',
        category: 'major',
        requiredCourse: 'true',
      );
      await expectLater(save(), throwsStateError);
      await expectLater(save(), throwsStateError);
      expect(repo.saves, 1);
      expect(repo.records.where((r) => r.kind == AdminKind.course).length, 1);
    },
  );
  test('lost link response is reconciled by ID and other curriculum classifications are preserved', () async {
    final repo = LostResponseRepository(AdminKind.curriculumCourse);
    addTearDown(repo.dispose);
    final coordinator = AdminCourseRegistration();
    final values = {
      'name': '과목',
      'code': 'C1',
      'credits': '3',
      'institutionId': 'school-a',
    };
    Future<AdminRecord> save() => coordinator.save(
      repository: repo,
      actorId: 'super-admin',
      courseValues: values,
      curriculumId: 'school-a-curr',
      category: 'major',
      requiredCourse: 'true',
    );
    await expectLater(save(), throwsStateError);
    final course = await save();
    expect(
      repo.records.where((r) => r.kind == AdminKind.curriculumCourse).length,
      1,
    );
    final second = AdminRecord(
      id: 'second',
      kind: AdminKind.curriculum,
      values: {
        'name': '두 번째 과정',
        'departmentId': 'school-a-dept',
        'year': '2027',
      },
    );
    await repo.save('super-admin', second);
    await AdminCourseRegistration().save(
      repository: repo,
      actorId: 'super-admin',
      original: course,
      courseValues: values,
      curriculumId: second.id,
      category: 'general',
      requiredCourse: 'false',
    );
    final links = repo.records
        .where((r) => r.kind == AdminKind.curriculumCourse)
        .toList();
    expect(links.length, 2);
    expect(
      links
          .singleWhere((r) => r.value('curriculumId') == 'school-a-curr')
          .value('required'),
      'true',
    );
    expect(
      links
          .singleWhere((r) => r.value('curriculumId') == 'second')
          .value('required'),
      'false',
    );
  });
  test('partial course success retries connection without duplicating course and keeps other curricula', () async {
    final repo = FailingLinkRepository();
    addTearDown(repo.dispose);
    final coordinator = AdminCourseRegistration();
    final values = {
      'name': '프로그래밍',
      'institutionId': 'school-a',
      'code': 'CS101',
      'credits': '3',
    };
    Future<AdminRecord> save() => coordinator.save(
      repository: repo,
      actorId: 'super-admin',
      courseValues: values,
      curriculumId: 'school-a-curr',
      category: 'major',
      requiredCourse: 'true',
    );
    await expectLater(save(), throwsStateError);
    expect(repo.records.where((r) => r.kind == AdminKind.course).length, 1);
    repo.failLink = false;
    final course = await save();
    expect(repo.courseSaves, 1);
    expect(repo.records.where((r) => r.kind == AdminKind.course).length, 1);
    final link = repo.records.singleWhere(
      (r) => r.kind == AdminKind.curriculumCourse,
    );
    expect(link.value('courseId'), course.id);
    expect(link.value('curriculumId'), 'school-a-curr');
    await save();
    expect(
      repo.records.where((r) => r.kind == AdminKind.curriculumCourse).length,
      1,
    );
  });
}
