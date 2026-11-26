import 'package:shared_preferences/shared_preferences.dart';

import 'form_draft_persistence.dart';

/// Windows/desktop disk-backed draft storage via SharedPreferences.
class SharedPreferencesFormDraftPersistence implements FormDraftPersistence {
  SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _prefs()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await _prefs()).setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await (await _prefs()).remove(key);
  }

  @override
  Future<Iterable<String>> keys() async => (await _prefs()).getKeys();
}

FormDraftPersistence createFormDraftPersistence() =>
    SharedPreferencesFormDraftPersistence();
