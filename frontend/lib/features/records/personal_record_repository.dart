import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

enum PersonalRecordKind {
  course,
  activity,
  experience,
  credential,
  portfolio,
  personalCurriculum,
  personalCurriculumCourse,
  personalGraduationRule,
}

/// Client-local personal data, never a transport DTO or official school record.
class PersonalRecord {
  PersonalRecord({required this.id, required Map<String, String> values})
    : values = Map.unmodifiable(values);
  final String id;
  final Map<String, String> values;

  String value(String key) => values[key] ?? '';

  static String newId() {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class PersonalRecordRepository {
  PersonalRecordRepository(this.kind);
  final PersonalRecordKind kind;
  SharedPreferences? _preferences;
  bool _loaded = false;
  List<PersonalRecord> _records = [];
  List<PersonalRecord> get records => List.unmodifiable(_records);
  String get storageKey => 'university_path.personal_records.${kind.name}.v1';

  Future<void> load() async {
    _loaded = false;
    _preferences ??= await SharedPreferences.getInstance();
    final raw = _preferences!.getString(storageKey);
    if (raw == null) {
      _loaded = true;
      return;
    }
    final decoded = jsonDecode(raw) as List;
    final records = decoded.map((item) {
      final map = item as Map;
      return PersonalRecord(
        id: map['id'] as String,
        values: Map<String, String>.from(map['values'] as Map),
      );
    }).toList();
    if (records.map((r) => r.id).toSet().length != records.length) {
      throw const FormatException('Duplicate personal record identifier');
    }
    _records = records;
    _loaded = true;
  }

  Future<void> save(PersonalRecord record) async {
    final next = [..._records];
    final index = next.indexWhere((r) => r.id == record.id);
    if (index < 0) {
      next.add(record);
    } else {
      next[index] = record;
    }
    await _write(next);
  }

  Future<void> delete(String id) =>
      _write(_records.where((r) => r.id != id).toList());

  Future<void> _write(List<PersonalRecord> records) async {
    if (!_loaded) throw StateError('Load records successfully before writing');
    final saved = await _preferences!.setString(
      storageKey,
      jsonEncode([
        for (final record in records)
          {'id': record.id, 'values': record.values},
      ]),
    );
    if (!saved) throw StateError('Personal record storage failed');
    _records = records;
  }
}
