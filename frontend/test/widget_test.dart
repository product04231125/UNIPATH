import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists personal planning data locally', () async {
    final repository = PlanningRepository();
    await repository.load();
    await repository.saveProfile(
      const PlanningProfile(
        school: '테스트대학교',
        department: '컴퓨터공학과',
        admissionYear: 2025,
        academicYearOverride: 2,
        weekStartsOn: WeekStartDay.tuesday,
      ),
    );
    await repository.saveEvent(
      PlanningEvent(
        id: 'deadline-1',
        title: '과제 마감',
        start: DateTime(2026, 10, 5, 9),
        end: DateTime(2026, 10, 5, 10),
        category: PlanningEventCategory.deadline,
      ),
    );

    final reloaded = PlanningRepository();
    await reloaded.load();

    expect(reloaded.profile.school, '테스트대학교');
    expect(reloaded.profile.academicYearFor(DateTime(2026, 10)), 2);
    expect(reloaded.profile.weekStartsOn, WeekStartDay.tuesday);
    expect(reloaded.events.single.title, '과제 마감');
  });

  testWidgets('renders and validates the login mock', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp());

    expect(find.text('나의 대학생활 경로를\n관리하세요.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('이메일 주소를 입력해 주세요.'), findsOneWidget);
    expect(find.text('비밀번호를 입력해 주세요.'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'mock@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('나의 대학생활 경로'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('shows the sign-up mock without creating an account', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp());

    await tester.tap(find.byKey(const Key('signup-tab')));
    await tester.pumpAndSettle();

    expect(find.text('이름'), findsOneWidget);
    expect(find.byKey(const Key('signup-submit')), findsOneWidget);
    expect(find.textContaining('계정, 학교 정보, 역할은 생성·저장되지 않습니다.'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('renders the UniversityPath workspace', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));
    await tester.pumpAndSettle();
    expect(find.text('UniversityPath'), findsOneWidget);
    expect(find.text('나의 대학생활 경로'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('returns to the login mock when the user signs out', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));

    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();

    expect(find.text('나의 대학생활 경로를\n관리하세요.'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'opens academic planning settings from the workspace navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );

      await tester.tap(find.text('설정'));
      await tester.pumpAndSettle();

      expect(find.text('학업과 계획'), findsOneWidget);
      expect(find.text('주 시작 요일'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('opens and sends a message through the assistant panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();
    expect(find.text('AI 도우미'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '졸업 요건을 확인해줘');
    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();

    expect(find.text('나: 졸업 요건을 확인해줘'), findsOneWidget);
    expect(find.textContaining('문서 근거 답변'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'uses compact navigation and an assistant overlay on narrow widths',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );

      expect(find.text('홈'), findsNothing);
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();

      expect(find.text('AI 도우미'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('keeps the home usable at 480 by 520', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 520));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));
    await tester.pumpAndSettle();

    expect(find.text('이번 주 일정'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('shows seven empty days in the home weekly schedule', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));
    await tester.pumpAndSettle();

    expect(find.text('일정 없음'), findsNWidgets(7));
    final now = DateTime.now();
    final sunday = now.subtract(Duration(days: now.weekday % 7));
    expect(find.text('일 ${sunday.month}/${sunday.day}'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('scrolls the full sidebar at a low desktop height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 520));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('설정'));
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();

    expect(find.text('학업과 계획'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('adds a personal record from the course menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));

    await tester.tap(find.text('수강 관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수강 과목 직접 입력'));
    await tester.pumpAndSettle();
    for (final entry in {
      'title': '운영체제',
      'term': '2026-2',
      'category': '전공선택',
      'credits': '3',
    }.entries) {
      final field = find.byKey(ValueKey('record-field-${entry.key}'));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    await tester.tap(find.text('내 기록에 저장'));
    await tester.pumpAndSettle();

    expect(find.text('운영체제'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('can hide record fixtures from the mock switch', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));

    await tester.tap(find.text('수강 관리'));
    await tester.pumpAndSettle();
    expect(find.text('자료구조'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mock-data-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('자료구조'), findsNothing);
    expect(find.text('수강 과목 직접 입력'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('opens every workspace menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));

    for (final menu in [
      ('수강 관리', '이번 학기 수강 과목'),
      ('일정', '개인 계획을 이 기기에 저장합니다.'),
      ('졸업 요건', '기준 선택'),
      ('활동', '등록한 활동'),
      ('경험', '경험 타임라인'),
      ('자격', '등록한 자격'),
      ('포트폴리오·성과', '포트폴리오 초안'),
      ('설정', '학업과 계획'),
    ]) {
      await tester.tap(find.text(menu.$1));
      await tester.pumpAndSettle();
      expect(find.textContaining(menu.$2), findsWidgets);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('saves a personal schedule on this device', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 768));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('일정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('일정 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '프로젝트 마감');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('프로젝트 마감'), findsWidgets);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('configures a personal academic rule set', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));

    await tester.tap(find.text('졸업 요건'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('내 학교·학과 기준 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('교육과정 추가'));
    await tester.pumpAndSettle();
    for (final entry in {
      'title': '개인 교육과정 A',
      'school': '테스트대학교',
      'department': '소프트웨어학과',
      'admissionYear': '2024',
      'curriculumYear': '2024',
    }.entries) {
      final field = find.byKey(ValueKey('record-field-${entry.key}'));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    await tester.tap(find.text('내 기록에 저장'));
    await tester.pumpAndSettle();

    expect(find.text('개인 교육과정 A'), findsOneWidget);
    expect(find.text('개인 기준 계산'), findsNothing);
    expect(find.textContaining('테스트대학교'), findsWidgets);
    await tester.binding.setSurfaceSize(null);
  });
}
