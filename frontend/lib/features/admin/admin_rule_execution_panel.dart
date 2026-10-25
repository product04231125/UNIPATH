import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/responsive_panels.dart';
import '../../shared/widgets/field_label.dart';
import '../api/rule_program_api.dart';
import '../api/rule_program_models.dart';
import '../api/school_knowledge_api.dart';
import '../api/school_knowledge_models.dart';
import '../auth/auth_api.dart';
import '../graduation/personal_calculation_draft.dart';
import 'admin_models.dart';
import 'admin_repository.dart';
import 'remote_admin_repository.dart';
import 'admin_requirement_draft.dart';

class AdminRuleExecutionPanel extends StatefulWidget {
  const AdminRuleExecutionPanel({
    super.key,
    required this.repository,
    required this.actorId,
    required this.schoolId,
    required this.ruleType,
    required this.description,
    required this.rule,
    required this.metadataDirty,
    required this.onBusy,
    required this.onChanged,
  });
  final AdminRepository repository;
  final String actorId, schoolId, ruleType, description;
  final AdminRecord? rule;
  final bool metadataDirty;
  final ValueChanged<bool> onBusy;
  final VoidCallback onChanged;
  @override
  State<AdminRuleExecutionPanel> createState() =>
      AdminRuleExecutionPanelState();
}

class AdminRuleExecutionPanelState extends State<AdminRuleExecutionPanel> {
  final _form = GlobalKey<FormState>();
  final _values = <String, String>{};
  final _drafts = <String, AdminRequirementDraft>{};
  final _evidence = <String, String>{};
  final _selectedEvidence = <String>{};
  List<SchoolKnowledgeView> _documents = [];
  List<SchoolKnowledgePageSummary> _pages = [];
  List<SchoolKnowledgeChunkView> _parts = [];
  List<CertificateRegistryCertificateView> _certificates = [];
  List<OfficialProgramHeader> _programs = [];
  OfficialProgramView? _existing;
  String _programId = '', _documentId = '';
  int? _page;
  bool _busy = false, _uncertain = false, _conflict = false, _reloaded = false;
  int _revision = 0, _inputRevision = 0;
  String? _error, _message;
  List<String> _serverFields = [];
  late String _initial;
  AdminRequirementDraft get draft =>
      _drafts.putIfAbsent(widget.ruleType, AdminRequirementDraft.new);
  ApiGateway? get _gateway => widget.repository is RemoteAdminRepository
      ? (widget.repository as RemoteAdminRepository).api
      : null;
  AdminRecord? get rule =>
      widget.repository.records
          .where((r) => r.id == widget.rule?.id)
          .firstOrNull ??
      widget.rule;
  AdminRecord? get parent => (rule?.value('ruleSetId').isNotEmpty ?? false)
      ? widget.repository.records
            .where((r) => r.id == rule!.value('ruleSetId'))
            .firstOrNull
      : rule;
  Iterable<AdminRecord> get courses => widget.repository.records.where(
    (r) =>
        r.kind == AdminKind.course &&
        widget.repository.school(r) == widget.schoolId &&
        widget.repository.canRead(widget.actorId, r) &&
        r.status == 'active',
  );
  bool get ready =>
      parent?.status == 'applied' &&
      rule?.status == 'applied' &&
      (parent!.kind != AdminKind.ruleSet ||
          widget.repository.records
              .where(
                (r) =>
                    r.kind == AdminKind.rule &&
                    r.value('ruleSetId') == parent!.id,
              )
              .every((r) => r.status == 'applied'));
  String get _fingerprint => jsonEncode({
    'values': {
      for (final e in _values.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    },
    'drafts': {
      for (final e in _drafts.entries)
        if (e.value.values.values.any((v) => v.isNotEmpty) ||
            e.value.selected.isNotEmpty ||
            e.value.observations.values.any(
              (v) => v.values.any((s) => s.isNotEmpty),
            ) ||
            !e.value.approval)
          e.key: {
            'values': e.value.values,
            'selected': e.value.selected.toList()..sort(),
            'observations': e.value.observations,
            'references': e.value.referenceVersions,
            'approval': e.value.approval,
          },
    },
    'evidence': _selectedEvidence.toList()..sort(),
  });
  bool get dirty => _fingerprint != _initial;
  bool get saving => _busy;
  @override
  void initState() {
    super.initState();
    draft;
    _initial = _fingerprint;
  }

  @override
  void dispose() {
    _revision++;
    super.dispose();
  }

  @override
  void didUpdateWidget(AdminRuleExecutionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolId != widget.schoolId ||
        oldWidget.rule?.id != widget.rule?.id) {
      _revision++;
      _documents = [];
      _pages = [];
      _parts = [];
      _certificates = [];
      _programs = [];
      _programId = '';
      _existing = null;
      _documentId = '';
      _page = null;
      _selectedEvidence.clear();
      _evidence.clear();
      _uncertain = false;
      _conflict = false;
    }
  }

  void _ensure() {
    final target =
        rule ??
        AdminRecord(
          id: '',
          kind: AdminKind.rule,
          values: {'institutionId': widget.schoolId},
        );
    if (!mounted ||
        !widget.repository.active(widget.actorId) ||
        !widget.repository.canWrite(widget.actorId, target)) {
      throw const AuthFailure(
        '관리 권한이 변경되었습니다. 다시 로그인하거나 자료를 읽어주세요.',
        status: 403,
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _serverFields = [];
    });
    widget.onBusy(true);
    try {
      _ensure();
      await action();
      _ensure();
    } catch (e) {
      if (mounted) {
        _error = e is AuthFailure
            ? e.message
            : e is FormatException
            ? e.message
            : e is StateError
            ? e.message
            : '처리하지 못했습니다. 입력을 유지했습니다. 다시 읽거나 재시도하세요.';
        if (e is AuthFailure) {
          _serverFields = e.fields;
          if (e.status == 401 || e.status == 403) {
            _documents = [];
            _pages = [];
            _parts = [];
            _certificates = [];
            _programs = [];
            _evidence.clear();
            _selectedEvidence.clear();
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusy(false);
      }
    }
  }

  Future<void> _load() => _run(() async {
    final api = _gateway;
    if (api == null) return;
    final revision = _revision;
    final documents = <SchoolKnowledgeView>[];
    final seen = <String>{};
    String? cursor;
    do {
      final page = await SchoolKnowledgeAdminApi(api).list(
        institutionId: widget.schoolId,
        status: 'approved',
        cursor: cursor,
      );
      _ensure();
      if (revision != _revision) return;
      documents.addAll(
        page.items.where(
          (d) =>
              d.institutionId == widget.schoolId &&
              d.status == 'approved' &&
              (d.departmentId == null ||
                  d.departmentId == rule?.value('departmentId')) &&
              (d.curriculumId == null ||
                  d.curriculumId == rule?.value('curriculumId')),
        ),
      );
      cursor = page.nextCursor;
      if (cursor != null && !seen.add(cursor)) {
        throw const FormatException('문서 목록이 반복됩니다. 다시 읽어주세요.');
      }
    } while (cursor != null);
    _documents = documents;
    if (widget.ruleType == 'certificate') {
      final certificates = <CertificateRegistryCertificateView>[];
      cursor = null;
      seen.clear();
      do {
        final page = await CertificateRegistryAdminApi(api)
            .certificates(cursor: cursor);
        _ensure();
        if (revision != _revision) return;
        certificates.addAll(page.items.where((r) => r.status == 'active'));
        cursor = page.nextCursor;
        if (cursor != null && !seen.add(cursor)) {
          throw const FormatException('자격 목록이 반복됩니다. 다시 읽어주세요.');
        }
      } while (cursor != null);
      _certificates = certificates;
    }
    final programs = <OfficialProgramHeader>[];
    cursor = null;
    seen.clear();
    if (ready) {
      do {
        final page = await OfficialProgramAdminApi(api).list(
          institutionId: widget.schoolId,
          ruleSetId: parent!.kind == AdminKind.ruleSet ? parent!.id : null,
          ruleId: parent!.kind == AdminKind.rule ? parent!.id : null,
          status: 'draft',
          cursor: cursor,
        );
        _ensure();
        if (revision != _revision) return;
        programs.addAll(
          page.items.where(
            (p) =>
                p.institutionId == widget.schoolId &&
                p.status == 'draft' &&
                p.sourceVersion == parent!.version &&
                (p.ruleSetId ?? p.ruleId) == parent!.id,
          ),
        );
        cursor = page.nextCursor;
        if (cursor != null && !seen.add(cursor)) {
          throw const FormatException('실행 초안 목록이 반복됩니다. 다시 읽어주세요.');
        }
      } while (cursor != null);
    }
    _programs = programs;
    _reloaded = true;
    _message = _uncertain || _conflict
        ? '서버 목록을 읽었습니다. 저장된 초안을 선택해 내용을 확인하세요.'
        : '근거와 실행 초안 목록을 읽었습니다.';
  });
  Future<void> _selectProgram(String id) async {
    if (_busy || (id == _programId && !_uncertain && !_conflict)) return;
    if (dirty && !await confirmInputDiscard(context)) return;
    if (!mounted) return;
    await _run(() async {
      if (id.isEmpty) {
        _existing = null;
        _programId = '';
        _uncertain = false;
        _conflict = false;
        return;
      }
      final value = await OfficialProgramAdminApi(_gateway!).get(id);
      _ensure();
      if (value.status != 'draft' ||
          value.sourceVersion != parent!.version ||
          (value.ruleSetId ?? value.ruleId) != parent!.id ||
          value.institutionId != widget.schoolId) {
        throw const FormatException('현재 요건의 실행 초안이 아닙니다. 다시 선택하세요.');
      }
      final entry = value.rules.where((r) => r.ruleId == rule!.id).firstOrNull;
      if (entry != null &&
          entry.condition.kind != executionKinds[widget.ruleType]) {
        throw const FormatException('규칙 종류와 저장된 실행 조건이 다릅니다. 원본을 다시 확인하세요.');
      }
      _values.addAll({
        'yearFrom': '${value.admissionYearFrom}',
        'yearTo': '${value.admissionYearTo}',
        'tracks': value.tracks.join(', '),
      });
      if (entry != null) {
        _drafts[widget.ruleType] = AdminRequirementDraft.fromCondition(
          entry.condition,
        );
      }
      _selectedEvidence.clear();
      _evidence.clear();
      if (entry != null) {
        for (final e in entry.evidence) {
          _selectedEvidence.add(e.chunkId);
          _evidence[e.chunkId] = '${e.title} · ${e.page}쪽 · ${e.excerpt}';
        }
      }
      _inputRevision++;
      _existing = value;
      _programId = id;
      _uncertain = false;
      _conflict = false;
      _initial = _fingerprint;
      _message = '실행 초안을 불러왔습니다. 다른 요건의 조건은 유지합니다.';
    });
  }

  Future<void> _selectDocument(String id) => _run(() async {
    _documentId = id;
    _page = null;
    _parts = [];
    _pages = [];
    final pages = <SchoolKnowledgePageSummary>[];
    int? cursor;
    final seen = <int>{};
    do {
      final list = await SchoolKnowledgeAdminApi(_gateway!)
          .pages(id, cursor: cursor);
      _ensure();
      pages.addAll(list.items.where((p) => !p.isBlank));
      cursor = list.nextCursor;
      if (cursor != null && !seen.add(cursor)) {
        throw const FormatException('페이지 목록이 반복됩니다.');
      }
    } while (cursor != null);
    _pages = pages;
  });
  Future<void> _selectPage(int page) => _run(() async {
    final value = await SchoolKnowledgeAdminApi(_gateway!)
        .page(_documentId, page);
    _ensure();
    if (value.knowledgeDocumentId != _documentId ||
        value.page != page ||
        value.version !=
            _documents.singleWhere((d) => d.id == _documentId).version) {
      throw const FormatException('요청과 다른 근거 페이지입니다.');
    }
    _page = page;
    _parts = value.isBlank
        ? []
        : value.parts.where((p) => p.warnings.isEmpty).toList();
    for (final p in _parts) {
      _evidence[p.id] =
          '${_documents.singleWhere((d) => d.id == _documentId).name} · $page쪽 · ${p.content}';
    }
  });
  Future<void> _apply() async {
    if (_busy || parent == null || widget.metadataDirty) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('요건을 검토·적용할까요?'),
        content: Text(
          parent!.kind == AdminKind.ruleSet
              ? '이 규칙 묶음의 모든 요건을 함께 적용합니다. 실행 조건 승인과 졸업 판정은 별도입니다.'
              : '저장한 요건 설명을 적용합니다. 실행 조건 승인과 졸업 판정은 별도입니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('검토·적용'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    await _run(() async {
      await widget.repository.apply(widget.actorId, parent!.id);
      _message = '요건이 적용되었습니다. 이제 실행 조건 초안을 저장할 수 있습니다.';
    });
  }

  bool validateForMetadata() => _form.currentState?.validate() ?? true;
  Future<void> _save() => _run(() async {
    if (!ready ||
        widget.metadataDirty ||
        _gateway == null ||
        _uncertain ||
        _conflict) {
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;
    final from = int.parse(_values['yearFrom']!);
    final to = int.parse(_values['yearTo']!);
    if (to < from || to - from >= 200) {
      throw const FormatException('적용 입학연도는 순서대로 200년 미만 범위로 입력하세요.');
    }
    final tracks = (_values['tracks'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (tracks.isEmpty ||
        tracks.length > 32 ||
        tracks.toSet().length != tracks.length ||
        tracks.any((s) => s.length > 64)) {
      throw const FormatException('이수 경로를 중복 없이 1~32개 입력하세요. 각 64자 이내입니다.');
    }
    if (_selectedEvidence.isEmpty ||
        _selectedEvidence.length > 8 ||
        !_evidence.keys.toSet().containsAll(_selectedEvidence)) {
      throw const FormatException('검토한 근거 문단을 1~8개 선택하세요.');
    }
    final condition = draft.condition(
      widget.ruleType,
      courses,
      _certificates,
      widget.description,
    );
    final entry = OfficialProgramRuleInput(
      ruleId: rule!.id,
      expectedVersion: rule!.version,
      condition: condition,
      evidenceChunkIds: _selectedEvidence.toList(),
    );
    final old = _existing;
    if (old != null &&
        (old.sourceVersion != parent!.version || old.status != 'draft')) {
      throw const FormatException('원본 요건이나 실행 초안이 바뀌었습니다. 다시 읽어주세요.');
    }
    final rules = [
      if (old != null)
        for (final r in old.rules.where((r) => r.ruleId != rule!.id))
          OfficialProgramRuleInput(
            ruleId: r.ruleId,
            expectedVersion: r.sourceVersion,
            condition: r.condition,
            evidenceChunkIds: r.evidence.map((e) => e.chunkId).toList(),
          ),
      entry,
    ];
    try {
      final api = OfficialProgramAdminApi(_gateway!);
      final saved = old == null
          ? await api.create(
              OfficialProgramCreate(
                admissionYearFrom: from,
                admissionYearTo: to,
                tracks: tracks,
                rules: rules,
                ruleSetId: parent!.kind == AdminKind.ruleSet
                    ? parent!.id
                    : null,
                ruleId: parent!.kind == AdminKind.rule ? parent!.id : null,
                expectedSourceVersion: parent!.version,
              ),
            )
          : await api.replace(
              old.id,
              OfficialProgramReplace(
                admissionYearFrom: from,
                admissionYearTo: to,
                tracks: tracks,
                rules: rules,
                expectedVersion: old.version,
              ),
            );
      _ensure();
      if (saved.status != 'draft' ||
          (saved.ruleSetId ?? saved.ruleId) != parent!.id ||
          saved.institutionId != widget.schoolId ||
          saved.sourceVersion != parent!.version ||
          !saved.rules.any(
            (r) => r.ruleId == rule!.id && r.sourceVersion == rule!.version,
          )) {
        throw const FormatException('요청과 다른 실행 초안입니다. 서버 목록을 다시 확인하세요.');
      }
      _existing = saved;
      _programId = saved.id;
      _initial = _fingerprint;
      _message = '계산 조건 초안을 서버에 저장했습니다. 아직 승인되지 않았습니다.';
    } on AuthFailure catch (e) {
      _reloaded = false;
      _uncertain = e.status == null || e.status! >= 500;
      _conflict = e.status == 409;
      rethrow;
    } on FormatException {
      _reloaded = false;
      _uncertain = true;
      rethrow;
    }
  });
  Widget _text(
    Map<String, String> values,
    String key,
    String label, {
    bool required = true,
    bool number = false,
    bool year = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: FieldLabel(
      label: '$label${required ? ' *' : ' (선택)'}',
      child: Semantics(
        label: label,
        child: TextFormField(
          key: ValueKey(
            'execution-$key-${identityHashCode(values)}-$_inputRevision',
          ),
          initialValue: values[key] ?? '',
          enabled: !_busy && !_uncertain && !_conflict,
          decoration: InputDecoration(
            errorText:
                _serverFields.any(
                  (f) =>
                      f.split('.').last ==
                          (const {
                                'yearFrom': 'admission_year_from',
                                'yearTo': 'admission_year_to',
                                'minimumCredits': 'minimum_credits',
                                'minimumGradePoints': 'minimum_grade_points',
                                'comparisonGradeScale':
                                    'comparison_grade_scale',
                                'thesisType': 'thesis_type',
                                'acceptedGrades': 'accepted_grades',
                              }[key] ??
                              key) ||
                      key == 'minimum' && f.endsWith('.minimum'),
                )
                ? '서버에서 이 입력을 확인해 달라고 요청했습니다.'
                : null,
          ),
          keyboardType: number || year
              ? TextInputType.number
              : TextInputType.text,
          onChanged: (v) {
            setState(() => values[key] = v);
            widget.onChanged();
          },
          validator: (v) => year
              ? (RegExp(r'^[1-9]\d{3}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : '네 자리 입학연도를 입력하세요.')
              : number
              ? validateCalculationAmount(v, optional: !required)
              : (required && (v?.trim().isEmpty ?? true)
                    ? '$label 입력이 필요합니다.'
                    : (v?.length ?? 0) >
                          (key == 'tracks'
                              ? 2080
                              : key == 'acceptedGrades'
                              ? 2580
                              : 128)
                    ? '입력 길이를 확인하세요.'
                    : null),
        ),
      ),
    ),
  );
  Widget _check(String label, bool value, ValueChanged<bool> change) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: _busy || _uncertain || _conflict
            ? null
            : (v) {
                setState(() => change(v!));
                widget.onChanged();
              },
      );
  @override
  Widget build(BuildContext context) {
    if (rule != null && !widget.repository.canRead(widget.actorId, rule!)) {
      return const Text('현재 계정으로 이 요건을 관리할 수 없습니다.');
    }
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 24),
          const Text(
            '종류별 계산 조건',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (widget.ruleType == 'credits' || widget.ruleType == 'volunteer')
            ResponsivePanels(
              children: [
                _text(
                  draft.values,
                  'minimum',
                  widget.ruleType == 'credits' ? '최소 필요 학점' : '최소 필요 봉사시간',
                  number: true,
                ),
                if (widget.ruleType == 'credits')
                  _text(draft.values, 'category', '이수구분', required: false),
              ],
            ),
          if (widget.ruleType == 'required_course') ...[
            const Text('필수로 이수할 과목을 선택하세요.'),
            if (courses.isEmpty)
              const Text('선택할 과목이 없습니다. 같은 학교에 과목을 먼저 등록하세요.'),
            for (final course in courses) ...[
              _check(
                '${course.name} · ${course.value('code')}',
                draft.selected.contains(course.id),
                (v) => v
                    ? draft.selected.add(course.id)
                    : {
                        draft.selected.remove(course.id),
                        draft.referenceVersions.remove(course.id),
                      },
              ),
              if (draft.selected.contains(course.id))
                ResponsivePanels(
                  children: [
                    for (final entry in {
                      'minimumCredits': '최소 이수 학점',
                      'minimumGradePoints': '최소 평점',
                      'comparisonGradeScale': '평점 비교 척도',
                    }.entries)
                      _text(
                        draft.observations.putIfAbsent(course.id, () => {}),
                        entry.key,
                        entry.value,
                        required: false,
                        number: entry.key != 'comparisonGradeScale',
                      ),
                  ],
                ),
            ],
            for (final id in draft.selected.where(
              (id) => !courses.any((r) => r.id == id),
            ))
              _check('선택한 과목을 사용할 수 없습니다. 선택 해제 후 다시 검토하세요.', true, (v) {
                draft.selected.remove(id);
                draft.referenceVersions.remove(id);
              }),
          ],
          if (widget.ruleType == 'certificate') ...[
            const Text('인정할 자격증을 선택하세요. 선택한 자격 중 하나 이상을 보유하는 조건입니다.'),
            for (final certificate in _certificates)
              _check(
                certificate.name,
                draft.selected.contains(certificate.id),
                (v) => v
                    ? draft.selected.add(certificate.id)
                    : {
                        draft.selected.remove(certificate.id),
                        draft.referenceVersions.remove(certificate.id),
                      },
              ),
            if (_certificates.isEmpty)
              const Text('근거·초안 다시 읽기를 눌러 활성 자격증 목록을 불러오세요.'),
            for (final id in draft.selected.where(
              (id) => !_certificates.any((r) => r.id == id),
            ))
              _check('선택한 자격증을 사용할 수 없습니다. 목록을 읽거나 선택 해제하세요.', true, (v) {
                draft.selected.remove(id);
                draft.referenceVersions.remove(id);
              }),
          ],
          if (widget.ruleType == 'thesis') ...[
            ResponsivePanels(
              children: [
                _text(draft.values, 'thesisType', '논문·작품 유형'),
                _text(
                  draft.values,
                  'acceptedGrades',
                  '허용 성적 (쉼표 구분)',
                  required: false,
                ),
              ],
            ),
            _check(
              '완료 외에 승인 상태도 조건에 포함',
              draft.approval,
              (v) => draft.approval = v,
            ),
          ],
          if (widget.ruleType == 'custom')
            const Text('한 줄 요건 설명을 수동 확인 조건으로 저장합니다. 자동 충족으로 계산하지 않습니다.'),
          if (_gateway == null)
            const Text('계산 조건 서버 저장은 로그인한 관리자 계정에서 사용할 수 있습니다.'),
          if (rule == null || widget.metadataDirty)
            const Text('요건 설명을 먼저 저장하세요. 계산 조건은 별도로 저장됩니다.'),
          if (rule != null && !ready && !widget.metadataDirty) ...[
            const Text(
              '실행 조건 API에는 적용된 요건이 필요합니다. 규칙 묶음에 속하면 묶음 전체를 함께 적용합니다.',
            ),
            OutlinedButton(
              onPressed: _busy || _gateway == null ? null : _apply,
              child: const Text('요건 검토·적용'),
            ),
          ],
          if (_gateway != null) ...[
            const SizedBox(height: 12),
            ResponsivePanels(
              children: [
                _text(_values, 'yearFrom', '적용 입학연도 시작', year: true),
                _text(_values, 'yearTo', '적용 입학연도 종료', year: true),
              ],
            ),
            _text(_values, 'tracks', '이수 경로 (쉼표 구분)'),
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: const Text('근거·초안 다시 읽기'),
            ),
            if (_busy) const LinearProgressIndicator(),
            AnchoredSelectField<String>(
              externalLabel: true,
              value: _programId,
              label: '저장할 실행 초안',
              options: [
                const SelectOption('', '새 실행 초안'),
                for (final p in _programs)
                  SelectOption(
                    p.id,
                    '${p.name} · v${p.version} · ${p.admissionYearFrom}~${p.admissionYearTo}',
                  ),
                if (_programId.isNotEmpty &&
                    !_programs.any((p) => p.id == _programId))
                  SelectOption(_programId, '현재 저장한 실행 초안'),
              ],
              onChanged: (id) {
                if (!_busy) _selectProgram(id);
              },
            ),
            const SizedBox(height: 12),
            AnchoredSelectField<String>(
              externalLabel: true,
              value: _documentId,
              label: '검토된 근거 문서',
              options: [
                const SelectOption('', '문서 선택'),
                for (final d in _documents) SelectOption(d.id, d.name),
                if (_documentId.isNotEmpty &&
                    !_documents.any((d) => d.id == _documentId))
                  SelectOption(_documentId, '사용할 수 없는 문서 · 다시 선택하세요'),
              ],
              onChanged: (id) {
                if (!_busy && id.isNotEmpty) _selectDocument(id);
              },
            ),
            if (_pages.isNotEmpty)
              AnchoredSelectField<int?>(
                externalLabel: true,
                value: _page,
                label: '근거 페이지',
                options: [
                  const SelectOption(null, '페이지 선택'),
                  for (final p in _pages) SelectOption(p.page, '${p.page}쪽'),
                ],
                onChanged: (p) {
                  if (!_busy && p != null) _selectPage(p);
                },
              ),
            for (final p in _parts)
              _check(
                p.content,
                _selectedEvidence.contains(p.id),
                (v) => v
                    ? _selectedEvidence.add(p.id)
                    : _selectedEvidence.remove(p.id),
              ),
            if (_selectedEvidence.isNotEmpty) ...[
              const Text('선택한 근거'),
              for (final id in _selectedEvidence.toList())
                _check(
                  _evidence[id] ?? '사용할 수 없는 근거',
                  true,
                  (v) => _selectedEvidence.remove(id),
                ),
            ],
            if (_documents.isEmpty)
              const Text(
                '사용할 근거가 없으면 학교 문서의 근거 검토를 먼저 완료해야 합니다. 임의의 근거는 만들지 않습니다.',
              ),
            if (_uncertain || _conflict) ...[
              const Text(
                '저장 결과나 버전이 불명확합니다. 서버 목록을 다시 읽고 기존 초안을 선택해 확인하세요. 자동 재전송하지 않습니다.',
              ),
              TextButton(
                onPressed: _busy || !_reloaded
                    ? null
                    : () async {
                        if (!await confirmInputDiscard(context) || !mounted) {
                          return;
                        }
                        setState(() {
                          _existing = null;
                          _programId = '';
                          _uncertain = false;
                          _conflict = false;
                        });
                      },
                child: const Text('저장 목록 확인 후 새 초안 준비'),
              ),
            ],
            FilledButton(
              onPressed:
                  _busy ||
                      !ready ||
                      widget.metadataDirty ||
                      _uncertain ||
                      _conflict
                  ? null
                  : _save,
              child: const Text('계산 조건 초안 저장'),
            ),
            const Text('이 저장은 실행 초안 저장입니다. 실행 조건 승인과 학생 졸업 판정은 별도입니다.'),
          ],
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
        ],
      ),
    );
  }
}
