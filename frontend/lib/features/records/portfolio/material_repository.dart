import 'package:sembast/blob.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../personal_record_repository.dart';
import '../../auth/local_data_owner.dart';
import 'material_database.dart';

class PersonalMaterial {
  PersonalMaterial({
    required this.id,
    required this.title,
    required this.type,
    required this.description,
    this.fileName = '',
    Uint8List? pdf,
  }) : pdf = pdf == null ? null : Uint8List.fromList(pdf);
  final String id, title, type, description, fileName;
  final Uint8List? pdf;
  Map<String, Object?> toMap() => {
    'title': title,
    'type': type,
    'description': description,
    'fileName': fileName,
    if (pdf != null) 'pdf': Blob(pdf!),
  };
  factory PersonalMaterial.fromMap(String id, Map<String, Object?> map) =>
      PersonalMaterial(
        id: id,
        title: map['title'] as String,
        type: map['type'] as String,
        description: map['description'] as String,
        fileName: map['fileName'] as String,
        pdf: (map['pdf'] as Blob?)?.bytes,
      );
}

/// Private, device-local material store. No upload/indexing or AI request.
class MaterialRepository {
  MaterialRepository({Future<Database> Function()? open, LocalDataOwner? owner})
    : _open = open ?? openMaterialDatabase,
      _owner = owner ?? LocalDataOwner.current();
  final Future<Database> Function() _open;
  final LocalDataOwner _owner;
  late final _store = stringMapStoreFactory.store(_owner.key('materials'));
  static const maxPdfBytes = 10 * 1024 * 1024;
  static const maxTotalBytes = 50 * 1024 * 1024;
  Future<List<PersonalMaterial>> load() async {
    final rows = await _store.find(await _open());
    return [
      for (final row in rows) PersonalMaterial.fromMap(row.key, row.value),
    ];
  }

  static void validatePdf(String name, Uint8List bytes) {
    if (bytes.length > maxPdfBytes) throw StateError('PDF는 10MB 이하로 선택하세요.');
    if (!name.toLowerCase().endsWith('.pdf') ||
        bytes.length < 5 ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw StateError('PDF 파일을 선택하세요.');
    }
  }

  Future<void> save(PersonalMaterial material) async {
    if (material.title.trim().isEmpty ||
        (material.pdf == null && material.description.trim().isEmpty)) {
      throw StateError('자료 이름과 내용 설명 또는 PDF를 입력하세요.');
    }
    if (material.pdf != null) validatePdf(material.fileName, material.pdf!);
    final db = await _open();
    await db.transaction((txn) async {
      final rows = await _store.find(txn);
      final total = rows
          .where((row) => row.key != material.id)
          .fold<int>(
            0,
            (sum, row) =>
                sum + ((row.value['pdf'] as Blob?)?.bytes.length ?? 0),
          );
      if (total + (material.pdf?.length ?? 0) > maxTotalBytes) {
        throw StateError('기기 PDF 보관 한도 50MB입니다. 불필요한 자료를 내보낸 뒤 정리하세요.');
      }
      await _store.record(material.id).put(txn, material.toMap());
    });
  }

  Future<void> delete(String id) async {
    await _store.record(id).delete(await _open());
  }

  static String newId() => PersonalRecord.newId();
}

Future<XFile?> pickMaterialPdf() => openFile(
  acceptedTypeGroups: [
    const XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      mimeTypes: ['application/pdf'],
    ),
  ],
);

Future<void> exportMaterialPdf(PersonalMaterial material) async {
  final bytes = material.pdf;
  if (bytes == null) return;
  final file = XFile.fromData(
    bytes,
    name: material.fileName,
    mimeType: 'application/pdf',
  );
  if (kIsWeb) {
    await file.saveTo(material.fileName);
  } else {
    final destination = await getSaveLocation(
      suggestedName: material.fileName,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (destination != null) await file.saveTo(destination.path);
  }
}
