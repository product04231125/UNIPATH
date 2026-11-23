import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/features/auth/material_file_gateway.dart';
import 'package:university_path_frontend/features/records/portfolio/material_repository.dart';

final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 synthetic'));

class MaterialsGateway extends ApiGateway implements MaterialFileGateway {
  final requests = <(String, String, Map<String, Object?>?)>[];
  final saved = <String, Map<String, Object?>>{};
  final failing = <String>{};

  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    requests.add((method, path, body));
    if (method == 'POST') {
      if (failing.contains(body!['id'])) {
        throw const AuthFailure('자료 PDF 보관 한도 50MB입니다.', status: 409);
      }
      saved[body['id'] as String] = body;
      return {};
    }
    if (method == 'GET') {
      return {
        'items': [
          for (final entry in saved.entries)
            {
              'id': entry.key,
              'title': entry.value['title'],
              'material_type': entry.value['material_type'],
              'description': entry.value['description'],
              'filename': (entry.value['file'] as Map?)?['filename'],
              'byte_count': entry.value['file'] == null ? 0 : pdf.length,
              'version': 1,
            },
        ],
      };
    }
    return null;
  }

  @override
  Future<Uint8List> materialFile(String id) async => pdf;
}

void main() {
  test(
    'device materials move to the account once, keeping their ids',
    () async {
      final db = await databaseFactoryMemory.openDatabase('account-materials');
      addTearDown(db.close);
      final device = DeviceMaterialRepository(
        open: () async => db,
        owner: const LocalDataOwner('owner'),
      );
      for (final (id, file) in [
        ('kept', true),
        ('note', false),
        ('big', true),
      ]) {
        await device.save(
          PersonalMaterial(
            id: id,
            title: '합성 $id',
            type: MaterialKinds.portfolio,
            description: file ? '' : '설명만 있는 자료',
            fileName: file ? '$id.pdf' : '',
            pdf: file ? pdf : null,
          ),
        );
      }
      final gateway = MaterialsGateway()..failing.add('big');
      final repo = AccountMaterialRepository(
        gateway,
        ownerId: 'owner',
        device: device,
      );
      final rows = await repo.load();
      expect(rows.map((m) => m.id), unorderedEquals(['kept', 'note']));
      final kept = rows.firstWhere((m) => m.id == 'kept');
      expect(kept.type, MaterialKinds.portfolio);
      expect(kept.hasPdf, isTrue);
      expect(kept.pdf, isNull);
      expect(await repo.pdf(kept), pdf);
      expect(gateway.saved['kept']!['material_type'], 'portfolio');
      expect(
        base64Decode((gateway.saved['kept']!['file'] as Map)['content_base64']),
        pdf,
      );
      // The one the account refused stays on the device and is counted.
      expect((await device.load()).single.id, 'big');
      expect(repo.unmovedCount, 1);
      // The move runs once per session, not on every read.
      final posts = gateway.requests.where((r) => r.$1 == 'POST').length;
      await repo.load();
      expect(gateway.requests.where((r) => r.$1 == 'POST').length, posts);
    },
  );

  test('updates keep, remove or replace the saved PDF', () async {
    final gateway = MaterialsGateway();
    final repo = AccountMaterialRepository(gateway, ownerId: 'owner');
    PersonalMaterial saved({String fileName = 'a.pdf', Uint8List? file}) =>
        PersonalMaterial(
          id: 'm',
          title: '합성 자료',
          type: MaterialKinds.resume,
          description: '설명',
          fileName: fileName,
          pdf: file,
          byteCount: 100,
          version: 3,
        );
    await repo.save(saved());
    expect(gateway.requests.last.$1, 'PUT');
    expect(gateway.requests.last.$2, 'me/materials/m');
    expect(gateway.requests.last.$3!.containsKey('file'), isFalse);
    expect(gateway.requests.last.$3!['expected_version'], 3);
    await repo.save(saved(fileName: ''));
    expect(gateway.requests.last.$3!['file'], isNull);
    expect(gateway.requests.last.$3!.containsKey('file'), isTrue);
    await repo.save(saved(fileName: 'b.pdf', file: pdf));
    expect((gateway.requests.last.$3!['file'] as Map)['filename'], 'b.pdf');
    await repo.delete(saved());
    expect(gateway.requests.last.$1, 'DELETE');
    expect(gateway.requests.last.$2, 'me/materials/m?expected_version=3');
    await repo.save(
      PersonalMaterial(
        id: 'new',
        title: '새 자료',
        type: MaterialKinds.other,
        description: '설명',
      ),
    );
    expect(gateway.requests.last.$1, 'POST');
    expect(gateway.requests.last.$3!['id'], 'new');
    expect(gateway.requests.last.$3!['material_type'], 'other');
    expect(
      () => repo.save(
        PersonalMaterial(id: 'x', title: '빈 자료', type: '', description: ''),
      ),
      throwsStateError,
    );
  });
}
