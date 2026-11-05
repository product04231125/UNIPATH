import 'dart:typed_data';

import '../auth/auth_api.dart';
import '../auth/record_files_gateway.dart';

enum RecordSourceStatus { submitted, verified, rejected, revoked, withdrawn }

enum RecordSourceKind { transcript, volunteer, certificate, thesis, other }

/// Private metadata is sent in a header; the body is the original PDF.
class RecordSourceUpload {
  const RecordSourceUpload({
    required this.clientId,
    required this.institutionId,
    required this.documentKind,
    required this.issuedOn,
    required this.filename,
    required this.reviewConsentConfirmed,
    this.departmentId,
    this.curriculumId,
  });
  final String clientId, institutionId, issuedOn, filename;
  final String? departmentId, curriculumId;
  final RecordSourceKind documentKind;
  final bool reviewConsentConfirmed;
  Map<String, Object?> toJson() {
    if (!reviewConsentConfirmed) {
      throw const FormatException('Explicit review consent required');
    }
    return {
      'client_id': clientId,
      'institution_id': institutionId,
      'department_id': ?departmentId,
      'curriculum_id': ?curriculumId,
      'document_kind': documentKind.name,
      'issued_on': issuedOn,
      'filename': filename,
      'review_consent_confirmed': true,
    };
  }
}

class RecordSource {
  RecordSource.fromJson(Map<String, dynamic> value)
    : id = value['id'] as String,
      ownerId = value['owner_id'] as String,
      clientId = value['client_id'] as String,
      institutionId = value['institution_id'] as String,
      departmentId = value['department_id'] as String?,
      curriculumId = value['curriculum_id'] as String?,
      documentKind = RecordSourceKind.values.byName(
        value['document_kind'] as String,
      ),
      issuedOn = value['issued_on'] as String,
      filename = value['filename'] as String,
      sha256 = value['sha256'] as String,
      byteCount = value['byte_count'] as int,
      status = RecordSourceStatus.values.byName(value['status'] as String),
      version = value['version'] as int,
      createdAt = DateTime.parse(value['created_at'] as String),
      updatedAt = DateTime.parse(value['updated_at'] as String) {
    if (value['graduation_eligible'] != false ||
        version < 1 ||
        byteCount < 1 ||
        byteCount > 2 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid private source metadata');
    }
  }
  final String id, ownerId, clientId, institutionId, issuedOn, filename, sha256;
  final String? departmentId, curriculumId;
  final RecordSourceKind documentKind;
  final RecordSourceStatus status;
  final int byteCount, version;
  final DateTime createdAt, updatedAt;
  bool get graduationEligible => false;
}

class RecordSourcePage {
  RecordSourcePage.fromJson(Map<String, dynamic> value)
    : items = List.unmodifiable(
        (value['items'] as List).map(
          (row) => RecordSource.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      ),
      nextCursor = value['next_cursor'] as String?;
  final List<RecordSource> items;
  final String? nextCursor;
}

class RecordSourceEvent {
  RecordSourceEvent.fromJson(Map<String, dynamic> value)
    : id = value['id'] as String,
      sourceId = value['source_id'] as String,
      actorId = value['actor_id'] as String?,
      version = value['version'] as int,
      action = RecordSourceStatus.values.byName(value['action'] as String),
      reason = value['reason'] as String,
      occurredAt = DateTime.parse(value['occurred_at'] as String);
  final String id, sourceId, reason;
  final String? actorId;
  final int version;
  final RecordSourceStatus action;
  final DateTime occurredAt;
}

/// Captures both metadata and file capabilities from the same current login.
/// Source verification never marks normalized records or graduation as approved.
class RecordSourceApi {
  const RecordSourceApi._(
    this.api,
    this.files,
    this.ownerId, {
    this.admin = false,
  });
  factory RecordSourceApi.forOwner(
    AuthApi auth,
    String ownerId, {
    bool admin = false,
  }) => RecordSourceApi._(
    auth.forOwner(ownerId),
    auth.recordFilesForOwner(ownerId),
    ownerId,
    admin: admin,
  );
  final ApiGateway api;
  final RecordFilesGateway files;
  final String ownerId;
  final bool admin;
  String get _path => '${admin ? 'admin' : 'me'}/official-record-sources';
  Future<RecordSourcePage> list({
    String? institutionId,
    RecordSourceStatus? status,
    String? cursor,
    int limit = 100,
  }) async {
    final query = Uri(
      queryParameters: {
        'institution_id': ?institutionId,
        'status': ?status?.name,
        'cursor': ?cursor,
        'limit': '$limit',
      },
    ).query;
    final page = RecordSourcePage.fromJson(
      (await api.request('GET', '$_path?$query'))!,
    );
    if (!admin && page.items.any((source) => source.ownerId != ownerId)) {
      throw const AuthFailure('자료의 계정을 확인하지 못했습니다.', status: 403);
    }
    return page;
  }

  Future<RecordSource> get(String id) async =>
      _decode((await api.request('GET', '$_path/$id'))!, id: id);
  Future<List<RecordSourceEvent>> events(String id) async => List.unmodifiable(
    ((await api.request('GET', '$_path/$id/events'))!['items'] as List).map(
      (row) =>
          RecordSourceEvent.fromJson(Map<String, dynamic>.from(row as Map)),
    ),
  );
  Future<Uint8List> download(String id) => files.download('$_path/$id/file');
  Future<RecordSource> upload(
    RecordSourceUpload metadata,
    Uint8List bytes,
  ) async {
    if (admin) throw StateError('Uploads belong to the source owner');
    final source = _decode(
      await files.upload(_path, bytes, metadata: metadata.toJson()),
    );
    if (source.clientId != metadata.clientId) {
      throw const FormatException('Source replay key mismatch');
    }
    return source;
  }

  Future<RecordSource> withdraw(String id, {required int expectedVersion}) {
    if (admin) throw StateError('Only the source owner can withdraw');
    return _transition(id, 'withdraw', {'expected_version': expectedVersion});
  }

  Future<RecordSource> verify(
    String id, {
    required int expectedVersion,
    required String expectedSha256,
    required bool schoolIssuedConfirmed,
    required bool subjectIdentityConfirmed,
  }) {
    if (!admin) throw StateError('School review requires administrator access');
    if (!schoolIssuedConfirmed || !subjectIdentityConfirmed) {
      throw const FormatException('Issuer and subject verification required');
    }
    return _transition(id, 'verify', {
      'expected_version': expectedVersion,
      'expected_sha256': expectedSha256,
      'school_issued_confirmed': true,
      'subject_identity_confirmed': true,
    });
  }

  Future<RecordSource> reject(
    String id, {
    required int expectedVersion,
    required String reason,
  }) {
    if (!admin) throw StateError('School review requires administrator access');
    return _transition(id, 'reject', {
      'expected_version': expectedVersion,
      'reason': reason,
    });
  }

  Future<RecordSource> revoke(
    String id, {
    required int expectedVersion,
    required String reason,
  }) {
    if (!admin) throw StateError('School review requires administrator access');
    return _transition(id, 'revoke', {
      'expected_version': expectedVersion,
      'reason': reason,
    });
  }

  Future<RecordSource> _transition(
    String id,
    String action,
    Map<String, Object?> body,
  ) async =>
      _decode((await api.request('POST', '$_path/$id/$action', body))!, id: id);

  RecordSource _decode(Map<String, dynamic> value, {String? id}) {
    final source = RecordSource.fromJson(value);
    if ((!admin && source.ownerId != ownerId) ||
        (id != null && source.id != id)) {
      throw const AuthFailure('자료의 계정과 요청을 확인하지 못했습니다.', status: 403);
    }
    return source;
  }
}
