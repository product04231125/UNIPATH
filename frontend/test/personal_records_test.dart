import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_record_fields.dart';
import 'package:university_path_frontend/features/records/course/course_page.dart';
import 'package:university_path_frontend/features/records/activity/activity_page.dart';
import 'package:university_path_frontend/features/records/experience/experience_page.dart';
import 'package:university_path_frontend/features/auth/guest_preview_scope.dart';
import 'package:university_path_frontend/features/records/local_record_workbench.dart';
import 'package:university_path_frontend/features/records/personal_repository_scope.dart';
import 'package:university_path_frontend/features/records/record_menu_page.dart';

import 'support/achievement_records_page.dart';

class _ActivityReviewRepository extends PersonalRecordRepository {
  _ActivityReviewRepository() : super(PersonalRecordKind.activity);

  bool failSaves = false;
  final submitted = <PersonalRecord>[];
  int deletes = 0;

  @override
  Future<void> save(PersonalRecord record) async {
    submitted.add(record);
    if (failSaves) throw StateError('Synthetic storage failure');
    await super.save(record);
  }

  @override
  Future<void> delete(String id, {int? expectedVersion}) async {
    deletes++;
    await super.delete(id, expectedVersion: expectedVersion);
  }
}

Future<void> _pumpActivityReview(
  WidgetTester tester, {
  required _ActivityReviewRepository repository,
  required ValueNotifier<bool> guest,
  Widget page = const ActivityPage(),
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final experience = PersonalRecordRepository(PersonalRecordKind.experience);
  await tester.pumpWidget(
    ValueListenableBuilder<bool>(
      valueListenable: guest,
      builder: (context, active, _) => GuestPreviewScope(
        active: active,
        child: MaterialApp(
          home: PersonalRepositoryScope(
            records: (kind) => switch (kind) {
              PersonalRecordKind.activity => repository,
              PersonalRecordKind.experience => experience,
              _ => PersonalRecordRepository(kind),
            },
            portfolio: () => throw UnimplementedError(),
            child: Scaffold(body: page),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _chooseActivityAdd(
  WidgetTester tester, {
  String choice = '봉사',
}) async {
  await tester.tap(find.text('활동 직접 기록'));
  await tester.pumpAndSettle();
  final option = find.text(choice);
  if (option.evaluate().isNotEmpty) {
    await tester.tap(option.last);
    await tester.pumpAndSettle();
  }
}

RecordMenuPage _activityMenu({
  Future<List<PersonalRecordField>> Function()? fieldsLoader,
  Future<String?> Function(Map<String, String>)? validateValues,
}) => RecordMenuPage(
  kind: PersonalRecordKind.activity,
  title: '활동',
  description: '활동 기록',
  listTitle: '등록한 활동',
  guideTitle: '활동 준비',
  guides: const [],
  addLabel: '활동 직접 기록',
  detailLabel: '기관 · 기간 · 역할',
  fieldsLoader: fieldsLoader,
  validateValues: validateValues,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('activity review guest blocks add edit and delete', (
    tester,
  ) async {
    final repository = _ActivityReviewRepository();
    await repository.load();
    await repository.save(
      PersonalRecord(id: 'existing', values: {'title': '기존 활동'}),
    );
    repository.submitted.clear();
    final guest = ValueNotifier(true);
    addTearDown(guest.dispose);
    await _pumpActivityReview(tester, repository: repository, guest: guest);
    for (final label in ['활동 직접 기록', '수정', '삭제']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text(GuestPreviewScope.blockedMessage), findsOneWidget);
    }
    expect(repository.submitted, isEmpty);
    expect(repository.deletes, 0);
    expect(repository.records.single.value('title'), '기존 활동');
  });

  testWidgets('activity review guest transition blocks open form save', (
    tester,
  ) async {
    final repository = _ActivityReviewRepository();
    final guest = ValueNotifier(false);
    addTearDown(guest.dispose);
    await _pumpActivityReview(tester, repository: repository, guest: guest);
    await _chooseActivityAdd(tester);
    final title = find.byKey(const ValueKey('record-field-title'));
    await tester.enterText(title, '보존할 활동');
    guest.value = true;
    await tester.pumpAndSettle();
    await tester.tap(find.text('내 기록에 저장'));
    await tester.pumpAndSettle();
    expect(repository.submitted, isEmpty);
    expect(tester.widget<TextFormField>(title).controller!.text, '보존할 활동');
    guest.value = false;
    await tester.pumpAndSettle();
    await tester.tap(find.text('내 기록에 저장'));
    await tester.pumpAndSettle();
    expect(repository.records.single.value('title'), '보존할 활동');
    expect(find.text('내 기록에 저장'), findsNothing);
  });

  testWidgets(
    'activity review guest transition during validation blocks save',
    (tester) async {
      final repository = _ActivityReviewRepository();
      final guest = ValueNotifier(false);
      addTearDown(guest.dispose);
      final validation = Completer<String?>();
      await _pumpActivityReview(
        tester,
        repository: repository,
        guest: guest,
        page: _activityMenu(validateValues: (_) => validation.future),
      );
      await tester.tap(find.text('활동 직접 기록'));
      await tester.pumpAndSettle();
      final title = find.byKey(const ValueKey('record-field-title'));
      await tester.enterText(title, '검증 대기 활동');
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pump();
      guest.value = true;
      await tester.pump();
      validation.complete(null);
      await tester.pumpAndSettle();
      expect(repository.submitted, isEmpty);
      expect(find.text('내 기록에 저장'), findsOneWidget);
      expect(tester.widget<TextFormField>(title).controller!.text, '검증 대기 활동');
    },
  );

  for (final becomeGuest in [false, true]) {
    testWidgets(
      'activity review pending fields avoid duplicate or guest forms guest=$becomeGuest',
      (tester) async {
        final repository = _ActivityReviewRepository();
        final guest = ValueNotifier(false);
        addTearDown(guest.dispose);
        final fields = Completer<List<PersonalRecordField>>();
        var loads = 0;
        await _pumpActivityReview(
          tester,
          repository: repository,
          guest: guest,
          page: _activityMenu(
            fieldsLoader: () async {
              loads++;
              return loads == 1
                  ? personalRecordFields(PersonalRecordKind.activity)
                  : fields.future;
            },
          ),
        );
        await tester.tap(find.text('활동 직접 기록'));
        await tester.pump();
        await tester.tap(find.text('활동 직접 기록'));
        await tester.pump();
        if (becomeGuest) {
          guest.value = true;
          await tester.pump();
        }
        fields.complete(personalRecordFields(PersonalRecordKind.activity));
        await tester.pumpAndSettle();
        expect(loads, 2);
        expect(
          find.text('내 기록에 저장'),
          becomeGuest ? findsNothing : findsOneWidget,
        );
        expect(repository.submitted, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'activity review failed save keeps input and retries the same record',
    (tester) async {
      final repository = _ActivityReviewRepository()..failSaves = true;
      final guest = ValueNotifier(false);
      addTearDown(guest.dispose);
      await _pumpActivityReview(tester, repository: repository, guest: guest);
      await _chooseActivityAdd(tester);
      final title = find.byKey(const ValueKey('record-field-title'));
      await tester.enterText(title, '다시 저장할 활동');
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(repository.records, isEmpty);
      expect(tester.widget<TextFormField>(title).controller!.text, '다시 저장할 활동');
      expect(find.textContaining('입력을 유지했으니 다시 시도하세요.'), findsOneWidget);
      repository.failSaves = false;
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(repository.records.single.value('title'), '다시 저장할 활동');
      expect(repository.submitted, hasLength(2));
      expect(repository.submitted.first.id, repository.submitted.last.id);
      expect(find.textContaining('활동 · 다시 저장할 활동'), findsOneWidget);
    },
  );

  testWidgets(
    'activity review guest transition during delete confirmation blocks delete',
    (tester) async {
      final repository = _ActivityReviewRepository();
      await repository.load();
      await repository.save(
        PersonalRecord(id: 'existing', values: {'title': '남길 활동'}),
      );
      final guest = ValueNotifier(false);
      addTearDown(guest.dispose);
      await _pumpActivityReview(tester, repository: repository, guest: guest);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      guest.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제').last);
      await tester.pumpAndSettle();
      expect(repository.deletes, 0);
      expect(repository.records.single.value('title'), '남길 활동');
    },
  );

  testWidgets('activity review workbench blocks guest save after validation', (
    tester,
  ) async {
    final repository = _ActivityReviewRepository();
    final guest = ValueNotifier(false);
    addTearDown(guest.dispose);
    final validation = Completer<String?>();
    await _pumpActivityReview(
      tester,
      repository: repository,
      guest: guest,
      page: LocalRecordWorkbench(
        kind: PersonalRecordKind.activity,
        title: '활동 작업대',
        repository: repository,
        fieldsLoader: () async =>
            personalRecordFields(PersonalRecordKind.activity),
        validateValues: (_) => validation.future,
      ),
    );
    final title = find.byKey(const ValueKey('record-field-title'));
    await tester.enterText(title, '작업대 입력');
    await tester.ensureVisible(find.text('등록'));
    await tester.tap(find.text('등록'));
    await tester.pump();
    guest.value = true;
    await tester.pump();
    validation.complete(null);
    await tester.pumpAndSettle();
    expect(repository.submitted, isEmpty);
    expect(tester.widget<TextFormField>(title).controller!.text, '작업대 입력');
    expect(find.text('등록'), findsOneWidget);
  });

  testWidgets(
    'activity review workbench guest transition blocks confirmed delete',
    (tester) async {
      final repository = _ActivityReviewRepository();
      await repository.load();
      await repository.save(
        PersonalRecord(id: 'existing', values: {'title': '작업대 활동'}),
      );
      final guest = ValueNotifier(false);
      addTearDown(guest.dispose);
      await _pumpActivityReview(
        tester,
        repository: repository,
        guest: guest,
        page: LocalRecordWorkbench(
          kind: PersonalRecordKind.activity,
          title: '활동 작업대',
          repository: repository,
          fieldsLoader: () async =>
              personalRecordFields(PersonalRecordKind.activity),
        ),
      );
      expect(find.text('개인 기록'), findsOneWidget);
      expect(find.text('개인 설정'), findsNothing);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      guest.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제').last);
      await tester.pumpAndSettle();
      expect(repository.deletes, 0);
      expect(repository.records.single.value('title'), '작업대 활동');
    },
  );

  testWidgets('activity review unknown approval is not a missing relation', (
    tester,
  ) async {
    final repository = _ActivityReviewRepository();
    await repository.load();
    await repository.save(
      PersonalRecord(
        id: 'unknown',
        values: {'title': '확인할 활동', 'approval': 'future_status'},
      ),
    );
    final guest = ValueNotifier(false);
    addTearDown(guest.dispose);
    await _pumpActivityReview(tester, repository: repository, guest: guest);
    expect(find.textContaining('알 수 없는 승인 상태'), findsOneWidget);
    expect(find.textContaining('연결 대상 없음'), findsNothing);
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    expect(find.text('알 수 없는 승인 상태 · 다시 선택하세요'), findsOneWidget);
    expect(repository.records.single.value('approval'), 'future_status');
  });

  testWidgets(
    'activity review opening 1365 confirmation leaves records unchanged',
    (tester) async {
      final repository = _ActivityReviewRepository();
      await repository.load();
      await repository.save(
        PersonalRecord(
          id: 'external',
          values: {
            'title': '외부 안내 활동',
            'approval': 'pending',
            'reportedHours': '2',
          },
        ),
      );
      repository.submitted.clear();
      final guest = ValueNotifier(false);
      addTearDown(guest.dispose);
      await _pumpActivityReview(tester, repository: repository, guest: guest);
      final link = find.textContaining('1365 봉사 찾기');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(repository.submitted, isEmpty);
      expect(repository.deletes, 0);
      expect(repository.records.single.values, {
        'title': '외부 안내 활동',
        'approval': 'pending',
        'reportedHours': '2',
      });
      final loaded = PersonalRecordRepository(PersonalRecordKind.activity);
      await loaded.load();
      expect(loaded.records.single.values, repository.records.single.values);
    },
  );

  test(
    'concurrent personal writes across owners preserve unrelated records',
    () async {
      final first = PersonalRecordRepository(PersonalRecordKind.experience);
      final second = PersonalRecordRepository(PersonalRecordKind.experience);
      await first.load();
      await second.load();
      await Future.wait([
        first.save(PersonalRecord(id: 'one', values: {'title': '첫 기록'})),
        second.save(PersonalRecord(id: 'two', values: {'title': '다른 기록'})),
      ]);
      final read = PersonalRecordRepository(PersonalRecordKind.experience);
      await read.load();
      expect(read.records.map((r) => r.id).toSet(), {'one', 'two'});
      await first.delete('one');
      await read.load();
      expect(read.records.single.id, 'two');
      await (await SharedPreferences.getInstance()).remove(read.storageKey);
      await read.load();
      expect(read.records, isEmpty);
    },
  );

  testWidgets(
    'activity preserves recorded meaning and localizes stored approval',
    (tester) async {
      final repo = PersonalRecordRepository(PersonalRecordKind.activity);
      await repo.load();
      await repo.save(
        PersonalRecord(
          id: 'approval-label',
          values: {'title': '내 활동', 'approval': 'needs_review'},
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ActivityPage())),
      );
      await tester.pumpAndSettle();
      expect(find.text('개인 기록'), findsOneWidget);
      expect(find.text('충족'), findsNothing);
      expect(find.textContaining('사용자가 확인한 승인 상태: 검토 필요'), findsOneWidget);
      expect(find.textContaining('needs_review'), findsNothing);
      final loaded = PersonalRecordRepository(PersonalRecordKind.activity);
      await loaded.load();
      expect(loaded.records.single.value('approval'), 'needs_review');
    },
  );

  testWidgets('activity shows empty personal state and collapses guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ActivityPage())),
    );
    await tester.pumpAndSettle();
    expect(find.text('개인 기록이 없습니다. 직접 입력해 주세요.'), findsOneWidget);
    expect(find.text('학과 멘토링'), findsNothing);
    expect(find.byType(ExpansionTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'activity add chooses volunteer other or experience and lists both kinds',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final activity = PersonalRecordRepository(PersonalRecordKind.activity);
      final experience = PersonalRecordRepository(PersonalRecordKind.experience);
      await activity.load();
      await experience.load();
      await tester.pumpWidget(
        MaterialApp(
          home: PersonalRepositoryScope(
            records: (kind) => switch (kind) {
              PersonalRecordKind.activity => activity,
              PersonalRecordKind.experience => experience,
              _ => PersonalRecordRepository(kind),
            },
            portfolio: () => throw UnimplementedError(),
            child: const Scaffold(body: ActivityPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _chooseActivityAdd(tester);
      await tester.enterText(
        find.byKey(const ValueKey('record-field-title')),
        '통합 봉사',
      );
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();

      await _chooseActivityAdd(tester, choice: '그 밖의 활동');
      await tester.enterText(
        find.byKey(const ValueKey('record-field-title')),
        '통합 기타',
      );
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();

      await _chooseActivityAdd(tester, choice: '프로젝트·인턴·동아리');
      await tester.enterText(
        find.byKey(const ValueKey('record-field-title')),
        '통합 프로젝트',
      );
      await tester.enterText(
        find.byKey(const ValueKey('record-field-type')),
        '프로젝트',
      );
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();

      expect(find.textContaining('활동 · 통합 봉사'), findsOneWidget);
      expect(find.textContaining('활동 · 통합 기타'), findsOneWidget);
      expect(find.textContaining('경험 · 통합 프로젝트'), findsOneWidget);
      expect(activity.records.map((r) => r.value('title')), [
        '통합 봉사',
        '통합 기타',
      ]);
      expect(experience.records.single.value('title'), '통합 프로젝트');
      expect(experience.records.single.value('type'), '프로젝트');
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'course shows personal records without example rows scale=$scale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(480, 520));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = PersonalRecordRepository(PersonalRecordKind.course);
        await repo.load();
        await repo.save(
          PersonalRecord(
            id: 'layout',
            values: {'title': '내 과목', 'term': '2026-2', 'credits': '2'},
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: universityPathTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(body: CoursePage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('내 과목'), findsOneWidget);
        expect(find.text('자료구조'), findsNothing);
        expect(find.text('개인 기록'), findsNothing);
        expect(find.textContaining('개인 입력 합계 2.0학점'), findsOneWidget);
        expect(
          find.textContaining('학기별 수강 계획과 개인 이수 기록을 정리합니다.'),
          findsOneWidget,
        );
        expect(find.textContaining('졸업 반영은 학교의 확정 기록'), findsNothing);
        expect(find.textContaining('학교에서 확인한 정보가 없으면'), findsNothing);
        await tester.ensureVisible(find.text('교육과정 확인'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('교육과정 확인'));
        await tester.pumpAndSettle();
        expect(find.text('• 인정 영역과 학점 분류 확인'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('personal repositories persist CRUD and isolate domains', () async {
    for (final kind in PersonalRecordKind.values) {
      final repo = PersonalRecordRepository(kind);
      await repo.load();
      final id = PersonalRecord.newId();
      await repo.save(PersonalRecord(id: id, values: {'title': kind.name}));
      final loaded = PersonalRecordRepository(kind);
      await loaded.load();
      expect(loaded.records.single.value('title'), kind.name);
      await loaded.save(PersonalRecord(id: id, values: {'title': '수정'}));
      expect(loaded.records.single.id, id);
      await loaded.delete(id);
      final empty = PersonalRecordRepository(kind);
      await empty.load();
      expect(empty.records, isEmpty);
    }
  });

  test('corrupted storage is not overwritten on load failure', () async {
    final repo = PersonalRecordRepository(PersonalRecordKind.course);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(repo.storageKey, 'invalid');
    await expectLater(repo.load(), throwsFormatException);
    await expectLater(
      repo.save(PersonalRecord(id: 'new', values: {'title': '새 기록'})),
      throwsStateError,
    );
    expect(prefs.getString(repo.storageKey), 'invalid');
  });

  test(
    'structured fields reject impossible values and preserve provenance',
    () {
      final fields = personalRecordFields(PersonalRecordKind.course);
      final credit = fields.firstWhere((f) => f.key == 'credits');
      for (final value in ['-1', '0', 'NaN', 'Infinity']) {
        expect(credit.validate(value), isNotNull);
      }
      expect(credit.validate('1.5'), isNull);
      const date = PersonalRecordField(
        'date',
        '날짜',
        type: PersonalFieldType.date,
      );
      expect(date.validate('2026-02-30'), isNotNull);
      expect(date.validate('2026-02-28'), isNull);
      expect(
        personalRecordCrossError({
          'startedOn': '2026-02-28',
          'endedOn': '2026-01-01',
        }),
        isNotNull,
      );
      expect(
        personalRecordCrossError({'approvedHours': '4', 'approval': 'pending'}),
        isNotNull,
      );
      expect(
        personalRecordCrossError({
          'approvedHours': '4',
          'approval': 'approved',
          'observedOn': '2026-02-28',
        }),
        isNull,
      );
    },
  );

  testWidgets(
    'course pick copies name and credits then filters personal semester totals',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final courses = PersonalRecordRepository(PersonalRecordKind.course);
      await courses.load();
      await courses.save(
        PersonalRecord(
          id: PersonalRecord.newId(),
          values: {
            'title': '다른 학기 합성 과목',
            'term': '2025-1',
            'category': '교양',
            'credits': '2',
          },
        ),
      );
      final curriculum = PersonalRecordRepository(
        PersonalRecordKind.personalCurriculumCourse,
      );
      await curriculum.load();
      await curriculum.save(
        PersonalRecord(
          id: PersonalRecord.newId(),
          values: {
            'title': '수정할 합성 과목',
            'courseCode': 'CS101',
            'credits': '3',
            'category': '전공',
            'requiredCourse': '필수',
          },
        ),
      );
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('수강 관리').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('수강 과목 추가'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('record-field-title')), findsNothing);
      expect(find.byKey(const ValueKey('record-field-credits')), findsNothing);
      expect(find.byKey(const ValueKey('record-field-detail')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('record-select-course')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('수정할 합성 과목').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('record-field-course-year')),
        '2026',
      );
      await tester.enterText(
        find.byKey(const ValueKey('record-field-term')),
        '2학기',
      );
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(find.textContaining('개인 입력 합계 5.0학점'), findsOneWidget);
      await tester.tap(find.text('전체 학기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2학기').last);
      await tester.pumpAndSettle();
      expect(find.text('다른 학기 합성 과목'), findsNothing);
      expect(find.textContaining('개인 입력 합계 3.0학점'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'structured activity dialog stays usable in a narrow enlarged window',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const UniversityPathApp(startAuthenticated: true),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('활동'));
      await tester.tap(find.byTooltip('활동'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('활동 직접 기록'));
      await _chooseActivityAdd(tester);
      final title = find.byKey(const ValueKey('record-field-title'));
      await tester.ensureVisible(title);
      await tester.enterText(title, '합성 봉사');
      final end = find.byKey(const ValueKey('record-field-observedOn'));
      await tester.ensureVisible(end);
      await tester.enterText(end, '2026-10-03');
      expect(find.text('내 기록에 저장').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'course searchable pick saves bound identity and deletes after remount',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final curriculum = PersonalRecordRepository(
        PersonalRecordKind.personalCurriculumCourse,
      );
      await curriculum.load();
      await curriculum.save(
        PersonalRecord(
          id: PersonalRecord.newId(),
          values: {
            'title': '합성 과목',
            'courseCode': 'CS101',
            'credits': '3',
            'category': '전공',
            'requiredCourse': '필수',
          },
        ),
      );
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('수강 관리').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('수강 과목 추가'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('record-select-course')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('합성 과목').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('record-field-term')),
        '2학기',
      );
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('홈').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('수강 관리').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('합성 과목'), findsWidgets);
      await tester.ensureVisible(find.text('수정').first);
      await tester.tap(find.text('수정').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('record-field-title')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('record-field-section')),
        'A',
      );
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(find.textContaining('합성 과목'), findsWidgets);
      await tester.ensureVisible(find.text('삭제').first);
      await tester.tap(find.text('삭제').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('합성 과목'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final item in [
    ('활동', '활동 직접 기록', {'title': '합성 활동'}),
    ('자격', '자격 직접 등록', {'title': '합성 자격'}),
  ]) {
    testWidgets(
      '${item.$1} supports structured input, remount and confirmed delete',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          const UniversityPathApp(startAuthenticated: true),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(item.$1).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(item.$2));
        await tester.pumpAndSettle();
        if (item.$1 == '활동') {
          await tester.tap(find.text('봉사').last);
          await tester.pumpAndSettle();
        }
        for (final field in item.$3.entries) {
          final input = find.byKey(ValueKey('record-field-${field.key}'));
          await tester.ensureVisible(input);
          await tester.enterText(input, field.value);
        }
        await tester.tap(find.text('내 기록에 저장'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('홈').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(item.$1).first);
        await tester.pumpAndSettle();
        expect(find.textContaining(item.$3['title']!), findsOneWidget);
        await tester.ensureVisible(find.text('수정').first);
        await tester.tap(find.text('수정').first);
        await tester.pumpAndSettle();
        final name = find.byKey(const ValueKey('record-field-title'));
        await tester.ensureVisible(name);
        await tester.enterText(name, '수정된 합성 기록');
        await tester.tap(find.text('내 기록에 저장'));
        await tester.pumpAndSettle();
        expect(find.textContaining('수정된 합성 기록'), findsOneWidget);
        await tester.ensureVisible(find.text('삭제').first);
        await tester.tap(find.text('삭제').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('삭제').last);
        await tester.pumpAndSettle();
        expect(find.textContaining(item.$3['title']!), findsNothing);
        expect(find.textContaining('수정된 합성 기록'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unused experience page still supports structured input and confirmed delete',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ExperiencePage())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('경험 직접 기록'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('record-field-title')),
        '합성 경험',
      );
      await tester.enterText(
        find.byKey(const ValueKey('record-field-type')),
        '프로젝트',
      );
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(find.text('합성 경험'), findsOneWidget);
      await tester.tap(find.text('삭제').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      expect(find.text('합성 경험'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unused portfolio achievements still support structured input and confirmed delete',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: achievementRecordsPage())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('성과 직접 기록'));
      await tester.pumpAndSettle();
      for (final field in {
        'title': '합성 성과',
        'type': '프로젝트',
        'role': '설계',
        'result': '시연 완료',
      }.entries) {
        final input = find.byKey(ValueKey('record-field-${field.key}'));
        await tester.ensureVisible(input);
        await tester.enterText(input, field.value);
      }
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(find.text('합성 성과'), findsOneWidget);
      await tester.tap(find.text('삭제').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      expect(find.text('합성 성과'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
