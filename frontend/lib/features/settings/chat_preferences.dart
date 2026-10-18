import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChatOpeningMode { detached, docked }

/// Device preference, independent of academic records and server accounts.
class ChatPreferences extends ChangeNotifier {
  ChatPreferences({this.writer});

  static const storageKey = 'university_path.chat_opening.v1';
  static const migrationKey = 'university_path.chat_opening.docked_default.v1';
  final Future<bool> Function(String key, String value)? writer;
  ChatOpeningMode _mode = ChatOpeningMode.docked;
  bool loading = true;
  bool loadFailed = false;
  bool saving = false;
  String? error;
  Future<void>? _load;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  ChatOpeningMode get mode => _mode;

  Future<void> load() => _load ??= _read();

  Future<void> _read() async {
    loading = true;
    loadFailed = false;
    error = null;
    _notify();
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(storageKey);
      final storedMode = switch (raw) {
        null || 'docked' => ChatOpeningMode.docked,
        'detached' => ChatOpeningMode.detached,
        _ => throw const FormatException('Unknown chat opening preference'),
      };
      if (preferences.getBool(migrationKey) != true) {
        // Write the new value before the marker so interrupted migration retries.
        if (!await preferences.setString(storageKey, 'docked') ||
            !await preferences.setBool(migrationKey, true)) {
          throw StateError('Chat preference migration failed');
        }
        _mode = ChatOpeningMode.docked;
      } else {
        _mode = storedMode;
      }
    } catch (_) {
      loadFailed = true;
      error = '채팅 설정을 읽지 못했습니다. 원본을 보존하고 다시 읽어 주세요.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> retry() {
    if (loading || saving) return load();
    _load = null;
    return load();
  }

  Future<void> setMode(ChatOpeningMode value) async {
    if (loading || loadFailed || saving) return;
    saving = true;
    error = null;
    _notify();
    try {
      final success = writer != null
          ? await writer!(storageKey, value.name)
          : await (await SharedPreferences.getInstance()).setString(
              storageKey,
              value.name,
            );
      if (!success) throw StateError('Preference write rejected');
      _mode = value;
    } catch (_) {
      error = '채팅 설정을 저장하지 못했습니다. 기존 설정을 유지합니다.';
    } finally {
      saving = false;
      _notify();
    }
  }
}
