import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:university_path_frontend/features/api/student_academic_api.dart';
import 'package:flutter/services.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/features/graduation/student_academic_page.dart';
import 'package:university_path_frontend/features/graduation/student_academic_record_search.dart';
import 'package:university_path_frontend/features/records/portfolio/material_repository.dart';

import 'student_academic_integration_test.dart' as fixture;

class SearchGateway extends fixture.AcademicTransport {
  final reads = <String>[];
  bool foreign = false, repeatCursor = false;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (Uri.parse(path).path == 'me/credential-records') {
      reads.add(path);
      final second = Uri.parse(path).queryParameters['cursor'] != null;
      return {
        'items': [
          {
            'id': second ? 'second' : 'first',
            'owner_id': foreign ? 'other' : 'owner',
            'title': second ? '다른 자격' : '자격 기록',
            'version': 1,
            'provider': '합성 기관',
            'detail': '어학 인증 검토',
            'earned_on': '2026-11-01',
          },
        ],
        'next_cursor': !second || repeatCursor ? 'next' : null,
      };
    }
    return super.request(method, path, body);
  }
}

class SearchMemory extends AcademicRecordSearchRepository {
  SearchMemory(super.api);
  bool failMaterial = false;
  final reads = <String>[];
  @override
  Future<List<AcademicRecordSearchHit>> load(String kind) async {
    reads.add(kind);
    if (kind == 'material' && failMaterial) throw StateError('unavailable');
    return [
      AcademicRecordSearchHit(kind, kind, '$kind 기록', {
        '메모': kind == 'credential' || kind == 'material' ? '어학 증빙' : '일반 메모',
        '날짜': '2026-11-01',
      }),
    ];
  }
}

void main() {
  setUpAll(() async {
    if (!fixture.capture) return;
    await (FontLoader('Pretendard')..addFont(
          rootBundle.load('assets/fonts/pretendard/Pretendard-Regular.otf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'search reads all pages and metadata without creating references',
    () async {
      final gateway = SearchGateway();
      final repo = AcademicRecordSearchRepository(
        StudentAcademicApi(gateway, 'owner'),
      );
      final rows = await repo.load('credential');
      expect(rows, hasLength(2));
      expect(rows.first.matches('어학 2026-11'), isTrue);
      expect(rows.first.matches('합성 기관'), isTrue);
      expect(gateway.reads, hasLength(2));
      expect(gateway.writes, isEmpty);
      gateway.foreign = true;
      await expectLater(repo.load('credential'), throwsFormatException);
      gateway.foreign = false;
      gateway.repeatCursor = true;
      await expectLater(repo.load('credential'), throwsFormatException);
    },
  );
  test('materials use the current account store and search description and filename', () async {
    final db = await databaseFactoryMemory.openDatabase(
      'academic-record-search',
    );
    addTearDown(db.close);
    final current = MaterialRepository(
      open: () async => db,
      owner: const LocalDataOwner('owner'),
    );
    final other = MaterialRepository(
      open: () async => db,
      owner: const LocalDataOwner('other'),
    );
    for (final pair in [(current, '내 자료'), (other, '다른 계정 자료')]) {
      await pair.$1.save(
        PersonalMaterial(
          id: 'same-id',
          title: pair.$2,
          type: MaterialKinds.other,
          description: '어학 인증 확인',
          fileName: 'language-proof.pdf',
        ),
      );
    }
    final repo = AcademicRecordSearchRepository(
      StudentAcademicApi(SearchGateway(), 'owner'),
      materials: current,
    );
    final rows = await repo.load('material');
    expect(rows.single.title, '내 자료');
    expect(rows.single.matches('어학 proof'), isTrue);
  });
  for (final certification in [false, true]) {
    testWidgets(
      '${certification ? 'certification' : 'checklist'} searches all kinds inline without changing O/X',
      (tester) async {
        final gateway = fixture.AcademicTransport();
        final api = StudentAcademicApi(gateway, 'owner');
        final repo = SearchMemory(api);
        final key = await fixture.mount(
          tester,
          gateway,
          child: StudentAcademicPage(
            api: api,
            profile: fixture.profile,
            recordSearch: repo,
          ),
        );
        if (certification) {
          await tester.tap(find.widgetWithText(ChoiceChip, '인증 요건'));
          await tester.pumpAndSettle();
        }
        expect(find.text('기록 연결'), findsNothing);
        await tester.tap(find.text('내 기록 찾기'));
        await tester.pumpAndSettle();
        expect(repo.reads.toSet(), academicSearchKinds.keys.toSet());
        expect(find.byType(AlertDialog), findsNothing);
        await tester.enterText(find.byType(TextField), '어학 2026');
        await tester.pumpAndSettle();
        expect(find.text('2개 기록'), findsOneWidget);
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, '자격'));
        await tester.tap(find.widgetWithText(ChoiceChip, '자격'));
        await tester.pumpAndSettle();
        expect(find.text('1개 기록'), findsOneWidget);
        await tester.ensureVisible(find.text('credential 기록'));
        await tester.tap(find.text('credential 기록'));
        await tester.pumpAndSettle();
        expect(find.text('메모: 어학 증빙'), findsOneWidget);
        expect(gateway.writes, isEmpty);
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(tester.takeException(), isNull);
        await fixture.screenshot(
          tester,
          key,
          certification
              ? 'certification-record-search'
              : 'checklist-record-search',
        );
      },
    );
  }
  testWidgets(
    'partial source failure preserves query and distinguishes failed search from empty',
    (tester) async {
      final repo = SearchMemory(
        StudentAcademicApi(fixture.AcademicTransport(), 'owner'),
      )..failMaterial = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StudentAcademicRecordSearch(repository: repo),
            ),
          ),
        ),
      );
      await tester.tap(find.text('내 기록 찾기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '없는 기록');
      await tester.pumpAndSettle();
      expect(find.textContaining('자료 기록을 불러오지 못했습니다.'), findsOneWidget);
      expect(find.text('검색 조건에 맞는 기록이 없습니다.'), findsNothing);
      repo.failMaterial = false;
      await tester.tap(find.text('기록 다시 불러오기'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '없는 기록',
      );
      expect(find.text('검색 조건에 맞는 기록이 없습니다.'), findsOneWidget);
    },
  );
}
