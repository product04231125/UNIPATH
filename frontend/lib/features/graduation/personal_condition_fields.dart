import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/responsive_panels.dart';
import 'personal_calculation_draft.dart';

/// The same explicit calculation fields used by the personal calculation page.
class PersonalConditionFields extends StatefulWidget {
  const PersonalConditionFields({
    super.key,
    required this.identity,
    required this.sources,
    required this.draft,
    required this.locked,
    required this.onChanged,
    this.onKindChanged,
  });
  final String identity;
  final PersonalCalculationSources sources;
  final PersonalCalculationDraft draft;
  final bool locked;
  final VoidCallback onChanged;
  final ValueChanged<String>? onKindChanged;
  @override
  State<PersonalConditionFields> createState() =>
      _PersonalConditionFieldsState();
}

class _PersonalConditionFieldsState extends State<PersonalConditionFields> {
  void _change(VoidCallback action) {
    setState(action);
    widget.onChanged();
  }

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
      readOnly: widget.locked,
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
      onChanged: (value) {
        values[key] = value;
        widget.onChanged();
      },
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
        if (!widget.locked) _change(() => values[key] = value);
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
      onChanged: widget.locked
          ? null
          : (value) => _change(() => change(value!)),
    ),
  );
  String _id(String id) => id.substring(0, 8);

  @override
  Widget build(BuildContext context) {
    final s = widget.sources;
    final draft = widget.draft;
    return Column(
      key: ValueKey('condition-${widget.identity}-${identityHashCode(draft)}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        ResponsivePanels(
          children: [
            AnchoredSelectField<String>(
              value: draft.kind,
              label: '실행할 계산 조건',
              externalLabel: true,
              options: [
                for (final e in personalConditionLabels.entries)
                  SelectOption(e.key, e.value),
              ],
              onChanged: (value) {
                if (!widget.locked) {
                  if (widget.onKindChanged != null) {
                    widget.onKindChanged!(value);
                    return;
                  }
                  _change(() {
                    draft.kind = value;
                    draft.values.clear();
                    draft.selected.clear();
                    draft.observations.clear();
                    draft.allCourses = false;
                  });
                }
              },
            ),
            if (draft.kind == 'minimum_credits' ||
                draft.kind == 'minimum_volunteer_hours')
              _field(
                draft.values,
                'minimum',
                draft.kind == 'minimum_credits' ? '최소 학점' : '최소 봉사 시간',
                number: true,
              ),
          ],
        ),
        KeyedSubtree(
          key: ValueKey(draft.kind),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
  }
}
