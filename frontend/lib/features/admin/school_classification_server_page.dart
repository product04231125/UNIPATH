import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/surface_card.dart';
import '../auth/auth_api.dart';
import '../records/personal_record_repository.dart';
import 'academic_workspace_api.dart';

/// School-owned source shared by the curriculum and graduation editors.
class SchoolClassificationServerPage extends StatefulWidget {
  const SchoolClassificationServerPage({
    super.key,
    required this.api,
    required this.ownerId,
    required this.schoolId,
    required this.schoolName,
  });
  final AcademicWorkspaceApi api;
  final String ownerId, schoolId, schoolName;
  @override
  State<SchoolClassificationServerPage> createState() =>
      SchoolClassificationServerPageState();
}

class SchoolClassificationServerPageState
    extends State<SchoolClassificationServerPage> {
  List<Map<String, dynamic>> _revisions = [], _nodes = [], _tracks = [];
  Map<String, dynamic>? _revision;
  final _label = TextEditingController(), _trackName = TextEditingController();
  String? _parent, _editing, _error, _message;
  bool _selectable = true, _busy = true;
  bool _loaded = false;
  int _epoch = 0;
  String _initial = '[]';
  List<String> _fields = [];
  Map<String, Object?>? _pending;
  String? _pendingOperation;
  String? _pendingTarget;
  bool get _draft => _revision?['status'] == 'draft';
  bool get dirty =>
      jsonEncode(_nodes) != _initial ||
      _label.text.isNotEmpty ||
      _trackName.text.isNotEmpty;
  Future<bool> allowLeave() async =>
      !_busy &&
      _pending == null &&
      (!dirty || await confirmInputDiscardAllowsLeave(context));

  @override
  void initState() {
    super.initState();
    _label.addListener(_inputChanged);
    _trackName.addListener(_inputChanged);
    _load();
  }

  void _inputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant SchoolClassificationServerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolId != widget.schoolId ||
        oldWidget.ownerId != widget.ownerId) {
      _pending = null;
      _pendingOperation = null;
      _label.clear();
      _trackName.clear();
      _revisions = [];
      _tracks = [];
      _adopt(null);
      _load();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _label.dispose();
    _trackName.dispose();
    super.dispose();
  }

  void _adopt(Map<String, dynamic>? revision) {
    _revision = revision;
    _nodes = revision == null
        ? []
        : [
            for (final row in revision['nodes'] as List)
              Map<String, dynamic>.from(row as Map),
          ];
    _initial = jsonEncode(_nodes);
    _label.clear();
    _editing = null;
    _parent = null;
    _selectable = true;
  }

  Future<void> _load({String? selected}) async {
    final epoch = ++_epoch, school = widget.schoolId;
    setState(() {
      _busy = true;
      _loaded = false;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.classifications(school),
        widget.api.tracks(school),
      ]);
      final revisions = results[0]
        ..sort(
          (a, b) => (b['revision'] as int).compareTo(a['revision'] as int),
        );
      final chosen =
          revisions.where((r) => r['id'] == selected).firstOrNull ??
          revisions.where((r) => r['status'] == 'draft').firstOrNull ??
          revisions.firstOrNull;
      final row = chosen == null
          ? null
          : await widget.api.classification(chosen['id'] as String, school);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _revisions = revisions;
        _tracks = results[1];
        _loaded = true;
        _adopt(row);
      });
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = _errorText(error));
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  String _errorText(Object error) => error is AuthFailure
      ? error.message
      : error is StateError
      ? error.message
      : '학교 기준을 처리하지 못했습니다. 작성 내용은 유지됩니다.';

  Future<void> _request(
    String operation,
    Map<String, Object?> body, {
    String? target,
  }) async {
    if (_busy) return;
    _pending ??= Map<String, Object?>.from(body);
    _pendingOperation ??= operation;
    _pendingTarget ??= target;
    await _sendPending();
  }

  Future<void> _sendPending() async {
    if (_busy || _pending == null) return;
    final school = widget.schoolId, epoch = _epoch;
    setState(() {
      _busy = true;
      _error = null;
      _fields = [];
    });
    try {
      final result = await switch (_pendingOperation) {
        'create' => widget.api.create(_pending!),
        'save' => widget.api.save(_pendingTarget!, _pending!),
        'publish' => widget.api.publish(_pendingTarget!, _pending!),
        'track' => widget.api.createTrack(_pending!),
        'track-update' => widget.api.updateTrack(_pendingTarget!, _pending!),
        _ => throw StateError('저장 동작을 확인하세요.'),
      };
      if (!mounted || epoch != _epoch || school != widget.schoolId) return;
      if (result['institution_id'] != school) {
        throw const FormatException('School mismatch');
      }
      final wasTrack = _pendingOperation!.startsWith('track');
      setState(() {
        if (wasTrack) {
          _tracks.removeWhere((row) => row['id'] == result['id']);
          _tracks.add(result);
          _trackName.clear();
        } else {
          _adopt(result);
          _revisions.removeWhere((row) => row['id'] == result['id']);
          _revisions.insert(0, result);
        }
        _pending = null;
        _pendingOperation = null;
        _pendingTarget = null;
        _message = wasTrack ? '이수 경로를 저장했습니다.' : '학교 분류를 저장했습니다.';
      });
    } catch (error) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _error = _errorText(error);
        if (error is AuthFailure) {
          _fields = error.fields;
          if (const [400, 401, 403, 404, 409, 422].contains(error.status)) {
            _pending = null;
            _pendingOperation = null;
            _pendingTarget = null;
          }
        }
      });
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Map<String, Object?> _nodeInput(Map<String, dynamic> row) => {
    if (row['id'] != null) 'id': row['id'] else 'client_ref': row['client_ref'],
    'parent_ref': row['parent_id'],
    'label': row['label'],
    'position': row['position'],
    'selectable': row['selectable'],
  };

  Future<void> _save() => _request('save', {
    'client_id': PersonalRecord.newId(),
    'expected_version': _revision!['version'],
    'nodes': [for (final node in _nodes) _nodeInput(node)],
  }, target: _revision!['id'] as String);

  String _key(Map<String, dynamic> row) =>
      (row['id'] ?? row['client_ref']) as String;

  void _editNode([Map<String, dynamic>? node]) {
    setState(() {
      _editing = node == null ? null : _key(node);
      _label.text = node?['label'] as String? ?? '';
      _parent = node?['parent_id'] as String?;
      _selectable = node?['selectable'] as bool? ?? true;
    });
  }

  bool _descendsFrom(String id, String ancestor) {
    final seen = <String>{};
    String? cursor = id;
    while (cursor != null && seen.add(cursor)) {
      if (cursor == ancestor) return true;
      cursor =
          _nodes.where((n) => _key(n) == cursor).firstOrNull?['parent_id']
              as String?;
    }
    return false;
  }

  void _applyNode() {
    final label = _label.text.trim();
    if (label.isEmpty || label.length > 128) {
      setState(() => _error = '분류 이름을 1~128자로 입력하세요.');
      return;
    }
    setState(() {
      final existing = _nodes.where((n) => _key(n) == _editing).firstOrNull;
      final siblings = _nodes.where(
        (n) => n['parent_id'] == _parent && _key(n) != _editing,
      );
      final position =
          siblings.fold<int>(
            -1,
            (a, n) => a > (n['position'] as int) ? a : n['position'] as int,
          ) +
          1;
      if (existing == null) {
        _nodes.add({
          'client_ref': PersonalRecord.newId(),
          'parent_id': _parent,
          'label': label,
          'position': position,
          'selectable': _selectable,
        });
      } else {
        if (existing['parent_id'] != _parent) existing['position'] = position;
        existing.addAll({
          'label': label,
          'parent_id': _parent,
          'selectable': _selectable,
        });
      }
      _label.clear();
      _editing = null;
      _parent = null;
      _selectable = true;
      _error = null;
      _message = null;
    });
  }

  Future<void> _removeNode(Map<String, dynamic> row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('분류를 제거할까요?'),
        content: Text('${row['label']} 및 하위 분류를 작성 중인 초안에서 제거합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('제거'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final keys = _nodes
        .where((n) => _descendsFrom(_key(n), _key(row)))
        .map(_key)
        .toSet();
    setState(() {
      _nodes.removeWhere((n) => keys.contains(_key(n)));
      if (keys.contains(_editing) || keys.contains(_parent)) _editNode();
    });
  }

  Future<void> _publish() async {
    if (_busy || dirty || _pending != null) return;
    setState(() => _busy = true);
    final epoch = _epoch;
    try {
      final preview = await widget.api.preview(
        _revision!['id'] as String,
        _revision!['version'] as int,
      );
      if (!mounted || epoch != _epoch) return;
      if ((preview['issues'] as List).isNotEmpty) {
        setState(() => _error = (preview['issues'] as List).join('\n'));
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('학교 분류를 게시할까요?'),
          content: const Text(
            '이 버전을 교육과정·졸업요건의 분류로 사용할 수 있습니다. 게시 후 수정은 새 버전으로 진행합니다. 학생 화면 반영은 후속 단계입니다.',
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
      if (!mounted || epoch != _epoch || confirmed != true) return;
      _pending = {
        'client_id': PersonalRecord.newId(),
        'expected_version': _revision!['version'],
        'expected_digest': preview['digest'],
        'review_note': '관리자 편집기에서 분류 내용을 확인하고 게시',
      };
      _pendingOperation = 'publish';
      _pendingTarget = _revision!['id'] as String;
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = _errorText(error));
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
    if (_pending != null && mounted && epoch == _epoch) await _sendPending();
  }

  Iterable<Widget> _nodeRows([String? parent, int depth = 0]) sync* {
    final rows = _nodes.where((n) => n['parent_id'] == parent).toList()
      ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    for (final row in rows) {
      final index = _nodes.indexOf(row);
      yield Padding(
        padding: EdgeInsets.only(left: depth * 16.0),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(row['label'] as String),
          subtitle: _fields.any((f) => f.contains('nodes.$index'))
              ? Text(
                  '이 분류 입력을 확인하세요.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              : Text(row['selectable'] == true ? '과목에서 선택 가능' : '하위 분류를 묶는 제목'),
          trailing: !_draft
              ? null
              : Wrap(
                  children: [
                    TextButton(
                      onPressed: _busy || _pending != null
                          ? null
                          : () => _editNode(row),
                      child: const Text('수정'),
                    ),
                    TextButton(
                      onPressed: _busy || _pending != null
                          ? null
                          : () => _removeNode(row),
                      child: const Text('제거'),
                    ),
                  ],
                ),
        ),
      );
      yield* _nodeRows(_key(row), depth + 1);
    }
  }

  Future<void> _renameTrack(Map<String, dynamic> track) async {
    final name = TextEditingController(text: track['name'] as String);
    try {
      final result = await showInputDialog<String>(
        context: context,
        builder: (context) => InputDialog(
          title: const Text('이수 경로 이름 수정'),
          changes: name,
          hasContent: () => name.text != track['name'],
          content: TextField(
            controller: name,
            maxLength: 128,
            decoration: const InputDecoration(labelText: '이수 경로 이름'),
          ),
          actions: [
            TextButton(
              onPressed: () => InputDialog.cancel<String>(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isNotEmpty) {
                  Navigator.pop(context, name.text.trim());
                }
              },
              child: const Text('저장'),
            ),
          ],
        ),
      );
      if (result != null && mounted) {
        await _request('track-update', {
          'client_id': PersonalRecord.newId(),
          'expected_version': track['version'],
          'name': result,
          'inactive': track['inactive_at'] != null,
        }, target: track['id'] as String);
      }
    } finally {
      name.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _busy || _pending != null || !_loaded;
    return SurfaceCard(
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FeatureLine.section(text: '학교별 교육과정 분류', padTop: false),
            Text('${widget.schoolName}의 이수구분·세부분류와 이수 경로를 관리합니다.'),
            const Text('학생 화면 반영은 후속 단계입니다.'),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_message != null)
              Semantics(liveRegion: true, child: Text(_message!)),
            if (_pending != null)
              OutlinedButton(
                onPressed: _busy ? null : _sendPending,
                child: const Text('같은 요청으로 다시 저장'),
              ),
            const SizedBox(height: 12),
            if (_revisions.isNotEmpty)
              AnchoredSelectField<String>(
                externalLabel: true,
                label: '분류 버전',
                value: _revision?['id'] as String? ?? '',
                options: [
                  for (final r in _revisions)
                    SelectOption(
                      r['id'] as String,
                      '${r['revision']}판 · ${r['status'] == 'draft'
                          ? '초안'
                          : r['status'] == 'published'
                          ? '게시됨'
                          : '철회됨'}',
                    ),
                ],
                onChanged: (id) async {
                  if (!disabled && await allowLeave()) {
                    await _load(selected: id);
                  }
                },
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy || _pending != null
                      ? null
                      : () async {
                          if (await allowLeave()) await _load();
                        },
                  child: const Text('다시 불러오기'),
                ),
                if (_revision == null || !_draft)
                  FilledButton(
                    onPressed:
                        disabled ||
                            _revisions.any((r) => r['status'] == 'draft')
                        ? null
                        : () => _request('create', {
                            'institution_id': widget.schoolId,
                            'client_id': PersonalRecord.newId(),
                            if (_revision != null)
                              'copy_from_id': _revision!['id'],
                          }),
                    child: Text(_revision == null ? '분류 작성 시작' : '새 버전으로 복사'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '이수구분·세부분류 ${_nodes.length}개',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (_nodes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('등록된 분류가 없습니다. 분류 작성을 시작한 뒤 이름과 상위 분류를 입력하세요.'),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.textScalerOf(context).scale(224),
              ),
              child: SingleChildScrollView(
                child: Column(children: [..._nodeRows()]),
              ),
            ),
            if (_draft) ...[
              const SizedBox(height: 12),
              FieldLabel(
                label: '분류 이름',
                child: TextField(
                  key: const ValueKey('server-classification-label'),
                  controller: _label,
                  enabled: !disabled,
                  maxLength: 128,
                ),
              ),
              AnchoredSelectField<String>(
                externalLabel: true,
                label: '상위 분류',
                value: _parent ?? '',
                options: [
                  const SelectOption('', '상위 없음 · 이수구분'),
                  for (final row in _nodes)
                    if (_editing == null ||
                        !_descendsFrom(_key(row), _editing!))
                      SelectOption(_key(row), row['label'] as String),
                ],
                onChanged: (id) {
                  if (!disabled) {
                    setState(() => _parent = id.isEmpty ? null : id);
                  }
                },
              ),
              CheckboxListTile(
                value: _selectable,
                title: const Text('과목에서 선택할 수 있는 분류'),
                onChanged: disabled
                    ? null
                    : (value) => setState(() => _selectable = value ?? true),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: disabled ? null : _applyNode,
                    child: Text(_editing == null ? '분류 추가' : '분류 수정 반영'),
                  ),
                  if (_editing != null)
                    TextButton(
                      onPressed: disabled ? null : () => _editNode(),
                      child: const Text('수정 취소'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: disabled || _label.text.isNotEmpty
                        ? null
                        : _save,
                    child: const Text('분류 저장'),
                  ),
                  OutlinedButton(
                    onPressed: disabled || dirty ? null : _publish,
                    child: const Text('게시'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Text(
              '이수 경로 ${_tracks.length}개',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (_tracks.isEmpty)
              const Text('등록된 이수 경로가 없습니다. 이 학교에서 사용하는 경로 이름을 추가하세요.'),
            for (final track in _tracks)
              ListTile(
                dense: true,
                title: Text(track['name'] as String),
                subtitle: Text(
                  track['inactive_at'] == null ? '사용 중' : '신규 선택 중지',
                ),
                leading: IconButton(
                  tooltip: '이수 경로 이름 수정',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: disabled ? null : () => _renameTrack(track),
                ),
                trailing: OutlinedButton(
                  onPressed: disabled
                      ? null
                      : () => _request('track-update', {
                          'client_id': PersonalRecord.newId(),
                          'expected_version': track['version'],
                          'name': track['name'],
                          'inactive': track['inactive_at'] == null,
                        }, target: track['id'] as String),
                  child: Text(track['inactive_at'] == null ? '사용 중지' : '다시 사용'),
                ),
              ),
            FieldLabel(
              label: '새 이수 경로 이름',
              child: TextField(
                controller: _trackName,
                enabled: !disabled,
                maxLength: 128,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: disabled
                    ? null
                    : () {
                        final name = _trackName.text.trim();
                        if (name.isEmpty) {
                          setState(() => _error = '이수 경로 이름을 입력하세요.');
                          return;
                        }
                        _request('track', {
                          'institution_id': widget.schoolId,
                          'client_id': PersonalRecord.newId(),
                          'name': name,
                        });
                      },
                child: const Text('이수 경로 추가'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
