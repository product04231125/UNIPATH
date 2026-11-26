import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:sembast/blob.dart';
import 'package:sembast/sembast.dart';

import '../../auth/auth_api.dart';
import '../../auth/material_file_gateway.dart';
import '../personal_record_repository.dart';
import '../../auth/local_data_owner.dart';
import 'material_database.dart';

abstract final class MaterialKinds {
  static const portfolio = '포트폴리오';
  static const resume = '이력서';
  static const coverLetter = '자기소개서';
  static const other = '증빙·기타';
  static const all = [portfolio, resume, coverLetter, other];
  static bool isAllowed(String type) => all.contains(type);
}

class PersonalMaterial {
  PersonalMaterial({
    required this.id,
    required this.title,
    required this.type,
    required this.description,
    this.fileName = '',
    Uint8List? pdf,
    int? byteCount,
    this.version = 0,
  }) : pdf = pdf == null ? null : Uint8List.fromList(pdf),
       byteCount = byteCount ?? pdf?.length ?? 0;
  final String id, title, type, description, fileName;

  /// The PDF when it is at hand: a newly picked file, or one kept on this device.
  /// Account materials leave it out and read it with [MaterialRepository.pdf].
  final Uint8List? pdf;
  final int byteCount;

  /// The saved version in the account; 0 before the first save.
  final int version;
  bool get hasPdf => pdf != null || (fileName.isNotEmpty && byteCount > 0);

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

/// A saved PDF's pages for the in-app viewer: how many there are and the sizes (points) of the
/// pages that can be shown.
class MaterialPages {
  const MaterialPages({required this.count, required this.sizes});
  MaterialPages.fromJson(Map<String, dynamic> json)
    : count = json['page_count'] as int,
      sizes = [
        for (final page in json['pages'] as List)
          (
            width: ((page as Map)['width'] as num).toDouble(),
            height: (page['height'] as num).toDouble(),
          ),
      ];
  final int count;
  final List<({double width, double height})> sizes;
}

/// Where 내 자료 is kept: the student's account, or this device before signing in.
abstract class MaterialRepository {
  /// One PDF: the most a single analysis request can send.
  static const maxPdfBytes = 8 * 1024 * 1024;
  static const maxTotalBytes = 50 * 1024 * 1024;

  /// True when materials are kept in the account rather than on this device.
  bool get inAccount;
  Future<List<PersonalMaterial>> load();

  /// Saves [material]. Its [PersonalMaterial.pdf] replaces the saved PDF, an empty
  /// [PersonalMaterial.fileName] removes it, and otherwise the saved PDF is kept.
  Future<void> save(PersonalMaterial material);
  Future<void> delete(PersonalMaterial material);

  /// The material's PDF, or null when it has none.
  Future<Uint8List?> pdf(PersonalMaterial material);

  /// True when a saved PDF can be shown in the app: the server renders its pages, so only
  /// materials kept in the account can.
  bool get canPreview;

  /// Page count and sizes of the saved PDF.
  Future<MaterialPages> pages(PersonalMaterial material);

  /// Page [number] (1-based) of the saved PDF as an image.
  Future<Uint8List> pageImage(PersonalMaterial material, int number);

  static void validatePdf(String name, Uint8List bytes) {
    if (bytes.length > maxPdfBytes) throw StateError('PDF는 8MB 이하로 선택하세요.');
    if (!name.toLowerCase().endsWith('.pdf') ||
        bytes.length < 5 ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw StateError('PDF 파일을 선택하세요.');
    }
  }

  static void validate(PersonalMaterial material) {
    if (material.title.trim().isEmpty ||
        (!material.hasPdf && material.description.trim().isEmpty)) {
      throw StateError('자료 이름과 내용 설명 또는 PDF를 입력하세요.');
    }
    if (material.pdf != null) validatePdf(material.fileName, material.pdf!);
  }

  static String newId() => PersonalRecord.newId();
}

/// Private, device-local material store, used before signing in and as the
/// source when a device's materials move to the account.
class DeviceMaterialRepository implements MaterialRepository {
  DeviceMaterialRepository({
    Future<Database> Function()? open,
    LocalDataOwner? owner,
  }) : _open = open ?? openMaterialDatabase,
       _owner = owner ?? LocalDataOwner.current();
  final Future<Database> Function() _open;
  final LocalDataOwner _owner;
  late final _store = stringMapStoreFactory.store(_owner.key('materials'));

  @override
  bool get inAccount => false;

  @override
  Future<List<PersonalMaterial>> load() async {
    final rows = await _store.find(await _open());
    return [
      for (final row in rows) PersonalMaterial.fromMap(row.key, row.value),
    ];
  }

  @override
  Future<void> save(PersonalMaterial material) async {
    MaterialRepository.validate(material);
    final db = await _open();
    await db.transaction((txn) async {
      final rows = await _store.find(txn);
      final saved = rows.where((row) => row.key == material.id).firstOrNull;
      // Keep the saved PDF unless a new one was picked or the file was removed.
      final keep = material.pdf == null && material.fileName.isNotEmpty
          ? (saved?.value['pdf'] as Blob?)
          : null;
      final value = {...material.toMap(), 'pdf': ?keep};
      final total = rows
          .where((row) => row.key != material.id)
          .fold<int>(
            0,
            (sum, row) =>
                sum + ((row.value['pdf'] as Blob?)?.bytes.length ?? 0),
          );
      final added = (value['pdf'] as Blob?)?.bytes.length ?? 0;
      if (total + added > MaterialRepository.maxTotalBytes) {
        throw StateError('기기 PDF 보관 한도 50MB입니다. 불필요한 자료를 내보낸 뒤 정리하세요.');
      }
      await _store.record(material.id).put(txn, value);
    });
  }

  @override
  Future<void> delete(PersonalMaterial material) => deleteId(material.id);

  Future<void> deleteId(String id) async {
    await _store.record(id).delete(await _open());
  }

  @override
  Future<Uint8List?> pdf(PersonalMaterial material) async {
    if (material.pdf != null) return material.pdf;
    final row = await _store.record(material.id).get(await _open());
    return (row?['pdf'] as Blob?)?.bytes;
  }

  @override
  bool get canPreview => false;

  @override
  Future<MaterialPages> pages(PersonalMaterial material) =>
      throw UnsupportedError('PDF는 로그인한 뒤 앱에서 볼 수 있습니다.');

  @override
  Future<Uint8List> pageImage(PersonalMaterial material, int number) =>
      throw UnsupportedError('PDF는 로그인한 뒤 앱에서 볼 수 있습니다.');
}

/// 내 자료 kept in the student's account. Materials still on this device move
/// to the account the first time the list is read, keeping their ids.
class AccountMaterialRepository implements MaterialRepository {
  AccountMaterialRepository(
    this.api, {
    required this.ownerId,
    DeviceMaterialRepository? device,
  }) : _device =
           device ?? DeviceMaterialRepository(owner: LocalDataOwner(ownerId));
  final ApiGateway api;
  final String ownerId;
  final DeviceMaterialRepository? _device;
  static const _path = 'me/materials';
  Future<void>? _moving;

  /// Device materials that could not move to the account (too large, over the
  /// account limit or a failed request); they stay on the device and are retried.
  int unmovedCount = 0;

  static const _codes = {
    MaterialKinds.portfolio: 'portfolio',
    MaterialKinds.resume: 'resume',
    MaterialKinds.coverLetter: 'cover_letter',
    MaterialKinds.other: 'other',
  };
  static String _label(String code) =>
      _codes.entries
          .where((e) => e.value == code)
          .map((e) => e.key)
          .firstOrNull ??
      MaterialKinds.other;
  static String _code(String type) => _codes[type] ?? 'other';

  @override
  bool get inAccount => true;

  Map<String, Object?> _file(PersonalMaterial m) => {
    'filename': m.fileName,
    'content_base64': base64Encode(m.pdf!),
  };

  Map<String, Object?> _body(PersonalMaterial m) => {
    'title': m.title.trim(),
    'material_type': _code(m.type),
    'description': m.description.trim(),
  };

  Future<void> _moveDeviceMaterials() async {
    final device = _device;
    if (device == null) return;
    var unmoved = 0;
    List<PersonalMaterial> local;
    try {
      local = await device.load();
    } catch (_) {
      return;
    }
    for (final m in local) {
      try {
        if (m.pdf != null) MaterialRepository.validatePdf(m.fileName, m.pdf!);
        await api.request('POST', _path, {
          'id': m.id,
          ..._body(m),
          if (m.pdf != null) 'file': _file(m),
        });
        await device.deleteId(m.id);
      } catch (_) {
        unmoved++;
      }
    }
    unmovedCount = unmoved;
  }

  @override
  Future<List<PersonalMaterial>> load() async {
    // Once per session; a failed move is retried with the next session.
    await (_moving ??= _moveDeviceMaterials());
    final value = await api.request('GET', _path);
    return [
      for (final raw in (value?['items'] as List? ?? const []))
        if (raw case final Map<String, dynamic> item)
          PersonalMaterial(
            id: item['id'] as String,
            title: item['title'] as String,
            type: _label(item['material_type'] as String),
            description: item['description'] as String? ?? '',
            fileName: item['filename'] as String? ?? '',
            byteCount: item['byte_count'] as int? ?? 0,
            version: item['version'] as int,
          ),
    ];
  }

  @override
  Future<void> save(PersonalMaterial material) async {
    MaterialRepository.validate(material);
    if (material.version == 0) {
      await api.request('POST', _path, {
        'id': material.id,
        ..._body(material),
        if (material.pdf != null) 'file': _file(material),
      });
      return;
    }
    await api.request('PUT', '$_path/${material.id}', {
      ..._body(material),
      'expected_version': material.version,
      if (material.pdf != null)
        'file': _file(material)
      else if (material.fileName.isEmpty)
        'file': null,
    });
  }

  @override
  Future<void> delete(PersonalMaterial material) => api.request(
    'DELETE',
    '$_path/${material.id}?expected_version=${material.version}',
  );

  @override
  Future<Uint8List?> pdf(PersonalMaterial material) async {
    if (material.pdf != null) return material.pdf;
    if (!material.hasPdf) return null;
    if (api case final MaterialFileGateway files) {
      return files.materialFile(material.id);
    }
    throw StateError('PDF는 로그인한 뒤 받을 수 있습니다.');
  }

  @override
  bool get canPreview => api is MaterialFileGateway;

  @override
  Future<MaterialPages> pages(PersonalMaterial material) async =>
      MaterialPages.fromJson(
        (await api.request('GET', '$_path/${material.id}/pages'))!,
      );

  @override
  Future<Uint8List> pageImage(PersonalMaterial material, int number) {
    if (api case final MaterialFileGateway files) {
      return files.materialPage(material.id, number);
    }
    throw StateError('PDF는 로그인한 뒤 볼 수 있습니다.');
  }
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

Future<void> exportMaterialPdf(
  PersonalMaterial material,
  Uint8List bytes,
) async {
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
