import 'package:flutter/material.dart';

import '../api/school_knowledge_api.dart';
import '../api/school_knowledge_models.dart';
import '../auth/auth_api.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/external_link_button.dart';
import 'school_context_form.dart';

String searchFieldLabel(String name) =>
    const {
      'institution_id': '학교',
      'department_id': '학과',
      'curriculum_id': '교육과정',
      'admission_year': '입학연도',
      'track': '이수 경로',
      'question': '검색 질문',
    }[name.split('.').last] ??
    '학교 적용 정보';

class SchoolDocumentSearchDialog extends StatefulWidget {
  const SchoolDocumentSearchDialog({
    super.key,
    required this.auth,
    required this.ownerId,
  });
  final AuthApi auth;
  final String ownerId;
  @override
  State<SchoolDocumentSearchDialog> createState() => _SearchState();
}

class _SearchState extends State<SchoolDocumentSearchDialog> {
  late final _gateway = widget.auth.forOwner(widget.ownerId);
  late final _api = SchoolKnowledgeApi(_gateway);
  final _context = GlobalKey<SchoolContextFormState>();
  final _question = TextEditingController();
  final _changes = ValueNotifier(0);
  SchoolKnowledgeSearchResponse? _result;
  String? _error;
  List<String> _fields = [];
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _question.addListener(_invalidate);
  }

  @override
  void dispose() {
    _question.dispose();
    _changes.dispose();
    super.dispose();
  }

  void _invalidate() {
    if (mounted) {
      setState(() {
        _result = null;
        _changes.value++;
      });
    }
  }

  Future<void> _search() async {
    if (_busy) return;
    final form = _context.currentState;
    final school = form?.institutionId, department = form?.departmentId;
    final yearText = form?.year.text.trim() ?? '',
        track = form?.track.text.trim() ?? '';
    final year = int.tryParse(yearText);
    final question = _question.text.trim();
    if (school == null ||
        department == null ||
        question.isEmpty ||
        question.length > 4000 ||
        yearText.isNotEmpty && (year == null || year < 1000 || year > 9999) ||
        track.length > 64) {
      setState(() {
        _error = '등록 학교·학과와 검색 질문을 입력하세요. 입학연도·이수 경로를 입력했다면 형식도 확인하세요.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fields = [];
      _result = null;
    });
    form!.showErrors([]);
    try {
      final result = await _api.search(
        SchoolKnowledgeSearch(
          question: question,
          context: SchoolKnowledgeContext(
            institutionId: school,
            departmentId: department,
            curriculumId: form.curriculumId,
            admissionYear: year,
            track: track.isEmpty ? null : track,
          ),
        ),
      );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is AuthFailure
              ? '${e.message}\n검색 질문과 학교 선택을 유지했습니다.'
              : '검색 결과를 확인하지 못했습니다. 질문과 선택을 유지했으니 다시 검색하세요.';
          _fields = e is AuthFailure ? e.fields : [];
          form.showErrors(_fields);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    title: const Text('학교 문서 검색·근거'),
    changes: Listenable.merge([_changes, _question]),
    saving: _busy,
    hasContent: () =>
        _question.text.isNotEmpty ||
        (_context.currentState?.hasSelection ?? false) ||
        (_context.currentState?.year.text.isNotEmpty ?? false) ||
        (_context.currentState?.track.text.isNotEmpty ?? false),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '학교가 본문 검색용으로 승인한 문서에서 근거를 찾습니다. 문서 적용만으로 검색 승인되지 않으며, 검색 결과는 졸업요건 판정이 아닙니다.',
        ),
        SchoolContextForm(
          key: _context,
          api: _gateway,
          disabled: _busy,
          showDate: false,
          onChanged: _invalidate,
        ),
        const Text('입학연도·이수 경로가 없으면 추가 정보를 요청할 수 있습니다. 학교 선택은 공식 학적 인증이 아닙니다.'),
        TextField(
          controller: _question,
          enabled: !_busy,
          minLines: 2,
          maxLines: 5,
          maxLength: 4000,
          decoration: InputDecoration(
            labelText: '검색 질문',
            errorText:
                _fields.any((f) => f == 'question' || f.endsWith('.question'))
                ? '검색 질문을 확인하세요.'
                : null,
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (_result case final r?) ...[
          Semantics(
            liveRegion: true,
            child: Text(switch (r.status) {
              'evidence_found' => '승인된 문서에서 근거를 찾았습니다.',
              'insufficient_evidence' => '조건에 맞는 승인 근거가 부족합니다. 적용 학교·교육과정·연도를 확인하거나 학교 담당자에게 자료 검토를 요청하세요.',
              'needs_user_input' => '적용 범위를 확인할 추가 정보가 필요합니다.',
              _ => '문서 검색을 완료하지 못했습니다. 잠시 후 다시 검색하세요.',
            }),
          ),
          if (r.missingFields.isNotEmpty)
            Text('추가 확인: ${r.missingFields.map(searchFieldLabel).join(', ')}'),
          for (final source in r.sources)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${source.title} · ${source.page}쪽',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SelectableText(source.excerpt),
                    ExternalLinkButton(
                      url: source.sourceUrl,
                      label: '공식 원문 확인',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => InputDialog.cancel<void>(context),
        child: const Text('닫기'),
      ),
      FilledButton(
        onPressed: _busy ? null : _search,
        child: Text(_busy ? '검색 중…' : '학교 문서 검색'),
      ),
    ],
  );
}
