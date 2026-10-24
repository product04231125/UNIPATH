import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../api/graduation_api.dart';
import '../records/personal_record_repository.dart';
import 'school_context_form.dart';
import '../../shared/widgets/content_scroll_view.dart';
import '../../shared/widgets/external_link_button.dart';
import '../../shared/widgets/page_header.dart';

String auditStatus(String value) => switch (value) {
  'satisfied' => '충족',
  'not_satisfied' => '미충족',
  'needs_review' => '확인 필요',
  'not_applicable' => '적용 기준 없음',
  _ => '상태 확인 필요',
};

class OfficialGraduationPage extends StatefulWidget {
  const OfficialGraduationPage({
    super.key,
    required this.auth,
    required this.ownerId,
    required this.onPersonal,
  });
  final AuthApi auth;
  final String ownerId;
  final VoidCallback onPersonal;
  @override
  State<OfficialGraduationPage> createState() => _OfficialGraduationState();
}

class _OfficialGraduationState extends State<OfficialGraduationPage> {
  late final _api = GraduationApi.forOwner(widget.auth, widget.ownerId);
  late final _gateway = widget.auth.forOwner(widget.ownerId);
  final _context = GlobalKey<SchoolContextFormState>();
  List<GraduationAuditHeader> _history = [];
  GraduationAuditView? _result;
  String? _cursor, _error, _fingerprint;
  String _clientId = PersonalRecord.newId();
  bool _busy = false, _loading = true, _uncertain = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.list(cursor: more ? _cursor : null);
      if (mounted) {
        setState(() {
          _history = [if (more) ..._history, ...page.items];
          _cursor = page.nextCursor;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AuthFailure
              ? e.message
              : '감사 이력을 읽지 못했습니다. 다시 읽기를 눌러 확인하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run() async {
    if (_busy) return;
    _context.currentState?.showErrors([]);
    final selected = _context.currentState?.value;
    final date = _context.currentState?.asOf;
    if (selected == null || date == null) {
      setState(() => _error = '학교·학과·교육과정·입학연도·이수 경로와 올바른 기준일을 확인하세요.');
      return;
    }
    final fingerprint = '${selected.toJson()}|$date';
    if (_fingerprint != null && _fingerprint != fingerprint) {
      if (_uncertain) {
        setState(
          () => _error = '앞선 감사 결과를 확인하지 못했습니다. 원래 기준으로 다시 시도하거나 이력을 확인하세요.',
        );
        return;
      }
      _clientId = PersonalRecord.newId();
    }
    _fingerprint = fingerprint;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _api.create(
        GraduationAuditCreate(
          context: selected,
          asOf: date,
          clientId: _clientId,
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _uncertain = false;
        _fingerprint = null;
        _clientId = PersonalRecord.newId();
      });
      await _load();
    } catch (e) {
      if (e is AuthFailure) _context.currentState?.showErrors(e.fields);
      if (mounted) {
        setState(() {
          _uncertain =
              e is! AuthFailure || e.status == null || e.status! >= 500;
          _error = e is AuthFailure
              ? '${e.message}\n선택한 기준과 입력을 유지했습니다.'
              : '결과를 확인하지 못했습니다. 같은 기준으로 재시도하거나 이력을 확인하세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detail(String id) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _api.get(id);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AuthFailure
              ? e.message
              : '이력의 상세와 현재 사용 가능 여부를 확인하지 못했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ContentScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: '학교 검토 자료 기준 졸업요건 감사',
          description: '학교가 검토한 규정과 승인 기록을 비교합니다. 학교의 최종 학위 수여 승인을 대신하지 않습니다.',
          actions: [
            TextButton(
              onPressed: _busy ? null : widget.onPersonal,
              child: const Text('내 학교·학과 기준 설정'),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SchoolContextForm(
              key: _context,
              api: _gateway,
              disabled: _busy,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _busy || _loading ? null : _run,
            child: Text(_busy ? '처리 중…' : '졸업요건 감사 실행'),
          ),
        ),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (_loading || _busy) const LinearProgressIndicator(),
        if (_result case final r?) ...[
          const SizedBox(height: 16),
          Text(
            '감사 결과 · ${auditStatus(r.status)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            '기준일 ${r.evaluatedOn} · 입학연도 ${r.context.admissionYear} · ${r.context.track}',
          ),
          Text(
            r.catalogComplete ? '전체 적용 규정 검토 확인됨' : '전체 적용 규정 검토가 완료되지 않았습니다.',
          ),
          Text(
            r.eligibleAsOf
                ? '당시 기준일에 요건 충족이 확인됐습니다.'
                : '당시 기준일의 전체 요건 충족으로 확인되지 않았습니다.',
          ),
          Text(
            r.currentUsable
                ? '현재 사용할 수 있는 근거입니다.'
                : '현재 사용할 수 없는 근거입니다. 재검토 후 새 감사를 실행하세요.',
          ),
          if (r.issues.isNotEmpty || r.currentIssues.isNotEmpty)
            const Text('규정 또는 승인 기록의 검토가 필요합니다. 학교 담당자에게 확인하세요.'),
          for (final row in r.results)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${row.title} · ${auditStatus(row.status)}'),
                    if (row.current != null)
                      Text(
                        '확인 값 ${row.current} · 필요 값 ${row.required ?? '미확인'} · 부족 값 ${row.deficit ?? '미확인'}',
                      ),
                    if (row.missingCourseIds.isNotEmpty)
                      Text('미이수 확인 과목 ${row.missingCourseIds.length}개'),
                    if (row.uncertainCourseIds.isNotEmpty)
                      Text('확인 필요 과목 ${row.uncertainCourseIds.length}개'),
                  ],
                ),
              ),
            ),
          Text('판정 근거', style: Theme.of(context).textTheme.titleMedium),
          for (final program in r.criteria) ...[
            Text('${program.name} · 판 ${program.sourceVersion}'),
            for (final rule in program.rules) ...[
              Text(rule.title),
              for (final source in rule.evidence) ...[
                Text(
                  '${source.title} · ${source.page}쪽 · 문서 판 ${source.documentVersion}',
                ),
                ExternalLinkButton(url: source.sourceUrl, label: '규정 원문 확인'),
              ],
            ],
          ],
          for (final evidence in r.recordEvidence)
            Text('승인 기록 근거 · 원본 ${evidence.sourcePage}쪽'),
          if (r.criteria.isEmpty) const Text('사용한 규정 근거가 없습니다.'),
        ],
        const SizedBox(height: 20),
        Text('감사 이력', style: Theme.of(context).textTheme.titleLarge),
        TextButton(
          onPressed: _busy || _loading ? null : _load,
          child: const Text('감사 이력 다시 읽기'),
        ),
        if (!_loading && _history.isEmpty) const Text('저장된 감사 이력이 없습니다.'),
        for (final row in _history)
          Card(
            child: ListTile(
              title: Text('${row.evaluatedOn} · ${auditStatus(row.status)}'),
              subtitle: const Text('당시 결과입니다. 상세에서 현재 사용 가능 여부를 확인하세요.'),
              onTap: _busy ? null : () => _detail(row.id),
            ),
          ),
        if (_cursor != null)
          TextButton(
            onPressed: _busy || _loading ? null : () => _load(more: true),
            child: const Text('감사 이력 더 보기'),
          ),
      ],
    ),
  );
}
