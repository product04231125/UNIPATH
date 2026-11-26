import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_academic_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/graduation/student_academic_contexts.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

import 'student_academic_integration_test.dart' as fixture;

class AuditTransport extends fixture.AcademicTransport {
  bool progressFails = false;
  bool restrictCurriculum = false;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final route = Uri.parse(path).path;
    if (progressFails && route.endsWith('academic-credit-progress')) {
      throw const AuthFailure('산입 조회만 실패', status: 503);
    }
    if (restrictCurriculum && route.endsWith('academic/options')) {
      final result = await super.request(method, path, body);
      return {
        ...result!,
        'curricula': [
          {
            'id': 'other-department',
            'name': '타 학과 전용 교육과정',
            'revision': 1,
            'scope': {
              'clauses': [
                {'department_id': 'additional'},
              ],
            },
          },
        ],
      };
    }
    return super.request(method, path, body);
  }
}

const profile = PlanningProfile(
  school: '합성 대학',
  department: '주학과',
  institutionId: 'school',
  departmentId: 'department',
  admissionYear: 2026,
);

Future<void> mount(WidgetTester tester, AuditTransport transport) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StudentAcademicContextsEditor(
            api: StudentAcademicApi(transport, 'owner'),
            profile: profile,
            onChanged: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('curriculum eligibility respects department, inclusive year bounds and selected tracks across clauses', () {
    final option = AcademicOption({
      'id': 'scoped',
      'name': '합성 교육과정',
      'scope': {
        'clauses': [
          {
            'department_id': 'department',
            'admission_from': 2020,
            'admission_to': 2026,
            'track_mode': 'selected',
            'track_ids': ['track'],
          },
          {'department_id': 'additional', 'track_mode': 'all'},
        ],
      },
    });
    expect(option.appliesTo('department', 'track', 2020), isTrue);
    expect(option.appliesTo('department', 'track', 2026), isTrue);
    expect(option.appliesTo('department', 'track', 2027), isFalse);
    expect(option.appliesTo('department', 'other', 2026), isFalse);
    expect(option.appliesTo('wrong', 'track', 2026), isFalse);
    expect(option.appliesTo('additional', 'other', 2019), isTrue);
    expect(option.appliesTo('department', 'track', null), isFalse);
    expect(
      AcademicOption({'id': 'missing', 'name': '범위 없음'})
          .appliesTo('department', 'track', 2026),
      isFalse,
    );
  });
  testWidgets('settings remain usable when unrelated credit progress fails', (
    tester,
  ) async {
    final transport = AuditTransport()..progressFails = true;
    await mount(tester, transport);
    expect(find.text('먼저 설정에서 등록 학교·주학과·입학연도를 저장하세요.'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is AnchoredSelectField<String> && w.label == '교육과정',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('settings exclude curricula outside the selected department', (
    tester,
  ) async {
    final transport = AuditTransport()..restrictCurriculum = true;
    await mount(tester, transport);
    final select = tester.widget<AnchoredSelectField<String>>(
      find.byWidgetPredicate(
        (w) => w is AnchoredSelectField<String> && w.label == '교육과정',
      ),
    );
    expect(select.options.any((o) => o.value == 'other-department'), isFalse);
    expect(tester.takeException(), isNull);
  });
}
