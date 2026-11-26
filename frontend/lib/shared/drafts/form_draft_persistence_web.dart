import 'package:web/web.dart' as web;

import 'form_draft_persistence.dart';

/// Web tab-session draft storage. Cleared when the tab/session ends.
class SessionStorageFormDraftPersistence implements FormDraftPersistence {
  web.Storage get _storage => web.window.sessionStorage;

  @override
  Future<String?> read(String key) async => _storage.getItem(key);

  @override
  Future<void> write(String key, String value) async {
    _storage.setItem(key, value);
  }

  @override
  Future<void> remove(String key) async {
    _storage.removeItem(key);
  }

  @override
  Future<Iterable<String>> keys() async => [
    for (var i = 0; i < _storage.length; i++)
      if (_storage.key(i) case final String key) key,
  ];
}

FormDraftPersistence createFormDraftPersistence() =>
    SessionStorageFormDraftPersistence();
