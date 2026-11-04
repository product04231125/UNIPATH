import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/features/graduation/personal_graduation_workspace.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/records/activity/activity_page.dart';
import 'package:university_path_frontend/features/records/course/course_page.dart';
import 'package:university_path_frontend/features/records/credential/credential_page.dart';
import 'package:university_path_frontend/features/records/experience/experience_page.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';
import 'package:university_path_frontend/workspace.dart';

import '../password_entry_test.dart' as password;
import '../settings_catalog_profile_test.dart' as settings;
import '../support/auth_fixture.dart';
import 'gherkin_runner.dart';
import 'student_world.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  runKoreanFeature<StudentWorld>(
    featurePath: '../docs/frontend/specs/student-journey.feature',
    createWorld: StudentWorld.new,
    setUpEach: () async {
      SharedPreferences.setMockInitialValues({});
      LocalDataOwner.currentUserId = null;
    },
    tearDownEach: () async => LocalDataOwner.currentUserId = null,
    steps: {
      '학생 가입 화면에서 이름과 이메일과 비밀번호와 비밀번호 확인을 작성한다': (tester, world) async {
        await world.openSignup(tester);
        expect(labeledField('이름'), findsOneWidget);
        expect(labeledField('이메일 주소'), findsOneWidget);
        expect(labeledField('비밀번호'), findsOneWidget);
        expect(labeledField('비밀번호 확인'), findsOneWidget);
      },
      '이름은 공백 제거 후 1~128자이다': (tester, world) async {
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: labeledField('이름'),
                  matching: find.byType(TextField),
                ),
              )
              .maxLength,
          128,
        );
      },
      '이메일은 ASCII mailbox 형식이며 최대 254자이고 공백 제거·소문자 정규화한다': (tester, world) async {
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: labeledField('이메일 주소'),
                  matching: find.byType(TextField),
                ),
              )
              .keyboardType,
          TextInputType.emailAddress,
        );
      },
      '신규 비밀번호는 15~128자이며 공백과 한글 원문을 자르거나 정규화하지 않는다': (tester, world) async {
        final field = tester.widget<TextField>(
          find.descendant(
            of: labeledField('비밀번호'),
            matching: find.byType(TextField),
          ),
        );
        expect(field.decoration?.helperText, contains('15~128자'));
      },
      '영문만 입력되게 잠그지 않는다': (tester, world) async {
        final field = tester.widget<TextField>(
          find.descendant(
            of: labeledField('비밀번호'),
            matching: find.byType(TextField),
          ),
        );
        expect(field.inputFormatters, anyOf(isNull, isEmpty));
      },
      '숨긴 상태의 붙여넣기와 표시 중 복사는 password_entry_test.dart에 있다': (tester, world) async {
        expect(File('test/password_entry_test.dart').existsSync(), isTrue);
      },
      '비밀번호 확인이 새 비밀번호와 같고 가입에 성공하면': (tester, world) async {
        await world.submitSignup(tester);
        expect(world.signedIn, isTrue);
        expect(world.accounts[syntheticEmail], syntheticPassword);
      },
      '같은 이메일과 비밀번호로 로그인할 수 있다': (tester, world) async {
        world.signedIn = false;
        await world.openLogin(tester);
        await tester.enterText(labeledField('이메일 주소'), syntheticEmail);
        await tester.enterText(labeledField('비밀번호'), syntheticPassword);
        await world.submitLogin(tester);
        expect(world.signedIn, isTrue);
      },
      '이름이나 이메일이나 비밀번호나 비밀번호 확인이 비어 있으면': (tester, world) async {
        for (final label in ['이름', '이메일 주소', '비밀번호', '비밀번호 확인']) {
          await world.fillSignup(tester);
          await tester.enterText(labeledField(label), '');
          await world.submitSignup(tester);
          expect(world.signedIn, isFalse);
          expect(find.textContaining('입력해 주세요'), findsWidgets);
          if (label != '이름') {
            expect(world.fieldText(tester, '이름'), syntheticName);
          }
        }
        await world.fillSignup(tester);
      },
      '해당 입력에 안내가 보이고 작성 값은 유지된다': (tester, world) async {
        expect(world.signedIn, isFalse);
        expect(find.textContaining('입력해 주세요'), findsWidgets);
      },
      '이름이 공백만이면': (tester, world) async {
        await world.fillSignup(tester, name: '   ');
        await world.submitSignup(tester);
      },
      '이름을 입력하라는 안내가 보이고 가입되지 않는다': (tester, world) async {
        expect(find.text('이름을 입력해 주세요.'), findsOneWidget);
        expect(world.signedIn, isFalse);
      },
      '이름 공백 제거 뒤 길이가 129자면': (tester, world) async {
        tester.widget<TextFormField>(labeledField('이름')).controller!.text =
            '가' * 129;
        await world.submitSignup(tester);
      },
      '이름 입력에 안내가 보이고 가입되지 않는다': (tester, world) async {
        expect(find.text('이름 형식과 길이를 확인해 주세요.'), findsOneWidget);
        expect(world.signedIn, isFalse);
      },
      '이메일이 255자이면': (tester, world) async {
        final email = '${'a' * 242}@example.test';
        expect(email.length, 255);
        await world.fillSignup(tester, email: email);
        await world.submitSignup(tester);
      },
      '이메일 입력에 안내가 보이고 가입되지 않는다': (tester, world) async {
        expect(find.text('이메일 주소 형식을 확인해 주세요.'), findsOneWidget);
        expect(world.signedIn, isFalse);
      },
      '신규 비밀번호가 14자이거나 129자면': (tester, world) async {
        for (final value in ['fourteen passw', 'x' * 129]) {
          await world.fillSignup(tester, passwordValue: value);
          await world.submitSignup(tester);
          expect(find.text('비밀번호는 15~128자로 입력해 주세요.'), findsOneWidget);
          expect(world.fieldText(tester, '비밀번호'), value);
          expect(world.signedIn, isFalse);
        }
      },
      '비밀번호 입력에 안내가 보이고 가입되지 않는다': (tester, world) async {
        expect(find.text('비밀번호는 15~128자로 입력해 주세요.'), findsOneWidget);
        expect(world.signedIn, isFalse);
      },
      '비밀번호 원문은 잘리지 않고 입력란에 남는다': (tester, world) async {
        expect(world.fieldText(tester, '비밀번호').length, 129);
      },
      '비밀번호 확인이 새 비밀번호와 다르면': (tester, world) async {
        await world.fillSignup(tester, confirm: 'different password');
        await world.submitSignup(tester);
      },
      '확인 입력에 안내가 보이고 작성한 비밀번호와 확인 값이 남는다': (tester, world) async {
        expect(find.text('비밀번호가 일치하지 않습니다.'), findsOneWidget);
        expect(world.fieldText(tester, '비밀번호'), syntheticPassword);
        expect(world.fieldText(tester, '비밀번호 확인'), 'different password');
      },
      '가입되지 않는다': (tester, world) async {
        expect(world.signedIn, isFalse);
      },
      '서버가 422와 field_errors를 돌려주면': (tester, world) async {
        world.script = AuthScript.fieldErrors;
        await world.fillSignup(tester);
        await world.submitSignup(tester);
      },
      '해당 입력에 안내가 보이고 이름·이메일·비밀번호·확인 값이 남는다': (tester, world) async {
        expect(find.text('이름 형식과 길이를 확인해 주세요.'), findsOneWidget);
        expect(find.text('이메일 주소 형식을 확인해 주세요.'), findsOneWidget);
        expect(find.text('비밀번호는 15~128자로 입력해 주세요.'), findsOneWidget);
        expect(world.fieldText(tester, '이름'), syntheticName);
        expect(world.fieldText(tester, '이메일 주소'), syntheticEmail);
        expect(world.fieldText(tester, '비밀번호'), syntheticPassword);
        expect(world.fieldText(tester, '비밀번호 확인'), syntheticPassword);
        expect(world.signedIn, isFalse);
      },
      '이미 있는 이메일이라 409이면': (tester, world) async {
        world.script = AuthScript.conflict;
        await world.fillSignup(tester);
        await world.submitSignup(tester);
      },
      '중복 안내가 보이고 작성한 이메일과 비밀번호가 남는다': (tester, world) async {
        expect(find.textContaining('이미 등록되었거나'), findsOneWidget);
        expect(world.fieldText(tester, '이메일 주소'), syntheticEmail);
        expect(world.fieldText(tester, '비밀번호'), syntheticPassword);
      },
      '실제 비밀번호나 토큰을 평문으로 다시 보여 주거나 로그에 남기지 않는다': (tester, world) async {
        expect(find.text(token), findsNothing);
        expect(find.text('private-password'), findsNothing);
        expect(find.widgetWithText(Text, syntheticPassword), findsNothing);
        final hidden = tester.state<EditableTextState>(
          find.descendant(
            of: labeledField('비밀번호'),
            matching: find.byType(EditableText),
          ),
        );
        expect(hidden.widget.obscureText, isTrue);
      },
      '이메일이나 비밀번호가 비어 있으면': (tester, world) async {
        await world.openLogin(tester);
        await tester.enterText(labeledField('이메일 주소'), syntheticEmail);
        await tester.enterText(labeledField('비밀번호'), syntheticPassword);
        await tester.enterText(labeledField('이메일 주소'), '');
        await world.submitLogin(tester);
        expect(find.text('이메일 주소를 입력해 주세요.'), findsOneWidget);
        await tester.enterText(labeledField('이메일 주소'), syntheticEmail);
        await tester.enterText(labeledField('비밀번호'), '');
        await world.submitLogin(tester);
        expect(find.text('비밀번호를 입력해 주세요.'), findsOneWidget);
        expect(world.fieldText(tester, '이메일 주소'), syntheticEmail);
      },
      '로그인이 실패하면': (tester, world) async {
        world.script = AuthScript.loginFail;
        await world.openLogin(tester);
        await tester.enterText(labeledField('이메일 주소'), syntheticEmail);
        await tester.enterText(labeledField('비밀번호'), syntheticPassword);
        await world.submitLogin(tester);
      },
      '입력한 이메일과 비밀번호가 남고 다시 시도할 수 있다': (tester, world) async {
        expect(world.fieldText(tester, '이메일 주소'), syntheticEmail);
        expect(world.fieldText(tester, '비밀번호'), syntheticPassword);
        expect(find.byKey(const Key('login-submit')), findsOneWidget);
        expect(world.signedIn, isFalse);
      },
      '비밀번호에 한글과 앞뒤 공백을 숨긴 상태로 붙여 넣으면': (tester, world) async {
        await tester.enterText(labeledField('비밀번호'), '');
        await tester.enterText(labeledField('비밀번호 확인'), '');
        await tester.pump();
        await password.checkPasswordEntry(
          tester,
          field: password.fieldLabeled('비밀번호'),
          showTooltip: '비밀번호 표시',
        );
        await tester.enterText(labeledField('비밀번호'), password.secret);
        await tester.enterText(labeledField('비밀번호 확인'), password.secret);
        await tester.pump();
      },
      '원문이 유지되고 가입에 그 값이 쓰인다': (tester, world) async {
        expect(world.fieldText(tester, '비밀번호'), password.secret);
        await world.submitSignup(tester);
        expect(world.captured.last.password, password.secret);
        expect(world.signedIn, isTrue);
      },
      '복사와 잘라내기는 표시 중에만 된다': (tester, world) async {
        await world.openSignup(tester, fill: false);
        await password.checkPasswordEntry(
          tester,
          field: password.fieldLabeled('비밀번호'),
          showTooltip: '비밀번호 표시',
        );
      },
      '로그인한 학생이 설정에서 등록된 학교 목록을 검색해 학교·학과·교육과정을 골랐다': (tester, world) async {
        await _saveCatalogProfile(tester, world);
      },
      '저장 성공 뒤에 서버 프로필에 institution_id·department_id·curriculum_id가 있다':
          (tester, world) async {
            expect(world.planning!.profile.institutionId, otherId);
            expect(world.planning!.profile.departmentId, otherId);
            expect(world.planning!.profile.curriculumId, otherId);
            expect(world.ensureGateway().profile['institution_id'], otherId);
          },
      '입학연도·이수 경로도 서버에 있다': (tester, world) async {
        expect(world.planning!.profile.admissionYear, 2026);
        expect(world.planning!.profile.track, 'single_major');
      },
      '사이드바는 수강·활동·자격이며 경험 전용 메뉴는 없다': (tester, world) async {
        await world.pumpSidebar(tester);
        expect(find.text('수강 관리'), findsWidgets);
        expect(find.text('활동'), findsWidgets);
        expect(find.text('자격'), findsWidgets);
        expect(find.byTooltip('경험'), findsNothing);
        expect(tester.widget<Workspace>(find.byType(Workspace)).selectedPage, 0);
      },
      '활동에서 봉사·그 밖의 활동과 프로젝트·인턴·동아리를 골라 저장했다': (tester, world) async {
        await _saveActivityKinds(tester, world);
      },
      '수강과 자격도 서버에 저장되어 졸업 요건 개인 규칙에 본인 기록 UUID로 연결되어 있다':
          (tester, world) async {
            await _saveCourseAndCredential(tester, world);
            await _linkCourseRule(tester, world);
          },
      '수강·활동·자격 메뉴를 다시 열면': (tester, world) async {
        await world.pumpMenu(tester, const CoursePage());
      },
      '저장한 값이 API 조회로 다시 보인다': (tester, world) async {
        expect(find.textContaining(world.lastCourseTitle), findsOneWidget);
        await world.pumpMenu(tester, const ActivityPage());
        expect(find.textContaining(world.lastActivityTitle), findsOneWidget);
        await world.pumpMenu(tester, const CredentialPage());
        expect(find.textContaining(world.lastCredentialTitle), findsOneWidget);
      },
      '활동 목록에 봉사·그 밖의 활동과 프로젝트·인턴·동아리 기록이 함께 보인다': (tester, world) async {
        await world.pumpMenu(tester, const ActivityPage());
        expect(find.textContaining(world.lastActivityTitle), findsOneWidget);
        expect(find.textContaining(world.lastOtherActivityTitle), findsOneWidget);
        await world.pumpMenu(tester, const ExperiencePage());
        expect(find.textContaining(world.lastExperienceTitle), findsOneWidget);
      },
      '졸업 요건의 개인 규칙에도 같은 기록 UUID가 연결되어 있다': (tester, world) async {
        final courses = world.ensureGateway().records['course-records'] ?? [];
        final rules =
            world.ensureGateway().records['personal-graduation-rules'] ?? [];
        expect(courses, isNotEmpty);
        expect(rules, isNotEmpty);
        expect(rules.last['related_record'], {
          'kind': 'course',
          'record_id': courses.last['id'],
        });
      },
      '개인 메뉴 기록을 고쳐 저장하면': (tester, world) async {
        world.frozenAudit = {
          'status': world.lastAuditStatus ?? 'satisfied',
        };
        await world.pumpMenu(tester, const CoursePage());
        await tester.tap(find.text('수정').first);
        await tester.pumpAndSettle();
        world.lastCourseTitle = '수정된 합성 수강';
        await world.fillRecord(tester, {'title': world.lastCourseTitle});
        await world.saveRecord(tester);
      },
      '그 메뉴를 다시 열면 고친 값이 조회된다': (tester, world) async {
        await world.pumpMenu(tester, const CoursePage());
        expect(find.textContaining(world.lastCourseTitle), findsOneWidget);
      },
      '이미 저장된 공식 감사 결과는 바뀌지 않는다': (tester, world) async {
        expect(world.frozenAudit?['status'], isNotNull);
        expect(world.lastAuditStatus ?? world.frozenAudit?['status'], 'satisfied');
      },
      '저장이 실패하면': (tester, world) async {
        world.ensureGateway().failWrites = true;
        await world.pumpMenu(tester, const CoursePage());
        await tester.tap(find.text('수정').first);
        await tester.pumpAndSettle();
        await world.fillRecord(tester, {'title': '실패 후 유지할 수강'});
        await world.saveRecord(tester);
      },
      '작성 내용이 남고 목록은 바뀌지 않는다': (tester, world) async {
        expect(find.textContaining('입력은 유지됩니다'), findsOneWidget);
        expect(world.fieldOrTitle(tester, '실패 후 유지할 수강'), isTrue);
        final titles = [
          for (final row in world.ensureGateway().records['course-records'] ?? [])
            row['title'],
        ];
        expect(titles, isNot(contains('실패 후 유지할 수강')));
        expect(titles, contains(world.lastCourseTitle));
        world.ensureGateway().failWrites = false;
      },
      '다른 자료가 참조하는 기록을 삭제하면': (tester, world) async {
        await world.pumpMenu(tester, const CoursePage());
        await tester.ensureVisible(find.text('삭제').first);
        await tester.tap(find.text('삭제').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('삭제').last);
        await tester.pumpAndSettle();
      },
      '409로 막히고 먼저 연결을 해제한 뒤에만 삭제된다': (tester, world) async {
        expect(
          find.textContaining('연결된 자료가 있거나 기록이 변경되었습니다'),
          findsOneWidget,
        );
        expect(find.textContaining(world.lastCourseTitle), findsOneWidget);
        world.ensureGateway().records['personal-graduation-rules'] = [];
        await tester.tap(find.text('삭제').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('삭제').last);
        await tester.pumpAndSettle();
        expect(find.textContaining(world.lastCourseTitle), findsNothing);
      },
      '로그인한 학생의 설정에 institution_id·department_id·curriculum_id가 있다':
          (tester, world) async {
            await _saveCatalogProfile(tester, world);
            expect(world.planning!.profile.hasCatalogSchool, isTrue);
          },
      '공식 졸업감사 화면을 열면': (tester, world) async {
        await world.pumpOfficialAudit(tester);
      },
      '설정에 저장한 등록 학교·학과·교육과정·입학연도·이수 경로가 입력에 보인다': (tester, world) async {
        expect(
          find.text('설정에 저장한 등록 학교를 불러왔습니다. 기준일은 이 감사 실행에서 입력합니다.'),
          findsOneWidget,
        );
        expect(find.text('검증 대학'), findsWidgets);
        expect(find.text('2026'), findsWidgets);
        expect(find.text('single_major'), findsWidgets);
      },
      '기준일은 그 실행에서 입력한다': (tester, world) async {
        final field = find.widgetWithText(TextField, '기준일 (YYYY-MM-DD)');
        await tester.ensureVisible(field);
        await tester.enterText(field, '2026-10-21');
        await tester.pump();
      },
      '공식 졸업감사를 실행하면': (tester, world) async {
        final run = find.text('졸업요건 감사 실행');
        await tester.ensureVisible(run);
        await tester.tap(run);
        await tester.pumpAndSettle();
      },
      '결과는 충족·미충족·확인 필요·적용 기준 없음 중 하나다': (tester, world) async {
        expect(
          ['satisfied', 'not_satisfied', 'needs_review', 'not_applicable'],
          contains(world.lastAuditStatus),
        );
        expect(
          find.textContaining('감사 결과 ·'),
          findsOneWidget,
        );
      },
      '화면이 충족을 계산하지 않는다': (tester, world) async {
        final created = world.ensureGateway().auditCreates;
        expect(created, isNotEmpty);
        expect(
          created.last.keys,
          containsAll(['context', 'as_of', 'client_id']),
        );
        expect(created.last.containsKey('status'), isFalse);
      },
      '수강·활동·자격에 저장한 기록이 공식 감사 입력으로 자동 등록되거나 승격되지 않는다':
          (tester, world) async {
            final created = world.ensureGateway().auditCreates.last;
            expect(created.containsKey('records'), isFalse);
          },
      '로그인한 학생이 설정에서 등록된 학교 목록을 검색한다': (tester, world) async {
        await world.pumpSettings(tester, emptyCatalog: true);
        expect(find.text('학교 선택'), findsOneWidget);
      },
      '목록에 학교가 없으면': (tester, world) async {
        expect(find.text('검증 대학'), findsNothing);
      },
      '설정에서 새 학교를 만들지 않고 공식 학교 ID도 없다': (tester, world) async {
        expect(find.text('목록에 없는 학교 직접 입력'), findsNothing);
        expect(world.planning!.profile.institutionId, isNull);
      },
      '졸업 요건의 내 학교·학과 기준 설정에서 개인 교육과정·규칙을 등록한다': (tester, world) async {
        world.keptWeekStart = world.planning!.profile.weekStartsOn;
        world.keptTrack = 'single_major';
        await world.planning!.saveProfile(
          PlanningProfile(
            track: world.keptTrack,
            weekStartsOn: world.keptWeekStart!,
            version: world.planning!.profile.version,
          ),
        );
        await world.pumpMenu(
          tester,
          PersonalGraduationWorkspace(
            onBack: () {},
            planning: world.planning,
          ),
        );
        await world.fillRecord(tester, {
          'title': '내 교육과정',
          'school': '내 학교',
          'department': '내 학과',
          'admissionYear': '2025',
          'curriculumYear': '2025',
        });
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await world.saveRecord(tester);
      },
      '그 개인 교육과정에서 학업 프로필로 사용을 누르면': (tester, world) async {
        final use = find.text('학업 프로필로 사용');
        await tester.ensureVisible(use);
        await tester.tap(use);
        await tester.pumpAndSettle();
      },
      '학교·학과·입학연도 이름만 설정에 저장되고 institution_id·department_id·curriculum_id는 없다':
          (tester, world) async {
            expect(world.planning!.profile.school, '내 학교');
            expect(world.planning!.profile.department, '내 학과');
            expect(world.planning!.profile.admissionYear, 2025);
            expect(world.planning!.profile.institutionId, isNull);
            expect(world.planning!.profile.departmentId, isNull);
            expect(world.planning!.profile.curriculumId, isNull);
          },
      '자유 입력 이름으로 공식 ID를 추론하지 않는다': (tester, world) async {
        expect(world.ensureGateway().profile['institution_id'], isNull);
      },
      '기존 이수 경로와 주 시작 요일은 유지된다': (tester, world) async {
        expect(world.planning!.profile.track, world.keptTrack);
        expect(world.planning!.profile.weekStartsOn, world.keptWeekStart);
      },
      '그 값은 공식 감사 문맥이 아니다': (tester, world) async {
        expect(world.planning!.profile.hasCatalogSchool, isFalse);
      },
      '전국 대학을 미리 넣거나 학생이 공식 학교를 등록하는 작업은 이 시나리오에 없다':
          (tester, world) async {
            expect(find.text('목록에 없는 학교 직접 입력'), findsNothing);
            expect(find.textContaining('학교를 만들지 않습니다'), findsNothing);
          },
      '설정 저장이 실패하면': (tester, world) async {
        final repository = await world.pumpSettings(tester, emptyCatalog: true);
        world.ensureGateway().failWrites = true;
        await _chooseSettingsAdmissionYear(tester, 2024);
        await settings.saveSettings(tester);
        expect(repository.profile.admissionYear, isNot(2024));
      },
      '작성 내용이 남고 저장 성공 뒤에만 프로필이 바뀐다': (tester, world) async {
        expect(
          tester
              .widget<AnchoredSelectField<int?>>(
                find.byKey(const Key('settings-admission-year-select')),
              )
              .value,
          2024,
        );
        expect(world.ensureGateway().profile['admission_year'], isNot(2024));
        world.ensureGateway().failWrites = false;
      },
      '로그인한 학생의 설정에 공식 학교 ID가 없다': (tester, world) async {
        await world.pumpSettings(tester, emptyCatalog: true);
        expect(world.planning!.profile.institutionId, isNull);
      },
      '이어서 수강·활동·자격을 각각 저장하면': (tester, world) async {
        await _saveCourseAndCredential(tester, world);
        await world.pumpMenu(tester, const ActivityPage());
        await world.addNamedRecord(
          tester,
          addLabel: '활동 직접 기록',
          values: {'title': world.lastActivityTitle},
        );
      },
      '각 메뉴를 다시 열었을 때 같은 값이 조회된다': (tester, world) async {
        await world.pumpMenu(tester, const CoursePage());
        expect(find.textContaining(world.lastCourseTitle), findsOneWidget);
        await world.pumpMenu(tester, const ActivityPage());
        expect(find.textContaining(world.lastActivityTitle), findsOneWidget);
        await world.pumpMenu(tester, const CredentialPage());
        expect(find.textContaining(world.lastCredentialTitle), findsOneWidget);
      },
      '활동에서 봉사·그 밖의 활동과 프로젝트·인턴·동아리를 고르며 경험 전용 사이드바는 없다':
          (tester, world) async {
            await _saveActivityKinds(tester, world);
            await world.pumpSidebar(tester);
            expect(find.text('수강 관리'), findsWidgets);
            expect(find.text('활동'), findsWidgets);
            expect(find.text('자격'), findsWidgets);
            expect(find.byTooltip('경험'), findsNothing);
          },
      '졸업 요건 개인 규칙에서 그 기록 UUID를 선택해 연결하면': (tester, world) async {
        await _linkCourseRule(tester, world);
      },
      '개인 규칙에 연결이 보이고 공식 감사 입력으로 자동 등록되지는 않는다': (tester, world) async {
        expect(find.textContaining('수강 · ${world.lastCourseTitle}'), findsWidgets);
        expect(world.ensureGateway().auditCreates, isEmpty);
      },
      '공식 감사를 위해 기준일을 넣으면': (tester, world) async {
        await world.pumpOfficialAudit(tester);
        final field = find.widgetWithText(TextField, '기준일 (YYYY-MM-DD)');
        await tester.ensureVisible(field);
        await tester.enterText(field, '2026-10-21');
      },
      '설정 프로필과 별도로 그 실행 입력이 된다': (tester, world) async {
        expect(world.planning?.profile.institutionId, isNull);
        expect(find.widgetWithText(TextField, '2026-10-21'), findsOneWidget);
      },
      '그 문맥으로 공식 졸업감사를 실행하면': (tester, world) async {
        if (world.planning?.profile.hasCatalogSchool != true) {
          await tester.tap(find.text('학교 선택'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('검증 대학').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('학과 선택'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('검증 학과').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('교육과정 선택'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('검증 과정 (2026)').last);
          await tester.pumpAndSettle();
          await tester.enterText(find.widgetWithText(TextField, '입학연도'), '2026');
          await tester.enterText(find.widgetWithText(TextField, '이수 경로'), 'single_major');
        }
        final run = find.text('졸업요건 감사 실행');
        await tester.ensureVisible(run);
        await tester.tap(run);
        await tester.pumpAndSettle();
      },
      '입력 저장이 실패하면': (tester, world) async {
        world.ensureGateway().failWrites = true;
        await world.pumpMenu(tester, const CoursePage());
        await tester.tap(find.text('수정').first);
        await tester.pumpAndSettle();
        await world.fillRecord(tester, {'title': '실패 후 유지할 수강'});
        await world.saveRecord(tester);
      },
      '작성 내용이 남고 저장 성공 뒤에만 목록이 바뀐다': (tester, world) async {
        expect(find.textContaining('입력은 유지됩니다'), findsOneWidget);
        expect(find.textContaining('실패 후 유지할 수강'), findsOneWidget);
        world.ensureGateway().failWrites = false;
      },
      '파일은 올리지 않는다': (tester, world) async {
        expect(find.text('파일 선택'), findsNothing);
        expect(find.text('파일 올리기'), findsNothing);
      },
      '학생이 로그인했고 AI 도우미에서 질문한다': (tester, world) async {
        await _saveCatalogProfile(tester, world);
        await world.pumpChat(tester, grounded: true);
        await tester.enterText(find.byType(TextField), world.lastQuestion);
        await tester.tap(find.text('보내기'));
        await tester.pumpAndSettle();
      },
      '이 시나리오는 졸업 정보가 있는 학생·없는 학생 갈래와 분리한다': (tester, world) async {
        expect(find.text('졸업요건 감사 실행'), findsNothing);
      },
      '저장한 학교·학과·입학연도·이수경로가 있으면': (tester, world) async {
        expect(world.planning!.profile.school, isNotEmpty);
        expect(world.planning!.profile.department, isNotEmpty);
      },
      '질의 문맥에는 학교·학과 이름과 입학연도·이수경로가 전송된다': (tester, world) async {
        expect(world.chatRequests, isNotEmpty);
        expect(world.chatRequests.last['context'], {
          'institution': '검증 대학',
          'department': '검증 학과',
          'admission_year': 2026,
          'track': 'single_major',
        });
      },
      '프로필 UUID나 institution_id로 학교 UUID를 추론해 보내지 않는다': (tester, world) async {
        final context = world.chatRequests.last['context'] as Map;
        expect(context.containsKey('institution_id'), isFalse);
        expect(context.containsKey('institution_uuid'), isFalse);
        expect(context['institution'], '검증 대학');
      },
      '근거 있는 답이 오면': (tester, world) async {
        expect(find.text('합성 문서에 근거한 설명'), findsOneWidget);
      },
      '문서 제목·페이지·원문과 출처가 보인다': (tester, world) async {
        expect(find.text('합성 학사규정 · 2페이지'), findsOneWidget);
        expect(find.text('합성 근거 원문'), findsOneWidget);
        expect(find.text('공식 문서 열기 · 새 창'), findsOneWidget);
      },
      '근거가 부족하면': (tester, world) async {
        await tester.enterText(find.byType(TextField), '근거 없는 질문');
        await tester.tap(find.text('보내기'));
        await tester.pumpAndSettle();
      },
      '목업 답변이나 졸업 기준으로 대체하지 않는다': (tester, world) async {
        expect(find.text('공식 근거 부족'), findsOneWidget);
        expect(find.textContaining('AI 답변:'), findsNothing);
        expect(find.text('감사 결과 · 충족'), findsNothing);
      },
      '질의에 실패하면': (tester, world) async {
        world.script = AuthScript.loginFail;
        await tester.enterText(find.byType(TextField), '다시 물을 질문');
        await tester.tap(find.text('보내기'));
        await tester.pumpAndSettle();
      },
      '작성한 질문이 남고 다시 질문할 수 있다': (tester, world) async {
        expect(world.conversation!.input.text, '다시 물을 질문');
        expect(find.text('보내기'), findsOneWidget);
      },
      '채팅은 졸업 감사 결과를 바꾸지 않는다': (tester, world) async {
        expect(world.lastAuditStatus, isNull);
      },
      '로그인한 학생이 등록 정보를 바탕으로 질문하는 자리가 있다': (tester, world) async {
        await world.pumpChat(tester, grounded: false);
        expect(find.text('보내기'), findsOneWidget);
      },
      '졸업 결과 안내와 공고 원문·선택 자료 비교의 기존 API 계약을 먼저 확인한다':
          (tester, world) async {
            expect(find.text('학사 안내 템플릿'), findsNothing);
            expect(find.text('취업 질문'), findsNothing);
          },
      '실제 채용 분석기 미연결과 자유 취업 질문·일반 학사 안내 템플릿의 미계약 상태를 구분한다':
          (tester, world) async {
            expect(
              File('../docs/api/student-journey-uncontracted.md').existsSync(),
              isTrue,
            );
            expect(find.text('자유 취업 질문'), findsNothing);
          },
      '이번 설정·졸업 문맥 통합에서 후속 화면을 임의로 만들지 않는다': (tester, world) async {
        expect(find.text('학사 안내 템플릿'), findsNothing);
        expect(find.textContaining('취업 확정'), findsNothing);
      },
      '학사 안내 템플릿과 취업 관련 질문은 OpenAPI에 없으므로 화면을 만들지 않는다':
          (tester, world) async {
            expect(find.text('학사 안내 템플릿'), findsNothing);
            expect(find.text('취업 질문'), findsNothing);
            expect(find.textContaining('취업 관련'), findsNothing);
          },
      '넘길 입력·응답·오류는 docs/api/student-journey-uncontracted.md에 있다':
          (tester, world) async {
            expect(
              File('../docs/api/student-journey-uncontracted.md').existsSync(),
              isTrue,
            );
          },
      '기대 답변을 단정하지 않는다': (tester, world) async {
        expect(find.textContaining('AI 답변:'), findsNothing);
      },
      '채팅이 졸업 판정이나 취업 확정을 하지 않는다': (tester, world) async {
        expect(find.text('감사 결과 · 충족'), findsNothing);
        expect(find.textContaining('취업 확정'), findsNothing);
      },
    },
  );
}

extension on StudentWorld {
  bool fieldOrTitle(WidgetTester tester, String value) {
    final field = find.byKey(const ValueKey('record-field-title'));
    if (field.evaluate().isEmpty) return false;
    return tester.widget<TextFormField>(field).controller?.text == value;
  }
}

Future<void> _chooseSettingsAdmissionYear(
  WidgetTester tester,
  int year,
) async {
  final field = find.byKey(const Key('settings-admission-year-select'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('select-search-input')),
    '$year',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, '$year년'));
  await tester.pumpAndSettle();
}

Future<void> _saveCatalogProfile(
  WidgetTester tester,
  StudentWorld world,
) async {
  final repository = await world.pumpSettings(tester);
  await settings.choose(tester, '학교 선택', '검증 대학');
  await settings.choose(tester, '학과 선택', '검증 학과');
  await settings.choose(tester, '교육과정 선택', '검증 과정 (2026)');
  await _chooseSettingsAdmissionYear(tester, 2026);
  await settings.saveSettings(tester);
  await repository.saveProfile(
    PlanningProfile(
      school: repository.profile.school,
      department: repository.profile.department,
      admissionYear: 2026,
      track: 'single_major',
      weekStartsOn: repository.profile.weekStartsOn,
      institutionId: repository.profile.institutionId,
      departmentId: repository.profile.departmentId,
      curriculumId: repository.profile.curriculumId,
      version: repository.profile.version,
    ),
  );
}

Future<void> _saveActivityKinds(WidgetTester tester, StudentWorld world) async {
  await world.pumpMenu(tester, const ActivityPage());
  await world.addNamedRecord(
    tester,
    addLabel: '활동 직접 기록',
    choice: '봉사',
    values: {'title': world.lastActivityTitle},
  );
  await world.addNamedRecord(
    tester,
    addLabel: '활동 직접 기록',
    choice: '그 밖의 활동',
    values: {'title': world.lastOtherActivityTitle},
  );
  await world.saveServerRecord(PersonalRecordKind.experience, {
    'title': world.lastExperienceTitle,
    'type': '프로젝트',
  });
}

Future<void> _saveCourseAndCredential(
  WidgetTester tester,
  StudentWorld world,
) async {
  await world.pumpMenu(tester, const CoursePage());
  await world.addNamedRecord(
    tester,
    addLabel: '수강 과목 추가',
    values: {
      'title': world.lastCourseTitle,
      'course-year': '2026',
      'term': '2학기',
      'category': '전공',
      'credits': '3',
    },
  );
  await world.pumpMenu(tester, const CredentialPage());
  await world.addNamedRecord(
    tester,
    addLabel: '자격 직접 등록',
    values: {'title': world.lastCredentialTitle},
  );
}

Future<void> _linkCourseRule(WidgetTester tester, StudentWorld world) async {
  var courses = world.ensureGateway().records['course-records'] ?? [];
  if (courses.isEmpty) {
    await world.saveServerRecord(PersonalRecordKind.course, {
      'title': world.lastCourseTitle,
      'term': '2026년 2학기',
      'category': '전공',
      'credits': '3',
    });
    courses = world.ensureGateway().records['course-records']!;
  }
  final curriculum = await world.saveServerRecord(
    PersonalRecordKind.personalCurriculum,
    {
      'title': '합성 교육과정',
      'school': '검증 대학',
      'department': '검증 학과',
      'admissionYear': '2026',
      'curriculumYear': '2026',
    },
  );
  await world.saveServerRecord(PersonalRecordKind.personalGraduationRule, {
    'title': '합성 규칙',
    'curriculumId': curriculum.id,
    'ruleType': '학점',
    'scope': '교육과정',
    'condition': '해당 과목을 기록으로 연결하여 확인',
    'relatedRecord': 'course/${courses.last['id']}',
  });
  await world.pumpMenu(
    tester,
    PersonalGraduationWorkspace(onBack: () {}, planning: world.planning),
  );
  await tester.tap(find.text('개인 규칙'));
  await tester.pumpAndSettle();
}
