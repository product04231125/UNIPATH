import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/content_scroll_view.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/surface_card.dart';
import '../api/personal_evaluation_api.dart';
import '../api/student_api.dart';
import '../api/student_api_models.dart';
import 'personal_calculation_controller.dart';
import 'personal_calculation_draft.dart';

class PersonalCalculationPage extends StatefulWidget {
  const PersonalCalculationPage({super.key, required this.controller});
  final PersonalCalculationController controller;
  @override
  State<PersonalCalculationPage> createState() =>
      _PersonalCalculationPageState();
}

class _PersonalCalculationPageState extends State<PersonalCalculationPage> {
  final _form = GlobalKey<FormState>();
  final _resultKey = GlobalKey();
  PersonalCalculationController get c => widget.controller;
  Future<void> _revealResult() async {
    if (!mounted || c.result == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final target = _resultKey.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 200),
      );
    }
  }

  Future<void> _calculate() async {
    await c.calculate();
    await _revealResult();
  }

  Future<void> _openResult(String id) async {
    await c.openResult(id);
    await _revealResult();
  }

  @override
  void initState() {
    super.initState();
    if (c.curricula.isEmpty && c.sources == null && !c.loading) {
      c.loadCurricula();
    }
    if (c.history.isEmpty && !c.historyLoading) c.loadHistory();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 작성'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _select(String id) async {
    if (c.locked) return;
    if (c.hasDraft &&
        !await _confirm(
          '조건을 다시 준비할까요?',
          '현재 작성한 계산 조건을 비우고 선택한 교육과정의 서버 자료를 다시 읽습니다. 저장된 기록과 계산 이력은 유지합니다.',
          '다시 불러오기',
        )) {
      return;
    }
    if (mounted) await c.select(id);
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
  Widget _error(String? text) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Semantics(
            liveRegion: true,
            child: Text(
              text,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );
  Widget _field(
    Map<String, String> values,
    String key,
    String label, {
    bool number = false,
    bool optional = false,
    int maxLength = 128,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextFormField(
      key: ValueKey('${identityHashCode(values)}-$key'),
      initialValue: values[key] ?? '',
      readOnly: c.locked,
      maxLength: number ? 32 : maxLength,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 5,
        counterText: '',
      ),
      onChanged: (value) => values[key] = value,
      validator: (value) => number
          ? validateCalculationAmount(value, optional: optional)
          : ((!optional && (value?.trim().isEmpty ?? true))
                ? '$label 입력이 필요합니다.'
                : null),
    ),
  );
  Widget _choice(
    Map<String, String> values,
    String key,
    String label,
    Map<String, String> options,
    String fallback,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: AnchoredSelectField<String>(
      value: values[key] ?? fallback,
      label: label,
      externalLabel: true,
      options: [for (final e in options.entries) SelectOption(e.key, e.value)],
      onChanged: (value) {
        if (!c.locked) setState(() => values[key] = value);
      },
    ),
  );
  Widget _check(
    String label,
    bool value,
    ValueChanged<bool> change, {
    String? subtitle,
  }) => Material(
    type: MaterialType.transparency,
    child: CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: c.locked ? null : (value) => setState(() => change(value!)),
    ),
  );
  String _id(String id) => id.substring(0, 8);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => ContentScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            title: '개인 기준 계산',
            contextLabel: PersonalEvaluationSummary.personalLabel,
            description: '서버에 저장한 본인 자료와 아래에서 직접 정한 조건으로 계산합니다. 학교 확인·승인이나 공식 졸업 판정을 대신하지 않습니다.',
          ),
          const SizedBox(height: 12),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading('1. 교육과정과 기준일'),
                if (c.loading) const LinearProgressIndicator(),
                if (c.curricula.isNotEmpty)
                  Semantics(
                    enabled: !c.locked,
                    child: IgnorePointer(
                      ignoring: c.locked,
                      child: ExcludeFocus(
                        excluding: c.locked,
                        child: AnchoredSelectField<String>(
                          value: c.sources?.curriculum.id ?? '',
                          label: '계산할 개인 교육과정',
                          externalLabel: true,
                          searchable: true,
                          options: [
                            const SelectOption('', '교육과정을 선택하세요'),
                            for (final row in c.curricula)
                              SelectOption(
                                row.id,
                                '${row.data.title} · ${row.data.curriculumYear} · ${_id(row.id)}',
                              ),
                          ],
                          onChanged: (id) {
                            if (id.isNotEmpty) _select(id);
                          },
                        ),
                      ),
                    ),
                  ),
                if (!c.loading && c.curricula.isEmpty && c.sourceError == null)
                  const Text('계산할 교육과정이 없습니다. 교육과정 탭에서 먼저 등록하세요.'),
                _error(c.sourceError),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: c.locked
                        ? null
                        : () => c.sources == null
                              ? c.loadCurricula()
                              : _select(c.sources!.curriculum.id),
                    icon: const Icon(Icons.refresh),
                    label: const Text('자료 다시 불러오기'),
                  ),
                ),
                TextFormField(
                  key: const ValueKey('calculation-as-of'),
                  initialValue: c.asOf,
                  readOnly: c.locked,
                  decoration: InputDecoration(
                    labelText: '계산 기준일 · YYYY-MM-DD',
                    helperText: '초기값은 UTC 오늘입니다. 이 날짜에 활성인 모든 규칙을 결과에 포함합니다.',
                    helperMaxLines: 4,
                    errorText: validateCalculationDay(c.asOf),
                  ),
                  onChanged: (value) => setState(() => c.asOf = value),
                  validator: validateCalculationDay,
                ),
                if (c.sources case final sources?) ...[
                  Text(
                    '불러온 교육과정 버전 ${sources.curriculum.version} · 과목 ${sources.links.length}개 · 규칙 ${sources.rules.length}개',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '조건 설명·필요한 값·현재 값·문자 성적은 자동 해석하지 않습니다. 조건을 지정하지 않은 활성 규칙은 확인 필요로 남습니다. 선택하지 않은 자료는 합산하지 않습니다.',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (c.sources case final sources?)
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _heading('2. 규칙별 명시적 조건'),
                  if (sources.rules.isEmpty)
                    const Text('이 교육과정에 규칙이 없습니다. 계산하면 적용 규칙 없음으로 저장합니다.'),
                  if (validateCalculationDay(c.asOf) != null)
                    const Text('기준일을 확인하세요. 유효한 날짜를 입력하면 적용 규칙을 표시합니다.'),
                  for (final rule in sources.rules)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              rule.data.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '규칙 버전 ${rule.version} · ${rule.data.effectiveFrom ?? '시작 제한 없음'} ~ ${rule.data.effectiveTo ?? '종료 제한 없음'}',
                            ),
                            Text('기록한 조건 설명: ${rule.data.condition}'),
                            if (validateCalculationDay(c.asOf) == null &&
                                sources.active(rule, c.asOf))
                              Semantics(
                                enabled: !c.locked,
                                child: IgnorePointer(
                                  ignoring: c.locked,
                                  child: ExcludeFocus(
                                    excluding: c.locked,
                                    child: _condition(
                                      rule,
                                      sources,
                                      c.drafts[rule.id]!,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const Text('기준일에 적용되지 않는 규칙 · 이번 계산에서 제외합니다.'),
                          ],
                        ),
                      ),
                    ),
                  _error(c.actionError),
                  if (c.pending != null)
                    const Text(
                      '전송한 조건과 자료 버전은 고정되어 있습니다. 응답 확인 실패 시 같은 요청으로 재시도하세요. 앱을 종료하면 작성 중 조건은 사라지므로, 다시 시작한 뒤에는 저장 이력을 먼저 확인하세요.',
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: c.busy || c.loading || c.sourceError != null
                            ? null
                            : () {
                                if (c.pending != null ||
                                    (_form.currentState?.validate() ?? false)) {
                                  _calculate();
                                }
                              },
                        icon: const Icon(Icons.calculate_outlined),
                        label: Text(
                          c.busy
                              ? '확인 중…'
                              : c.pending == null
                              ? '계산하고 결과 저장'
                              : '같은 요청으로 다시 확인',
                        ),
                      ),
                      if (c.pending != null)
                        OutlinedButton(
                          onPressed: c.busy
                              ? null
                              : () async {
                                  if (await _confirm(
                                        '새 계산을 준비할까요?',
                                        '이전 요청이 이미 저장되었을 수 있습니다. 아래 이력을 먼저 확인하세요. 새 계산은 별도 결과를 생성하며 기존 이력을 삭제하지 않습니다.',
                                        '새 계산 준비',
                                      ) &&
                                      mounted) {
                                    c.newCalculation();
                                  }
                                },
                          child: const Text('새 계산 준비'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (c.sources == null) _error(c.actionError),
          const SizedBox(height: 16),
          if (c.result case final result?) _result(result),
          const SizedBox(height: 12),
          _history(),
        ],
      ),
    ),
  );

  Widget _condition(
    StudentRecord<StudentPersonalGraduationRuleCreate> rule,
    PersonalCalculationSources s,
    PersonalCalculationDraft draft,
  ) => Column(
    key: ValueKey('condition-${rule.id}-${identityHashCode(draft)}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      AnchoredSelectField<String>(
        value: draft.kind,
        label: '실행할 계산 조건',
        externalLabel: true,
        options: [
          for (final e in personalConditionLabels.entries)
            SelectOption(e.key, e.value),
        ],
        onChanged: (value) {
          if (!c.locked) {
            setState(() {
              draft.kind = value;
              draft.values.clear();
              draft.selected.clear();
              draft.observations.clear();
              draft.allCourses = false;
            });
          }
        },
      ),
      KeyedSubtree(
        key: ValueKey(draft.kind),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (draft.kind == 'minimum_credits' ||
                draft.kind == 'minimum_volunteer_hours')
              _field(
                draft.values,
                'minimum',
                draft.kind == 'minimum_credits' ? '최소 학점' : '최소 봉사 시간',
                number: true,
              ),
            if (draft.kind == 'minimum_credits') ...[
              _field(
                draft.values,
                'category',
                '이수구분 필터 · 선택',
                optional: true,
                helper: '수강 기록의 이수구분과 정확히 같은 값만 합산합니다. 비워두면 전체 분류입니다.',
              ),
              _check(
                '불러온 연결 수강 기록 전체 선택',
                draft.allCourses,
                (value) => draft.allCourses = value,
              ),
              const Text(
                '교육과정 과목에 연결된 수강 기록만 선택합니다. 이수 기록 상태의 실제 학점을 합산하며, 예정·진행 중은 충족 근거가 아닙니다.',
              ),
              if (!draft.allCourses)
                for (final row in s.linkedCourses)
                  _check(
                    '${row.data.title} · ${row.data.term} · ${_id(row.id)}',
                    draft.selected.contains(row.id),
                    (value) => value
                        ? draft.selected.add(row.id)
                        : draft.selected.remove(row.id),
                    subtitle:
                        '${row.data.credits}학점 · ${row.data.category} · ${row.data.completion}',
                  ),
              if (s.linkedCourses.isEmpty)
                const Text('연결된 수강 기록이 없습니다. 빈 선택은 0개 자료로 계산합니다.'),
            ],
            if (draft.kind == 'minimum_volunteer_hours') ...[
              const Text(
                '개인 활동에 직접 기록한 승인 상태·승인 시간·관찰일을 사용합니다. 보고 시간은 합산하지 않습니다. 이 입력은 학교의 승인 확인이 아닙니다.',
              ),
              for (final row in s.activities)
                _check(
                  '${row.data.title} · ${_id(row.id)}',
                  draft.selected.contains(row.id),
                  (value) => value
                      ? draft.selected.add(row.id)
                      : draft.selected.remove(row.id),
                  subtitle:
                      '승인 시간 ${row.data.approvedHours ?? '미기록'} · 상태 ${row.data.approval ?? '미기록'} · 관찰일 ${row.data.observedOn ?? '미기록'}',
                ),
              if (s.activities.isEmpty)
                const Text('활동이 없습니다. 빈 선택은 0개 자료로 계산합니다.'),
            ],
            if (draft.kind == 'required_courses') ...[
              const Text(
                '필수로 계산할 교육과정 과목을 선택하세요. 점수와 비교 척도는 직접 입력하며 A+ 같은 문자 성적을 자동 환산하지 않습니다.',
              ),
              if (s.links.isEmpty) const Text('교육과정 과목을 먼저 등록하세요.'),
              for (final row in s.links) ...[
                _check(
                  '${row.data.title} · ${row.data.courseCode} · ${_id(row.id)}',
                  draft.selected.contains(row.id),
                  (value) => value
                      ? draft.selected.add(row.id)
                      : draft.selected.remove(row.id),
                  subtitle: row.data.courseRecordId == null
                      ? '수강 기록 연결 없음'
                      : '연결 수강 ${row.data.courseRecordId}',
                ),
                if (draft.selected.contains(row.id)) ...[
                  _field(
                    draft.observation(row.id),
                    'minimumCredits',
                    '이 과목의 최소 학점 · 선택',
                    number: true,
                    optional: true,
                  ),
                  _field(
                    draft.observation(row.id),
                    'minimumGradePoints',
                    '최소 성적 점수 · 선택',
                    number: true,
                    optional: true,
                  ),
                  _field(
                    draft.observation(row.id),
                    'comparisonGradeScale',
                    '비교 척도 · 성적 기준과 함께 입력',
                    optional: true,
                    helper: '예: 4.5. 학교 성적을 자동 변환하지 않습니다.',
                  ),
                  if (row.data.courseRecordId != null) ...[
                    _field(
                      draft.observation(row.id),
                      'points',
                      '연결 수강 기록의 내 성적 점수 · 선택',
                      number: true,
                      optional: true,
                    ),
                    _field(
                      draft.observation(row.id),
                      'scale',
                      '내 성적 척도 · 점수와 함께 입력',
                      optional: true,
                    ),
                  ],
                ],
              ],
            ],
            if (draft.kind == 'any_certificate') ...[
              const Text(
                '계산할 자격을 선택하고 보유·유효 여부를 직접 확인하세요. 기존 상태 문구는 보유 확인으로 자동 사용하지 않습니다. 기본값은 미확인입니다.',
              ),
              if (s.credentials.isEmpty) const Text('자격 기록을 먼저 등록하세요.'),
              for (final row in s.credentials) ...[
                _check(
                  '${row.data.title} · ${row.data.provider} · ${_id(row.id)}',
                  draft.selected.contains(row.id),
                  (value) => value
                      ? draft.selected.add(row.id)
                      : draft.selected.remove(row.id),
                  subtitle:
                      '취득 ${row.data.earnedOn ?? '미기록'} · 만료 ${row.data.expiresOn ?? '미기록'}',
                ),
                if (draft.selected.contains(row.id)) ...[
                  _choice(
                    draft.observation(row.id),
                    'possession',
                    '내가 확인한 보유 상태',
                    const {'unknown': '미확인', 'held': '보유', 'not_held': '미보유'},
                    'unknown',
                  ),
                  _check(
                    '내가 이 자격의 유효 여부를 확인함',
                    draft.observation(row.id)['validityKnown'] == 'true',
                    (value) =>
                        draft.observation(row.id)['validityKnown'] = '$value',
                  ),
                ],
              ],
            ],
            if (draft.kind == 'thesis') ...[
              _field(
                draft.values,
                'thesisType',
                '계산할 논문·작품 유형',
                helper: '성과 기록의 논문·작품 유형과 일치해야 합니다.',
              ),
              _check(
                '승인 상태를 충족 조건에 포함',
                draft.requiresApproval,
                (value) => draft.requiresApproval = value,
              ),
              _field(
                draft.values,
                'acceptedGrades',
                '허용할 문자 성적 · 쉼표로 구분 · 선택',
                optional: true,
                maxLength: 2600,
                helper: '예: A, B. 비워두면 성적 제한 없음. 숫자로 환산하지 않습니다.',
              ),
              const Text(
                '개인 성과의 완료·승인 관찰을 직접 선택합니다. 승인 판단에는 기준일 이내의 승인일도 필요합니다. 학교의 사실 확인을 의미하지 않습니다.',
              ),
              for (final row in s.achievements.where(
                (r) => r.data.thesisType.isNotEmpty,
              )) ...[
                _check(
                  '${row.data.title} · ${row.data.thesisType} · ${_id(row.id)}',
                  draft.selected.contains(row.id),
                  (value) => value
                      ? draft.selected.add(row.id)
                      : draft.selected.remove(row.id),
                  subtitle:
                      '문자 성적 ${row.data.thesisGrade.isEmpty ? '미기록' : row.data.thesisGrade} · 승인일 ${row.data.thesisApprovedOn ?? '미기록'}',
                ),
                if (draft.selected.contains(row.id)) ...[
                  _choice(
                    draft.observation(row.id),
                    'completion',
                    '내가 확인한 완료 상태',
                    const {
                      'unknown': '미확인',
                      'completed': '완료',
                      'in_progress': '진행 중',
                    },
                    'unknown',
                  ),
                  _choice(
                    draft.observation(row.id),
                    'approval',
                    '내가 확인한 승인 상태',
                    const {
                      'needs_review': '확인 필요',
                      'approved': '승인으로 기록',
                      'pending': '대기',
                      'rejected': '반려',
                    },
                    'needs_review',
                  ),
                ],
              ],
              if (!s.achievements.any((r) => r.data.thesisType.isNotEmpty))
                const Text('논문·작품 유형을 입력한 성과가 없습니다. 빈 선택으로도 계산할 수 있습니다.'),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _result(PersonalEvaluation result) => SurfaceCard(
    key: _resultKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('계산 결과'),
        const Text(PersonalEvaluationSummary.personalLabel),
        Text(
          '${result.curriculumTitle} · 기준일 ${result.evaluatedOn} · 교육과정 버전 ${result.curriculumVersion}',
        ),
        Text('저장 시각 ${result.createdAt.toLocal()}'),
        Text(
          '전체 상태: ${calculationStatus(result.status)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(calculationReason(result.reason)),
        const Text(
          '저장 당시의 결과입니다. 원본을 수정해도 이력은 바뀌지 않습니다. 변경된 자료는 새 계산으로 확인하세요.',
        ),
        for (final item in result.results)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                Text(
                  '${item.title} · ${calculationStatus(item.status)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(calculationReason(item.reason)),
                Text(
                  '현재 ${item.current ?? '확인 필요'} · 필요 ${item.requiredValue ?? '해당 없음'} · 부족 ${item.deficit ?? '확인 필요'}',
                ),
                Text('규칙 버전 ${item.ruleVersion} · ${item.ruleId}'),
                if (item.condition case final condition?) ...[
                  Text(
                    '실행 조건: ${personalConditionLabels[condition.toJson()['kind']]}',
                  ),
                  Text(describePersonalCondition(condition)),
                ] else
                  const Text('실행 조건 미지정 · 기록한 자유 문장은 실행하지 않았습니다.'),
                if (item.missingCourseIds.isNotEmpty)
                  Text('미충족 교육과정 과목 ID: ${item.missingCourseIds.join(', ')}'),
                if (item.uncertainCourseIds.isNotEmpty)
                  Text(
                    '확인 필요 교육과정 과목 ID: ${item.uncertainCourseIds.join(', ')}',
                  ),
                if (item.evidenceRecordIds.isNotEmpty)
                  Text('사용한 기록 ID: ${item.evidenceRecordIds.join(', ')}'),
              ],
            ),
          ),
        Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('저장 당시 사용한 자료 버전'),
            children: [
              for (final source in result.sourceVersions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${source.kind} · ${source.recordId} · 버전 ${source.version}',
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _history() => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('저장된 계산 이력'),
        const Text(
          '삭제된 교육과정의 과거 결과도 조회할 수 있습니다. 결과를 삭제해도 수강·활동 등 원본 기록은 남습니다.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: c.historyLoading ? null : () => c.loadHistory(),
            icon: const Icon(Icons.refresh),
            label: const Text('이력 다시 불러오기'),
          ),
        ),
        if (c.historyLoading) const LinearProgressIndicator(),
        _error(c.historyError),
        if (c.history.isEmpty && !c.historyLoading && c.historyError == null)
          const Text('저장된 계산 결과가 없습니다.'),
        for (final row in c.history)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${row.curriculumTitle} · ${row.evaluatedOn} · ${calculationStatus(row.status)}',
                ),
                Text('저장 ${row.createdAt.toLocal()} · ${_id(row.id)}'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton(
                      onPressed: c.busy ? null : () => _openResult(row.id),
                      child: const Text('결과 보기'),
                    ),
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () async {
                              if (await _confirm(
                                    '이 계산 결과를 삭제할까요?',
                                    '${row.curriculumTitle} · ${row.evaluatedOn}의 저장된 결과만 삭제합니다. 원본 기록은 유지합니다.',
                                    '결과 삭제',
                                  ) &&
                                  mounted) {
                                await c.remove(row);
                              }
                            },
                      child: const Text('결과 삭제'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (c.nextCursor != null)
          OutlinedButton(
            onPressed: c.historyLoading
                ? null
                : () => c.loadHistory(more: true),
            child: const Text('이력 더 보기'),
          ),
      ],
    ),
  );
}

String calculationStatus(PersonalEvaluationStatus status) => switch (status) {
  PersonalEvaluationStatus.satisfied => '충족',
  PersonalEvaluationStatus.notSatisfied => '미충족',
  PersonalEvaluationStatus.needsReview => '확인 필요',
  PersonalEvaluationStatus.notApplicable => '적용 규칙 없음',
};

String calculationReason(String reason) =>
    const {
      'threshold_met': '선택한 자료가 명시한 기준을 충족합니다.',
      'below_threshold': '선택한 자료가 기준에 부족합니다.',
      'incomplete_record_data': '기준을 확인할 자료가 일부 부족합니다.',
      'academic_records_unavailable': '수강 자료를 확인할 수 없습니다.',
      'missing_required_courses': '선택한 필수 과목 중 미충족 과목이 있습니다.',
      'course_data_needs_review': '과목이나 성적 자료를 확인해야 합니다.',
      'required_courses_met': '선택한 필수 과목 조건을 충족합니다.',
      'volunteer_records_unavailable': '봉사 자료를 확인할 수 없습니다.',
      'no_applicable_rules': '기준일에 적용할 규칙이 없습니다.',
      'requirements_not_met': '미충족 요건이 있습니다.',
      'record_data_needs_review': '자료나 계산 조건을 확인해야 합니다.',
      'all_requirements_met': '이번 개인 계산의 모든 요건을 충족합니다.',
      'explicit_condition_required': '실행 조건을 직접 지정해야 합니다.',
      'ambiguous_personal_course_mapping':
          '같은 수강 기록에 여러 필수 과목이 연결되어 확인이 필요합니다.',
    }[reason] ??
    '세부 확인 사유: $reason';

String describePersonalCondition(
  PersonalCondition condition,
) => switch (condition) {
  PersonalCreditCondition(
    :final minimum,
    :final category,
    :final courseRecordIds,
  ) =>
    '최소 $minimum학점 · 분류 ${category ?? '전체'} · 수강 ${courseRecordIds?.join(', ') ?? '연결 전체'}',
  PersonalVolunteerCondition(:final minimum, :final activityIds) =>
    '최소 $minimum시간 · 활동 ${activityIds.isEmpty ? '선택 없음' : activityIds.join(', ')}',
  PersonalCourseCondition(:final courses, :final grades) => [
    for (final row in courses)
      '과목 ${row.curriculumCourseId} · 최소 학점 ${row.minimumCredits ?? '제한 없음'} · 최소 성적 ${row.minimumGradePoints ?? '제한 없음'} · 척도 ${row.comparisonGradeScale ?? '없음'}',
    for (final row in grades)
      '수강 ${row.courseRecordId} · 관찰 성적 ${row.points} · 척도 ${row.scale}',
  ].join('\n'),
  PersonalCertificateCondition(:final certificates) => [
    for (final row in certificates)
      '자격 ${row.credentialId} · 보유 ${const {'held': '보유', 'not_held': '미보유', 'unknown': '미확인'}[row.possession] ?? row.possession} · 유효 여부 ${row.validityKnown ? '직접 확인함' : '미확인'}',
  ].join('\n'),
  PersonalThesisCondition(
    :final thesisType,
    :final requiresApproval,
    :final acceptedGrades,
    :final records,
  ) =>
    '유형 $thesisType · 승인 ${requiresApproval ? '필요' : '불필요'} · 허용 성적 ${acceptedGrades.isEmpty ? '제한 없음' : acceptedGrades.join(', ')}\n${[for (final row in records) '성과 ${row.achievementId} · 완료 ${row.completion} · 승인 ${row.approval}'].join('\n')}',
};
