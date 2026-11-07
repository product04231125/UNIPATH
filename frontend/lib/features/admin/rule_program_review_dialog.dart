import 'package:flutter/material.dart';
import '../../shared/app_style.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/external_link_button.dart';
import '../auth/auth_api.dart';
import '../api/rule_program_api.dart';
import '../api/rule_program_models.dart';

class RuleProgramReviewDialog extends StatefulWidget {
  const RuleProgramReviewDialog({super.key, required this.gateway, required this.institutionId,
    this.ruleSetId, this.ruleId, required this.ensureAllowed});
  final ApiGateway gateway;
  final String institutionId;
  final String? ruleSetId, ruleId;
  final VoidCallback ensureAllowed;
  @override State<RuleProgramReviewDialog> createState() => _ReviewState();
}
class _ReviewState extends State<RuleProgramReviewDialog> {
  final _note = TextEditingController();
  final _changes = ChangeNotifier();
  final _checks = List.filled(4, false);
  final _headers = <OfficialProgramHeader>[];
  OfficialProgramView? _program;
  bool _busy = false, _refreshRequired = false, _denied = false;
  String? _error, _message;
  List<String> _fields = [];
  OfficialProgramAdminApi get _api => OfficialProgramAdminApi(widget.gateway);
  bool get _dirty => _note.text.isNotEmpty || _checks.any((value) => value);
  @override void initState() { super.initState(); _note.addListener(_changed); Future.microtask(_load); }
  void _changed() { if (mounted) setState(() {}); _changes.notifyListeners(); }
  @override void dispose() { _note.dispose(); _changes.dispose(); super.dispose(); }
  bool _matches(OfficialProgramView value) => value.institutionId == widget.institutionId &&
    value.ruleSetId == widget.ruleSetId && value.ruleId == widget.ruleId;
  Future<void> _run(Future<void> Function() action, {bool mutation = false}) async {
    if (_busy || _denied) return;
    setState(() { _busy = true; _error = null; _fields = []; });
    try {
      widget.ensureAllowed(); await action();
      if (mounted) widget.ensureAllowed();
    } catch (error) {
      if (!mounted) return;
      _error = error is AuthFailure ? error.message : '자료나 처리 결과를 확인하지 못했습니다. 다시 읽어 확인하세요.';
      if (error is AuthFailure) _fields = error.fields;
      if (error is AuthFailure && (error.status == 401 || error.status == 403)) {
        _denied = true; _program = null; _headers.clear();
      } else if ((mutation || _program != null) && !(error is AuthFailure && error.status == 422)) {
        _refreshRequired = true;
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _load() => _run(() async {
    final rows = <OfficialProgramHeader>[];
    final seen = <String>{}; String? cursor;
    do {
      final page = await _api.list(institutionId: widget.institutionId, ruleSetId: widget.ruleSetId, ruleId: widget.ruleId, cursor: cursor);
      if (!mounted) return; widget.ensureAllowed();
      rows.addAll(page.items.where((p) => p.institutionId == widget.institutionId && p.ruleSetId == widget.ruleSetId && p.ruleId == widget.ruleId));
      cursor = page.nextCursor;
      if (cursor != null && !seen.add(cursor)) throw const FormatException('Repeated cursor');
    } while (cursor != null);
    _headers..clear()..addAll(rows);
  });
  Future<void> _open(String id) async {
    if (_busy || _denied) return;
    if (_dirty && !await confirmInputDiscardAllowsLeave(context)) return;
    if (!mounted) return;
    await _run(() async {
      _program = null;
      final value = await _api.get(id);
      if (!mounted) return; widget.ensureAllowed();
      if (value.id != id || !_matches(value)) throw const FormatException('Program scope mismatch');
      _program = value; _refreshRequired = false; _message = null;
      _checks.fillRange(0, 4, false); _note.clear();
    });
  }
  Future<void> _decide(bool approve) async {
    final program = _program;
    if (program == null || _busy || _denied || _refreshRequired || _note.text.trim().isEmpty || _note.text.trim().length > 500) return;
    if (approve && (program.status != 'draft' || !_checks.every((v) => v) || program.missingRuleIds.isNotEmpty || program.rules.isEmpty)) return;
    if (!approve && program.status != 'approved') return;
    await _run(() async {
      final value = approve
        ? await _api.approve(program.id, OfficialProgramApprove(expectedVersion: program.version,
            conditionsVerified: _checks[0], sourcesVerified: _checks[1], applicabilityVerified: _checks[2],
            completeSourceContextVerified: _checks[3], reviewNote: _note.text.trim()))
        : await _api.revoke(program.id, OfficialProgramRevoke(expectedVersion: program.version, reason: _note.text.trim()));
      if (!mounted) return; widget.ensureAllowed();
      if (value.id != program.id || !_matches(value) || value.status != (approve ? 'approved' : 'revoked')) throw const FormatException('Decision response mismatch');
      _program = value;
      final index = _headers.indexWhere((row) => row.id == value.id);
      if (index >= 0) _headers[index] = OfficialProgramHeader.fromJson(value.toJson());
      _checks.fillRange(0, 4, false); _note.clear();
      _message = approve ? '실행본을 승인했습니다.' : '실행본을 회수했습니다.';
    }, mutation: true);
  }
  String _status(String value) => switch(value) { 'draft' => '초안', 'approved' => '승인됨', 'revoked' => '회수됨', _ => '확인 필요' };
  static const _labels = {'kind':'조건 종류','minimum':'최소값','category':'이수구분','courses':'필수 과목','course_id':'과목 ID',
    'expected_version':'검토 버전','minimum_credits':'최소 학점','minimum_grade_points':'최소 평점','comparison_grade_scale':'평점 척도',
    'certificates':'대상 자격','certificate_id':'자격 ID','thesis_type':'논문·작품 종류','requires_approval':'승인 필요','accepted_grades':'허용 성적','instruction':'직접 확인할 문장'};
  String _describe(Object? value) {
    if (value is Map) return value.entries.map((e) => '${_labels[e.key] ?? e.key}: ${e.key == 'kind' ? (const {'minimum_credits':'최소 학점','required_courses':'필수 과목','minimum_volunteer_hours':'최소 봉사 시간','any_certificate':'지정 자격','thesis':'논문·졸업작품','manual_review':'직접 확인'}[e.value] ?? '확인 필요') : _describe(e.value)}').join(' · ');
    if (value is List) return value.map(_describe).join(' / ');
    if (value is bool) return value ? '예' : '아니요';
    return value?.toString() ?? '없음';
  }
  @override Widget build(BuildContext context) {
    final program = _program;
    final validNote = _note.text.trim().isNotEmpty && _note.text.trim().length <= 500;
    return InputDialog(
      title: const Text('실행본 승인·회수 검토'), changes: _changes, hasContent: () => _dirty,
      hasUnsavedChanges: () => _dirty, saving: _busy,
      content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_busy) const LinearProgressIndicator(),
        if (!_denied) ...[
          OutlinedButton(onPressed: _busy ? null : _load, child: const Text('실행본 목록 다시 읽기')),
          if (_headers.isEmpty && !_busy) const Text('저장된 실행본이 없습니다.'),
          for (final row in _headers) TextButton(key: ValueKey('review-program-${row.id}'), onPressed: _busy ? null : () => _open(row.id),
            child: Text('${row.name} · ${_status(row.status)} · v${row.version}')),
          if (program != null) ...[
            FeatureLine.section(text: '${program.name} · ${_status(program.status)}'),
            Text('입학연도 ${program.admissionYearFrom}~${program.admissionYearTo} · ${program.tracks.join(', ')}'),
            Text('학교 ${program.institutionId} · 학과 ${program.departmentId ?? '전체'} · 교육과정 ${program.curriculumId ?? '전체'}'),
            Text('원본 버전 ${program.sourceVersion} · 실행본 버전 ${program.version}'),
            Text('적용 기간 ${program.effectiveFrom ?? '시작 제한 없음'} ~ ${program.effectiveTo ?? '종료 제한 없음'}'),
            if (program.missingRuleIds.isNotEmpty) Text('조건이 없는 요건 ${program.missingRuleIds.length}개'),
            for (final rule in program.rules) ...[
              FeatureLine.section(text: rule.title),
              SelectableText(_describe(rule.condition.toJson())),
              for (final reference in rule.references) Text('${reference.name} · ${reference.code} · 검토 버전 ${reference.version}'),
              if (rule.evidence.isEmpty) const Text('근거 문단 없는 직접 확인 요건입니다.'),
              for (final source in rule.evidence) ...[
                Text('${source.title} · ${source.page}쪽 · 문서 버전 ${source.documentVersion}'),
                SelectableText(source.excerpt),
                ExternalLinkButton(url: source.sourceUrl, label: '전체 원문 확인'),
              ],
            ],
            if (program.reviewNote.isNotEmpty) Text('검토 메모: ${program.reviewNote}'),
            if (program.revocationReason.isNotEmpty) Text('회수 사유: ${program.revocationReason}'),
            if (_refreshRequired) ...[
              const Text('버전 또는 처리 결과를 다시 확인해야 합니다. 자동 재전송하지 않습니다.'),
              OutlinedButton(onPressed: _busy ? null : () => _open(program.id), child: const Text('선택 실행본 다시 읽기')),
            ],
            if (program.status == 'draft') ...[
              for (var i = 0; i < 4; i++) CheckboxListTile(key: ValueKey('program-review-check-$i'), value: _checks[i],
                onChanged: _busy || _refreshRequired ? null : (value) { _checks[i] = value == true; _changed(); },
                title: Text(const ['수치·종류·비교 조건을 확인했습니다.', '출처를 확인했습니다.', '학교·학과·교육과정·연도·이수 경로를 확인했습니다.', '예외·부칙을 포함한 전체 원문 문맥을 확인했습니다.'][i])),
            ],
            if (program.status != 'revoked') FieldLabel(label: program.status == 'draft' ? '검토 메모 (필수)' : '회수 사유 (필수)', child: TextField(
              key: const ValueKey('program-review-note'), controller: _note, enabled: !_busy && !_refreshRequired, maxLength: 500,
              decoration: InputDecoration(errorText: _fields.any((f) => f.endsWith('review_note') || f.endsWith('reason')) ? '입력을 확인하세요.' : null),
            )),
          ],
        ],
        if (_error != null) Semantics(liveRegion:true, child: Text(_error!)),
        if (_message != null) Semantics(liveRegion:true, child: Text(_message!)),
      ]),
      actions: [
        TextButton(onPressed: _busy ? null : () => InputDialog.cancel<void>(context), child: const Text('닫기')),
        if (!_denied && program?.status == 'draft') FilledButton(key: const ValueKey('program-review-approve'),
          onPressed: _busy || _refreshRequired || !validNote || !_checks.every((v) => v) || program!.missingRuleIds.isNotEmpty || program.rules.isEmpty ? null : () => _decide(true), child: const Text('검토 완료·승인')),
        if (!_denied && program?.status == 'approved') FilledButton(key: const ValueKey('program-review-revoke'), style: destructiveButtonStyle(context),
          onPressed: _busy || _refreshRequired || !validNote ? null : () => _decide(false), child: const Text('실행본 회수')),
      ],
    );
  }
}
