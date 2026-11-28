import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:sembast/sembast_io.dart' as disk;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/material_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/materials_page.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/shared/widgets/surface_card.dart';

import 'support/memory_materials.dart';
import 'support/record_actions.dart';

import 'package:university_path_frontend/shared/widgets/record_tile.dart';

void main() {
  // 내 자료 also lists 활동·자격증 records, kept in (mock) local storage here.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'material repositories retain their original owner across account changes',
    () async {
      final db = await databaseFactoryMemory.openDatabase(
        'materials-owner-isolation',
      );
      addTearDown(db.close);
      final first = DeviceMaterialRepository(
        open: () async => db,
        owner: const LocalDataOwner('first'),
      );
      final second = DeviceMaterialRepository(
        open: () async => db,
        owner: const LocalDataOwner('second'),
      );
      final anonymous = DeviceMaterialRepository(
        open: () async => db,
        owner: const LocalDataOwner(null),
      );
      await first.save(
        PersonalMaterial(
          id: 'same',
          title: '첫 계정',
          type: '',
          description: '개인 자료',
        ),
      );
      expect(await second.load(), isEmpty);
      expect(await anonymous.load(), isEmpty);
      await second.save(
        PersonalMaterial(
          id: 'same',
          title: '둘째 계정',
          type: '',
          description: '다른 자료',
        ),
      );
      await second.deleteId('same');
      expect((await first.load()).single.title, '첫 계정');
    },
  );
  final pdf = Uint8List.fromList('%PDF-1.4\nsynthetic test\n%%EOF'.codeUnits);
  test('PDF and metadata survive another repository, failed validation and deletion', () async {
    final db = await databaseFactoryMemory.openDatabase('materials-repository');
    addTearDown(db.close);
    final repo = DeviceMaterialRepository(open: () async => db);
    await repo.save(
      PersonalMaterial(
        id: 'pdf',
        title: '자료',
        type: '포트폴리오',
        description: '핵심 성과',
        fileName: 'test.pdf',
        pdf: pdf,
      ),
    );
    final restored = await DeviceMaterialRepository(open: () async => db)
        .load();
    expect(restored.single.pdf, pdf);
    expect(restored.single.description, '핵심 성과');
    await expectLater(
      repo.save(
        PersonalMaterial(
          id: 'pdf',
          title: '잘못된 파일',
          type: '',
          description: '',
          fileName: 'test.pdf',
          pdf: Uint8List(6),
        ),
      ),
      throwsStateError,
    );
    expect((await repo.load()).single.title, '자료');
    expect(
      () => MaterialRepository.validatePdf(
        'large.pdf',
        Uint8List(MaterialRepository.maxPdfBytes + 1),
      ),
      throwsStateError,
    );
    await repo.save(
      PersonalMaterial(
        id: 'note',
        title: '자료 설명',
        type: '이력서',
        description: '첨부 없이 보관',
      ),
    );
    await repo.deleteId('pdf');
    expect((await repo.load()).single.id, 'note');
  });

  test(
    'PDF bytes persist after closing and reopening the native database',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'unipath-material-test-',
      );
      final path = '${directory.path}${Platform.pathSeparator}materials.db';
      var db = await disk.databaseFactoryIo.openDatabase(path);
      try {
        await DeviceMaterialRepository(open: () async => db).save(
          PersonalMaterial(
            id: 'file',
            title: '합성 PDF',
            type: 'PDF',
            description: '재시작 검증',
            fileName: 'synthetic.pdf',
            pdf: pdf,
          ),
        );
        await db.close();
        db = await disk.databaseFactoryIo.openDatabase(path);
        final rows = await DeviceMaterialRepository(open: () async => db)
            .load();
        expect(rows.single.pdf, pdf);
        expect(rows.single.fileName, 'synthetic.pdf');
      } finally {
        await db.close();
        final parent = Directory.systemTemp.absolute.path;
        if (!directory.absolute.path.startsWith(parent) ||
            !directory.path.contains('unipath-material-test-')) {
          throw StateError('Unexpected test path');
        }
        await directory.delete(recursive: true);
      }
    },
  );

  // Narrow 480 viewport checks stay out of scope (AGENTS 2026-10-25).
  for (final size in [const Size(1440, 900)]) {
    testWidgets(
      'material note PDF cancel failure edit export and scale at $size',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.binding.setSurfaceSize(size);
        final semantics = tester.ensureSemantics();

        final repo = MemoryMaterials();
        XFile? selected;
        PersonalMaterial? exported;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(size.width == 480 ? 2 : 1),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: MaterialsPage(
                repository: repo,
                pickPdf: () async => selected,
                exportPdf: (value, _) async => exported = value,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder finder) async {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        Future<void> fill(String key, String value) async {
          final field = find.byKey(ValueKey('material-$key'));
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          await tester.enterText(field, value);
        }

        Future<void> selectKind(String kind) async {
          await tap(find.byKey(const ValueKey('material-type')));
          final option = find.text(kind).last;
          await tester.ensureVisible(option);
          await tester.pumpAndSettle();
          await tester.tap(option);
          await tester.pumpAndSettle();
        }

        // Like 활동·자격증: the page lists, `+` opens the input dialog.
        expect(find.byKey(const ValueKey('material-title')), findsNothing);
        await openMaterialForm(tester);
        expect(find.text('자료 추가'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('material-title')))
              .label,
          contains('자료 이름 (필수)'),
        );
        expect(find.text('자료 종류 (필수)'), findsOneWidget);
        semantics.dispose();
        final save = find.widgetWithText(FilledButton, '자료 등록');
        await fill('title', '내 이력서');
        await selectKind('이력서');
        await fill('description', '내 프로젝트와 성과가 들어 있는 자료');
        await tap(find.text('PDF 선택')); // Cancel preserves note.
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('material-title')),
              )
              .controller!
              .text,
          '내 이력서',
        );
        selected = XFile.fromData(
          Uint8List.fromList('invalid'.codeUnits),
          name: 'invalid.pdf',
          path: 'invalid.pdf',
        );
        await tap(find.text('PDF 선택'));
        expect(find.text('PDF 파일을 선택하세요.'), findsOneWidget);
        selected = XFile.fromData(pdf, name: 'resume.pdf', path: 'resume.pdf');
        await tap(find.text('PDF 선택'));
        await tap(save);
        expect(find.byKey(const ValueKey('material-title')), findsNothing);
        expect((await repo.load()).single.pdf, pdf);
        expect((await repo.load()).single.type, '이력서');
        expect(find.text('내 이력서'), findsOneWidget);
        expect(find.text('이력서'), findsWidgets);
        expect(find.text('자료 1'), findsOneWidget);
        await tapRecordAction(tester, '수정');
        expect(find.text('자료 수정'), findsOneWidget);
        await fill('description', '수정된 설명');
        await tap(find.widgetWithText(FilledButton, '저장'));
        expect((await repo.load()).single.description, '수정된 설명');
        await tapRecordAction(tester, 'PDF 내보내기');
        expect(exported!.pdf, pdf);
        await tapRecordAction(tester, '삭제');
        await tester.tap(find.widgetWithText(FilledButton, '삭제').last);
        await tester.pumpAndSettle();
        expect(await repo.load(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('storage failure preserves selected PDF and input for retry', (
    tester,
  ) async {
    final repo = MemoryMaterials()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MaterialsPage(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('다시 읽기'), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('다시 읽기'));
    await tester.pumpAndSettle();
    await openMaterialForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey('material-title')),
      '보존할 입력',
    );
    await tester.tap(find.byKey(const ValueKey('material-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('증빙·기타').last);
    await tester.pumpAndSettle();
    repo.fail = true;
    final save = find.widgetWithText(FilledButton, '자료 등록');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    // Missing description is rejected without clearing the title.
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('material-title')))
          .controller!
          .text,
      '보존할 입력',
    );
    await tester.enterText(
      find.byKey(const ValueKey('material-description')),
      '보존할 설명',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('material-description')),
          )
          .controller!
          .text,
      '보존할 설명',
    );
    repo.fail = false;
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await repo.load()).single.title, '보존할 입력');
    expect(find.byKey(const ValueKey('material-title')), findsNothing);
    expect(find.text('보존할 입력'), findsOneWidget);
  });

  testWidgets('legacy free-text type stays listed until a kind is saved', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = MemoryMaterials();
    await repo.save(
      PersonalMaterial(
        id: 'legacy',
        title: '옛 자료',
        type: '자유 입력 종류',
        description: '기존 설명',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MaterialsPage(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('옛 자료'), findsOneWidget);
    expect(find.text('자유 입력 종류'), findsOneWidget);
    await tapRecordAction(tester, '수정');
    final save = find.widgetWithText(FilledButton, '저장');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('자료 종류를 선택하세요.'), findsOneWidget);
    // The saved tile keeps the old type until a valid kind is saved.
    expect(find.text('자유 입력 종류'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('material-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('material-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('증빙·기타').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await repo.load()).single.type, '증빙·기타');
    expect(
      find.descendant(
        of: find.byType(RecordTile),
        matching: find.text('증빙·기타'),
      ),
      findsOneWidget,
    );
    expect(find.text('자유 입력 종류'), findsNothing);
  });

  testWidgets(
    'a new material requires its own kind after saving or cancelling',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = MemoryMaterials();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MaterialsPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> open() => openMaterialForm(tester);

      Future<void> selectKind(String kind) async {
        await tester.tap(find.byKey(const ValueKey('material-type')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kind).last);
        await tester.pumpAndSettle();
      }

      Future<void> fillAndSave(String title) async {
        await tester.enterText(
          find.byKey(const ValueKey('material-title')),
          title,
        );
        await tester.enterText(
          find.byKey(const ValueKey('material-description')),
          '보관할 설명',
        );
        final save = find.widgetWithText(FilledButton, '자료 등록');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
      }

      Future<void> cancel() async {
        final button = find.widgetWithText(TextButton, '취소');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('input-discard-delete')));
        await tester.pumpAndSettle();
      }

      await open();
      await selectKind('이력서');
      await fillAndSave('첫 자료');
      expect(repo.records.length, 1);
      // The next 자료 추가 starts empty: the saved kind is not carried over.
      await open();
      await fillAndSave('두 번째 자료');
      expect(find.text('자료 종류를 선택하세요.'), findsOneWidget);
      expect(repo.records.length, 1);
      await cancel();
      expect(find.byKey(const ValueKey('material-title')), findsNothing);

      // A kind picked and then cancelled is gone too.
      await open();
      await selectKind('포트폴리오');
      await cancel();
      await open();
      await fillAndSave('취소 후 자료');
      expect(find.text('자료 종류를 선택하세요.'), findsOneWidget);
      expect(repo.records.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('내 자료 lists 활동·자격증 records with files and filters them by kind', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = MemoryMaterials();
    for (final entry in [
      ('a', '이력서', '첫 자료', '알파 설명'),
      ('b', '포트폴리오', '둘째 자료', '베타 설명'),
    ]) {
      await repo.save(
        PersonalMaterial(
          id: entry.$1,
          type: entry.$2,
          title: entry.$3,
          description: entry.$4,
        ),
      );
    }
    for (final (kind, id, title) in [
      (PersonalRecordKind.activity, 'v', '합성 봉사'),
      (PersonalRecordKind.experience, 'p', '합성 프로젝트'),
      (PersonalRecordKind.credential, 'c', '합성 자격'),
    ]) {
      final records = PersonalRecordRepository(kind);
      await records.load();
      await records.save(PersonalRecord(id: id, values: {'title': title}));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MaterialsPage(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    // Every record and file is a tile in one grid, each with its own ⋮ menu.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('material-catalog')),
        matching: find.byType(RecordTile),
      ),
      findsNWidgets(5),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('material-row-a')),
        matching: find.byIcon(Icons.more_vert),
      ),
      findsOneWidget,
    );
    for (final label in ['전체 5', '활동 2', '자격증 1', '자료 2']) {
      expect(find.text(label), findsOneWidget);
    }

    Future<void> filter(String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await filter('자격증 1');
    expect(find.text('합성 자격'), findsOneWidget);
    expect(find.text('합성 봉사'), findsNothing);
    expect(find.text('첫 자료'), findsNothing);
    // With one kind shown, `+` opens that kind's form without asking.
    await tester.tap(find.byTooltip('자료 추가'));
    await tester.pumpAndSettle();
    expect(find.text('무엇을 기록할까요?'), findsNothing);
    expect(find.text('자격증 추가'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    await filter('활동 2');
    expect(find.text('합성 봉사'), findsOneWidget);
    expect(find.text('합성 프로젝트'), findsOneWidget);
    expect(find.text('합성 자격'), findsNothing);
    // Only the activity kinds are offered.
    await tester.tap(find.byTooltip('자료 추가'));
    await tester.pumpAndSettle();
    expect(find.text('무엇을 기록할까요?'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-add-volunteer')), findsOne);
    expect(find.byKey(const ValueKey('material-add-credential')), findsNothing);
    expect(find.byKey(const ValueKey('material-add-file')), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await filter('자료 2');
    expect(find.text('첫 자료'), findsOneWidget);
    expect(find.text('둘째 자료'), findsOneWidget);
    expect(find.text('합성 봉사'), findsNothing);
    await tester.tap(find.byTooltip('자료 추가'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('material-title')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await filter('전체 5');
    expect(find.byType(RecordTile), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('내 자료 is one card with kind chips and adds with + like 활동', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = MemoryMaterials();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MaterialsPage(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('material-filters')), findsOneWidget);
    expect(find.text('전체 0'), findsOneWidget);
    expect(find.text('아직 기록한 자료가 없습니다'), findsOneWidget);
    // The list card and the collapsed 자료 준비 guide; no form card beside them.
    expect(find.byType(SurfaceCard), findsNWidgets(2));
    expect(find.text('자료 준비'), findsOneWidget);
    expect(find.byKey(const ValueKey('material-title')), findsNothing);
    expect(find.byTooltip('자료 추가'), findsOneWidget);
    // `…` holds 임시저장 불러오기 (no 다시 읽기 for device stores).
    expect(find.byTooltip('더보기'), findsOneWidget);

    // The empty list's button asks what to record, like `+`.
    await tester.tap(find.text('첫 자료 추가'));
    await tester.pumpAndSettle();
    expect(find.text('무엇을 기록할까요?'), findsOneWidget);
    for (final label in ['봉사', '프로젝트', '인턴', '동아리', '그 밖의 활동', '자격증']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.byKey(const ValueKey('material-add-file')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('input-dialog-surface')), findsOneWidget);
    expect(find.text('자료 추가'), findsOneWidget);
    // Nothing typed yet: a click outside closes it without asking.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('input-dialog-surface')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved PDF opens in the viewer from its tile and the form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = MemoryMaterials()..preview = true;
    repo.records['m'] = PersonalMaterial(
      id: 'm',
      title: '합성 포트폴리오',
      type: MaterialKinds.portfolio,
      description: '',
      fileName: 'portfolio.pdf',
      pdf: Uint8List.fromList(utf8.encode('%PDF-1.4 synthetic')),
    );
    PersonalMaterial? exported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MaterialsPage(
            repository: repo,
            exportPdf: (value, _) async => exported = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('material-view-m')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('material-preview')), findsOneWidget);
    expect(find.text('portfolio.pdf · 2쪽'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(repo.pageRequests, contains(1));
    await tester.tap(find.byTooltip('확대'));
    await tester.pumpAndSettle();
    expect(find.text('125%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('material-preview-zoom')));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('material-preview-export')));
    await tester.pumpAndSettle();
    expect(exported?.id, 'm');
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('material-preview')), findsNothing);

    // Editing the material offers the saved PDF too.
    await tester.tap(find.byKey(const ValueKey('material-row-m')));
    await tester.pumpAndSettle();
    final formView = find.byKey(const ValueKey('material-form-view'));
    await tester.ensureVisible(formView);
    await tester.tap(formView);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('material-preview')), findsOneWidget);
  });

  testWidgets('a device store has no in-app viewer, only export', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = MemoryMaterials();
    repo.records['m'] = PersonalMaterial(
      id: 'm',
      title: '합성 포트폴리오',
      type: MaterialKinds.portfolio,
      description: '',
      fileName: 'portfolio.pdf',
      pdf: Uint8List.fromList(utf8.encode('%PDF-1.4 synthetic')),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MaterialsPage(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('material-view-m')), findsNothing);
  });
}
