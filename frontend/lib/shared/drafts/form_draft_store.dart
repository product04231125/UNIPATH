import 'dart:convert';
import 'dart:math';

import '../../features/auth/local_data_owner.dart';
import 'form_draft_entry.dart';
import 'form_draft_persistence.dart';
import 'form_draft_persistence_stub.dart'
    if (dart.library.html) 'form_draft_persistence_web.dart'
    if (dart.library.io) 'form_draft_persistence_io.dart';

const formDraftKeyPrefix = 'university_path.form_drafts.v1.';
const formDraftMaxPerCollection = 10;

String formDraftCollectionKey(String screenId) =>
    LocalDataOwner.current().key('$formDraftKeyPrefix$screenId');

/// Client-only multi-slot form drafts. Not formal records or calculation drafts.
class FormDraftStore {
  FormDraftStore(this._persistence);

  final FormDraftPersistence _persistence;

  static FormDraftStore? _instance;

  static FormDraftStore get instance =>
      _instance ??= FormDraftStore(createFormDraftPersistence());

  static set instance(FormDraftStore store) => _instance = store;

  static void resetInstanceForTest([FormDraftStore? store]) {
    _instance = store;
  }

  Future<List<FormDraftEntry>> list(String collectionKey) async {
    final entries = await _readAll(collectionKey);
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  Future<FormDraftEntry> add(
    String collectionKey, {
    required String summary,
    required Map<String, Object?> payload,
  }) async {
    final entries = await _readAll(collectionKey);
    final entry = FormDraftEntry(
      id: _newId(),
      savedAt: DateTime.now(),
      summary: summary.trim().isEmpty ? '(내용 없음)' : summary.trim(),
      payload: Map<String, Object?>.from(payload),
    );
    entries.add(entry);
    entries.sort((a, b) => a.savedAt.compareTo(b.savedAt));
    while (entries.length > formDraftMaxPerCollection) {
      entries.removeAt(0);
    }
    await _writeAll(collectionKey, entries);
    return entry;
  }

  Future<FormDraftEntry?> get(String collectionKey, String id) async {
    for (final entry in await _readAll(collectionKey)) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<void> delete(String collectionKey, String id) async {
    final entries = await _readAll(collectionKey);
    final next = entries.where((e) => e.id != id).toList();
    if (next.length == entries.length) return;
    if (next.isEmpty) {
      await _persistence.remove(collectionKey);
    } else {
      await _writeAll(collectionKey, next);
    }
  }

  Future<void> clearCollection(String collectionKey) async {
    await _persistence.remove(collectionKey);
  }

  /// Removes every form-draft collection owned by [userId].
  Future<void> clearForOwner(String userId) async {
    final marker = '.account.$userId';
    final doomed = <String>[];
    for (final key in await _persistence.keys()) {
      if (key.contains(formDraftKeyPrefix) && key.contains(marker)) {
        doomed.add(key);
      }
    }
    for (final key in doomed) {
      await _persistence.remove(key);
    }
  }

  Future<List<FormDraftEntry>> _readAll(String collectionKey) async {
    final raw = await _persistence.read(collectionKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map)
            FormDraftEntry.fromJson(Map<String, Object?>.from(item)),
      ].where((e) => e.id.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(
    String collectionKey,
    List<FormDraftEntry> entries,
  ) async {
    await _persistence.write(
      collectionKey,
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }

  static String _newId() {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// Builds a one-line draft summary from form field values.
String formDraftSummaryFromValues(
  Map<String, String> values, {
  List<String> preferredKeys = const ['title', 'name', 'label'],
}) {
  for (final key in preferredKeys) {
    final value = values[key]?.trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  for (final value in values.values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '(내용 없음)';
}
