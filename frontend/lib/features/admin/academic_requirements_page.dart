import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/responsive_panels.dart';
import '../../shared/widgets/surface_card.dart';
import '../auth/auth_api.dart';
import '../records/personal_record_repository.dart';
import 'academic_checklist_editor.dart';
import 'academic_credit_preview.dart';
import 'academic_credit_record_bindings.dart';
import 'academic_explanation_tables.dart';
import 'academic_requirement_content.dart';
import 'academic_scope_form.dart';
import 'academic_workspace_api.dart';
import 'academic_write_controller.dart';
import 'admin_models.dart';
import 'graduation_certification.dart';
import 'graduation_certification_page.dart';
import 'graduation_credit_grid.dart';
import 'graduation_credit_grid_page.dart';
import 'graduation_template_preview.dart';

class AcademicRequirementsPage extends StatefulWidget {
  const AcademicRequirementsPage({
    super.key,
    required this.api,
    required this.ownerId,
    required this.schoolId,
    required this.schoolName,
    required this.kind,
    required this.records,
  });
  final AcademicWorkspaceApi api;
  final String ownerId, schoolId, schoolName, kind;
  final List<AdminRecord> records;
  @override
  State<AcademicRequirementsPage> createState() =>
      AcademicRequirementsPageState();
}

class AcademicRequirementsPageState extends State<AcademicRequirementsPage> {
  static const labels = {
    'checklist': '한 줄 요건',
    'credit_table': '학점표',
    'certification': '인증 요건',
  };
  late AcademicWriteController _write;
  final _scope = GlobalKey<AcademicScopeFormState>();
  var _checklist = GlobalKey<AcademicChecklistEditorState>();
  var _grid = GlobalKey<GraduationCreditGridPageState>();
  var _cert = GlobalKey<GraduationCertificationPageState>();
  var _tables = GlobalKey<AcademicExplanationTablesState>();
  final _name = TextEditingController(),
      _from = TextEditingController(),
      _to = TextEditingController();
  List<Map<String, dynamic>> _documents = [],
      _classifications = [],
      _curricula = [],
      _nodes = [],
      _tracks = [];
  Map<String, dynamic>? _revision;
  Map<String, dynamic> _initialContent = {};
  GraduationCreditGrid? _initialGrid;
  GraduationCertificationDraft? _initialCert;
  List<Map<String, dynamic>> _initialTables = [];
  String _classification = '', _curriculum = '', _legacy = '';
  bool _loading = true, _loaded = false;
  int _epoch = 0;
  String? _error, _message;
  String _initial = '';
  bool get _busy => _loading || _write.busy;
  bool get _editable => _revision?['status'] == 'draft';
  bool get _disabled => _busy || _write.uncertain || !_loaded;
  String get _fingerprint => jsonEncode([
    _name.text,
    _from.text,
    _to.text,
    _classification,
    _curriculum,
  ]);
  bool get dirty =>
      _fingerprint != _initial ||
      (_scope.currentState?.dirty ?? false) ||
      (_checklist.currentState?.dirty ?? false) ||
      (_grid.currentState?.dirty ?? false) ||
      (_cert.currentState?.dirty ?? false) ||
      (_tables.currentState?.dirty ?? false);
  Future<bool> allowLeave() async =>
      !_busy &&
      !_write.uncertain &&
      (!dirty || await confirmInputDiscardAllowsLeave(context));
  void _changed() {
    if (mounted) setState(() {});
  }

  List<AdminRecord> get _departments => widget.records
      .where(
        (r) =>
            r.kind == AdminKind.department &&
            r.value('institutionId') == widget.schoolId,
      )
      .toList();
  List<SelectOption<String>> get _departmentOptions => [
    for (final d in _departments) SelectOption(d.id, d.name),
  ];
  void _initWriter() {
    _write = AcademicWriteController(widget.api, widget.schoolId)
      ..addListener(_changed);
  }

  @override
  void initState() {
    super.initState();
    _initWriter();
    for (final c in [_name, _from, _to]) {
      c.addListener(_changed);
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant AcademicRequirementsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolId != widget.schoolId ||
        oldWidget.ownerId != widget.ownerId ||
        oldWidget.kind != widget.kind) {
      _write.dispose();
      _initWriter();
      _documents = [];
      _adopt(null);
      _load();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _write.dispose();
    _name.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _adopt(Map<String, dynamic>? revision) {
    _revision = revision;
    _name.text = revision?['name'] as String? ?? labels[widget.kind]!;
    _from.text = revision?['effective_from'] as String? ?? '';
    _to.text = revision?['effective_to'] as String? ?? '';
    _classification = revision?['classification_revision_id'] as String? ?? '';
    _curriculum = revision?['curriculum_revision_id'] as String? ?? '';
    _legacy = '';
    _initialContent = revision == null
        ? {'kind': widget.kind}
        : Map<String, dynamic>.from(revision['content'] as Map);
    _initialGrid = widget.kind == 'credit_table' && revision != null
        ? creditGridFromAcademic(_initialContent)
        : null;
    _initialCert = widget.kind == 'certification' && revision != null
        ? certificationFromAcademic(_initialContent)
        : null;
    _initialTables = List<Map<String, dynamic>>.from(
      _initialContent['tables'] as List? ?? [],
    );
    _checklist = GlobalKey();
    _grid = GlobalKey();
    _cert = GlobalKey();
    _tables = GlobalKey();
    _initial = _fingerprint;
  }

  String _messageFor(Object e) => e is AuthFailure
      ? e.message
      : e is FormatException
      ? e.message
      : e is StateError
      ? e.message
      : '졸업요건을 처리하지 못했습니다. 입력은 유지됩니다.';
  Future<void> _load({String? selected}) async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _loaded = false;
      _error = null;
    });
    try {
      final data = await Future.wait([
        widget.api.requirements(widget.schoolId, widget.kind),
        widget.api.classifications(widget.schoolId),
        widget.api.curricula(widget.schoolId),
        widget.api.tracks(widget.schoolId),
      ]);
      final docs = data[0]
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      final chosen =
          docs.where((d) => d['id'] == selected).firstOrNull ??
          docs.firstOrNull;
      final revision = chosen == null
          ? null
          : await widget.api.requirement(
              chosen['id'] as String,
              widget.schoolId,
            );
      final classId = revision?['classification_revision_id'] as String?;
      final classification = classId == null
          ? null
          : await widget.api.classification(classId, widget.schoolId);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _documents = docs;
        _classifications = data[1]
            .where((r) => r['status'] == 'published')
            .toList();
        _curricula = data[2].where((r) => r['status'] == 'published').toList();
        _tracks = data[3];
        _nodes = classification == null
            ? []
            : List<Map<String, dynamic>>.from(classification['nodes'] as List);
        _adopt(revision);
        _loaded = true;
      });
    } catch (e) {
      if (mounted && epoch == _epoch) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  String? _date(TextEditingController controller) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    final date = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        date == null ||
        date.toIso8601String().substring(0, 10) != value) {
      throw const FormatException('적용 기간을 YYYY-MM-DD 형식의 실제 날짜로 입력하세요.');
    }
    return value;
  }

  Map<String, Object?> get _command => {
    'client_id': PersonalRecord.newId(),
    'expected_version': _revision!['version'],
  };
  Map<String, Object?> _context() => {
    'classification_revision_id': _classification.isEmpty
        ? null
        : _classification,
    'curriculum_revision_id': _curriculum.isEmpty ? null : _curriculum,
    'effective_from': _date(_from),
    'effective_to': _date(_to),
  };
  Map<String, Object?> get _content => switch (widget.kind) {
    'checklist' =>
      _checklist.currentState?.content ??
          Map<String, Object?>.from(_initialContent),
    'credit_table' => creditGridToAcademic(
      _grid.currentState?.draft ?? _initialGrid!,
    ),
    _ => certificationToAcademic(
      _cert.currentState?.draft ?? _initialCert!,
      tables: _tables.currentState?.value ?? _initialTables,
    ),
  };
  Future<void> _accept(Map<String, dynamic>? result, int epoch) async {
    if (result == null || !mounted || epoch != _epoch) return;
    if (result['kind'] != widget.kind) {
      setState(() => _error = '다른 종류의 졸업요건 응답입니다. 다시 불러오세요.');
      return;
    }
    final id = result['classification_revision_id'] as String?;
    setState(() => _loading = true);
    Map<String, dynamic>? classification;
    if (id != null) {
      try {
        classification = await widget.api.classification(id, widget.schoolId);
      } catch (_) {
        /* Saved content remains authoritative. */
      }
    }
    if (!mounted || epoch != _epoch) return;
    setState(() {
      if (classification != null) {
        _nodes = List<Map<String, dynamic>>.from(
          classification['nodes'] as List,
        );
      }
      _adopt(result);
      _loading = false;
      _documents.removeWhere((d) => d['id'] == result['id']);
      _documents.add(result);
      _message = '${labels[widget.kind]}을 저장했습니다.';
    });
  }

  Future<void> _send(
    String method,
    String suffix,
    Map<String, Object?> body,
  ) async {
    final epoch = _epoch;
    await _accept(
      await _write.send(
        method,
        '${AcademicWorkspaceApi.path}/requirement-revisions$suffix',
        body,
      ),
      epoch,
    );
  }

  Future<void> _create() async {
    try {
      if (_name.text.trim().isEmpty) {
        throw const FormatException('기준 이름을 입력하세요.');
      }
      await _send('POST', '', {
        'client_id': PersonalRecord.newId(),
        'institution_id': widget.schoolId,
        'kind': widget.kind,
        'name': _name.text.trim(),
        ..._context(),
        if (_legacy.isNotEmpty) 'legacy_rule_id': _legacy,
      });
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    }
  }

  Future<void> _save() async {
    try {
      await _send('PUT', '/${_revision!['id']}', {
        ..._command,
        'name': _name.text.trim(),
        ..._context(),
        'scope': _scope.currentState!.value,
        'content': _content,
      });
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    }
  }

  Future<void> _publish() async {
    if (dirty || _revision == null) return;
    final epoch = _epoch;
    setState(() => _loading = true);
    try {
      final preview = await widget.api.previewRequirement(
        _revision!['id'] as String,
        _revision!['version'] as int,
      );
      if (!mounted || epoch != _epoch) return;
      final issues = List<String>.from(preview['issues'] as List);
      if (issues.isNotEmpty) {
        setState(() => _error = issues.join('\n'));
        return;
      }
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${labels[widget.kind]}을 게시할까요?'),
          content: const Text('적용 대상과 내용을 이 버전으로 고정합니다. 학생 화면 반영은 후속 단계입니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('게시'),
            ),
          ],
        ),
      );
      if (!mounted || epoch != _epoch || yes != true) return;
      setState(() => _loading = false);
      await _send('POST', '/${_revision!['id']}/publish', {
        ..._command,
        'expected_digest': preview['digest'],
        'review_note': '관리자 편집기에서 적용 대상과 본문 검토',
      });
    } catch (e) {
      if (mounted && epoch == _epoch) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _chooseContext({
    String? classification,
    String? curriculum,
  }) async {
    if (_disabled || !_editable && _revision != null) return;
    if (widget.kind == 'credit_table' &&
        (_grid.currentState?.draft.columns.any(
              (c) => c.classificationNodeId != null,
            ) ??
            false)) {
      setState(() => _error = '열의 분류 연결을 먼저 정리한 뒤 학교 분류 기준을 변경하세요.');
      return;
    }
    final epoch = _epoch;
    setState(() => _loading = true);
    try {
      final selectedCurriculum = curriculum ?? _curriculum;
      final selectedClass = curriculum != null && curriculum.isNotEmpty
          ? _curricula.firstWhere(
                  (c) => c['id'] == curriculum,
                )['classification_revision_id']
                as String
          : classification ?? _classification;
      final row = selectedClass.isEmpty
          ? null
          : await widget.api.classification(selectedClass, widget.schoolId);
      if (mounted && epoch == _epoch) {
        setState(() {
          _curriculum = selectedCurriculum;
          _classification = selectedClass;
          _nodes = row == null
              ? []
              : List<Map<String, dynamic>>.from(row['nodes'] as List);
        });
      }
    } catch (e) {
      if (mounted && epoch == _epoch) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  String _nodeLabel(Map<String, dynamic> node) {
    final labels = <String>[], seen = <String>{};
    Map<String, dynamic>? current = node;
    while (current != null && seen.add(current['id'] as String)) {
      labels.insert(0, current['label'] as String);
      current = _nodes
          .where((n) => n['id'] == current?['parent_id'])
          .firstOrNull;
    }
    return labels.join(' / ');
  }

  List<SelectOption<String>> get _groupOptions {
    final result = <SelectOption<String>>[];
    void walk(List<GraduationCertificationGroup> groups) {
      for (final g in groups) {
        result.add(SelectOption(g.id, g.label.isEmpty ? '이름 미입력' : g.label));
        walk(g.groups);
      }
    }

    walk(_cert.currentState?.draft.groups ?? _initialCert?.groups ?? []);
    return result;
  }

  Future<void> _withdraw() async {
    final reason = TextEditingController();
    try {
      final text = await showInputDialog<String>(
        context: context,
        builder: (context) => InputDialog(
          title: const Text('게시 철회'),
          hasContent: () => reason.text.isNotEmpty,
          changes: reason,
          content: TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: '철회 사유'),
            maxLength: 1000,
          ),
          actions: [
            TextButton(
              onPressed: () => InputDialog.cancel<String>(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().isNotEmpty) {
                  Navigator.pop(context, reason.text.trim());
                }
              },
              child: const Text('철회'),
            ),
          ],
        ),
      );
      if (text != null && mounted) {
        await _send('POST', '/${_revision!['id']}/withdraw', {
          ..._command,
          'reason': text,
        });
      }
    } finally {
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _disabled,
        canEdit = !_disabled && (_revision == null || _editable);
    return SurfaceCard(
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FeatureLine.section(text: labels[widget.kind]!, padTop: false),
            Text('${widget.schoolName}의 적용 대상과 기준을 작성합니다. 학생 화면 반영은 후속 단계입니다.'),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null || _write.error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error ?? _write.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_message != null) Text(_message!),
            if (_write.uncertain)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final epoch = _epoch;
                        await _accept(await _write.retry(), epoch);
                      },
                child: const Text('같은 요청으로 다시 저장'),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy || _write.uncertain
                      ? null
                      : () async {
                          if (await allowLeave()) {
                            await _load(selected: _revision?['id'] as String?);
                          }
                        },
                  child: const Text('다시 불러오기'),
                ),
                TextButton(
                  onPressed: disabled
                      ? null
                      : () async {
                          if (await allowLeave()) setState(() => _adopt(null));
                        },
                  child: Text('새 ${labels[widget.kind]}'),
                ),
              ],
            ),
            if (_documents.isNotEmpty)
              AnchoredSelectField<String>(
                externalLabel: true,
                label: '저장된 기준',
                value: _revision?['id'] as String? ?? '',
                options: [
                  SelectOption('', '새 ${labels[widget.kind]}'),
                  for (final d in _documents)
                    SelectOption(
                      d['id'] as String,
                      '${d['name']} · ${d['revision']}판 · ${d['status'] == 'draft'
                          ? '초안'
                          : d['status'] == 'published'
                          ? '게시됨'
                          : '철회됨'}',
                    ),
                ],
                onChanged: (id) async {
                  if (!disabled && await allowLeave()) {
                    if (id.isEmpty) {
                      setState(() => _adopt(null));
                    } else {
                      await _load(selected: id);
                    }
                  }
                },
              ),
            FieldLabel(
              label: '기준 이름',
              child: TextField(
                key: const ValueKey('requirement-name'),
                controller: _name,
                enabled: canEdit,
                maxLength: 128,
                decoration: InputDecoration(
                  errorText:
                      _write.fields.any((f) => f == 'name' || f == 'body.name')
                      ? '기준 이름을 확인하세요.'
                      : null,
                ),
              ),
            ),
            if (_revision == null && widget.kind == 'checklist')
              AnchoredSelectField<String>(
                externalLabel: true,
                label: '기존 요건 설명 가져오기 · 선택',
                value: _legacy,
                options: [
                  const SelectOption('', '새로 작성'),
                  for (final r in widget.records)
                    if (r.kind == AdminKind.rule &&
                        r.value('institutionId') == widget.schoolId)
                      SelectOption(r.id, r.name),
                ],
                onChanged: (id) {
                  if (canEdit) setState(() => _legacy = id);
                },
              ),
            AnchoredSelectField<String>(
              externalLabel: true,
              label: '적용 교육과정 · 선택',
              value: _curriculum,
              options: [
                const SelectOption('', '학교·학과 기준으로 직접 지정'),
                for (final c in _curricula)
                  SelectOption(
                    c['id'] as String,
                    '${c['name']} · ${c['revision']}판',
                  ),
              ],
              onChanged: (id) {
                if (canEdit) _chooseContext(curriculum: id);
              },
            ),
            if (widget.kind == 'credit_table')
              AnchoredSelectField<String>(
                externalLabel: true,
                label: '학점 연결에 사용할 학교 분류 · 선택',
                value: _classification,
                options: [
                  const SelectOption('', '표 내용만 작성'),
                  for (final c in _classifications)
                    SelectOption(c['id'] as String, '학교 분류 ${c['revision']}판'),
                ],
                onChanged: (id) {
                  if (canEdit && _curriculum.isEmpty) {
                    _chooseContext(classification: id);
                  }
                },
              ),
            ResponsivePanels(
              children: [
                FieldLabel(
                  label: '적용 시작일 · 선택',
                  child: TextField(
                    controller: _from,
                    enabled: canEdit,
                    decoration: InputDecoration(
                      hintText: 'YYYY-MM-DD',
                      errorText: _write.fieldError('effective_from'),
                    ),
                  ),
                ),
                FieldLabel(
                  label: '적용 종료일 · 선택',
                  child: TextField(
                    controller: _to,
                    enabled: canEdit,
                    decoration: InputDecoration(
                      hintText: 'YYYY-MM-DD',
                      errorText: _write.fieldError('effective_to'),
                    ),
                  ),
                ),
              ],
            ),
            if (_revision == null)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: canEdit ? _create : null,
                  child: const Text('작성 시작'),
                ),
              )
            else ...[
              const SizedBox(height: 16),
              AcademicScopeForm(
                key: _scope,
                initial: Map<String, dynamic>.from(_revision!['scope'] as Map),
                resetKey: '${_revision!['id']}:${_revision!['version']}',
                departments: _departmentOptions,
                tracks: _tracks,
                enabled: canEdit,
                onChanged: _changed,
              ),
              if (_write.fieldError('scope') case final String message)
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              if (widget.kind == 'checklist')
                AcademicChecklistEditor(
                  key: _checklist,
                  initial: _initialContent,
                  enabled: canEdit,
                  departments: _departmentOptions,
                  tracks: _tracks,
                  onChanged: _changed,
                )
              else if (widget.kind == 'credit_table')
                if (_editable)
                  AbsorbPointer(
                    absorbing: disabled,
                    child: ExcludeFocus(
                      excluding: disabled,
                      child: GraduationCreditGridPage(
                        key: _grid,
                        embedded: true,
                        initial: _initialGrid,
                        schoolName: widget.schoolName,
                        departments: _departments,
                        classificationOptions: [
                          for (final n in _nodes)
                            SelectOption(n['id'] as String, _nodeLabel(n)),
                        ],
                        tracks: _tracks,
                        onDirtyChanged: (_) => _changed(),
                      ),
                    ),
                  )
                else
                  AcademicCreditPreview(grid: _initialGrid!)
              else ...[
                if (_editable)
                  AbsorbPointer(
                    absorbing: disabled,
                    child: ExcludeFocus(
                      excluding: disabled,
                      child: GraduationCertificationPage(
                        key: _cert,
                        embedded: true,
                        initial: _initialCert,
                        schoolName: widget.schoolName,
                        departments: _departments,
                        tracks: _tracks,
                        onDirtyChanged: (_) => _changed(),
                      ),
                    ),
                  )
                else
                  GraduationCertificationPreview(
                    draft: _initialCert!,
                    schoolName: widget.schoolName,
                    departments: _departments,
                    showContext: false,
                  ),
                const SizedBox(height: 16),
                AcademicExplanationTables(
                  key: _tables,
                  initial: _initialTables,
                  enabled: canEdit,
                  groups: _groupOptions,
                  onChanged: _changed,
                ),
              ],
              if (_write.fieldError('content') case final String message)
                Text(
                  '요건 본문: $message',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  if (widget.kind == 'credit_table' &&
                      _revision!['status'] != 'withdrawn')
                    OutlinedButton(
                      onPressed: disabled || dirty
                          ? null
                          : () => editCreditRecordBindings(
                              context,
                              widget.api,
                              widget.schoolId,
                              _revision!,
                            ),
                      child: const Text('성적표 이수구분 연결'),
                    ),
                  if (_editable) ...[
                    FilledButton(
                      onPressed: disabled ? null : _save,
                      child: Text('${labels[widget.kind]} 저장'),
                    ),
                    OutlinedButton(
                      onPressed: disabled || dirty ? null : _publish,
                      child: const Text('게시'),
                    ),
                  ] else if (_revision!['status'] == 'published') ...[
                    OutlinedButton(
                      onPressed: disabled
                          ? null
                          : () => _send(
                              'POST',
                              '/${_revision!['id']}/drafts',
                              _command,
                            ),
                      child: const Text('새 버전으로 수정'),
                    ),
                    TextButton(
                      onPressed: disabled ? null : _withdraw,
                      child: const Text('게시 철회'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
