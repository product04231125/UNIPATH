import '../auth/auth_api.dart';
import 'official_record_models.dart';

export 'official_record_models.dart';

/// All calls belong to the captured login. School scope is enforced by the server.
class OfficialRecordsApi {
  const OfficialRecordsApi._(this.api, this.ownerId, this.admin);
  factory OfficialRecordsApi.forOwner(
    AuthApi auth,
    String ownerId, {
    bool admin = false,
  }) => OfficialRecordsApi._(auth.forOwner(ownerId), ownerId, admin);

  final ApiGateway api;
  final String ownerId;
  final bool admin;
  String get _path => '${admin ? 'admin' : 'me'}/official-record-batches';

  Future<SchoolRecordBatchList> list({
    String? sourceId,
    String? institutionId,
    String? kind,
    String? status,
    String? cursor,
    int limit = 20,
  }) async {
    final query = Uri(
      queryParameters: {
        'source_id': ?sourceId,
        'institution_id': ?institutionId,
        'kind': ?kind,
        'status': ?status,
        'cursor': ?cursor,
        'limit': '$limit',
      },
    ).query;
    final page = SchoolRecordBatchList.fromJson(
      (await api.request('GET', '$_path?$query'))!,
    );
    for (final row in page.items) {
      _owner(row.ownerId);
    }
    return page;
  }

  Future<SchoolRecordBatchView> get(String id) async =>
      _decode((await api.request('GET', '$_path/$id'))!, id: id);

  Future<SchoolRecordBatchEventList> events(String id) async {
    final page = SchoolRecordBatchEventList.fromJson(
      (await api.request('GET', '$_path/$id/events'))!,
    );
    if (page.items.any((event) => event.batchId != id)) {
      throw const FormatException('School record event request mismatch');
    }
    return page;
  }

  Future<SchoolRecordBatchView> create(SchoolRecordBatchCreate body) async {
    _staff();
    final batch = _decode((await api.request('POST', _path, body.toJson()))!);
    if (batch.clientId != body.clientId || batch.sourceId != body.sourceId) {
      throw const FormatException('School record creation request mismatch');
    }
    return batch;
  }

  Future<SchoolRecordBatchView> replace(
    String id,
    SchoolRecordBatchReplace body,
  ) => _write('PUT', id, '', body);

  Future<SchoolRecordBatchView> approve(
    String id,
    SchoolRecordBatchApprove body,
  ) {
    if (!body.recordsReviewed ||
        !body.contextReviewed ||
        !body.coverageReviewed) {
      throw const FormatException('Explicit school record review required');
    }
    return _write('POST', id, '/approve', body);
  }

  Future<SchoolRecordBatchView> revoke(
    String id,
    SchoolRecordBatchRevoke body,
  ) => _write('POST', id, '/revoke', body);

  Future<SchoolRecordBatchView> discard(
    String id,
    SchoolRecordBatchRevoke body,
  ) => _write('POST', id, '/discard', body);

  Future<SchoolRecordBatchView> _write(
    String method,
    String id,
    String action,
    SchoolRecordPayload body,
  ) async {
    _staff();
    return _decode(
      (await api.request(method, '$_path/$id$action', body.toJson()))!,
      id: id,
    );
  }

  void _staff() {
    if (!admin) throw StateError('School records require administrator review');
  }

  void _owner(String value) {
    if (!admin && value != ownerId) {
      throw const AuthFailure('학교 기록의 계정을 확인하지 못했습니다.', status: 403);
    }
  }

  SchoolRecordBatchView _decode(Map<String, dynamic> value, {String? id}) {
    final batch = SchoolRecordBatchView.fromJson(value);
    _owner(batch.ownerId);
    if (id != null && batch.id != id) {
      throw const FormatException('School record request mismatch');
    }
    return batch;
  }
}
