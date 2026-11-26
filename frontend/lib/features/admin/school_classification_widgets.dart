import 'package:flutter/material.dart';

import '../../shared/drafts/form_draft_picker.dart';
import '../../shared/drafts/form_draft_store.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/feature_actions.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/app_style.dart';
import 'school_classification_drafts.dart';

class SchoolClassificationSection extends StatefulWidget {
  const SchoolClassificationSection({
    super.key,
    required this.drafts,
    required this.schoolId,
    required this.schoolName,
  });
  final SchoolClassificationDrafts drafts;
  final String schoolId, schoolName;
  @override
  State<SchoolClassificationSection> createState() => _SectionState();
}

class _SectionState extends State<SchoolClassificationSection> {
  bool _busy = false;
  String? _message;
  Future<void> _edit([SchoolClassification? item]) async {
    await showInputDialog<void>(
      context: context,
      builder: (_) => _ClassificationEditor(
        drafts: widget.drafts,
        schoolId: widget.schoolId,
        initial: item,
      ),
    );
  }

  Future<void> _remove(SchoolClassification item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.name} 초안을 삭제할까요?'),
        content: const Text('이 분류 초안을 삭제합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: destructiveButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('초안 삭제'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      widget.drafts.remove(widget.schoolId, item.id);
    } catch (error) {
      setState(
        () =>
            _message = error is StateError ? error.message : '초안을 삭제하지 못했습니다.',
      );
    }
  }

  Future<void> _persist(bool load) async {
    if (_busy) return;
    final school = widget.schoolId;
    final key = formDraftCollectionKey('admin.classifications.$school');
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (load) {
        final entry = await showFormDraftPicker(
          context: context,
          collectionKey: key,
        );
        if (!mounted || widget.schoolId != school || entry == null) return;
        if (widget.drafts.entries(school).isNotEmpty &&
            !await confirmInputDiscardAllowsLeave(context)) {
          return;
        }
        if (!mounted || widget.schoolId != school) return;
        widget.drafts.restoreSchool(
          school,
          Map<String, dynamic>.from(entry.payload),
        );
        _message = '학교 분류·연결 초안을 불러왔습니다.';
      } else {
        await FormDraftStore.instance.add(
          key,
          summary: '${widget.schoolName} 분류·연결 초안',
          payload: widget.drafts.exportSchool(school),
        );
        if (!mounted || widget.schoolId != school) return;
        _message = '분류·연결을 임시저장했습니다. 학생 기준에는 반영되지 않습니다.';
      }
    } catch (error) {
      if (mounted && widget.schoolId == school) {
        _message = error is StateError
            ? error.message
            : '초안 처리를 완료하지 못했습니다. 작성 내용은 유지됩니다.';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  final _listControllers = {
    for (final kind in SchoolClassificationKind.values)
      kind: ScrollController(),
  };

  @override
  void didUpdateWidget(covariant SchoolClassificationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolId == widget.schoolId) return;
    _message = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final controller in _listControllers.values) {
        if (controller.hasClients) controller.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _listControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _list(BuildContext context, SchoolClassificationKind kind) {
    final items = widget.drafts.entries(widget.schoolId, kind);
    final colors = Theme.of(context).colorScheme;
    final compact = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Container(
      key: ValueKey('classification-list-${kind.name}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FeatureLine.section(
            text: kind.label,
            padTop: false,
            trailing: Text('${items.length}개'),
          ),
          if (items.isEmpty) Text('등록한 ${kind.label}이 없습니다. 분류 초안 추가에서 등록하세요.'),
          if (items.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.textScalerOf(context).scale(64) * 3,
              ),
              child: Scrollbar(
                controller: _listControllers[kind],
                thumbVisibility: true,
                child: ListView.separated(
                  primary: false,
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(right: 16),
                  controller: _listControllers[kind],
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: colors.outlineVariant),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final details = [
                      if (item.parentId != null)
                        widget.drafts.get(item.parentId)?.name ?? '',
                      if (item.description.isNotEmpty) item.description,
                    ].where((text) => text.isNotEmpty).join(' · ');
                    return Padding(
                      key: ValueKey('classification-row-${item.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: details.isEmpty
                                ? FeatureLine.one(text: item.name)
                                : FeatureLine.two(
                                    primary: item.name,
                                    secondary: details,
                                    divided: false,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                style: compact,
                                onPressed: _busy ? null : () => _edit(item),
                                child: const Text('수정'),
                              ),
                              FilledButton(
                                style: destructiveButtonStyle(context)
                                    .merge(compact),
                                onPressed: _busy ? null : () => _remove(item),
                                child: const Text('초안 삭제'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: AnimatedBuilder(
      animation: widget.drafts,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FeatureLine.section(
            text: '학교별 교육과정 분류',
            padTop: false,
            trailing: OutlinedButton(
              onPressed: _busy ? null : () => _persist(true),
              child: const Text('분류·연결 불러오기'),
            ),
          ),
          FeatureLine.two(
            primary: widget.schoolName,
            secondary: '학교 분류 저장은 연결 전입니다. 지금은 임시저장만 가능하며 학생 기준에는 반영되지 않습니다.',
            divided: false,
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Semantics(liveRegion: true, child: Text(_message!)),
          for (final kind in SchoolClassificationKind.values.where(
            (k) => k != SchoolClassificationKind.requirement,
          )) ...[
            SizedBox(height: FeatureLine.slotGap(context)),
            _list(context, kind),
          ],
          FeatureActions(
            children: [
              FilledButton.icon(
                key: const ValueKey('classification-add'),
                onPressed: _busy ? null : () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('분류 초안 추가'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _persist(false),
                child: const Text('분류·연결 임시저장'),
              ),
              const FilledButton(
                onPressed: null,
                child: Text('학교 분류 저장 · 연결 전'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ClassificationEditor extends StatefulWidget {
  const _ClassificationEditor({
    required this.drafts,
    required this.schoolId,
    this.initial,
  });
  final SchoolClassificationDrafts drafts;
  final String schoolId;
  final SchoolClassification? initial;
  @override
  State<_ClassificationEditor> createState() => _ClassificationEditorState();
}

class _ClassificationEditorState extends State<_ClassificationEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _description = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late var _kind = widget.initial?.kind ?? SchoolClassificationKind.category;
  late String? _parent = widget.initial?.parentId;
  late bool? _required = widget.initial?.requiredCourse;
  final _changes = ValueNotifier(0);
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _changes.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _kind != (widget.initial?.kind ?? SchoolClassificationKind.category) ||
      _name.text != (widget.initial?.name ?? '') ||
      _description.text != (widget.initial?.description ?? '') ||
      _parent != widget.initial?.parentId ||
      _required != widget.initial?.requiredCourse;
  Widget _field(
    String label,
    String key,
    TextEditingController controller,
    int max, {
    bool required = true,
  }) => FieldLabel(
    label: label,
    child: TextFormField(
      key: ValueKey('classification-$key'),
      controller: controller,
      maxLength: max,
      maxLines: key == 'description' ? 3 : 1,
      validator: (value) => required && (value?.trim().isEmpty ?? true)
          ? '$label 입력이 필요합니다.'
          : null,
    ),
  );
  void _save() {
    if (!_form.currentState!.validate()) return;
    try {
      widget.drafts.save(
        id: widget.initial?.id,
        schoolId: widget.schoolId,
        kind: _kind,
        name: _name.text,
        description: _description.text,
        parentId: _kind == SchoolClassificationKind.subcategory
            ? _parent
            : null,
        requiredCourse: _kind == SchoolClassificationKind.requirement
            ? _required
            : null,
      );
      Navigator.pop(context);
    } catch (error) {
      setState(
        () => _error = error is StateError ? error.message : '분류 초안을 확인하세요.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    title: Text(widget.initial == null ? '학교 분류 초안 추가' : '학교 분류 초안 수정'),
    changes: Listenable.merge([_changes, _name, _description]),
    hasContent: () => _dirty,
    editing: widget.initial != null,
    content: Form(
      key: _form,
      child: Column(
        children: [
          AbsorbPointer(
            absorbing: widget.initial != null,
            child: AnchoredSelectField<SchoolClassificationKind>(
              value: _kind,
              label: '분류 종류',
              options: [
                for (final kind in SchoolClassificationKind.values.where((k) => k != SchoolClassificationKind.requirement))
                  SelectOption(kind, kind.label),
              ],
              onChanged: (kind) {
                setState(() {
                  _kind = kind;
                  _parent = null;
                  _required = null;
                });
                _changes.value++;
              },
            ),
          ),
          _field('이름', 'name', _name, 128),
          _field('설명', 'description', _description, 1000, required: false),
          if (_kind == SchoolClassificationKind.subcategory)
            AnchoredSelectField<String?>(
              value: _parent,
              label: '상위 이수구분',
              options: [
                const SelectOption(null, '선택하세요'),
                for (final row in widget.drafts.entries(
                  widget.schoolId,
                  SchoolClassificationKind.category,
                ))
                  SelectOption(row.id, row.name),
              ],
              onChanged: (id) {
                setState(() => _parent = id);
                _changes.value++;
              },
            ),
          if (_kind == SchoolClassificationKind.requirement)
            AnchoredSelectField<bool?>(
              value: _required,
              label: '구분 의미',
              options: const [
                SelectOption(null, '선택하세요'),
                SelectOption(true, '필수'),
                SelectOption(false, '선택'),
              ],
              onChanged: (value) {
                setState(() => _required = value);
                _changes.value++;
              },
            ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => InputDialog.cancel<void>(context),
        child: const Text('취소'),
      ),
      FilledButton(
        key: const ValueKey('classification-save-draft'),
        onPressed: _save,
        child: const Text('초안 등록'),
      ),
    ],
  );
}

class SchoolClassificationBindingFields extends StatelessWidget {
  const SchoolClassificationBindingFields({
    super.key,
    required this.drafts,
    required this.schoolId,
    required this.target,
    this.locked = false,
    this.kinds = SchoolClassificationKind.values,
    this.inferSubcategoryParent = false,
    this.showHeading = true,
  });
  final SchoolClassificationDrafts drafts;
  final String schoolId, target;
  final bool locked;
  final bool inferSubcategoryParent;
  final bool showHeading;
  final List<SchoolClassificationKind> kinds;
  @override
  Widget build(BuildContext context) {
    if (schoolId.isEmpty) return const Text('학교를 선택하면 분류 연결 초안을 작성할 수 있습니다.');
    return AnimatedBuilder(
      animation: drafts,
      builder: (context, _) {
        final values = drafts.binding(schoolId, target);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeading) Text(inferSubcategoryParent ? '세부분류·이수 경로 초안 · 서버 저장 전' : '분류 연결 초안 · 서버 저장 전'),
            for (final kind in kinds)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: AbsorbPointer(
                  absorbing: locked,
                  child: AnchoredSelectField<String>(
                    key: ValueKey(
                      'classification-binding-$target-${kind.name}',
                    ),
                    value: kind == SchoolClassificationKind.requirement
                        ? switch (drafts.get(values[kind])?.requiredCourse) { true => 'true', false => 'false', null => '' }
                        : values[kind] ?? '',
                    label: kind.label,
                    searchable: true,
                    options: [
                      const SelectOption('', '연결하지 않음'),
                      if (kind == SchoolClassificationKind.requirement) ...const [
                        SelectOption('true', '필수'), SelectOption('false', '선택'),
                      ],
                      for (final item
                          in drafts
                              .entries(schoolId, kind)
                              .where(
                                (item) =>
                                    kind != SchoolClassificationKind.requirement && (kind !=
                                        SchoolClassificationKind.subcategory || inferSubcategoryParent ||
                                    item.parentId ==
                                        values[SchoolClassificationKind
                                            .category]),
                              ))
                        SelectOption(item.id, item.name),
                    ],
                    onChanged: (id) {
                      if (locked) return;
                      final next = Map<SchoolClassificationKind, String>.from(
                        values,
                      )..[kind] = kind == SchoolClassificationKind.requirement && id.isNotEmpty
                          ? drafts.requirementId(schoolId, id == 'true') : id;
                      if (kind == SchoolClassificationKind.category) {
                        next.remove(SchoolClassificationKind.subcategory);
                      }
                      if (inferSubcategoryParent && kind == SchoolClassificationKind.subcategory) {
                        final parent = drafts.get(id)?.parentId;
                        if (parent != null) {
                          next[SchoolClassificationKind.category] = parent;
                        } else {
                          next.remove(SchoolClassificationKind.category);
                        }
                      }
                      drafts.bind(schoolId, target, next);
                    },
                  ),
                ),
              ),
            if (drafts.entries(schoolId).isEmpty)
              const Text('교육과정·과목의 학교별 교육과정 분류에서 먼저 분류 초안을 추가하세요.'),
          ],
        );
      },
    );
  }
}
