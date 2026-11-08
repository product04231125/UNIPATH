import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_course_registration.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';

class FailingLinkRepository extends FakeAdminRepository {
  bool failLink = true;
  int courseSaves = 0;
  @override Future<void> save(String actorId, AdminRecord record) async {
    if (record.kind == AdminKind.curriculumCourse && failLink) throw StateError('link offline');
    if (record.kind == AdminKind.course) courseSaves++;
    await super.save(actorId, record);
  }
}
void main() {
  test('partial course success retries connection without duplicating course and keeps other curricula', () async {
    final repo = FailingLinkRepository();
    addTearDown(repo.dispose);
    final coordinator = AdminCourseRegistration();
    final values = {'name': '프로그래밍', 'institutionId': 'school-a', 'code': 'CS101', 'credits': '3'};
    Future<AdminRecord> save() => coordinator.save(repository: repo, actorId: 'super-admin', courseValues: values,
      curriculumId: 'school-a-curr', category: 'major', requiredCourse: 'true');
    await expectLater(save(), throwsStateError);
    expect(repo.records.where((r) => r.kind == AdminKind.course).length, 1);
    repo.failLink = false;
    final course = await save();
    expect(repo.courseSaves, 1);
    expect(repo.records.where((r) => r.kind == AdminKind.course).length, 1);
    final link = repo.records.singleWhere((r) => r.kind == AdminKind.curriculumCourse);
    expect(link.value('courseId'), course.id);
    expect(link.value('curriculumId'), 'school-a-curr');
    await save();
    expect(repo.records.where((r) => r.kind == AdminKind.curriculumCourse).length, 1);
  });
}
