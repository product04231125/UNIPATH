import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/api/student_api_models.dart';
import 'package:university_path_frontend/features/records/course/course_pick_options.dart';
import 'package:university_path_frontend/features/records/personal_record_codec.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

import 'student_academic_integration_test.dart' as fixture;

class RegistrationTransport extends fixture.AcademicTransport {
  final routes = <String>[];
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) {
    routes.add(path);
    return super.request(method, path, body);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('registration uses selected published context and preserves school classification and PF', () async {
    final transport = RegistrationTransport();
    transport.courses.add({
      ...transport.courses.first,
      'id': 'pf-entry',
      'course_name': '합성 P/F',
      'grading_basis': 'pass_fail',
      'recognized_credits': null,
    });
    final repo = PersonalRecordRepository(PersonalRecordKind.course);
    await repo.load();
    await repo.save(
      PersonalRecord(
        id: 'existing',
        values: {'title': '기존 수강', 'credits': '2'},
      ),
    );
    final options = await loadCoursePickOptions(
      courseRepository: repo,
      studentApi: StudentApi(transport, ownerId: 'owner'),
      institutionId: 'school',
      curriculumId: 'old-curriculum',
    );
    expect(options.first.id, 'academic:context:entry');
    expect(options.first.label, startsWith('공통 설계 (SHARED)'));
    expect(options.first.label, isNot(contains('학교 교육과정')));
    expect(options.first.category, '교양 / 기초');
    expect(options.first.requiredCourse, isTrue);
    final pf = options.singleWhere((o) => o.id.endsWith(':pf-entry'));
    expect(pf.gradingBasis, 'pass_fail');
    expect(pf.credits, isEmpty);
    expect(transport.routes, ['me/academic-contexts']);
    expect(repo.records.single.id, 'existing');
  });
  test('P/F unknown and zero credits survive wire encoding separately without assuming a pass', () {
    for (final amount in ['', '0', '1']) {
      final payload =
          const PersonalRecordCodec(PersonalRecordKind.course).encode({
            'title': '합성 P/F',
            'term': '2026 1학기',
            'category': '교양',
            'credits': amount,
            'gradingBasis': 'pass_fail',
            'completion': '이수 기록',
            'grade': '',
          }) as StudentCourseRecordCreate;
      final wire = payload.toJson();
      expect(wire['credits'], amount.isEmpty ? null : amount);
      expect(wire['grading_basis'], 'pass_fail');
      expect(wire['grade'], '');
      expect(StudentCourseRecordCreate.fromJson(wire).credits, amount);
    }
  });
}
