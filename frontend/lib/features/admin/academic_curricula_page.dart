import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/responsive_panels.dart';
import '../../shared/widgets/surface_card.dart';
import '../auth/auth_api.dart';
import '../records/personal_record_repository.dart';
import 'academic_scope_form.dart';
import 'academic_workspace_api.dart';
import 'academic_write_controller.dart';
import 'admin_models.dart';

class AcademicCurriculaPage extends StatefulWidget {
  const AcademicCurriculaPage({
    super.key,
    required this.api,
    required this.ownerId,
    required this.schoolId,
    required this.records,
    this.refreshCatalog,
  });
  final AcademicWorkspaceApi api;
  final String ownerId, schoolId;
  final List<AdminRecord> records;
  final Future<void> Function()? refreshCatalog;
  @override
  State<AcademicCurriculaPage> createState() => AcademicCurriculaPageState();
}

class AcademicCurriculaPageState extends State<AcademicCurriculaPage> {
  late AcademicWriteController _write;
  final _scope = GlobalKey<AcademicScopeFormState>();
  final _name = TextEditingController(), _year = TextEditingController();
  final _courseName = TextEditingController(),
      _courseCode = TextEditingController();
  final _credits = TextEditingController(),
      _recognized = TextEditingController();
  List<Map<String, dynamic>> _revisions = [],
      _classifications = [],
      _nodes = [],
      _tracks = [],
      _entries = [];
  Map<String, dynamic>? _revision;
  String _classification = '',
      _course = '',
      _node = '',
      _requirement = 'required',
      _legacy = '';
  String? _error, _message;
  String? _editingCourse;
  bool _loading = true, _loaded = false;
  int _epoch = 0;
  String _initial = '';
  bool get _busy => _loading || _write.busy;
  bool get _editable => _revision?['status'] == 'draft';
  bool get _disabled => _busy || _write.uncertain || !_loaded;
  List<AdminRecord> _records(AdminKind kind) => widget.records
      .where(
        (r) => r.kind == kind && r.value('institutionId') == widget.schoolId,
      )
      .toList();
  String get _fingerprint =>
      jsonEncode([_name.text, _year.text, _classification, _entries]);
  bool get _metadataDirty =>
      _fingerprint != _initial || (_scope.currentState?.dirty ?? false);
  bool get dirty =>
      _metadataDirty ||
      _courseName.text.isNotEmpty ||
      _courseCode.text.isNotEmpty ||
      _editingCourse != null;
  Future<bool> allowLeave() async =>
      !_busy &&
      !_write.uncertain &&
      (!dirty || await confirmInputDiscardAllowsLeave(context));
  void _changed() {
    if (mounted) setState(() {});
  }

  void _initWriter() {
    _write = AcademicWriteController(widget.api, widget.schoolId)
      ..addListener(_changed);
  }

  @override
  void initState() {
    super.initState();
    _initWriter();
    for (final c in [_name, _year, _courseName, _courseCode]) {
      c.addListener(_changed);
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant AcademicCurriculaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolId != widget.schoolId ||
        oldWidget.ownerId != widget.ownerId) {
      _write.dispose();
      _initWriter();
      _revision = null;
      _revisions = [];
      _entries = [];
      _nodes = [];
      _name.clear();
      _year.clear();
      _courseName.clear();
      _courseCode.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _write.dispose();
    for (final c in [
      _name,
      _year,
      _courseName,
      _courseCode,
      _credits,
      _recognized,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({String? selected}) async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _loaded = false;
      _error = null;
    });
    try {
      final data = await Future.wait([
        widget.api.curricula(widget.schoolId),
        widget.api.classifications(widget.schoolId),
        widget.api.tracks(widget.schoolId),
      ]);
      final revisions = data[0]
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      final classes = data[1].where((c) => c['status'] == 'published').toList()
        ..sort(
          (a, b) => (b['revision'] as int).compareTo(a['revision'] as int),
        );
      final chosen =
          revisions.where((r) => r['id'] == selected).firstOrNull ??
          revisions.firstOrNull;
      final revision = chosen == null
          ? null
          : await widget.api.curriculum(
              chosen['id'] as String,
              widget.schoolId,
            );
      final classId =
          revision?['classification_revision_id'] as String? ??
          classes.firstOrNull?['id'] as String? ??
          '';
      final classification = classId.isEmpty
          ? null
          : await widget.api.classification(classId, widget.schoolId);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _revisions = revisions;
        _classifications = classes;
        _tracks = data[2];
        _classification = classId;
        _nodes = classification == null
            ? []
            : List<Map<String, dynamic>>.from(classification['nodes'] as List);
        _adopt(revision);
        _loaded = true;
      });
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  String _messageFor(Object e) => e is AuthFailure
      ? e.message
      : e is FormatException
      ? e.message
      : e is StateError
      ? e.message
      : '교육과정 자료를 처리하지 못했습니다. 입력은 유지됩니다.';
  void _adopt(Map<String, dynamic>? revision) {
    _revision = revision;
    _name.text = revision?['name'] as String? ?? '';
    _year.text = '${revision?['curriculum_year'] ?? ''}';
    _entries = revision == null
        ? []
        : [
            for (final row in revision['courses'] as List)
              Map<String, dynamic>.from(row as Map),
          ];
    if (revision != null) {
      _classification = revision['classification_revision_id'] as String;
    }
    _courseName.clear();
    _courseCode.clear();
    _course = '';
    _node = '';
    _editingCourse = null;
    _initial = _fingerprint;
  }

  Future<void> _send(
    String method,
    String suffix,
    Map<String, Object?> body,
  ) async {
    final epoch = _epoch;
    final result = await _write.send(
      method,
      '${AcademicWorkspaceApi.path}/$suffix',
      body,
    );
    if (result != null && mounted && epoch == _epoch) {
      setState(() {
        _adopt(result);
        _revisions.removeWhere((r) => r['id'] == result['id']);
        _revisions.add(result);
        _message = '교육과정을 저장했습니다.';
      });
      if (suffix.endsWith('/course-entries')) {
        try {
          await widget.refreshCatalog?.call();
        } catch (_) {
          if (mounted) {
            setState(
              () => _message = '과목과 연결은 저장됐지만 목록 갱신을 완료하지 못했습니다. 다시 불러오세요.',
            );
          }
        }
      }
    }
  }

  Future<void> _retry() async {
    final epoch = _epoch;
    final result = await _write.retry();
    if (result != null && mounted && epoch == _epoch) {
      setState(() {
        _adopt(result);
        _revisions.removeWhere((r) => r['id'] == result['id']);
        _revisions.add(result);
        _message = '교육과정을 저장했습니다.';
      });
      try {
        await widget.refreshCatalog?.call();
      } catch (_) {
        if (mounted) setState(() => _message = '저장은 완료됐지만 과목 목록 갱신이 필요합니다.');
      }
    }
  }

  Future<void> _refreshSources() async {
    final epoch = _epoch;
    setState(() => _loading = true);
    try {
      await widget.refreshCatalog?.call();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        for (final entry in _entries) {
          final source = _records(AdminKind.course)
              .where((r) => r.id == entry['course_id'])
              .firstOrNull;
          if (source != null) {
            entry['course_version'] = source.version;
            entry['course_name'] = source.name;
            entry['course_code'] = source.value('code');
          }
        }
      });
    } catch (e) {
      if (mounted && epoch == _epoch) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Map<String, Object?> get _command => {
    'client_id': PersonalRecord.newId(),
    'expected_version': _revision!['version'],
  };
  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _classification.isEmpty) {
      setState(() => _error = '교육과정 이름과 게시된 학교 분류를 선택하세요.');
      return;
    }
    await _send('POST', 'curriculum-revisions', {
      'client_id': PersonalRecord.newId(),
      'institution_id': widget.schoolId,
      'name': _name.text.trim(),
      'curriculum_year': int.tryParse(_year.text),
      'classification_revision_id': _classification,
      if (_legacy.isNotEmpty) 'legacy_curriculum_id': _legacy,
    });
  }

  Future<void> _save() async {
    try {
      final scope = _scope.currentState?.value ?? {'clauses': <Object>[]};
      if (_name.text.trim().isEmpty) {
        throw const FormatException('교육과정 이름을 입력하세요.');
      }
      await _send('PUT', 'curriculum-revisions/${_revision!['id']}', {
        ..._command,
        'name': _name.text.trim(),
        'curriculum_year': int.tryParse(_year.text),
        'classification_revision_id': _classification,
        'scope': scope,
        'courses': [
          for (final row in _entries)
            {
              'id': row['id'],
              'course_id': row['course_id'],
              'expected_course_version': row['course_version'],
              'classification_node_id': row['classification_node_id'],
              'requirement': row['requirement'],
              'recognized_credits': row['recognized_credits'],
              'position': _entries.indexOf(row),
            },
        ],
      });
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    }
  }

  Future<void> _addCourse() async {
    if (_node.isEmpty) {
      setState(() => _error = '학교 분류를 선택하세요.');
      return;
    }
    final amount = double.tryParse(_recognized.text);
    if (amount == null || !amount.isFinite || amount < 0 || amount > 100) {
      setState(() => _error = '인정학점을 0~100 범위로 입력하세요.');
      return;
    }
    if (_editingCourse != null) {
      setState(() {
        final row = _entries.firstWhere((r) => r['id'] == _editingCourse);
        row.addAll({
          'classification_node_id': _node,
          'requirement': _requirement,
          'recognized_credits': _recognized.text,
        });
        _editingCourse = null;
        _course = '';
        _node = '';
        _courseName.clear();
        _courseCode.clear();
      });
      return;
    }
    if (_metadataDirty) {
      setState(() => _error = '교육과정의 이름·적용 대상·과목 변경을 먼저 저장하세요.');
      return;
    }
    final selected = _records(AdminKind.course)
        .where((r) => r.id == _course)
        .firstOrNull;
    if (selected == null &&
        (_courseName.text.trim().isEmpty || _courseCode.text.trim().isEmpty)) {
      setState(() => _error = '과목을 선택하거나 새 과목의 이름과 코드를 입력하세요.');
      return;
    }
    await _send(
      'POST',
      'curriculum-revisions/${_revision!['id']}/course-entries',
      {
        ..._command,
        if (selected != null) ...{
          'course_id': selected.id,
          'expected_course_version': selected.version,
        } else
          'new_course': {
            'name': _courseName.text.trim(),
            'code': _courseCode.text.trim(),
            'credits': _credits.text,
          },
        'classification_node_id': _node,
        'requirement': _requirement,
        'recognized_credits': _recognized.text,
      },
    );
  }

  Future<void> _publish() async {
    if (dirty) return;
    final epoch = _epoch;
    setState(() => _loading = true);
    try {
      final preview = await widget.api.previewCurriculum(
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
          title: const Text('교육과정을 게시할까요?'),
          content: const Text(
            '적용 대상과 과목 연결을 이 버전으로 고정합니다. 수정할 때는 새 버전을 만듭니다. 학생 반영은 후속 단계입니다.',
          ),
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
      await _send('POST', 'curriculum-revisions/${_revision!['id']}/publish', {
        ..._command,
        'expected_digest': preview['digest'],
        'review_note': '관리자 편집기에서 적용 대상·과목 분류 확인',
      });
    } catch (e) {
      if (mounted && epoch == _epoch) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  String _nodeLabel(String id) {
    final parts = <String>[], seen = <String>{};
    String? cursor = id;
    while (cursor != null && seen.add(cursor)) {
      final n = _nodes.where((n) => n['id'] == cursor).firstOrNull;
      if (n == null) break;
      parts.insert(0, n['label'] as String);
      cursor = n['parent_id'] as String?;
    }
    return parts.isEmpty ? '분류 확인 필요' : parts.join(' / ');
  }

  static const requirements = {
    'required': '필수',
    'elective': '선택',
    'not_specified': '구분 없음',
  };
  Widget _number(String label, TextEditingController controller) => FieldLabel(
    label: label,
    child: TextField(
      controller: controller,
      key: ValueKey(
        identical(controller, _recognized)
            ? 'curriculum-recognized-credits'
            : 'curriculum-source-credits',
      ),
      enabled: !_disabled && (_revision == null || _editable),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        TextInputFormatter.withFunction(
          (old, value) =>
              RegExp(r'^\d*(?:\.\d{0,3})?$').hasMatch(value.text) ? value : old,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final disabled = _disabled;
    final editable = _revision == null || _editable;
    return SurfaceCard(
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FeatureLine.section(text: '교육과정·과목', padTop: false),
            const Text(
              '학교 분류를 한 번 선택하고 교육과정별로 과목을 연결합니다. 기존 자료는 아래에서 선택해 보존하며 가져올 수 있습니다.',
            ),
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
                onPressed: _busy ? null : _retry,
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
                          if (await allowLeave()) {
                            setState(() {
                              _adopt(null);
                              _legacy = '';
                            });
                          }
                        },
                  child: const Text('새 교육과정'),
                ),
              ],
            ),
            if (_revisions.isNotEmpty)
              AnchoredSelectField<String>(
                externalLabel: true,
                value: _revision?['id'] as String? ?? '',
                label: '교육과정',
                options: [
                  const SelectOption('', '새 교육과정'),
                  for (final r in _revisions)
                    SelectOption(
                      r['id'] as String,
                      '${r['name']} · ${r['revision']}판 · ${r['status'] == 'draft' ? '초안' : '게시됨'}',
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
            const SizedBox(height: 12),
            if (_revision == null && _records(AdminKind.curriculum).isNotEmpty)
              AnchoredSelectField<String>(
                externalLabel: true,
                label: '기존 교육과정 가져오기',
                value: _legacy,
                options: [
                  const SelectOption('', '새로 작성'),
                  for (final r in _records(AdminKind.curriculum))
                    SelectOption(r.id, r.name),
                ],
                onChanged: (id) {
                  if (disabled) return;
                  setState(() {
                    _legacy = id;
                    final row = _records(AdminKind.curriculum)
                        .where((r) => r.id == id)
                        .firstOrNull;
                    if (row != null) {
                      _name.text = row.name;
                      _year.text = row.value('year');
                    }
                  });
                },
              ),
            ResponsivePanels(
              children: [
                FieldLabel(
                  label: '교육과정 이름',
                  child: TextField(
                    controller: _name,
                    key: const ValueKey('curriculum-name'),
                    enabled: !disabled && editable,
                    decoration: InputDecoration(
                      errorText: _write.fieldError('name'),
                    ),
                    maxLength: 128,
                  ),
                ),
                FieldLabel(
                  label: '교육과정 기준 연도',
                  child: TextField(
                    controller: _year,
                    enabled: !disabled && editable,
                    decoration: InputDecoration(
                      errorText: _write.fieldError('curriculum_year'),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                  ),
                ),
              ],
            ),
            if (_classifications.isEmpty)
              const Text('학교·학과 메뉴에서 학교 분류를 작성하고 게시하세요.'),
            AnchoredSelectField<String>(
              externalLabel: true,
              label: '학교 분류 기준',
              value: _classification,
              options: [
                const SelectOption('', '분류 선택'),
                for (final r in _classifications)
                  SelectOption(r['id'] as String, '학교 분류 ${r['revision']}판'),
              ],
              onChanged: (id) async {
                if (disabled || !editable) return;
                if (_entries.isNotEmpty) {
                  setState(
                    () =>
                        _error = '연결된 과목이 있습니다. 먼저 과목 연결을 정리한 뒤 분류 기준을 변경하세요.',
                  );
                  return;
                }
                if (id.isEmpty) return;
                final epoch = _epoch;
                setState(() => _loading = true);
                try {
                  final row = await widget.api.classification(
                    id,
                    widget.schoolId,
                  );
                  if (mounted && epoch == _epoch) {
                    setState(() {
                      _classification = id;
                      _nodes = List<Map<String, dynamic>>.from(
                        row['nodes'] as List,
                      );
                      _node = '';
                    });
                  }
                } catch (e) {
                  if (mounted) setState(() => _error = _messageFor(e));
                } finally {
                  if (mounted && epoch == _epoch) {
                    setState(() => _loading = false);
                  }
                }
              },
            ),
            if (_revision == null)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: disabled || _classification.isEmpty
                      ? null
                      : _create,
                  child: const Text('교육과정 작성 시작'),
                ),
              )
            else ...[
              const SizedBox(height: 16),
              AcademicScopeForm(
                key: _scope,
                resetKey: '${_revision!['id']}:${_revision!['version']}',
                initial: Map<String, dynamic>.from(_revision!['scope'] as Map),
                departments: [
                  for (final r in _records(AdminKind.department))
                    SelectOption(r.id, r.name),
                ],
                tracks: _tracks,
                enabled: !disabled && _editable,
                onChanged: _changed,
              ),
              if (_write.fieldError('scope') case final String message)
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              Text(
                '연결 과목 ${_entries.length}개',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_write.fieldError('courses') case final String message)
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_editable)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: disabled ? null : _refreshSources,
                    child: const Text('최신 과목 이름·코드 확인'),
                  ),
                ),
              if (_entries.isEmpty)
                const Text('연결된 과목이 없습니다. 기존 과목을 선택하거나 새 과목을 등록하세요.'),
              for (final row in _entries)
                ListTile(
                  dense: true,
                  title: Text('${row['course_name']} · ${row['course_code']}'),
                  subtitle: Text(
                    '${_nodeLabel(row['classification_node_id'] as String)} · ${requirements[row['requirement']]} · ${row['recognized_credits']}학점',
                  ),
                  trailing: !_editable
                      ? null
                      : Wrap(
                          children: [
                            TextButton(
                              onPressed: disabled
                                  ? null
                                  : () => setState(() {
                                      _editingCourse = row['id'] as String;
                                      _course = row['course_id'] as String;
                                      _node =
                                          row['classification_node_id']
                                              as String;
                                      _requirement =
                                          row['requirement'] as String;
                                      _recognized.text =
                                          '${row['recognized_credits']}';
                                    }),
                              child: const Text('수정'),
                            ),
                            TextButton(
                              onPressed: disabled
                                  ? null
                                  : () => setState(() => _entries.remove(row)),
                              child: const Text('연결 제거'),
                            ),
                          ],
                        ),
                ),
              if ((_revision!['legacy_courses'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '기존 과목: ${(_revision!['legacy_courses'] as List).map((r) => r['course_name']).join(', ')}. 과목별 학교 분류를 선택해 연결하세요. 원본은 삭제하지 않습니다.',
                  ),
                ),
              if (_editable) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed:
                          disabled ||
                              _editingCourse != null ||
                              _courseName.text.isNotEmpty ||
                              _courseCode.text.isNotEmpty
                          ? null
                          : _save,
                      child: const Text('교육과정 저장'),
                    ),
                    OutlinedButton(
                      onPressed: disabled || dirty ? null : _publish,
                      child: const Text('게시'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const FeatureLine.section(text: '과목 추가', padTop: false),
                if (_editingCourse != null)
                  Text('과목 분류·인정학점 수정 중')
                else
                  AnchoredSelectField<String>(
                    externalLabel: true,
                    label: '과목',
                    value: _course,
                    options: [
                      const SelectOption('', '새 과목 등록'),
                      for (final r in _records(AdminKind.course))
                        SelectOption(r.id, '${r.name} · ${r.value('code')}'),
                    ],
                    onChanged: (id) {
                      if (disabled) return;
                      setState(() {
                        _course = id;
                        _courseName.clear();
                        _courseCode.clear();
                        final row = _records(AdminKind.course)
                            .where((r) => r.id == id)
                            .firstOrNull;
                        if (row != null) {
                          _credits.text = row.value('credits');
                          _recognized.text = row.value('credits');
                        }
                      });
                    },
                  ),
                if (_course.isEmpty && _editingCourse == null) ...[
                  ResponsivePanels(
                    children: [
                      FieldLabel(
                        label: '새 과목 이름',
                        child: TextField(
                          controller: _courseName,
                          key: const ValueKey('curriculum-new-course-name'),
                          enabled: !disabled,
                          maxLength: 128,
                        ),
                      ),
                      FieldLabel(
                        label: '학교 공식 과목 코드',
                        child: TextField(
                          controller: _courseCode,
                          key: const ValueKey('curriculum-new-course-code'),
                          enabled: !disabled,
                          maxLength: 64,
                        ),
                      ),
                    ],
                  ),
                  _number('과목 기본 학점', _credits),
                ],
                AnchoredSelectField<String>(
                  externalLabel: true,
                  label: '이수구분·세부분류',
                  value: _node,
                  options: [
                    const SelectOption('', '학교 분류 선택'),
                    for (final node in _nodes)
                      if (node['selectable'] == true)
                        SelectOption(
                          node['id'] as String,
                          _nodeLabel(node['id'] as String),
                        ),
                  ],
                  onChanged: (id) {
                    if (!disabled) setState(() => _node = id);
                  },
                ),
                AnchoredSelectField<String>(
                  externalLabel: true,
                  label: '필수·선택',
                  value: _requirement,
                  options: [
                    for (final e in requirements.entries)
                      SelectOption(e.key, e.value),
                  ],
                  onChanged: (v) {
                    if (!disabled) setState(() => _requirement = v);
                  },
                ),
                _number('이 교육과정 인정학점', _recognized),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: disabled ? null : _addCourse,
                      child: Text(
                        _editingCourse == null ? '과목 등록·연결' : '과목 수정 반영',
                      ),
                    ),
                    TextButton(
                      onPressed: disabled
                          ? null
                          : () => setState(() {
                              _editingCourse = null;
                              _course = '';
                              _node = '';
                              _courseName.clear();
                              _courseCode.clear();
                            }),
                      child: const Text('과목 입력 취소'),
                    ),
                  ],
                ),
              ] else if (_revision!['status'] == 'published')
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: disabled
                        ? null
                        : () => _send(
                            'POST',
                            'curriculum-revisions/${_revision!['id']}/drafts',
                            _command,
                          ),
                    child: const Text('새 버전으로 수정'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
