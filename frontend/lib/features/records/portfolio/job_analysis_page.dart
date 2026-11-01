import 'package:flutter/material.dart';

import '../../../shared/widgets/content_scroll_view.dart';
import '../../../shared/widgets/field_label.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/surface_card.dart';
import '../personal_record_repository.dart';
import '../personal_repository_scope.dart';

class JobAnalysisPage extends StatefulWidget {
  const JobAnalysisPage({super.key});

  @override
  State<JobAnalysisPage> createState() => JobAnalysisPageState();
}

class JobAnalysisPageState extends State<JobAnalysisPage> {
  static const _kinds = [
    PersonalRecordKind.activity,
    PersonalRecordKind.experience,
    PersonalRecordKind.credential,
    PersonalRecordKind.course,
    PersonalRecordKind.portfolio,
  ];
  static const _kindLabels = {
    PersonalRecordKind.activity: '활동',
    PersonalRecordKind.experience: '경험',
    PersonalRecordKind.credential: '자격',
    PersonalRecordKind.course: '수강',
    PersonalRecordKind.portfolio: '성과',
  };

  final _posting = TextEditingController();
  final _url = TextEditingController();
  final _selected = <String>{};
  final _records = <PersonalRecordKind, List<PersonalRecord>>{};
  var _loading = true;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _posting.addListener(_onInput);
    _url.addListener(_onInput);
    _load();
  }

  @override
  void dispose() {
    _posting.removeListener(_onInput);
    _url.removeListener(_onInput);
    _posting.dispose();
    _url.dispose();
    super.dispose();
  }

  void _onInput() {
    if (mounted) setState(() {});
  }

  bool get _urlInvalid {
    final text = _url.text.trim();
    if (text.isEmpty) return false;
    final uri = Uri.tryParse(text);
    return uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty;
  }

  String get _unavailableReason {
    final reasons = <String>[
      '학생용 채용 분석 API가 아직 없습니다. 공고 텍스트, 주소, 선택한 기록을 서버로 보내지 않았고 답변을 만들지 않았습니다.',
    ];
    if (_posting.text.trim().isEmpty && _url.text.trim().isEmpty) {
      reasons.add('비교할 공고 텍스트와 주소가 없습니다.');
    }
    if (_urlInvalid) {
      reasons.add('주소가 http:// 또는 https:// 로 시작하는 형식이 아닙니다.');
    }
    return reasons.join(' ');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final scope = PersonalRepositoryScope.read(context);
      final loaded = <PersonalRecordKind, List<PersonalRecord>>{};
      for (final kind in _kinds) {
        final repo = scope?.records(kind) ?? PersonalRecordRepository(kind);
        await repo.load();
        loaded[kind] = repo.records;
      }
      if (mounted) {
        setState(() {
          _records
            ..clear()
            ..addAll(loaded);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  String _key(PersonalRecordKind kind, PersonalRecord record) =>
      '${kind.name}/${record.id}';

  @override
  Widget build(BuildContext context) => ContentScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: '채용공고 분석',
          description: '공고 텍스트와 주소를 준비합니다. 분석을 할 수 없으면 그 이유를 표시합니다.',
        ),
        const SizedBox(height: 16),
        FieldLabel(
          label: '채용공고 텍스트',
          child: TextFormField(
            key: const ValueKey('job-posting-text'),
            controller: _posting,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(hintText: '비교할 공고 본문을 붙여 넣으세요.'),
          ),
        ),
        const SizedBox(height: 16),
        FieldLabel(
          label: '채용공고 주소',
          child: TextFormField(
            key: const ValueKey('job-posting-url'),
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://',
              errorText: _urlInvalid
                  ? 'http:// 또는 https:// 로 시작하는 주소를 입력하세요.'
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '비교에 넣을 개인 기록',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text('학생이 고른 항목만 포함합니다. 기록을 자동으로 넣거나 분석하지 않습니다.'),
              const SizedBox(height: 12),
              if (_loading)
                const LinearProgressIndicator()
              else if (_failed) ...[
                const Text('개인 기록을 읽지 못했습니다. 선택한 항목은 유지합니다.'),
                TextButton(onPressed: _load, child: const Text('다시 읽기')),
              ] else if (_records.values.every((list) => list.isEmpty))
                const Text(
                  '선택할 개인 기록이 없습니다. 활동·수강·자격 메뉴에서 기록을 추가한 뒤 다시 열어 주세요.',
                )
              else
                for (final kind in _kinds)
                  if ((_records[kind] ?? const []).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        _kindLabels[kind]!,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    for (final record in _records[kind]!)
                      Row(
                        children: [
                          Checkbox(
                            key: ValueKey('job-record-${_key(kind, record)}'),
                            value: _selected.contains(_key(kind, record)),
                            onChanged: (value) {
                              setState(() {
                                final key = _key(kind, record);
                                if (value == true) {
                                  _selected.add(key);
                                } else {
                                  _selected.remove(key);
                                }
                              });
                            },
                          ),
                          Expanded(child: Text(record.value('title'))),
                        ],
                      ),
                  ],
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('선택한 기록 ${_selected.length}개'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('분석 상태', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Text('상태: 분석할 수 없음'),
              const SizedBox(height: 8),
              Text(
                '이유: $_unavailableReason',
                key: const ValueKey('job-analysis-reason'),
              ),
              const SizedBox(height: 8),
              const Text('답변: 받은 답변 없음'),
              const SizedBox(height: 8),
              const Text('근거: 받은 근거 없음'),
              const SizedBox(height: 8),
              const Text('불확실한 부분: 받은 내용 없음'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const FilledButton(onPressed: null, child: Text('분석 실행 불가 · 연결 전')),
      ],
    ),
  );
}
