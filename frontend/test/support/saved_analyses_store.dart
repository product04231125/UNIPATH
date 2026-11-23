/// In-memory `me/analysis-results` for page tests: saves, lists, stars and reopens.
class SavedAnalysesStore {
  final items = <Map<String, dynamic>>[];
  final requests = <(String, String, Map<String, Object?>?)>[];
  var _next = 0;

  static bool handles(String path) => path.startsWith('me/analysis-results');

  Map<String, dynamic> _summary(Map<String, dynamic> row) => {
    for (final key in ['id', 'kind', 'title', 'summary', 'favorite'])
      key: row[key],
    'created_at': row['created_at'],
  };

  Map<String, dynamic>? handle(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) {
    requests.add((method, path, body));
    final uri = Uri.parse(path);
    final id = uri.pathSegments.length > 2 ? uri.pathSegments.last : null;
    if (method == 'GET' && id == null) {
      final kind = uri.queryParameters['kind'];
      final rows = [
        ...items.where((i) => i['favorite'] == true),
        ...items.where((i) => i['favorite'] != true),
      ].where((i) => kind == null || i['kind'] == kind);
      return {
        'items': [for (final row in rows) _summary(row)],
      };
    }
    if (method == 'POST') {
      final row = <String, dynamic>{
        ...body!,
        'id': 'saved-${_next++}',
        'favorite': false,
        'created_at': '2026-11-24T02:13:00+09:00',
      };
      items.insert(0, row);
      return _summary(row);
    }
    final row = items.firstWhere((i) => i['id'] == id);
    switch (method) {
      case 'GET':
        return {
          ..._summary(row),
          'input': row['input'],
          'result': row['result'],
        };
      case 'PATCH':
        row['favorite'] = body!['favorite'];
        return _summary(row);
      case 'DELETE':
        items.remove(row);
        return null;
    }
    throw StateError('Unexpected $method $path');
  }
}
