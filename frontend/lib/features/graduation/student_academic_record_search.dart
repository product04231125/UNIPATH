import 'package:flutter/material.dart';

import '../api/student_academic_api.dart';
import '../auth/local_data_owner.dart';
import '../records/course/course_status.dart';
import '../records/portfolio/material_repository.dart';

const academicSearchKinds = {
  'course': '수강',
  'activity': '활동',
  'credential': '자격',
  'experience': '경험',
  'achievement': '성과',
  'material': '자료',
};

class AcademicRecordSearchHit {
  const AcademicRecordSearchHit(this.id, this.kind, this.title, this.details);
  final String id, kind, title;
  final Map<String, String> details;
  bool matches(String query) {
    final text = '$title ${details.values.join(' ')}'.toLowerCase();
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }
}

class AcademicRecordSearchRepository {
  AcademicRecordSearchRepository(this.api, {MaterialRepository? materials})
    : materials =
          materials ?? MaterialRepository(owner: LocalDataOwner(api.ownerId));
  final StudentAcademicApi api;
  final MaterialRepository materials;
  Future<List<AcademicRecordSearchHit>> load(String kind) async {
    if (kind == 'material') {
      return [
        for (final r in await materials.load())
          AcademicRecordSearchHit(r.id, kind, r.title, {
            '자료 종류': r.type,
            '설명': r.description,
            if (r.fileName.isNotEmpty) '파일명': r.fileName,
          }),
      ];
    }
    return [
      for (final r in await api.records(kind: kind))
        AcademicRecordSearchHit(r.id, kind, r.title, {
          ...r.details,
          if (r.completion != null) '수강 상태': courseStatusLabel(r.completion!),
        }),
    ];
  }
}

/// Read-only lookup: no requirement response or record reference is written.
class StudentAcademicRecordSearch extends StatefulWidget {
  const StudentAcademicRecordSearch({super.key, required this.repository});
  final AcademicRecordSearchRepository repository;
  @override
  State<StudentAcademicRecordSearch> createState() => _SearchState();
}

class _SearchState extends State<StudentAcademicRecordSearch> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  bool _open = false, _loading = false;
  String _kind = 'all';
  int _generation = 0;
  final _results = <String, List<AcademicRecordSearchHit>>{};
  final _failed = <String>{};
  @override
  void didUpdateWidget(covariant StudentAcademicRecordSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository.api.ownerId != widget.repository.api.ownerId) {
      _generation++;
      _open = false;
      _loading = false;
      _kind = 'all';
      _query.clear();
      _results.clear();
      _failed.clear();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _results.clear();
      _failed.clear();
    });
    await Future.wait(
      academicSearchKinds.keys.map((kind) async {
        try {
          final records = await widget.repository.load(kind);
          if (mounted && generation == _generation) _results[kind] = records;
        } catch (_) {
          if (mounted && generation == _generation) _failed.add(kind);
        }
      }),
    );
    if (mounted && generation == _generation) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hits = [
      for (final entry in _results.entries)
        if (_kind == 'all' || _kind == entry.key)
          ...entry.value.where((r) => r.matches(_query.text)),
    ]..sort((a, b) => a.title.compareTo(b.title));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: Icon(_open ? Icons.expand_less : Icons.search),
            label: Text(_open ? '기록 검색 닫기' : '내 기록 찾기'),
            onPressed: () {
              setState(() => _open = !_open);
              if (_open && _results.isEmpty && !_loading) _load();
            },
          ),
        ),
        if (_open) ...[
          TextField(
            controller: _query,
            decoration: const InputDecoration(
              labelText: '내 기록 검색',
              hintText: '과목명·자격명·메모·날짜',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final entry in {'all': '전체', ...academicSearchKinds}.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _kind == entry.key,
                  onSelected: (_) => setState(() => _kind = entry.key),
                ),
              TextButton(
                onPressed: _loading ? null : _load,
                child: const Text('기록 다시 불러오기'),
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_failed.isNotEmpty)
            Text(
              '${_failed.map((k) => academicSearchKinds[k]).join('·')} 기록을 불러오지 못했습니다. 다시 불러오세요.',
            ),
          if (!_loading && hits.isEmpty)
            Text(
              _failed.isEmpty ? '검색 조건에 맞는 기록이 없습니다.' : '불러온 기록에서 검색 결과가 없습니다.',
            ),
          if (!_loading && hits.isNotEmpty) ...[
            Text('${hits.length}개 기록'),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    children: [
                      for (final hit in hits)
                        ExpansionTile(
                          key: ValueKey('${hit.kind}/${hit.id}'),
                          title: Text(hit.title),
                          subtitle: Text(
                            academicSearchKinds[hit.kind] ?? hit.kind,
                          ),
                          children: [
                            if (hit.details.isEmpty)
                              const Text('등록된 상세 내용이 없습니다.'),
                            for (final entry in hit.details.entries)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SelectableText(
                                    '${entry.key}: ${entry.value}',
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
