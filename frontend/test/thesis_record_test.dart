import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/records/personal_record_fields.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_page.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_workspace_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'thesis fields remain optional and preserve original grade and provenance',
    () async {
      final fields = personalRecordFields(PersonalRecordKind.portfolio);
      for (final key in [
        'thesisType',
        'thesisStatus',
        'thesisGrade',
        'thesisApprovedOn',
      ]) {
        expect(fields.singleWhere((f) => f.key == key).validate(''), isNull);
      }
      final date = fields.singleWhere((f) => f.key == 'thesisApprovedOn');
      expect(date.validate('2026-02-30'), isNotNull);
      expect(date.validate('2026-02-28'), isNull);
      final repo = PersonalRecordRepository(PersonalRecordKind.portfolio);
      await repo.load();
      await repo.save(
        PersonalRecord(
          id: 'legacy',
          values: {
            'title': '기존 합성 성과',
            'type': '프로젝트',
            'role': '설계',
            'result': '시연',
          },
        ),
      );
      final reload = PersonalRecordRepository(PersonalRecordKind.portfolio);
      await reload.load();
      expect(reload.records.single.value('thesisGrade'), isEmpty);
      final source = PortfolioSource(
        PersonalRecordKind.portfolio,
        PersonalRecord(
          id: 'thesis',
          values: {
            'title': '합성 논문',
            'thesisType': '졸업논문',
            'thesisStatus': '제출 기록',
            'thesisGrade': 'Pass (원문)',
            'thesisApprovedOn': '2026-02-28',
          },
        ),
      );
      expect(source.text, contains('원 성적 표기: Pass (원문)'));
      expect(source.text, contains('학교 승인 처리 아님: 2026-02-28'));
    },
  );

  for (final size in [const Size(1440, 900), const Size(480, 520)]) {
    testWidgets(
      'thesis CRUD retains fields and rejects invalid dates at $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Widget page() => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(size.width == 480 ? 2 : 1),
            ),
            child: child!,
          ),
          home: const Scaffold(body: PortfolioPage(showMockData: false)),
        );
        Future<void> fill(String key, String value) async {
          final field = find.byKey(ValueKey('record-field-$key'));
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          await tester.enterText(field, value);
        }

        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('성과 직접 기록'));
        await tester.tap(find.text('성과 직접 기록'));
        await tester.pumpAndSettle();
        for (final entry in {
          'title': '합성 캡스톤',
          'type': '논문',
          'thesisType': '캡스톤 발표',
          'thesisStatus': '학교 화면에서 결과 확인',
          'thesisGrade': 'P / 통과 (원문)',
          'thesisApprovedOn': '2026-02-30',
          'role': '실험 설계',
          'result': '발표 완료',
        }.entries) {
          await fill(entry.key, entry.value);
        }
        await tester.tap(find.text('내 기록에 저장'));
        await tester.pumpAndSettle();
        final date = find.byKey(
          const ValueKey('record-field-thesisApprovedOn'),
        );
        expect(
          tester.widget<TextFormField>(date).controller!.text,
          '2026-02-30',
        );
        expect(find.text('실제 날짜를 YYYY-MM-DD 형식으로 입력하세요.'), findsOneWidget);
        await fill('thesisApprovedOn', '2026-02-28');
        await tester.tap(find.text('내 기록에 저장'));
        await tester.pumpAndSettle();
        final repo = PersonalRecordRepository(PersonalRecordKind.portfolio);
        await repo.load();
        final id = repo.records.single.id;
        expect(repo.records.single.value('thesisGrade'), 'P / 통과 (원문)');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('수정'));
        await tester.tap(find.text('수정'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(date).controller!.text,
          '2026-02-28',
        );
        await fill('thesisStatus', '직접 재확인');
        await tester.tap(find.text('내 기록에 저장'));
        await tester.pumpAndSettle();
        await repo.load();
        expect(repo.records.single.id, id);
        expect(repo.records.single.value('thesisStatus'), '직접 재확인');
        await tester.ensureVisible(find.text('삭제'));
        await tester.tap(find.text('삭제'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('취소'));
        await tester.pumpAndSettle();
        await repo.load();
        expect(repo.records, hasLength(1));
        await tester.ensureVisible(find.text('삭제'));
        await tester.tap(find.text('삭제'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('삭제').last);
        await tester.pumpAndSettle();
        final empty = PersonalRecordRepository(PersonalRecordKind.portfolio);
        await empty.load();
        expect(empty.records, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
