import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/surface_card.dart';
import '../api/student_academic_api.dart';
import '../auth/guest_preview_scope.dart';
import '../planning/planning_repository.dart';
import 'student_academic_controller.dart';

class _ContextDraft {
  _ContextDraft({
    this.id,
    required this.department,
    this.track = '',
    this.curriculum = '',
    required int? year,
    required this.primary,
  }) : year = TextEditingController(text: year?.toString() ?? '');
  factory _ContextDraft.fromContext(AcademicStudentContext c) => _ContextDraft(
    id: c.id,
    department: c.departmentId,
    track: c.trackId,
    curriculum: c.curriculumId,
    year: c.year,
    primary: c.primary,
  );
  final String? id;
  String department, track, curriculum;
  bool primary;
  final TextEditingController year;
  Map<String, Object?> get value => {
    'id': id,
    'department_id': department,
    'track_id': track,
    'curriculum_revision_id': curriculum,
    'admission_year': int.tryParse(year.text),
    'primary': primary,
  };
}

Future<bool> editStudentAcademicContexts(
  BuildContext context,
  StudentAcademicApi api,
  PlanningProfile profile,
) async {
  if (GuestPreviewScope.isActive(context)) {
    GuestPreviewScope.showBlockedMessage(context);
    return false;
  }
  final key = GlobalKey<StudentAcademicContextsEditorState>();
  final changes = ValueNotifier<int>(0);
  try {
    return await showInputDialog<bool>(
          context: context,
          builder: (context) => AnimatedBuilder(
            animation: changes,
            builder: (context, _) => InputDialog(
              title: const Text('주전공·추가 전공 학업 기준'),
              saving: key.currentState?.blocked ?? true,
              hasContent: () => key.currentState?.dirty ?? false,
              changes: changes,
              content: StudentAcademicContextsEditor(
                key: key,
                api: api,
                profile: profile,
                onChanged: () => changes.value++,
              ),
              actions: [
                TextButton(
                  onPressed: (key.currentState?.blocked ?? true)
                      ? null
                      : () => InputDialog.cancel<bool>(context, false),
                  child: const Text('닫기'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  } finally {
    changes.dispose();
  }
}

class StudentAcademicContextsEditor extends StatefulWidget {
  const StudentAcademicContextsEditor({
    super.key,
    required this.api,
    required this.profile,
    required this.onChanged,
  });
  final StudentAcademicApi api;
  final PlanningProfile profile;
  final VoidCallback onChanged;
  @override
  State<StudentAcademicContextsEditor> createState() =>
      StudentAcademicContextsEditorState();
}

class StudentAcademicContextsEditorState
    extends State<StudentAcademicContextsEditor> {
  late final StudentAcademicController c;
  AcademicStudentOptions? _options;
  List<_ContextDraft> _drafts = [];
  String _initial = '';
  String? _error;
  bool _loading = true;
  bool get blocked => _loading || c.saving || c.loading || c.uncertain;
  bool get dirty =>
      jsonEncode(
        _drafts.map((d) => {...d.value, 'year_text': d.year.text}).toList(),
      ) !=
      _initial;
  void _changed() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged();
    });
  }

  @override
  void initState() {
    super.initState();
    c = StudentAcademicController(widget.api, contextsOnly: true)
      ..addListener(_changed);
    _load();
  }

  void _adopt() {
    for (final d in _drafts) {
      d.year.dispose();
    }
    _drafts = c.workspace!.contexts
        .where((value) => value.institutionId == widget.profile.institutionId)
        .map(_ContextDraft.fromContext)
        .toList();
    for (final draft in _drafts.where((value) => value.primary)) {
      if (draft.department != widget.profile.departmentId) {
        draft.department = widget.profile.departmentId ?? '';
        draft.curriculum = '';
      }
    }
    if (_drafts.isEmpty) {
      _drafts.add(
        _ContextDraft(
          department: widget.profile.departmentId ?? '',
          year: widget.profile.admissionYear,
          primary: true,
        ),
      );
    }
    for (final d in _drafts) {
      d.year.addListener(_changed);
    }
    _initial = jsonEncode(
      _drafts.map((d) => {...d.value, 'year_text': d.year.text}).toList(),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await c.load();
    if (!mounted) return;
    try {
      final school = c.workspace?.institutionId;
      if (!c.loaded) {
        throw StateError(c.error ?? '학업 기준을 불러오지 못했습니다.');
      }
      if (school == null) {
        throw StateError('먼저 설정에서 등록 학교·주학과·입학연도를 저장하세요.');
      }
      final options = await widget.api.options(school);
      if (!mounted) return;
      setState(() {
        _options = options;
        _adopt();
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message
              : '학교 기준 목록을 읽지 못했습니다. 다시 불러오세요.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _changed();
      }
    }
  }

  Future<void> _save() async {
    for (final d in _drafts) {
      final year = int.tryParse(d.year.text);
      if (d.department.isEmpty ||
          d.track.isEmpty ||
          d.curriculum.isEmpty ||
          year == null ||
          year < 1000 ||
          year > 9999) {
        setState(() => _error = '각 전공의 학과·경로·교육과정·네 자리 적용 입학연도를 확인하세요.');
        return;
      }
      if (!_eligible(d).any((o) => o.id == d.curriculum)) {
        setState(() => _error = '학과·이수 경로·적용 입학연도에 맞는 교육과정을 다시 선택하세요.');
        return;
      }
    }
    setState(() => _error = null);
    final yes = await c.send('PUT', 'me/academic-contexts', {
      ...c.command(c.workspace!.version),
      'contexts': _drafts.map((d) => d.value).toList(),
    });
    if (yes && mounted) {
      if (c.loaded) {
        setState(_adopt);
      } else {
        setState(() => _error = '저장은 완료됐습니다. 다시 불러와 저장된 기준을 확인하세요.');
      }
    }
  }

  @override
  void dispose() {
    c.dispose();
    for (final d in _drafts) {
      d.year.dispose();
    }
    super.dispose();
  }

  List<SelectOption<String>> _choices(
    List<AcademicOption> options,
    String selected,
  ) => [
    const SelectOption('', '선택'),
    ...options.map((o) => SelectOption(o.id, o.label)),
    if (selected.isNotEmpty && !options.any((o) => o.id == selected))
      SelectOption(selected, '이전 선택 · 다시 확인'),
  ];
  List<AcademicOption> _eligible(_ContextDraft d) => _options!.curricula
      .where(
        (o) => o.appliesTo(d.department, d.track, int.tryParse(d.year.text)),
      )
      .toList();
  void _recheck(_ContextDraft d) {
    if (!_eligible(d).any((o) => o.id == d.curriculum)) d.curriculum = '';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('학교·주학과·입학연도는 저장한 프로필을 사용합니다. 전공별 이수 경로와 교육과정을 선택하세요.'),
      if (_loading || c.loading || c.saving) const LinearProgressIndicator(),
      if (_error != null || c.error != null)
        Text(
          _error ?? c.error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (c.message != null) Text(c.message!),
      if (c.fieldError('contexts') case final String error)
        Text(
          error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      TextButton(
        onPressed: blocked
            ? null
            : () async {
                if (!dirty || await confirmInputDiscardAllowsLeave(context)) {
                  await _load();
                }
              },
        child: const Text('기준 목록 다시 불러오기'),
      ),
      if (_options != null) ...[
        for (final d in _drafts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  d.primary ? '주전공' : '추가 전공',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                AnchoredSelectField<String>(
                  externalLabel: true,
                  label: '학과',
                  value: d.department,
                  options: _choices(_options!.departments, d.department),
                  onChanged: (value) {
                    if (!blocked && !d.primary) {
                      setState(() {
                        d.department = value;
                        _recheck(d);
                      });
                    }
                  },
                ),
                AnchoredSelectField<String>(
                  externalLabel: true,
                  label: '이수 경로',
                  value: d.track,
                  options: _choices(_options!.tracks, d.track),
                  onChanged: (value) {
                    if (!blocked) {
                      setState(() {
                        d.track = value;
                        _recheck(d);
                      });
                    }
                  },
                ),
                AnchoredSelectField<String>(
                  externalLabel: true,
                  label: '교육과정',
                  value: d.curriculum,
                  options: _choices(_eligible(d), d.curriculum),
                  onChanged: (value) {
                    if (!blocked) setState(() => d.curriculum = value);
                  },
                ),
                FieldLabel(
                  label: '적용 입학연도',
                  child: TextField(
                    controller: d.year,
                    onChanged: (_) => setState(() => _recheck(d)),
                    enabled: !blocked,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                  ),
                ),
                if (!d.primary)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: blocked
                          ? null
                          : () {
                              setState(() => _drafts.remove(d));
                              d.year.dispose();
                              _changed();
                            },
                      child: const Text('추가 전공 연결 제거'),
                    ),
                  ),
              ],
            ),
          ),
        OutlinedButton(
          onPressed: blocked
              ? null
              : () => setState(() {
                  final d = _ContextDraft(
                    department: '',
                    year: widget.profile.admissionYear,
                    primary: false,
                  );
                  d.year.addListener(_changed);
                  _drafts.add(d);
                  _changed();
                }),
          child: const Text('추가 전공 연결'),
        ),
        FilledButton(
          onPressed: blocked || !c.loaded ? null : _save,
          child: const Text('학업 기준 저장'),
        ),
      ],
      if (c.uncertain)
        OutlinedButton(
          onPressed: c.saving
              ? null
              : () async {
                  if (await c.retry() && mounted && c.loaded) setState(_adopt);
                },
          child: const Text('같은 요청으로 다시 저장'),
        ),
    ],
  );
}

class StudentAcademicSettingsEntry extends StatelessWidget {
  const StudentAcademicSettingsEntry({
    super.key,
    required this.api,
    required this.profile,
  });
  final StudentAcademicApi api;
  final PlanningProfile profile;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('주전공·추가 전공 학업 기준', style: Theme.of(context).textTheme.titleMedium),
        const Text('학교의 이수 경로와 게시 교육과정을 연결합니다. 기존 개인 설정과 수강 기록은 유지됩니다.'),
        OutlinedButton(
          onPressed: () => editStudentAcademicContexts(context, api, profile),
          child: const Text('학업 기준 설정'),
        ),
      ],
    ),
  );
}
