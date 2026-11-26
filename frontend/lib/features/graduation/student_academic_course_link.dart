import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/input_dialog.dart';
import '../api/student_academic_api.dart';
import '../auth/guest_preview_scope.dart';
import 'student_academic_controller.dart';

Future<void> editStudentAcademicCourseLink(
  BuildContext context,
  StudentAcademicApi api, {
  String? recordId,
}) async {
  if (GuestPreviewScope.isActive(context)) {
    GuestPreviewScope.showBlockedMessage(context);
    return;
  }
  final key = GlobalKey<StudentAcademicCourseLinkEditorState>(),
      changes = ValueNotifier<int>(0);
  try {
    await showInputDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: changes,
        builder: (context, _) => InputDialog(
          title: const Text('수강 기록의 학점 산입'),
          saving: key.currentState?.blocked ?? true,
          changes: changes,
          hasContent: () => key.currentState?.dirty ?? false,
          content: StudentAcademicCourseLinkEditor(
            key: key,
            api: api,
            recordId: recordId,
            onChanged: () => changes.value++,
          ),
          actions: [
            TextButton(
              onPressed: (key.currentState?.blocked ?? true)
                  ? null
                  : () => InputDialog.cancel<void>(context),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  } finally {
    changes.dispose();
  }
}

class StudentAcademicCourseLinkEditor extends StatefulWidget {
  const StudentAcademicCourseLinkEditor({
    super.key,
    required this.api,
    required this.onChanged,
    this.recordId,
  });
  final StudentAcademicApi api;
  final String? recordId;
  final VoidCallback onChanged;
  @override
  State<StudentAcademicCourseLinkEditor> createState() =>
      StudentAcademicCourseLinkEditorState();
}

class StudentAcademicCourseLinkEditorState
    extends State<StudentAcademicCourseLinkEditor> {
  late final StudentAcademicController c;
  List<AcademicStudentRecord> _records = [];
  final _earned = TextEditingController();
  String _record = '',
      _context = '',
      _entry = '',
      _result = 'needs_review',
      _initial = '';
  bool _included = true, _loading = true;
  String? _error;
  bool get blocked => _loading || c.loading || c.saving || c.uncertain;
  String get _fingerprint =>
      '$_record|$_context|$_entry|$_result|$_included|${_earned.text}';
  bool get dirty => _fingerprint != _initial;
  AcademicStudentContext? get _selectedContext =>
      c.workspace?.contexts.where((v) => v.id == _context).firstOrNull;
  AcademicStudentCourseLink? get _link => c.progress?.links
      .where((l) => l.recordId == _record && l.contextId == _context)
      .firstOrNull;
  void _changed() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged();
    });
  }

  @override
  void initState() {
    super.initState();
    c = StudentAcademicController(widget.api)..addListener(_changed);
    _earned.addListener(_changed);
    _load();
  }

  void _adoptLink() {
    final l = _link;
    _entry = l?.entryId ?? '';
    _result = l?.result ?? 'needs_review';
    _earned.text = l?.earned ?? '';
    _included = l?.included ?? true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await c.load();
    try {
      final records = await widget.api.records(onlyCourses: true);
      if (!mounted) return;
      setState(() {
        _records = records;
        _record = widget.recordId ?? _record;
        final previous = c.progress?.links
            .where(
              (l) =>
                  l.recordId == _record &&
                  (c.workspace?.contexts.any(
                        (value) => value.id == l.contextId,
                      ) ??
                      false),
            )
            .firstOrNull;
        _context =
            previous?.contextId ??
            (c.workspace?.contexts.length == 1
                ? c.workspace!.contexts.single.id
                : '');
        _adoptLink();
        _initial = _fingerprint;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '수강 기록을 읽지 못했습니다. 다시 불러오세요.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _changed();
      }
    }
  }

  Future<void> _save() async {
    final record = _records.where((r) => r.id == _record).firstOrNull;
    if (record == null ||
        _context.isEmpty ||
        _entry.isEmpty ||
        (_result == 'completed' && _earned.text.isEmpty)) {
      setState(() => _error = '수강 기록·전공·교육과정 과목과 취득학점을 확인하세요.');
      return;
    }
    final amount = _earned.text.trim();
    if (amount.isNotEmpty &&
        (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(amount) ||
            double.parse(amount) > 100)) {
      setState(() => _error = '취득학점은 0~100, 소수 셋째 자리까지 입력하세요.');
      return;
    }
    setState(() => _error = null);
    final yes = await c.send(
      'PUT',
      'me/course-records/$_record/academic-link',
      {
        ...c.command(_link?.version ?? 0),
        'context_id': _context,
        'entry_id': _entry,
        'expected_record_version': record.version,
        'result': _result,
        'earned_credits': amount.isEmpty ? null : amount,
        'included': _included,
      },
    );
    if (mounted && yes) setState(() => _initial = _fingerprint);
  }

  @override
  void dispose() {
    c.dispose();
    _earned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('개인 수강 기록과 교육과정 과목을 연결합니다. 학교 분류와 인정학점은 교육과정 기준을 사용합니다.'),
      if (_loading || c.loading || c.saving) const LinearProgressIndicator(),
      if (_error != null || c.error != null)
        Text(
          _error ?? c.error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (c.message != null) Text(c.message!),
      if (c.fieldError('entry_id') case final String error) Text(error),
      if (c.workspace != null && c.workspace!.contexts.isEmpty)
        const Text('설정에서 주전공·추가 전공 학업 기준을 먼저 연결하세요.'),
      AnchoredSelectField<String>(
        externalLabel: true,
        label: '수강 기록',
        value: _record,
        options: [
          const SelectOption('', '선택'),
          ..._records.map(
            (r) => SelectOption(r.id, '${r.title} · ${r.credits ?? "?"}학점'),
          ),
        ],
        onChanged: (value) {
          if (!blocked && widget.recordId == null) {
            setState(() {
              _record = value;
              _adoptLink();
            });
          }
        },
      ),
      AnchoredSelectField<String>(
        externalLabel: true,
        label: '적용 전공·경로',
        value: _context,
        options: [
          const SelectOption('', '선택'),
          ...?c.workspace?.contexts.map((v) => SelectOption(v.id, v.label)),
        ],
        onChanged: (value) {
          if (!blocked) {
            setState(() {
              _context = value;
              _adoptLink();
            });
          }
        },
      ),
      AnchoredSelectField<String>(
        externalLabel: true,
        label: '교육과정 과목',
        value: _entry,
        options: [
          const SelectOption('', '선택'),
          ...?_selectedContext?.courses.map((v) => SelectOption(v.id, v.label)),
          if (_entry.isNotEmpty &&
              !(_selectedContext?.courses.any((v) => v.id == _entry) ?? false))
            SelectOption(_entry, '이전 교육과정 과목 · 다시 선택'),
        ],
        onChanged: (value) {
          if (!blocked) setState(() => _entry = value);
        },
      ),
      AnchoredSelectField<String>(
        externalLabel: true,
        label: '이수 결과',
        value: _result,
        options: const [
          SelectOption('needs_review', '확인 필요'),
          SelectOption('completed', '이수'),
          SelectOption('not_completed', '미이수'),
        ],
        onChanged: (value) {
          if (!blocked) setState(() => _result = value);
        },
      ),
      FieldLabel(
        label: '취득학점',
        child: TextField(
          key: const ValueKey('academic-earned-credits'),
          controller: _earned,
          enabled: !blocked,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            errorText: c.fieldError('earned_credits'),
          ),
        ),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('이 기록을 학점 산입에 사용'),
        value: _included,
        onChanged: blocked
            ? null
            : (value) => setState(() => _included = value ?? false),
      ),
      const Text('재수강은 산입할 기록을 선택하세요. 전공 간 중복 인정은 학교 정책 확인이 필요합니다.'),
      if (c.uncertain)
        OutlinedButton(
          onPressed: c.saving
              ? null
              : () async {
                  if (await c.retry() && mounted) {
                    setState(() => _initial = _fingerprint);
                  }
                },
          child: const Text('같은 요청으로 다시 저장'),
        ),
      FilledButton(
        onPressed: blocked || !c.loaded ? null : _save,
        child: const Text('수강 산입 연결 저장'),
      ),
      TextButton(
        onPressed: blocked
            ? null
            : () async {
                if (!dirty || await confirmInputDiscardAllowsLeave(context)) {
                  await _load();
                }
              },
        child: const Text('다시 불러오기'),
      ),
    ],
  );
}
