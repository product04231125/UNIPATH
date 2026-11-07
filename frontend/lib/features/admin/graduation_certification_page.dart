import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/digits_only_hint.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/surface_card.dart';
import 'admin_models.dart';
import 'graduation_certification.dart';
import 'graduation_template_preview.dart';

class GraduationCertificationPage extends StatefulWidget {
  const GraduationCertificationPage({
    super.key,
    required this.schoolName,
    required this.departments,
    this.initial,
    this.scrollable = false,
  });

  final String schoolName;
  final List<AdminRecord> departments;
  final GraduationCertificationDraft? initial;
  final bool scrollable;

  @override
  State<GraduationCertificationPage> createState() =>
      GraduationCertificationPageState();
}

class GraduationCertificationPageState
    extends State<GraduationCertificationPage> {
  late GraduationCertificationDraft _draft;
  final _groupLabels = <String, TextEditingController>{};
  final _itemLabels = <String, TextEditingController>{};
  final _exemptionLabels = <String, TextEditingController>{};
  final _pickCounts = <String, TextEditingController>{};
  late final String _initial;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial != null
        ? copyCertificationDraft(widget.initial!)
        : GraduationCertificationDraft(
            departmentId: widget.departments.firstOrNull?.id ?? '',
          );
    _syncControllers();
    _initial = _fingerprint;
  }

  @override
  void dispose() {
    for (final controller in [
      ..._groupLabels.values,
      ..._itemLabels.values,
      ..._exemptionLabels.values,
      ..._pickCounts.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _fingerprint => jsonEncode([
    _draft.departmentId,
    [
      for (final g in _allGroups())
        [
          g.id,
          g.label,
          g.choice.name,
          g.pickCount,
          [
            for (final i in g.items) [i.id, i.label, i.kind.name],
          ],
          g.exemptions,
          [for (final child in g.groups) child.id],
        ],
    ],
  ]);

  bool get dirty => _fingerprint != _initial;

  Future<bool> allowLeave() async =>
      !dirty || await confirmInputDiscardAllowsLeave(context);

  Iterable<GraduationCertificationGroup> _allGroups([
    List<GraduationCertificationGroup>? groups,
  ]) sync* {
    for (final group in groups ?? _draft.groups) {
      yield group;
      yield* _allGroups(group.groups);
    }
  }

  void _syncControllers() {
    _bind(_groupLabels, [for (final group in _allGroups()) group.id], (id) {
      final group = _allGroups().firstWhere((g) => g.id == id);
      return TextEditingController(text: group.label)..addListener(() {
        group.label = _groupLabels[id]!.text;
        setState(() {});
      });
    });
    _bind(
      _itemLabels,
      [
        for (final group in _allGroups())
          for (final item in group.items) item.id,
      ],
      (id) {
        final item = _allGroups()
            .expand((group) => group.items)
            .firstWhere((entry) => entry.id == id);
        return TextEditingController(text: item.label)..addListener(() {
          item.label = _itemLabels[id]!.text;
          setState(() {});
        });
      },
    );
    _bind(
      _exemptionLabels,
      [
        for (final group in _allGroups())
          for (var index = 0; index < group.exemptions.length; index++)
            '${group.id}/$index',
      ],
      (key) {
        final parts = key.split('/');
        final group = _allGroups().firstWhere((g) => g.id == parts[0]);
        final index = int.parse(parts[1]);
        return TextEditingController(text: group.exemptions[index])
          ..addListener(() {
            group.exemptions[index] = _exemptionLabels[key]!.text;
            setState(() {});
          });
      },
    );
    _bind(
      _pickCounts,
      [
        for (final group in _allGroups())
          if (group.choice == GraduationCertificationChoice.pickN) group.id,
      ],
      (id) {
        final group = _allGroups().firstWhere((g) => g.id == id);
        return TextEditingController(
          text: group.pickCount == null ? '' : '${group.pickCount}',
        )..addListener(() {
          final text = _pickCounts[id]!.text.trim();
          group.pickCount = text.isEmpty ? null : int.tryParse(text);
          setState(() {});
        });
      },
    );
  }

  void _bind(
    Map<String, TextEditingController> map,
    List<String> ids,
    TextEditingController Function(String id) create,
  ) {
    for (final id in map.keys.toList()) {
      if (!ids.contains(id)) map.remove(id)?.dispose();
    }
    for (final id in ids) {
      map.putIfAbsent(id, () => create(id));
    }
  }

  void _addGroup([GraduationCertificationGroup? parent]) {
    setState(() {
      (parent?.groups ?? _draft.groups).add(
        GraduationCertificationGroup(
          id: GraduationCertificationDraft.newId('group'),
        ),
      );
      _syncControllers();
    });
  }

  void _addItem(GraduationCertificationGroup group) {
    setState(() {
      group.items.add(
        GraduationCertificationItem(
          id: GraduationCertificationDraft.newId('item'),
        ),
      );
      _syncControllers();
    });
  }

  void _addExemption(GraduationCertificationGroup group) {
    setState(() {
      group.exemptions.add('');
      _syncControllers();
    });
  }

  void _removeGroup(
    GraduationCertificationGroup group, [
    GraduationCertificationGroup? parent,
  ]) {
    setState(() {
      (parent?.groups ?? _draft.groups).remove(group);
      _syncControllers();
    });
  }

  void _removeItem(
    GraduationCertificationGroup group,
    GraduationCertificationItem item,
  ) {
    setState(() {
      group.items.remove(item);
      _syncControllers();
    });
  }

  void _removeExemption(GraduationCertificationGroup group, int index) {
    setState(() {
      group.exemptions.removeAt(index);
      _syncControllers();
    });
  }

  Widget _removeButton({required Key key, required VoidCallback onPressed}) =>
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: key,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: onPressed,
          child: const Text('제거'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final body = SurfaceCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FeatureLine.section(
            text: '인증 요건',
            padTop: false,
            padBottom: false,
          ),
          const SizedBox(height: 8),
          const Text(
            '묶음마다 모두·택 1·택 N을 고르고 기준 한 줄을 적습니다. 창의영역 같은 이름은 학교에 고정하지 않습니다.',
          ),
          Text('학교: ${widget.schoolName}'),
          const SizedBox(height: 12),
          FieldLabel(
            label: '학과',
            child: widget.departments.isEmpty
                ? const Text('현재 학교에 등록된 학과가 없습니다. 학교·학과 메뉴에서 학과를 먼저 등록하세요.')
                : AnchoredSelectField<String>(
                    key: const ValueKey('certification-department'),
                    externalLabel: true,
                    value: _draft.departmentId,
                    label: '학과',
                    options: [
                      for (final department in widget.departments)
                        SelectOption(department.id, department.name),
                    ],
                    onChanged: (id) => setState(() => _draft.departmentId = id),
                  ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('certification-add-group'),
                onPressed: () => _addGroup(),
                child: const Text('묶음 추가'),
              ),
              OutlinedButton(
                key: const ValueKey('certification-preview'),
                onPressed: () => showGraduationTemplatePreview(
                  context: context,
                  title: '인증 요건 미리보기',
                  child: GraduationCertificationPreview(
                    draft: _draft,
                    schoolName: widget.schoolName,
                    departments: widget.departments,
                  ),
                ),
                child: const Text('미리보기'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_draft.groups.isEmpty)
            const Text('묶음을 추가해 인증 요건을 적으세요. 다른 학교는 묶음 이름과 깊이를 직접 정합니다.')
          else
            for (final group in _draft.groups) _groupCard(group, depth: 0),
          const SizedBox(height: 12),
          const Text(
            '저장은 연결되지 않았습니다. 인증 묶음은 현재 실행 규칙 API의 자격·봉사 조건 하나에 넣을 수 없습니다.',
          ),
          const SizedBox(height: 8),
          const FilledButton(
            onPressed: null,
            child: Text('인증 요건 저장 불가 · 연결 전'),
          ),
        ],
      ),
    );
    if (!widget.scrollable) return body;
    return SingleChildScrollView(child: body);
  }

  Widget _groupCard(
    GraduationCertificationGroup group, {
    required int depth,
    GraduationCertificationGroup? parent,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 16, bottom: 12),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: _removeButton(
                key: ValueKey('certification-remove-group-${group.id}'),
                onPressed: () => _removeGroup(group, parent),
              ),
            ),
            FieldLabel(
              label: '묶음 이름',
              child: TextField(
                key: ValueKey('certification-group-${group.id}'),
                controller: _groupLabels[group.id],
                decoration: const InputDecoration(hintText: '창의영역'),
              ),
            ),
            const SizedBox(height: 12),
            FieldLabel(
              label: '선택 방식',
              child: AnchoredSelectField<GraduationCertificationChoice>(
                key: ValueKey('certification-choice-${group.id}'),
                externalLabel: true,
                value: group.choice,
                label: '선택 방식',
                options: [
                  for (final choice in GraduationCertificationChoice.values)
                    SelectOption(choice, certificationChoiceLabel(choice)),
                ],
                onChanged: (choice) => setState(() {
                  group.choice = choice;
                  _syncControllers();
                }),
              ),
            ),
            if (group.choice == GraduationCertificationChoice.pickN) ...[
              const SizedBox(height: 12),
              FieldLabel(
                label: '택하는 개수',
                child: TextField(
                  key: ValueKey('certification-pick-${group.id}'),
                  controller: _pickCounts[group.id],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: digitsOnlyDecoration(
                    context,
                    base: InputDecoration(
                      hintText: '2',
                      errorText: certificationPickCountError(
                        _pickCounts[group.id]?.text ?? '',
                        group.items.length,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text('기준 한 줄. 종류 표시는 이후 연결용이며 취득 여부를 판정하지 않습니다.'),
            for (final item in group.items) ...[
              const SizedBox(height: 8),
              TextField(
                key: ValueKey('certification-item-${item.id}'),
                controller: _itemLabels[item.id],
                decoration: const InputDecoration(hintText: '워드프로세서 1급 이상'),
              ),
              _removeButton(
                key: ValueKey('certification-remove-item-${item.id}'),
                onPressed: () => _removeItem(group, item),
              ),
              const SizedBox(height: 8),
              AnchoredSelectField<GraduationCertificationKind>(
                key: ValueKey('certification-kind-${item.id}'),
                externalLabel: true,
                value: item.kind,
                label: '종류 표시',
                options: [
                  for (final kind in GraduationCertificationKind.values)
                    SelectOption(kind, certificationKindLabel(kind)),
                ],
                onChanged: (kind) => setState(() => item.kind = kind),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('certification-add-item-${group.id}'),
                onPressed: () => _addItem(group),
                child: const Text('기준 추가'),
              ),
            ),
            const Text('면제 대상은 이수 경로나 과정 이름입니다.'),
            for (var index = 0; index < group.exemptions.length; index++) ...[
              const SizedBox(height: 8),
              TextField(
                key: ValueKey('certification-exempt-${group.id}-$index'),
                controller: _exemptionLabels['${group.id}/$index'],
                decoration: const InputDecoration(hintText: '직장인 교과과정'),
              ),
              _removeButton(
                key: ValueKey('certification-remove-exempt-${group.id}-$index'),
                onPressed: () => _removeExemption(group, index),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('certification-add-exempt-${group.id}'),
                onPressed: () => _addExemption(group),
                child: const Text('면제 대상 추가'),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('certification-add-child-${group.id}'),
                onPressed: () => _addGroup(group),
                child: const Text('안쪽 묶음 추가'),
              ),
            ),
            for (final child in group.groups)
              _groupCard(child, depth: depth + 1, parent: group),
          ],
        ),
      ),
    );
  }
}
