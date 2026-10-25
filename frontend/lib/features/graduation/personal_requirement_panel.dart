import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/input_dialog.dart';
import '../api/personal_evaluation_api.dart';
import '../records/personal_record_repository.dart';
import '../records/personal_repository_scope.dart';
import 'personal_calculation_controller.dart';
import 'personal_calculation_draft.dart';
import 'personal_condition_fields.dart';

/// Stores explicit criteria through the existing immutable evaluation API.
/// The rule metadata API has no typed-condition persistence field.
class PersonalRequirementPanel extends StatefulWidget {
  const PersonalRequirementPanel({
    super.key,
    required this.curriculumId,
    required this.rule,
    required this.metadataDirty,
    required this.onChanged,
    required this.onBusy,
  });
  final String curriculumId;
  final PersonalRecord? rule;
  final bool metadataDirty;
  final ValueChanged<PersonalCalculationDraft> onChanged;
  final ValueChanged<bool> onBusy;
  @override
  State<PersonalRequirementPanel> createState() =>
      PersonalRequirementPanelState();
}

class PersonalRequirementPanelState extends State<PersonalRequirementPanel> {
  final _form = GlobalKey<FormState>();
  PersonalCalculationController? _controller;
  PersonalCalculationDraft draft = PersonalCalculationDraft();
  final _drafts = <String, PersonalCalculationDraft>{};
  String _initial = '';
  bool _loading = false, _restored = false;
  int _revision = 0;
  String? _error;
  String get _fingerprint => jsonEncode({
    'kind': draft.kind,
    'values': draft.values,
    'selected': draft.selected.toList()..sort(),
    'observations': draft.observations,
    'all': draft.allCourses,
    'approval': draft.requiresApproval,
  });
  bool get dirty => _initial.isNotEmpty && _fingerprint != _initial;
  bool validateForMetadata() {
    if (draft.kind == 'none' && widget.rule == null) {
      setState(() => _error = '계산 조건 종류를 선택하세요.');
      return false;
    }
    return _form.currentState?.validate() ?? false;
  }

  bool get locked => _loading || (_controller?.pending != null);
  @override
  void initState() {
    super.initState();
    _initial = _fingerprint;
    Future.microtask(_load);
  }

  @override
  void didUpdateWidget(PersonalRequirementPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.curriculumId != widget.curriculumId && !locked) {
      Future.microtask(_load);
    }
  }

  @override
  void dispose() {
    _revision++;
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final scope = PersonalRepositoryScope.read(context);
    final shared = scope?.calculations;
    if (shared == null || widget.curriculumId.isEmpty) return;
    final revision = ++_revision;
    _controller?.dispose();
    _controller = null;
    setState(() {
      _loading = true;
      _error = null;
    });
    widget.onBusy(true);
    final c = PersonalCalculationController(
      shared.student,
      ensureOpen: shared.ensureOpen,
    );
    try {
      await c.select(widget.curriculumId);
      if (c.sourceError != null) throw StateError(c.sourceError!);
      final history = await c.evaluations.list(
        curriculumId: widget.curriculumId,
        limit: 1,
      );
      if (history.items.isNotEmpty) {
        final last = await c.evaluations.get(history.items.first.id);
        for (final item in last.results) {
          final saved = c.sources!.rules
              .where(
                (r) => r.id == item.ruleId && r.version == item.ruleVersion,
              )
              .firstOrNull;
          if (saved == null || item.condition == null) continue;
          c.drafts[item.ruleId] = PersonalCalculationDraft.fromCondition(
            item.condition!,
            sources: c.sources,
          );
          if (!_restored && item.ruleId == widget.rule?.id && !dirty) {
            draft = c.drafts[item.ruleId]!;
            _initial = _fingerprint;
          }
        }
      }
      if (!mounted || revision != _revision) {
        c.dispose();
        return;
      }
      _controller?.dispose();
      _controller = c;
      _restored = true;
    } catch (e) {
      c.dispose();
      if (mounted && revision == _revision) {
        _error = PersonalCalculationController.message(e);
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _loading = false);
        widget.onBusy(false);
      }
    }
  }

  void _changed() {
    widget.onChanged(draft);
    setState(() {});
  }

  Future<void> _calculate() async {
    final c = _controller;
    final rule = widget.rule;
    if (c == null || rule == null || _loading) return;
    if (c.pending == null && !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    widget.onBusy(true);
    try {
      if (c.pending == null) {
        // Reload rule/source versions after the metadata save, preserving the user's criterion.
        final retained = Map.of(c.drafts);
        final versions = {for (final r in c.sources!.rules) r.id: r.version};
        await c.select(widget.curriculumId);
        if (c.sourceError != null) throw StateError(c.sourceError!);
        for (final entry in retained.entries) {
          if (c.sources!.rules.any(
            (r) => r.id == entry.key && r.version == versions[entry.key],
          )) {
            c.drafts[entry.key] = entry.value;
          }
        }
        if (!c.sources!.rules.any(
          (r) => r.id == rule.id && r.version == rule.version,
        )) {
          throw StateError('요건이 변경되었습니다. 저장된 요건을 다시 읽어주세요.');
        }
        if (!c.sources!.rules.any(
          (r) => r.id == rule.id && c.sources!.active(r, c.asOf),
        )) {
          throw StateError('현재 기준일에 적용되는 요건만 계산할 수 있습니다. 적용 기간을 확인하세요.');
        }
        if (draft.kind == 'none') throw StateError('계산할 조건 종류를 선택하세요.');
        c.drafts[rule.id] = draft;
      }
      await c.calculate();
      if (c.actionError != null) throw StateError(c.actionError!);
      _initial = _fingerprint;
    } catch (e) {
      if (mounted) {
        _error = e is StateError
            ? e.message
            : PersonalCalculationController.message(e);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        widget.onBusy(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final result = c?.result?.results
        .where((r) => r.ruleId == widget.rule?.id)
        .firstOrNull;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('계산 조건', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (c?.sources != null)
            PersonalConditionFields(
              identity: widget.rule?.id ?? 'new',
              sources: c!.sources!,
              draft: draft,
              locked: locked,
              onChanged: _changed,
              onKindChanged: (value) {
                _drafts[draft.kind] = draft;
                draft =
                    _drafts[value] ??
                    (PersonalCalculationDraft()..kind = value);
                _changed();
              },
            )
          else ...[
            AnchoredSelectField<String>(
              value: draft.kind,
              label: '실행할 계산 조건',
              options: [
                for (final entry in personalConditionLabels.entries)
                  SelectOption(entry.key, entry.value),
              ],
              onChanged: (value) {
                if (!locked) {
                  _drafts[draft.kind] = draft;
                  draft = _drafts[value] ?? PersonalCalculationDraft()
                    ..kind = value;
                  _changed();
                }
              },
            ),
            if (draft.kind == 'minimum_credits' ||
                draft.kind == 'minimum_volunteer_hours')
              TextFormField(
                key: ValueKey('requirement-minimum-${draft.kind}'),
                initialValue: draft.values['minimum'],
                decoration: InputDecoration(
                  labelText: draft.kind == 'minimum_credits'
                      ? '최소 학점'
                      : '최소 봉사 시간',
                ),
                validator: (value) => validateCalculationAmount(value),
                onChanged: (value) {
                  draft.values['minimum'] = value;
                  _changed();
                },
              ),
            Text(
              widget.curriculumId.isEmpty
                  ? '교육과정을 선택하면 연결할 기록을 읽습니다.'
                  : '실제 로그인 계정에서 계산 자료와 조건 저장 API를 사용할 수 있습니다.',
            ),
          ],
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c == null && widget.curriculumId.isNotEmpty)
            TextButton(
              onPressed: _loading ? null : _load,
              child: const Text('계산 자료 다시 읽기'),
            ),
          const Text('요건 설명 저장과 계산 조건 저장은 별도입니다. 계산 조건은 서버의 계산 이력에 보존됩니다.'),
          if (widget.rule == null || widget.metadataDirty)
            const Text('요건을 먼저 저장한 뒤 계산 조건을 저장하세요.'),
          FilledButton.icon(
            onPressed:
                _loading ||
                    c == null ||
                    widget.rule == null ||
                    widget.metadataDirty
                ? null
                : _calculate,
            icon: const Icon(Icons.calculate_outlined),
            label: Text(
              c?.pending != null ? '같은 계산 요청으로 다시 확인' : '계산 조건 저장·계산',
            ),
          ),
          if (c?.pending != null)
            TextButton(
              onPressed: _loading
                  ? null
                  : () async {
                      if (c!.result == null &&
                          !await confirmInputDiscard(context)) {
                        return;
                      }
                      if (!mounted) return;
                      c.newCalculation();
                      setState(() {});
                    },
              child: const Text('새 계산 조건 작성'),
            ),
          if (result != null)
            Semantics(
              liveRegion: true,
              child: Text(
                '현재 ${result.current ?? '확인 필요'} / 필요 ${result.requiredValue ?? '확인 필요'} · 부족 ${result.deficit ?? '확인 필요'} · ${switch (result.status) {
                  PersonalEvaluationStatus.satisfied => '충족',
                  PersonalEvaluationStatus.notSatisfied => '미충족',
                  PersonalEvaluationStatus.needsReview => '확인 필요',
                  PersonalEvaluationStatus.notApplicable => '적용 기준 없음',
                }}',
              ),
            ),
        ],
      ),
    );
  }
}
