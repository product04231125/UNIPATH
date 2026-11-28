import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/records/portfolio/material_repository.dart';

/// A 1×1 white PNG standing in for a rendered page.
final pageImageBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
  ),
);

/// In-memory 내 자료 file store for widget tests (the device store needs a
/// platform directory the test host does not have).
class MemoryMaterials implements MaterialRepository {
  final records = <String, PersonalMaterial>{};
  bool fail = false;
  @override
  bool get inAccount => false;
  @override
  Future<List<PersonalMaterial>> load() async {
    if (fail) throw StateError('읽기 실패');
    return records.values.toList();
  }

  @override
  Future<void> save(PersonalMaterial material) async {
    if (fail) throw StateError('쓰기 실패');
    if (!material.hasPdf && material.description.trim().isEmpty) {
      throw StateError('설명 또는 PDF를 입력하세요.');
    }
    // Like the real stores: a missing PDF with its file name keeps the saved one.
    final keep = material.pdf == null && material.fileName.isNotEmpty
        ? records[material.id]?.pdf
        : null;
    records[material.id] = keep == null
        ? material
        : PersonalMaterial(
            id: material.id,
            title: material.title,
            type: material.type,
            description: material.description,
            fileName: material.fileName,
            pdf: keep,
          );
  }

  @override
  Future<void> delete(PersonalMaterial material) => deleteId(material.id);

  Future<void> deleteId(String id) async {
    records.remove(id);
  }

  @override
  Future<Uint8List?> pdf(PersonalMaterial material) async =>
      material.pdf ?? records[material.id]?.pdf;

  /// Pretends a server renders pages (an account store).
  bool preview = false;
  final pageRequests = <int>[];

  @override
  bool get canPreview => preview;

  @override
  Future<MaterialPages> pages(PersonalMaterial material) async =>
      const MaterialPages(
        count: 2,
        sizes: [(width: 595, height: 842), (width: 595, height: 842)],
      );

  @override
  Future<Uint8List> pageImage(PersonalMaterial material, int number) async {
    pageRequests.add(number);
    return pageImageBytes;
  }
}

/// `+` on 내 자료 asks what to record; picks 자료 (a file) when asked.
Future<void> openMaterialForm(WidgetTester tester) async {
  await tester.tap(find.byTooltip('자료 추가'));
  await tester.pumpAndSettle();
  final file = find.byKey(const ValueKey('material-add-file'));
  if (file.evaluate().isNotEmpty) {
    await tester.ensureVisible(file);
    await tester.pumpAndSettle();
    await tester.tap(file);
    await tester.pumpAndSettle();
  }
}
