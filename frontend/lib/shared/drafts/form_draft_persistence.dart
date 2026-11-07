/// Key/value backend for [FormDraftStore]. Platform-specific.
abstract class FormDraftPersistence {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
  Future<Iterable<String>> keys();
}

/// In-memory backend for tests and fallbacks.
class MemoryFormDraftPersistence implements FormDraftPersistence {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<Iterable<String>> keys() async => _values.keys.toList(growable: false);
}
