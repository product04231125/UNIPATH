import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_page.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_drafts_page.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_workspace_repository.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

Future<void> seedRecords() async {
  final works = PersonalRecordRepository(PersonalRecordKind.portfolio);
  await works.load();
  for (final id in ['work-1', 'work-2']) {
    await works.save(
      PersonalRecord(
        id: id,
        values: {
          'title': '합성 성과 $id',
          'type': '프로젝트',
          'role': '합성 설계',
          'result': '합성 결과',
        },
      ),
    );
  }
  final experiences = PersonalRecordRepository(PersonalRecordKind.experience);
  await experiences.load();
  await experiences.save(
    PersonalRecord(
      id: 'experience-1',
      values: {'title': '합성 경험', 'role': '합성 역할', 'result': '합성 경험 결과'},
    ),
  );
}

Future<void> fill(WidgetTester tester, String key, String text) async {
  final field = find.byKey(ValueKey('portfolio-$key'));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

Future<void> selectSource(WidgetTester tester, String ref) async {
  final checkbox = find.byKey(ValueKey('portfolio-source-$ref'));
  await tester.ensureVisible(checkbox);
  await tester.pumpAndSettle();
  await tester.tap(checkbox);
  await tester.pumpAndSettle();
}

Widget portfolioPage() =>
    const MaterialApp(home: Scaffold(body: PortfolioPage(showMockData: false)));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('compositions and documents persist independently without mutating source records', () async {
    await seedRecords();
    final repo = PortfolioWorkspaceRepository();
    await repo.load();
    await repo.saveComposition(
      PortfolioComposition(
        id: 'composition',
        title: '합성 구성',
        audience: PortfolioAudience.publicReview,
        reviewed: true,
        sources: ['portfolio/work-2', 'portfolio/work-1'],
      ),
    );
    await repo.saveDocument(
      ApplicationDocument(
        id: 'document',
        title: '합성 문서',
        target: '합성 기업',
        role: '합성 직무',
        type: '자기소개서',
        body: '사용자 원문',
        sources: ['experience/experience-1', 'portfolio/work-1'],
      ),
    );
    final loaded = PortfolioWorkspaceRepository();
    await loaded.load();
    expect(loaded.compositions.single.sources, [
      'portfolio/work-2',
      'portfolio/work-1',
    ]);
    expect(loaded.compositions.single.audience, PortfolioAudience.publicReview);
    expect(loaded.documents.single.body, '사용자 원문');
    await loaded.deleteComposition('composition');
    expect(loaded.documents.single.id, 'document');
    await loaded.deleteDocument('document');
    final works = PersonalRecordRepository(PersonalRecordKind.portfolio);
    await works.load();
    expect(works.records.length, 2);
    expect(works.records.first.value('result'), '합성 결과');
  });

  test(
    'deleted sources remain explicit and unknown audiences default private',
    () async {
      await seedRecords();
      final repo = PortfolioWorkspaceRepository();
      await repo.load();
      await repo.saveComposition(
        PortfolioComposition(
          id: 'composition',
          title: '합성 구성',
          sources: ['portfolio/work-1'],
        ),
      );
      await repo.saveDocument(
        ApplicationDocument(
          id: 'document',
          title: '보존할 문서',
          target: '합성 기관',
          role: '합성 직무',
          type: '이력서',
          body: '직접 작성하여 보존할 본문',
          sources: ['portfolio/work-1'],
        ),
      );
      final works = PersonalRecordRepository(PersonalRecordKind.portfolio);
      await works.load();
      await works.delete('work-1');
      final loaded = PortfolioWorkspaceRepository();
      await loaded.load();
      expect(loaded.compositions.single.sources, ['portfolio/work-1']);
      expect(loaded.documents.single.sources, ['portfolio/work-1']);
      expect(loaded.documents.single.body, '직접 작성하여 보존할 본문');
      expect(
        loaded.compositionText(loaded.compositions.single),
        contains('원본 기록 삭제됨'),
      );
      await loaded.saveComposition(
        PortfolioComposition(
          id: 'composition',
          title: '수정',
          sources: ['portfolio/work-1'],
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      final root = jsonDecode(
        prefs.getString(PortfolioWorkspaceRepository.storageKey)!,
      ) as Map;
      root['compositions'][0]['audience'] = 'future_unknown';
      await prefs.setString(
        PortfolioWorkspaceRepository.storageKey,
        jsonEncode(root),
      );
      final safe = PortfolioWorkspaceRepository();
      await safe.load();
      expect(safe.compositions.single.audience, PortfolioAudience.private);
    },
  );

  test(
    'invalid references and unreviewed public drafts are not saved',
    () async {
      await seedRecords();
      final repo = PortfolioWorkspaceRepository();
      await repo.load();
      await expectLater(
        repo.saveComposition(
          PortfolioComposition(
            id: 'x',
            title: '합성',
            audience: PortfolioAudience.publicReview,
            sources: ['portfolio/work-1'],
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.saveComposition(
          PortfolioComposition(
            id: 'x',
            title: '합성',
            sources: ['experience/experience-1'],
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.saveComposition(
          PortfolioComposition(
            id: 'x',
            title: '합성',
            sources: ['portfolio/missing'],
          ),
        ),
        throwsArgumentError,
      );
      expect(repo.compositions, isEmpty);
    },
  );

  test('load and write failures retain original workspace bytes and in-memory data', () async {
    await seedRecords();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PortfolioWorkspaceRepository.storageKey,
      'invalid synthetic json',
    );
    final corrupt = PortfolioWorkspaceRepository();
    await expectLater(corrupt.load(), throwsFormatException);
    await expectLater(
      corrupt.saveComposition(
        PortfolioComposition(id: 'new', title: '새 구성', sources: []),
      ),
      throwsStateError,
    );
    expect(
      prefs.getString(PortfolioWorkspaceRepository.storageKey),
      'invalid synthetic json',
    );
    await prefs.remove(PortfolioWorkspaceRepository.storageKey);
    final repo = PortfolioWorkspaceRepository(writer: (_, _) async => false);
    await repo.load();
    await expectLater(
      repo.saveDocument(
        ApplicationDocument(
          id: 'new',
          title: '문서',
          target: '기관',
          role: '직무',
          type: '이력서',
          sources: [],
        ),
      ),
      throwsStateError,
    );
    expect(repo.documents, isEmpty);
    expect(prefs.getString(PortfolioWorkspaceRepository.storageKey), isNull);
  });

  testWidgets(
    'portfolio selects, reorders, reviews, edits and deletes compositions after remount',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await seedRecords();
      await tester.pumpWidget(portfolioPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('2. 포트폴리오 구성'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('포트폴리오 구성 추가'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('초안 저장'));
      await tester.pumpAndSettle();
      expect(find.text('구성 이름을 입력하세요.'), findsOneWidget);
      await fill(tester, 'title', '합성 포트폴리오');
      await selectSource(tester, 'portfolio/work-1');
      await selectSource(tester, 'portfolio/work-2');
      final up = find.byKey(const ValueKey('portfolio-up-portfolio/work-2'));
      await tester.ensureVisible(up);
      await tester.tap(up);
      await tester.pumpAndSettle();
      final audience = find.byKey(const ValueKey('portfolio-audience'));
      await tester.ensureVisible(audience);
      await tester.tap(audience);
      await tester.pumpAndSettle();
      await tester.tap(find.text('공개 검토용').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('초안 저장'));
      await tester.pumpAndSettle();
      expect(find.text('공개할 내용의 권한과 사실 관계를 직접 확인하세요.'), findsOneWidget);
      final review = find.byKey(const ValueKey('portfolio-review'));
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.tap(find.text('초안 저장'));
      await tester.pumpAndSettle();
      final loaded = PortfolioWorkspaceRepository();
      await loaded.load();
      expect(loaded.compositions.single.sources, [
        'portfolio/work-2',
        'portfolio/work-1',
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(portfolioPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('2. 포트폴리오 구성'));
      await tester.pumpAndSettle();
      expect(find.text('합성 포트폴리오'), findsOneWidget);
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      await fill(tester, 'title', '수정된 포트폴리오');
      await tester.ensureVisible(review);
      expect(tester.widget<CheckboxListTile>(review).value, isFalse);
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.tap(find.text('초안 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('미리보기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('게시되지 않음'), findsWidgets);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text('수정된 포트폴리오'), findsOneWidget);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      expect(find.text('수정된 포트폴리오'), findsNothing);
      await tester.tap(find.text('1. 성과 기록'));
      await tester.pumpAndSettle();
      expect(find.text('합성 성과 work-1'), findsOneWidget);
      expect(find.text('합성 성과 work-2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'application drafts import only confirmed facts, preserve edits, copy and delete independently',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await seedRecords();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(portfolioPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('3. 지원 문서'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('지원 문서 초안 추가'));
      await tester.pumpAndSettle();
      await fill(tester, 'title', '합성 지원 문서');
      await fill(tester, 'target', '합성 기업');
      await fill(tester, 'role', '합성 개발 직무');
      await fill(tester, 'body', '직접 작성한 원문');
      await selectSource(tester, 'experience/experience-1');
      await selectSource(tester, 'portfolio/work-1');
      final importButton = find.text('선택한 기록을 본문에 가져오기');
      await tester.ensureVisible(importButton);
      await tester.tap(importButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('portfolio-body')))
            .controller!
            .text,
        '직접 작성한 원문',
      );
      await tester.ensureVisible(importButton);
      await tester.tap(importButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('본문 끝에 추가'));
      await tester.pumpAndSettle();
      final body = tester
          .widget<TextFormField>(find.byKey(const ValueKey('portfolio-body')))
          .controller!
          .text;
      expect(body, startsWith('직접 작성한 원문'));
      expect(body, contains('합성 경험 결과'));
      expect(body, isNot(contains('work-2')));
      await tester.tap(find.text('초안 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2. 포트폴리오 구성'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3. 지원 문서'));
      await tester.pumpAndSettle();
      expect(find.text('합성 지원 문서'), findsOneWidget);
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      await fill(tester, 'body', '직접 고친 본문');
      await tester.tap(find.text('초안 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('미리보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('초안 텍스트 복사'));
      await tester.pumpAndSettle();
      expect(copied, contains('직접 고친 본문'));
      expect(copied, contains('미제출'));
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      expect(find.text('합성 지원 문서'), findsNothing);
      final sources = PersonalRecordRepository(PersonalRecordKind.experience);
      await sources.load();
      expect(sources.records.single.id, 'experience-1');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed draft save retains form and source selections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedRecords();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortfolioDraftsPage(
            isDocument: false,
            repository: PortfolioWorkspaceRepository(
              writer: (_, _) async => false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('포트폴리오 구성 추가'));
    await tester.pumpAndSettle();
    await fill(tester, 'title', '보존할 합성 초안');
    await selectSource(tester, 'portfolio/work-1');
    await tester.tap(find.text('초안 저장'));
    await tester.pumpAndSettle();
    expect(find.textContaining('입력은 유지됩니다.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('portfolio-title')))
          .controller!
          .text,
      '보존할 합성 초안',
    );
    expect(find.text('1. 성과 · 합성 성과 work-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final stage in ['2. 포트폴리오 구성', '3. 지원 문서']) {
    testWidgets('$stage remains usable at 480x520 with 200 percent text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(480, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await seedRecords();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: PortfolioPage(showMockData: false)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(stage));
      await tester.pumpAndSettle();
      final add = find.text(
        stage.startsWith('2') ? '포트폴리오 구성 추가' : '지원 문서 초안 추가',
      );
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await selectSource(tester, 'portfolio/work-1');
      expect(find.text('초안 저장').hitTestable(), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
