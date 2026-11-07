import 'dart:html' as html;

import 'form_draft_persistence.dart';

/// Web tab-session draft storage. Cleared when the tab/session ends.
class SessionStorageFormDraftPersistence implements FormDraftPersistence {
  html.Storage get _storage => html.window.sessionStorage;

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<void> write(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _storage.remove(key);
  }

  @override
  Future<Iterable<String>> keys() async => _storage.keys.toList(growable: false);
}

FormDraftPersistence createFormDraftPersistence() =>
    SessionStorageFormDraftPersistence();
