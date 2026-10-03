import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../personal_record_repository.dart';

enum PortfolioAudience { private, application, publicReview }

String audienceLabel(PortfolioAudience audience) => switch (audience) {
  PortfolioAudience.private => '나만 보기',
  PortfolioAudience.application => '지원처 제출 검토용',
  PortfolioAudience.publicReview => '공개 검토용',
};

class PortfolioComposition {
  PortfolioComposition({
    required this.id,
    required this.title,
    this.description = '',
    this.audience = PortfolioAudience.private,
    this.reviewed = false,
    required List<String> sources,
  }) : sources = List.unmodifiable(sources);
  final String id, title, description;
  final PortfolioAudience audience;
  final bool reviewed;
  final List<String> sources;
}

class ApplicationDocument {
  ApplicationDocument({
    required this.id,
    required this.title,
    required this.target,
    required this.role,
    required this.type,
    this.body = '',
    required List<String> sources,
  }) : sources = List.unmodifiable(sources);
  final String id, title, target, role, type, body;
  final List<String> sources;
}

class PortfolioSource {
  const PortfolioSource(this.kind, this.record);
  final PersonalRecordKind kind;
  final PersonalRecord record;
  String get ref => '${kind.name}/${record.id}';
  String get label =>
      '${kind == PersonalRecordKind.portfolio ? '성과' : '경험'} · ${record.value('title')}';
  String get text => [
    record.value('title'),
    for (final (key, label) in [
      ('type', '종류'),
      ('thesisType', '논문·캡스톤 유형'),
      ('thesisStatus', '논문·캡스톤 개인 기록 상태'),
      ('thesisGrade', '논문·캡스톤 원 성적 표기'),
      ('thesisApprovedOn', '사용자가 확인한 논문·캡스톤 승인일 · 학교 승인 처리 아님'),
      ('organization', '기관'),
      ('startedOn', '시작일'),
      ('endedOn', '종료일'),
      ('role', '역할'),
      ('result', '결과'),
      ('detail', '메모'),
      ('evidenceUrl', '참고 링크'),
    ])
      if (record.value(key).isNotEmpty) '$label: ${record.value(key)}',
  ].join('\n');
}

/// Client-local compositions/documents, not ERD entities or published content.
class PortfolioWorkspaceRepository {
  PortfolioWorkspaceRepository({this.writer});
  final Future<bool> Function(String key, String value)? writer;
  static const storageKey = 'university_path.portfolio_workspace.v1';
  SharedPreferences? _preferences;
  bool _loaded = false;
  List<PortfolioComposition> _compositions = [];
  List<ApplicationDocument> _documents = [];
  Map<String, PortfolioSource> _sources = {};
  List<PortfolioComposition> get compositions =>
      List.unmodifiable(_compositions);
  List<ApplicationDocument> get documents => List.unmodifiable(_documents);
  Map<String, PortfolioSource> get sources => Map.unmodifiable(_sources);

  Future<void> load() async {
    _loaded = false;
    _preferences ??= await SharedPreferences.getInstance();
    final raw = _preferences!.getString(storageKey);
    final root = raw == null
        ? {'compositions': [], 'documents': []}
        : jsonDecode(raw) as Map;
    final compositions = [
      for (final item in root['compositions'] as List)
        PortfolioComposition(
          id: item['id'] as String,
          title: item['title'] as String,
          description: item['description'] as String,
          audience:
              PortfolioAudience.values
                  .where((a) => a.name == item['audience'])
                  .firstOrNull ??
              PortfolioAudience.private,
          reviewed: item['reviewed'] as bool,
          sources: List<String>.from(item['sources'] as List),
        ),
    ];
    final documents = [
      for (final item in root['documents'] as List)
        ApplicationDocument(
          id: item['id'] as String,
          title: item['title'] as String,
          target: item['target'] as String,
          role: item['role'] as String,
          type: item['type'] as String,
          body: item['body'] as String,
          sources: List<String>.from(item['sources'] as List),
        ),
    ];
    _uniqueIds([
      ...compositions.map((c) => c.id),
      ...documents.map((d) => d.id),
    ]);
    for (final refs in [
      ...compositions.map((c) => c.sources),
      ...documents.map((d) => d.sources),
    ]) {
      _uniqueIds(refs);
      if (refs.any(
        (ref) => !RegExp(r'^(portfolio|experience)/[^/]+$').hasMatch(ref),
      )) {
        throw const FormatException('Invalid personal source reference');
      }
    }
    await reloadSources();
    _compositions = compositions;
    _documents = documents;
    _loaded = true;
  }

  void _uniqueIds(List<String> ids) {
    if (ids.any((id) => id.isEmpty) || ids.toSet().length != ids.length) {
      throw const FormatException('Invalid or duplicate identifier');
    }
  }

  Future<void> reloadSources() async {
    final sources = <String, PortfolioSource>{};
    for (final kind in [
      PersonalRecordKind.portfolio,
      PersonalRecordKind.experience,
    ]) {
      final repo = PersonalRecordRepository(kind);
      await repo.load();
      for (final record in repo.records) {
        final source = PortfolioSource(kind, record);
        sources[source.ref] = source;
      }
    }
    _sources = sources;
  }

  Future<void> saveComposition(PortfolioComposition composition) async {
    if (composition.title.trim().isEmpty) throw ArgumentError('구성 이름을 입력하세요.');
    if (composition.audience == PortfolioAudience.publicReview &&
        !composition.reviewed) {
      throw ArgumentError('공개할 내용의 권한과 사실 관계를 확인하세요.');
    }
    final previous = _compositions
        .where((c) => c.id == composition.id)
        .firstOrNull;
    await _validateRefs(
      composition.sources,
      previous?.sources ?? [],
      onlyPortfolio: true,
    );
    final next = [
      ..._compositions.where((c) => c.id != composition.id),
      composition,
    ];
    await _write(next, _documents);
  }

  Future<void> saveDocument(ApplicationDocument document) async {
    if ([
      document.title,
      document.target,
      document.role,
      document.type,
    ].any((s) => s.trim().isEmpty)) {
      throw ArgumentError('문서 이름·지원처·직무·종류를 입력하세요.');
    }
    final previous = _documents.where((d) => d.id == document.id).firstOrNull;
    await _validateRefs(document.sources, previous?.sources ?? []);
    await _write(_compositions, [
      ..._documents.where((d) => d.id != document.id),
      document,
    ]);
  }

  Future<void> _validateRefs(
    List<String> refs,
    List<String> previous, {
    bool onlyPortfolio = false,
  }) async {
    _uniqueIds(refs);
    await reloadSources();
    if (refs.any(
      (ref) =>
          (!sources.containsKey(ref) && !previous.contains(ref)) ||
          (onlyPortfolio && !ref.startsWith('portfolio/')),
    )) {
      throw ArgumentError('연결할 개인 기록을 다시 선택하세요.');
    }
  }

  Future<void> deleteComposition(String id) =>
      _write(_compositions.where((c) => c.id != id).toList(), _documents);
  Future<void> deleteDocument(String id) =>
      _write(_compositions, _documents.where((d) => d.id != id).toList());

  Future<void> _write(
    List<PortfolioComposition> compositions,
    List<ApplicationDocument> documents,
  ) async {
    if (!_loaded) throw StateError('Load workspace before writing');
    _uniqueIds([
      ...compositions.map((c) => c.id),
      ...documents.map((d) => d.id),
    ]);
    final raw = jsonEncode({
      'compositions': [
        for (final c in compositions)
          {
            'id': c.id,
            'title': c.title,
            'description': c.description,
            'audience': c.audience.name,
            'reviewed': c.reviewed,
            'sources': c.sources,
          },
      ],
      'documents': [
        for (final d in documents)
          {
            'id': d.id,
            'title': d.title,
            'target': d.target,
            'role': d.role,
            'type': d.type,
            'body': d.body,
            'sources': d.sources,
          },
      ],
    });
    final saved =
        await (writer?.call(storageKey, raw) ??
            _preferences!.setString(storageKey, raw));
    if (!saved) throw StateError('Local workspace write failed');
    _compositions = compositions;
    _documents = documents;
  }

  String compositionText(PortfolioComposition composition) => [
    composition.title,
    '로컬 구성 · ${audienceLabel(composition.audience)} · 게시되지 않음',
    if (composition.description.isNotEmpty) composition.description,
    for (final ref in composition.sources)
      sources[ref]?.text ?? '원본 기록 삭제됨 · 연결 없음',
  ].join('\n\n');
}
