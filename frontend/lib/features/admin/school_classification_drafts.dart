import 'package:flutter/foundation.dart';

import '../records/personal_record_repository.dart';

// Client draft schema only. It is never sent to the current academic API.
enum SchoolClassificationKind { category, subcategory, requirement, track }

extension ClassificationLabel on SchoolClassificationKind {
  String get label => switch (this) {
    SchoolClassificationKind.category => '이수구분',
    SchoolClassificationKind.subcategory => '세부분류',
    SchoolClassificationKind.requirement => '필수·선택 구분',
    SchoolClassificationKind.track => '이수 경로',
  };
}

class SchoolClassification {
  const SchoolClassification({
    required this.id,
    required this.schoolId,
    required this.kind,
    required this.code,
    required this.name,
    this.description = '',
    this.parentId,
    this.requiredCourse,
  });
  final String id, schoolId, code, name, description;
  final SchoolClassificationKind kind;
  final String? parentId;
  final bool? requiredCourse;
  Map<String, Object?> toDraft() => {
    'id': id,
    'school': schoolId,
    'kind': kind.name,
    'code': code,
    'name': name,
    'description': description,
    'parent': parentId,
    'required': requiredCourse,
  };
  factory SchoolClassification.fromDraft(Map<String, dynamic> value) =>
      SchoolClassification(
        id: value['id'] as String,
        schoolId: value['school'] as String,
        kind: SchoolClassificationKind.values.byName(value['kind'] as String),
        code: value['code'] as String? ?? value['id'] as String,
        name: value['name'] as String,
        description: value['description'] as String? ?? '',
        parentId: value['parent'] as String?,
        requiredCourse: value['required'] as bool?,
      );
}

class SchoolClassificationDrafts extends ChangeNotifier {
  final _items = <String, SchoolClassification>{};
  final _bindings = <String, Map<SchoolClassificationKind, String>>{};
  List<SchoolClassification> entries(
    String school, [
    SchoolClassificationKind? kind,
  ]) => _items.values
      .where(
        (entry) =>
            entry.schoolId == school && (kind == null || entry.kind == kind),
      )
      .toList();
  String _key(String school, String target) => '$school\u0000$target';
  Map<SchoolClassificationKind, String> binding(String school, String target) =>
      Map.unmodifiable(_bindings[_key(school, target)] ?? {});
  SchoolClassification? get(String? id) => _items[id];
  void _validate(SchoolClassification value) {
    if (value.schoolId.isEmpty ||
        value.id.isEmpty ||
        value.code.trim().isEmpty ||
        value.code.length > 64 ||
        value.name.trim().isEmpty ||
        value.name.length > 128 ||
        value.description.length > 1000) {
      throw StateError('학교·코드·이름을 입력하고 길이를 확인하세요.');
    }
    if (_items.values.any(
      (old) =>
          old.id != value.id &&
          old.schoolId == value.schoolId &&
          old.kind == value.kind &&
          old.code.toLowerCase() == value.code.toLowerCase(),
    )) {
      throw StateError('같은 학교·분류 종류에서 코드는 중복될 수 없습니다.');
    }
    final old = _items[value.id];
    if (old != null &&
        (old.schoolId != value.schoolId || old.kind != value.kind)) {
      throw StateError('기존 분류의 학교·종류·ID는 바꿀 수 없습니다.');
    }
    if (value.kind == SchoolClassificationKind.subcategory) {
      final parent = _items[value.parentId];
      if (parent == null ||
          parent.schoolId != value.schoolId ||
          parent.kind != SchoolClassificationKind.category) {
        throw StateError('같은 학교의 상위 이수구분을 선택하세요.');
      }
    } else if (value.parentId != null) {
      throw StateError('세부분류만 상위 이수구분을 연결합니다.');
    }
    if ((value.kind == SchoolClassificationKind.requirement) !=
        (value.requiredCourse != null)) {
      throw StateError('필수·선택 구분에는 의미를 선택하세요.');
    }
    if (old != null &&
        old.parentId != value.parentId &&
        _bindings.values.any((b) => b.values.contains(value.id))) {
      throw StateError('연결된 세부분류의 상위 항목은 연결을 해제한 뒤 바꾸세요.');
    }
  }

  void save({
    String? id,
    required String schoolId,
    required SchoolClassificationKind kind,
    String? code,
    required String name,
    String description = '',
    String? parentId,
    bool? requiredCourse,
  }) {
    final identity = id ?? PersonalRecord.newId();
    final value = SchoolClassification(
      id: identity,
      schoolId: schoolId,
      kind: kind,
      code: code?.trim() ?? _items[identity]?.code ?? identity,
      name: name.trim(),
      description: description,
      parentId: parentId,
      requiredCourse: requiredCourse,
    );
    _validate(value);
    _items[value.id] = value;
    notifyListeners();
  }

  String requirementId(String school, bool required) {
    final existing = entries(school, SchoolClassificationKind.requirement)
        .where((item) => item.requiredCourse == required).firstOrNull;
    if (existing != null) return existing.id;
    final id = PersonalRecord.newId();
    save(id: id, schoolId: school, kind: SchoolClassificationKind.requirement,
      name: required ? '필수' : '선택', requiredCourse: required);
    return id;
  }

  void remove(String school, String id) {
    if (_items[id]?.schoolId != school) throw StateError('다른 학교의 분류입니다.');
    if (_items.values.any((e) => e.parentId == id) ||
        _bindings.values.any((b) => b.values.contains(id))) {
      throw StateError('세부분류나 등록 초안에 연결되어 있습니다. 연결을 먼저 해제하세요.');
    }
    _items.remove(id);
    notifyListeners();
  }

  void bind(
    String school,
    String target,
    Map<SchoolClassificationKind, String> values,
  ) {
    final next = Map<SchoolClassificationKind, String>.from(values)
      ..removeWhere((k, id) => id.isEmpty);
    for (final pair in next.entries) {
      final item = _items[pair.value];
      if (item == null || item.schoolId != school || item.kind != pair.key) {
        throw StateError('같은 학교의 분류 ID를 선택하세요.');
      }
    }
    final sub = _items[next[SchoolClassificationKind.subcategory]];
    if (sub != null && sub.parentId != next[SchoolClassificationKind.category]) {
      throw StateError('이수구분과 세부분류의 연결이 다릅니다.');
    }
    _bindings[_key(school, target)] = next;
    notifyListeners();
  }

  void moveBinding(String school, String oldTarget, String newTarget) {
    if (oldTarget == newTarget) return;
    final values = _bindings.remove(_key(school, oldTarget));
    if (values != null) {
      _bindings[_key(school, newTarget)] = values;
      notifyListeners();
    }
  }

  Map<String, Object?> exportSchool(String school) => {
    'draft_version': 1,
    'school': school,
    'items': [for (final item in entries(school)) item.toDraft()],
    'bindings': {
      for (final entry in _bindings.entries.where(
        (e) => e.key.startsWith('$school\u0000'),
      ))
        entry.key.substring(school.length + 1): {
          for (final pair in entry.value.entries) pair.key.name: pair.value,
        },
    },
  };
  void restoreSchool(String school, Map<String, dynamic> data) {
    if (data['draft_version'] != 1 || data['school'] != school) {
      throw StateError('현재 학교의 분류 초안이 아닙니다.');
    }
    final staged = SchoolClassificationDrafts();
    final rows = (data['items'] as List)
        .map(
          (e) => SchoolClassification.fromDraft(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
    if (rows.length > 1000 ||
        rows.map((e) => e.id).toSet().length != rows.length ||
        rows.any(
          (e) =>
              e.schoolId != school ||
              _items[e.id] != null && _items[e.id]!.schoolId != school,
        )) {
      throw StateError('분류 초안의 학교·ID·개수를 확인하세요.');
    }
    for (final kind in SchoolClassificationKind.values) {
      for (final row in rows.where((e) => e.kind == kind)) {
        staged._validate(row);
        staged._items[row.id] = row;
      }
    }
    final bindings = Map<String, dynamic>.from(data['bindings'] as Map);
    if (bindings.length > 10000) throw StateError('연결 초안이 너무 많습니다.');
    for (final entry in bindings.entries) {
      staged.bind(school, entry.key, {
        for (final pair in Map<String, dynamic>.from(
          entry.value as Map,
        ).entries)
          SchoolClassificationKind.values.byName(pair.key):
              pair.value as String,
      });
    }
    _items.removeWhere((id, e) => e.schoolId == school);
    _items.addAll(staged._items);
    _bindings.removeWhere((key, value) => key.startsWith('$school\u0000'));
    _bindings.addAll(staged._bindings);
    staged.dispose();
    notifyListeners();
  }
}
