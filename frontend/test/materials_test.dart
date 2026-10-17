import 'dart:typed_data';
import 'dart:io';

import 'package:sembast/sembast_io.dart' as disk;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:university_path_frontend/features/records/portfolio/material_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/materials_page.dart';

class MemoryMaterials extends MaterialRepository {
  final records = <String, PersonalMaterial>{};
  bool fail = false;
  @override
  Future<List<PersonalMaterial>> load() async {
    if (fail) throw StateError('읽기 실패');
    return records.values.toList();
  }

  @override
  Future<void> save(PersonalMaterial material) async {
    if (fail) throw StateError('쓰기 실패');
    if (material.pdf == null && material.description.trim().isEmpty) {
      throw StateError('설명 또는 PDF를 입력하세요.');
    }
    records[material.id] = material;
  }

  @override
  Future<void> delete(String id) async {
    records.remove(id);
  }
}

void main() {
  final pdf = Uint8List.fromList('%PDF-1.4\nsynthetic test\n%%EOF'.codeUnits);
  test('PDF and metadata survive another repository, failed validation and deletion', () async {
    final db = await databaseFactoryMemory.openDatabase('materials-repository');
    addTearDown(db.close);
    final repo = MaterialRepository(open: () async => db);
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
    final restored = await MaterialRepository(open: () async => db).load();
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
    await repo.delete('pdf');
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
        await MaterialRepository(open: () async => db).save(
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
        final rows = await MaterialRepository(open: () async => db).load();
        expect(rows.single.pdf, pdf);
        expect(rows.single.fileName, 'synthetic.pdf');
      } finally {
        await db.close();
        final parent = Directory.systemTemp.absolute.path;
        if (!directory.absolute.path.startsWith(parent) ||
            !directory.path.contains('unipath-material-test-'))
          throw StateError('Unexpected test path');
        await directory.delete(recursive: true);
      }
    },
  );

  for (final size in [const Size(1440, 900), const Size(480, 520)]) {
    testWidgets(
      'material note PDF cancel failure edit export and scale at $size',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.binding.setSurfaceSize(size);
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
                exportPdf: (value) async => exported = value,
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

        final save = find.widgetWithText(FilledButton, '자료 등록');
        await fill('title', '내 이력서');
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
        expect((await repo.load()).single.pdf, pdf);
        await tap(find.text('수정'));
        await fill('description', '수정된 설명');
        await tap(save);
        expect((await repo.load()).single.description, '수정된 설명');
        await tap(find.text('PDF 내보내기'));
        expect(exported!.pdf, pdf);
        await tap(find.text('삭제'));
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
    await tester.enterText(
      find.byKey(const ValueKey('material-title')),
      '보존할 입력',
    );
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
  });
}
