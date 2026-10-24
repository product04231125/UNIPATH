import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/official_records_api.dart';
import '../api/record_source_api.dart';
import '../api/rule_program_api.dart';
import '../api/rule_program_models.dart';
import '../api/student_catalog_api.dart';
import '../api/student_api_models.dart';
import '../auth/auth_api.dart';
import '../graduation/school_context_form.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/input_dialog.dart';
import 'personal_record_repository.dart';
import 'official_record_labels.dart';

class OfficialRecordEditor extends StatefulWidget {
  const OfficialRecordEditor({
    super.key,
    required this.auth,
    required this.ownerId,
    required this.source,
    this.batch,
  });
  final AuthApi auth;
  final String ownerId;
  final RecordSource source;
  final SchoolRecordBatchView? batch;
  @override
  State<OfficialRecordEditor> createState() => _EditorState();
}

class _EditorState extends State<OfficialRecordEditor> {
  late final _api = OfficialRecordsApi.forOwner(
    widget.auth,
    widget.ownerId,
    admin: true,
  );
  final _context = GlobalKey<SchoolContextFormState>();
  final _pages = TextEditingController(), _date = TextEditingController();
  final _changes = ValueNotifier(0);
  late String _kind =
      widget.batch?.kind ??
      switch (widget.source.documentKind) {
        RecordSourceKind.volunteer => 'volunteers',
        RecordSourceKind.certificate => 'certificates',
        RecordSourceKind.thesis => 'theses',
        _ => 'academics',
      };
  late String _coverage = widget.batch?.coverage ?? 'partial';
  late final List<SchoolRecordPayload> _rows = widget.batch == null
      ? []
      : [...recordRows(widget.batch!.data)];
  String _clientId = PersonalRecord.newId();
  String? _error, _fingerprint;
  bool _busy = false, _uncertain = false, _dirty = false;
  List<String> _fields = [];
  @override
  void initState() {
    super.initState();
    _pages.text = widget.batch?.pageCount.toString() ?? '';
    _date.text = widget.batch?.recordsAsOf ?? '';
  }

  @override
  void dispose() {
    _pages.dispose();
    _date.dispose();
    _changes.dispose();
    super.dispose();
  }

  Future<void> _row({int? index}) async {
    if (_busy || _rows.length >= 500 && index == null) return;
    setState(() => _busy = true);
    final result = await showInputDialog<SchoolRecordPayload>(
      context: context,
      builder: (_) => OfficialRecordRowDialog(
        api: widget.auth.forOwner(widget.ownerId),
        institutionId: widget.source.institutionId,
        kind: _kind,
        row: index == null ? null : _rows[index],
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) {
        if (index == null) {
          _rows.add(result);
        } else {
          _rows[index] = result;
        }
        _dirty = true;
      }
    });
  }

  Future<void> _remove(int index) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('이 초안에서 기록을 뺄까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('유지'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('기록 빼기'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      setState(() {
        _rows.removeAt(index);
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final form = _context.currentState;
    final pages = int.tryParse(_pages.text);
    final date = _date.text.trim();
    final parsed = DateTime.tryParse(date);
    if (form?.institutionId != widget.source.institutionId ||
        pages == null ||
        pages < 1 ||
        pages > 500 ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().split('T').first != date ||
        date.compareTo(widget.source.issuedOn) > 0) {
      setState(() => _error = '학교 기준·원본 전체 쪽수(1~500)·기록 기준일(발급일 이하)을 확인하세요.');
      return;
    }
    final yearText = form!.year.text.trim(), trackText = form.track.text.trim();
    final year = int.tryParse(yearText);
    if (yearText.isNotEmpty && (year == null || year < 1000 || year > 9999) ||
        trackText.length > 64) {
      setState(() => _error = '입학연도와 이수 경로를 확인하세요.');
      return;
    }
    final scope = SchoolRecordContext(
      departmentId: form.departmentId,
      curriculumId: form.curriculumId,
      admissionYear: year,
      track: trackText.isEmpty ? null : trackText,
    );
    int sourcePage(SchoolRecordPayload row) => switch (row) {
      SchoolRecordAcademicRecord r => r.sourcePage,
      SchoolRecordVolunteerRecord r => r.sourcePage,
      SchoolRecordCertificateRecord r => r.sourcePage,
      SchoolRecordThesisRecord r => r.sourcePage,
      _ => 0,
    };
    if (_rows.any((r) => sourcePage(r) > pages)) {
      setState(() => _error = '기록의 원본 쪽이 전체 쪽수보다 큽니다.');
      return;
    }
    final SchoolRecordData data = switch (_kind) {
      'academics' => SchoolRecordAcademicData(
        pageCount: pages,
        recordsAsOf: date,
        coverage: _coverage,
        context: scope,
        kind: _kind,
        records: _rows.cast<SchoolRecordAcademicRecord>(),
      ),
      'volunteers' => SchoolRecordVolunteerData(
        pageCount: pages,
        recordsAsOf: date,
        coverage: _coverage,
        context: scope,
        kind: _kind,
        records: _rows.cast<SchoolRecordVolunteerRecord>(),
      ),
      'certificates' => SchoolRecordCertificateData(
        pageCount: pages,
        recordsAsOf: date,
        coverage: _coverage,
        context: scope,
        kind: _kind,
        records: _rows.cast<SchoolRecordCertificateRecord>(),
      ),
      _ => SchoolRecordThesisData(
        pageCount: pages,
        recordsAsOf: date,
        coverage: _coverage,
        context: scope,
        kind: _kind,
        records: _rows.cast<SchoolRecordThesisRecord>(),
      ),
    };
    final fingerprint = jsonEncode(data.toJson());
    if (_fingerprint != null && _fingerprint != fingerprint) {
      if (_uncertain) {
        setState(
          () => _error = '이전 저장 결과를 확인하지 못했습니다. 원래 내용으로 재시도하거나 목록에서 확인하세요.',
        );
        return;
      }
      _clientId = PersonalRecord.newId();
    }
    _fingerprint = fingerprint;
    setState(() {
      _busy = true;
      _error = null;
      _fields = [];
    });
    try {
      if (widget.batch case final batch?) {
        await _api.replace(
          batch.id,
          SchoolRecordBatchReplace(expectedVersion: batch.version, data: data),
        );
      } else {
        await _api.create(
          SchoolRecordBatchCreate(
            sourceId: widget.source.id,
            expectedSourceVersion: widget.source.version,
            clientId: _clientId,
            data: data,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uncertain =
              e is! AuthFailure || e.status == null || e.status! >= 500;
          _fields = e is AuthFailure ? e.fields : [];
          form.showErrors(_fields);
          _error =
              '${e is AuthFailure ? e.message : '저장 결과를 확인하지 못했습니다.'}\n검토 내용과 입력을 유지했습니다.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? fieldError(String field) =>
      _fields.any((s) => s == field || s.endsWith('.$field'))
      ? '이 입력을 확인하세요.'
      : null;
  @override
  Widget build(BuildContext context) => InputDialog(
    title: Text(widget.batch == null ? '학교 확인 기록 초안 등록' : '학교 확인 기록 초안 수정'),
    changes: Listenable.merge([_changes, _pages, _date]),
    saving: _busy,
    hasContent: () => widget.batch == null
        ? _pages.text.isNotEmpty ||
              _date.text.isNotEmpty ||
              _rows.isNotEmpty ||
              _dirty
        : _dirty ||
              _pages.text != widget.batch!.pageCount.toString() ||
              _date.text != widget.batch!.recordsAsOf,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${widget.source.filename} · 발급일 ${widget.source.issuedOn}'),
        const Text(
          '원본을 직접 대조해 입력하세요. 문자 성적을 숫자로 환산하거나 개인 기록을 자동 복사하지 않습니다. 빈 숫자는 미확인으로 보존합니다.',
        ),
        SchoolContextForm(
          key: _context,
          api: widget.auth.forOwner(widget.ownerId),
          disabled: _busy,
          showDate: false,
          initialInstitutionId: widget.source.institutionId,
          initialDepartmentId:
              widget.batch?.context.departmentId ?? widget.source.departmentId,
          initialCurriculumId:
              widget.batch?.context.curriculumId ?? widget.source.curriculumId,
          initialAdmissionYear: widget.batch?.context.admissionYear,
          initialTrack: widget.batch?.context.track,
          lockInstitution: true,
          onChanged: () {
            _dirty = true;
            _changes.value++;
          },
        ),
        const Text('학과·입학연도·이수 경로는 승인 전에 반드시 확인해야 합니다. 교육과정 미지정은 별도 문맥입니다.'),
        TextField(
          controller: _pages,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '원본 전체 쪽수',
            errorText: fieldError('page_count'),
          ),
        ),
        TextField(
          controller: _date,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: '기록 기준일 (YYYY-MM-DD)',
            errorText: fieldError('records_as_of'),
          ),
        ),
        AnchoredSelectField(
          value: _kind,
          label: '기록 종류',
          options: [
            'academics',
            'volunteers',
            'certificates',
            'theses',
          ].map((k) => SelectOption(k, recordLabel(k))).toList(),
          onChanged: (v) {
            if (!_busy && widget.batch == null && _rows.isEmpty) {
              setState(() {
                _kind = v;
                _dirty = true;
              });
            }
          },
        ),
        const Text('기록을 추가한 뒤에는 종류를 바꿀 수 없습니다. 종류를 바꾸려면 기록을 먼저 빼세요.'),
        AnchoredSelectField(
          value: _coverage,
          label: '검토 범위',
          options: [
            'partial',
            'complete',
          ].map((v) => SelectOption(v, recordLabel(v))).toList(),
          onChanged: (v) {
            if (!_busy) {
              setState(() {
                _coverage = v;
                _dirty = true;
              });
            }
          },
        ),
        const Text(
          '전체 기록 확인에서 0건은 해당 종류의 기록이 없음을 확인했다는 뜻입니다. 일부 검토는 감사 계산에 사용할 수 없습니다.',
        ),
        for (final (index, row) in _rows.indexed)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(recordSummary(row, widget.batch?.references ?? [])),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: _busy ? null : () => _row(index: index),
                        child: const Text('기록 수정'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _remove(index),
                        child: const Text('기록 빼기'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        TextButton(
          onPressed: _busy || _rows.length >= 500 ? null : () => _row(),
          child: const Text('대조한 기록 추가'),
        ),
        if (_error != null) Text(_error!),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => InputDialog.cancel<void>(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: const Text('검토 초안 저장'),
      ),
    ],
  );
}

class OfficialRecordRowDialog extends StatefulWidget {
  const OfficialRecordRowDialog({
    super.key,
    required this.api,
    required this.institutionId,
    required this.kind,
    this.row,
  });
  final ApiGateway api;
  final String institutionId, kind;
  final SchoolRecordPayload? row;
  @override
  State<OfficialRecordRowDialog> createState() => _RowState();
}

class _RowState extends State<OfficialRecordRowDialog> {
  final _page = TextEditingController(),
      _amount = TextEditingController(),
      _category = TextEditingController(),
      _grade = TextEditingController(),
      _points = TextEditingController(),
      _scale = TextEditingController(),
      _type = TextEditingController(),
      _expires = TextEditingController();
  late final String _clientId = switch (widget.row) {
    SchoolRecordAcademicRecord r => r.clientId,
    SchoolRecordVolunteerRecord r => r.clientId,
    SchoolRecordCertificateRecord r => r.clientId,
    SchoolRecordThesisRecord r => r.clientId,
    _ => PersonalRecord.newId(),
  };
  final _changes = ValueNotifier(0);
  List<StudentCoursePublicView> _courses = [];
  List<CertificateRegistryCertificateView> _certificates = [];
  String? _selection, _error;
  String _status = 'needs_review';
  bool? _completed;
  bool _validity = false, _loading = false;
  late final String _initialSnapshot;
  String get _snapshot => jsonEncode([
    for (final c in _controllers) c.text,
    _selection,
    _status,
    _completed,
    _validity,
  ]);
  List<TextEditingController> get _controllers => [
    _page,
    _amount,
    _category,
    _grade,
    _points,
    _scale,
    _type,
    _expires,
  ];
  @override
  void initState() {
    super.initState();
    switch (widget.row) {
      case SchoolRecordAcademicRecord r:
        _page.text = '${r.sourcePage}';
        _selection = r.courseId;
        _status = r.completionStatus;
        _amount.text = r.earnedCredits ?? '';
        _category.text = r.category ?? '';
        _grade.text = r.originalGrade ?? '';
        _points.text = r.gradePoints ?? '';
        _scale.text = r.gradeScale ?? '';
      case SchoolRecordVolunteerRecord r:
        _page.text = '${r.sourcePage}';
        _status = r.approvalStatus;
        _amount.text = r.approvedHours ?? '';
      case SchoolRecordCertificateRecord r:
        _page.text = '${r.sourcePage}';
        _selection = r.certificateId;
        _status = r.approvalStatus;
        _validity = r.validityKnown;
        _expires.text = r.expiresOn ?? '';
      case SchoolRecordThesisRecord r:
        _page.text = '${r.sourcePage}';
        _status = r.approvalStatus;
        _type.text = r.thesisType;
        _grade.text = r.grade ?? '';
        _completed = r.isCompleted;
      default:
        break;
    }
    _initialSnapshot = _snapshot;
    if (widget.kind == 'academics' || widget.kind == 'certificates') _load();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _changes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      String? cursor;
      final courses = <StudentCoursePublicView>[],
          certificates = <CertificateRegistryCertificateView>[];
      do {
        if (widget.kind == 'academics') {
          final page = await StudentCatalogApi(widget.api).list(
            StudentCatalogResources.courses,
            institutionId: widget.institutionId,
            cursor: cursor,
          );
          courses.addAll(page.items);
          cursor = page.nextCursor;
        } else {
          final page = await CertificateCatalogApi(widget.api)
              .certificates(cursor: cursor);
          certificates.addAll(page.items.where((r) => r.status == 'active'));
          cursor = page.nextCursor;
        }
      } while (cursor != null);
      if (mounted) {
        setState(() {
          _courses = courses;
          _certificates = certificates;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AuthFailure
              ? e.message
              : '등록 기준을 읽지 못했습니다. 다시 읽으세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();
  bool amountValid(TextEditingController c) {
    final raw = c.text.trim();
    return raw.isEmpty ||
        RegExp(r'^\d+(\.\d{1,6})?$').hasMatch(raw) &&
            (double.tryParse(raw) ?? double.infinity) <= 1000000;
  }

  void _save() {
    final page = int.tryParse(_page.text);
    if (page == null ||
        page < 1 ||
        page > 500 ||
        !amountValid(_amount) ||
        !amountValid(_points) ||
        _controllers.any((c) => c != _page && c.text.trim().length > 128)) {
      setState(
        () => _error =
            '원본 쪽(1~500), 숫자(0~1000000·소수 6자리 이하), 글자 수(128자 이하)를 확인하세요.',
      );
      return;
    }
    SchoolRecordPayload? result;
    switch (widget.kind) {
      case 'academics':
        final course = _courses.where((r) => r.id == _selection).firstOrNull;
        if (course == null ||
            (text(_points) == null) != (text(_scale) == null)) {
          setState(() => _error = '등록 과목을 선택하고 숫자 평점·척도는 함께 입력하거나 비워두세요.');
          return;
        }
        result = SchoolRecordAcademicRecord(
          clientId: _clientId,
          sourcePage: page,
          courseId: course.id,
          expectedCourseVersion: course.version,
          completionStatus: _status,
          earnedCredits: text(_amount),
          category: text(_category),
          originalGrade: text(_grade),
          gradePoints: text(_points),
          gradeScale: text(_scale),
        );
      case 'volunteers':
        result = SchoolRecordVolunteerRecord(
          clientId: _clientId,
          sourcePage: page,
          approvalStatus: _status,
          approvedHours: text(_amount),
        );
      case 'certificates':
        final certificate = _certificates
            .where((r) => r.id == _selection)
            .firstOrNull;
        final raw = text(_expires), date = DateTime.tryParse(_expires.text);
        if (certificate == null ||
            raw != null &&
                (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) ||
                    date == null ||
                    date.toIso8601String().split('T').first != raw)) {
          setState(() => _error = '활성 자격과 유효한 만료일을 확인하세요.');
          return;
        }
        if (!_validity && raw != null) {
          setState(() => _error = '만료일을 확인했다면 유효기간 확인을 표시하세요.');
          return;
        }
        result = SchoolRecordCertificateRecord(
          clientId: _clientId,
          sourcePage: page,
          certificateId: certificate.id,
          expectedCertificateVersion: certificate.version,
          approvalStatus: _status,
          expiresOn: raw,
          validityKnown: _validity,
        );
      case 'theses':
        if (text(_type) == null) {
          setState(() => _error = '논문 유형을 입력하세요.');
          return;
        }
        result = SchoolRecordThesisRecord(
          clientId: _clientId,
          sourcePage: page,
          thesisType: text(_type)!,
          approvalStatus: _status,
          isCompleted: _completed,
          grade: text(_grade),
        );
    }
    Navigator.pop(context, result);
  }

  TextField field(String label, TextEditingController c) => TextField(
    controller: c,
    decoration: InputDecoration(labelText: label),
  );
  @override
  Widget build(BuildContext context) {
    final academic = widget.kind == 'academics';
    return InputDialog(
      title: Text('${recordLabel(widget.kind)} 기록 대조'),
      changes: Listenable.merge([_changes, ..._controllers]),
      hasContent: () => _snapshot != _initialSnapshot,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (academic || widget.kind == 'certificates') ...[
            TextButton(
              onPressed: _loading ? null : _load,
              child: const Text('등록 기준 다시 읽기'),
            ),
            AnchoredSelectField<String?>(
              value:
                  (academic
                      ? _courses.any((r) => r.id == _selection)
                      : _certificates.any((r) => r.id == _selection))
                  ? _selection
                  : null,
              label: academic ? '등록 과목' : '등록 자격',
              searchable: true,
              options: [
                const SelectOption(null, '선택하세요'),
                if (academic)
                  ..._courses.map(
                    (r) => SelectOption(
                      r.id,
                      '${r.name} (${r.code}) · 판 ${r.version}',
                    ),
                  )
                else
                  ..._certificates.map(
                    (r) => SelectOption(
                      r.id,
                      '${r.name} (${r.code}) · 판 ${r.version}',
                    ),
                  ),
              ],
              onChanged: (v) {
                if (!_loading) {
                  setState(() {
                    _selection = v;
                  });
                }
              },
            ),
          ],
          field('원본 쪽', _page),
          AnchoredSelectField(
            value: _status,
            label: academic ? '이수 상태' : '원본의 승인 상태',
            options:
                (academic
                        ? ['completed', 'failed', 'in_progress', 'needs_review']
                        : ['approved', 'pending', 'rejected', 'needs_review'])
                    .map((v) => SelectOption(v, recordLabel(v)))
                    .toList(),
            onChanged: (v) => setState(() {
              _status = v;
            }),
          ),
          if (academic || widget.kind == 'volunteers')
            field(
              academic ? '취득 학점 (미확인 시 비움)' : '승인 봉사시간 (미확인 시 비움)',
              _amount,
            ),
          if (academic) ...[
            field('이수 분류', _category),
            field('원문 성적', _grade),
            field('숫자 평점 (원본에 있을 때만)', _points),
            field('평점 척도 (원본 그대로)', _scale),
          ],
          if (widget.kind == 'certificates') ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _validity,
              onChanged: (v) => setState(() {
                _validity = v ?? false;
              }),
              title: const Text('유효기간을 확인했습니다 (빈 만료일은 기간 제한 없음).'),
            ),
            field('만료일 (YYYY-MM-DD, 미확인 시 비움)', _expires),
          ],
          if (widget.kind == 'theses') ...[
            field('논문 유형', _type),
            AnchoredSelectField<bool?>(
              value: _completed,
              label: '완료 여부',
              options: const [
                SelectOption(null, '미확인'),
                SelectOption(true, '완료'),
                SelectOption(false, '미완료'),
              ],
              onChanged: (v) => setState(() {
                _completed = v;
              }),
            ),
            field('원문 논문 성적', _grade),
          ],
          if (_error != null) Text(_error!),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => InputDialog.cancel<SchoolRecordPayload>(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: const Text('대조 내용 반영'),
        ),
      ],
    );
  }
}
