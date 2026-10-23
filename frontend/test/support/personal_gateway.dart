import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/personal_record_codec.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

import 'auth_fixture.dart';
import 'personal_workspace_fixture.dart';

class PersonalGateway implements ApiGateway {
  final calls = <(String, String, Map<String, Object?>?)>[];
  bool failWrites = false;
  bool empty = false;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    calls.add((method, path, body));
    if (method == 'POST' && path == 'me/personal-imports') {
      final mappings = <Map<String, Object?>>[];
      for (final entry in body!.entries) {
        if (entry.value is! List) continue;
        for (final row in entry.value as List) {
          mappings.add({
            'resource': entry.key.replaceAll('_', '-'),
            'client_id': row['client_id'],
            'record_id': row['client_id'],
            'version_at_import': 1,
            'outcome': 'created',
          });
        }
      }
      return {
        'import_id': body['import_id'],
        'owner_id': body['source_owner_id'],
        'record_count': mappings.length,
        'profile_version_at_import': null,
        'mappings': mappings,
        'committed_at': '2026-10-19T00:00:00Z',
        'replayed': false,
        'origin': 'personal',
        'official': false,
      };
    }
    if (method != 'GET' && failWrites) {
      throw const AuthFailure('다른 변경이 있습니다. 다시 읽어주세요.', status: 409);
    }
    for (final kind in PersonalRecordKind.values.where((kind) => kind.hasServerContract)) {
      final codec = PersonalRecordCodec(kind);
      if (Uri.parse(path).path == 'me/${codec.resource.path}') {
        final row = {
          ...codec
              .encode(fixtureValues(kind), clientId: fixtureId(kind))
              .toJson(),
          'id': fixtureId(kind),
          'owner_id': userId,
          'version': 1,
          'origin': 'personal',
          'official': false,
          'created_at': '2026-10-19T00:00:00Z',
          'updated_at': '2026-10-19T00:00:00Z',
        };
        return {
          'items': empty ? [] : [row],
          'next_cursor': null,
        };
      }
    }
    if (path.startsWith('me/portfolio-compositions?') ||
        path.startsWith('me/application-documents?')) {
      return {'items': [], 'next_cursor': null};
    }
    throw StateError('Unexpected synthetic gateway call $method $path');
  }

  StudentApi get api => StudentApi(this, ownerId: userId);
}
