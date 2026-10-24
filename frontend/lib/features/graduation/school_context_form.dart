import 'package:flutter/material.dart';

import '../api/graduation_api.dart';
import '../api/student_api.dart';
import '../api/student_api_models.dart';
import '../api/student_catalog_api.dart';
import '../auth/auth_api.dart';
import '../../shared/widgets/anchored_select_field.dart';

/// Explicit registered identifiers, never names inferred from a personal profile.
class SchoolContextForm extends StatefulWidget {
  const SchoolContextForm({
    super.key,
    required this.api,
    this.disabled = false,
    this.showStudy = true,
    this.showDate = true,
    this.onChanged,
    this.initialInstitutionId,
    this.initialDepartmentId,
    this.initialCurriculumId,
    this.initialAdmissionYear,
    this.initialTrack,
    this.lockInstitution = false,
  });
  final ApiGateway api;
  final bool disabled;
  final bool showStudy, showDate;
  final VoidCallback? onChanged;
  final String? initialInstitutionId,
      initialDepartmentId,
      initialCurriculumId,
      initialTrack;
  final int? initialAdmissionYear;
  final bool lockInstitution;
  @override
  State<SchoolContextForm> createState() => SchoolContextFormState();
}

class SchoolContextFormState extends State<SchoolContextForm> {
  late final _catalog = StudentCatalogApi(widget.api);
  final year = TextEditingController(), track = TextEditingController();
  final date = TextEditingController(
    text: DateTime.now().toIso8601String().split('T').first,
  );
  List<StudentInstitutionView> _schools = [];
  List<StudentDepartmentPublicView> _departments = [];
  List<StudentCurriculumPublicView> _curricula = [];
  String? _school, _department, _curriculum, _error;
  bool _loading = true;
  String? get institutionId => _loading || _error != null ? null : _school;
  String? get departmentId => _department;
  String? get curriculumId => _curriculum;
  bool get hasSelection =>
      _school != null || _department != null || _curriculum != null;
  List<String> _fields = [];
  void showErrors(List<String> fields) => setState(() => _fields = fields);
  String? _fieldError(String name) =>
      _fields.any((field) => field == name || field.endsWith('.$name'))
      ? '이 입력을 확인하세요.'
      : null;
  GraduationContext? get value {
    final y = int.tryParse(year.text);
    if (_loading ||
        _school == null ||
        _department == null ||
        _curriculum == null ||
        y == null ||
        y < 1000 ||
        y > 9999 ||
        track.text.trim().isEmpty ||
        track.text.trim().length > 64) {
      return null;
    }
    return GraduationContext(
      institutionId: _school!,
      departmentId: _department!,
      curriculumId: _curriculum!,
      admissionYear: y,
      track: track.text.trim(),
    );
  }

  String? get asOf {
    final raw = date.text.trim();
    final d = DateTime.tryParse(raw);
    final today = DateTime.now();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) ||
        d == null ||
        d.toIso8601String().split('T').first != raw ||
        d.isAfter(DateTime(today.year, today.month, today.day))) {
      return null;
    }
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _school = widget.initialInstitutionId;
    _department = widget.initialDepartmentId;
    _curriculum = widget.initialCurriculumId;
    year.text = widget.initialAdmissionYear?.toString() ?? '';
    track.text = widget.initialTrack ?? '';
    year.addListener(_notifyChanged);
    track.addListener(_notifyChanged);
    date.addListener(_notifyChanged);
    _load();
  }

  void _notifyChanged() => widget.onChanged?.call();

  @override
  void dispose() {
    year.dispose();
    track.dispose();
    date.dispose();
    super.dispose();
  }

  Future<List<T>> _all<T extends StudentPayload>(
    StudentResource<T> resource, {
    String? school,
    String? department,
  }) async {
    final rows = <T>[];
    String? cursor;
    do {
      final page = await _catalog.list(
        resource,
        institutionId: school,
        departmentId: department,
        cursor: cursor,
      );
      rows.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    return rows;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schools = await _all(StudentCatalogResources.institutions);
      final departments = _school == null
          ? <StudentDepartmentPublicView>[]
          : await _all(StudentCatalogResources.departments, school: _school);
      final curricula = _department == null
          ? <StudentCurriculumPublicView>[]
          : await _all(
              StudentCatalogResources.curricula,
              school: _school,
              department: _department,
            );
      if (mounted) {
        setState(() {
          _schools = schools;
          _departments = departments;
          _curricula = curricula;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AuthFailure
              ? e.message
              : '학교 기준을 읽지 못했습니다. 선택과 입력을 유지했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) ...[
        Text(_error!),
        TextButton(
          onPressed: _loading || widget.disabled ? null : _load,
          child: const Text('학교 기준 다시 읽기'),
        ),
      ],
      if (widget.lockInstitution)
        Text(
          '검토 학교: ${_schools.where((s) => s.id == _school).firstOrNull?.name ?? '학교 기준 확인 중'}',
        )
      else
        AnchoredSelectField<String?>(
          value: _schools.any((s) => s.id == _school) ? _school : null,
          label: '학교',
          searchable: true,
          options: [
            const SelectOption(null, '학교 선택'),
            ..._schools.map((s) => SelectOption(s.id, s.name)),
          ],
          onChanged: (v) {
            if (_loading || widget.disabled || widget.lockInstitution) return;
            setState(() {
              _school = v;
              _department = null;
              _curriculum = null;
              _departments = [];
              _curricula = [];
            });
            widget.onChanged?.call();
            _load();
          },
        ),
      const SizedBox(height: 12),
      AnchoredSelectField<String?>(
        value: _departments.any((s) => s.id == _department)
            ? _department
            : null,
        label: '학과',
        searchable: true,
        options: [
          const SelectOption(null, '학과 선택'),
          ..._departments.map((s) => SelectOption(s.id, s.name)),
        ],
        onChanged: (v) {
          if (_loading || widget.disabled) return;
          setState(() {
            _department = v;
            _curriculum = null;
            _curricula = [];
          });
          widget.onChanged?.call();
          _load();
        },
      ),
      const SizedBox(height: 12),
      AnchoredSelectField<String?>(
        value: _curricula.any((s) => s.id == _curriculum) ? _curriculum : null,
        label: '교육과정',
        searchable: true,
        options: [
          const SelectOption(null, '교육과정 선택'),
          ..._curricula.map((s) => SelectOption(s.id, '${s.name} (${s.year})')),
        ],
        onChanged: (v) {
          if (!_loading && !widget.disabled) {
            setState(() => _curriculum = v);
            widget.onChanged?.call();
          }
        },
      ),
      const SizedBox(height: 12),
      if (widget.showStudy)
        TextField(
          controller: year,
          enabled: !widget.disabled,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: InputDecoration(
            labelText: '입학연도',
            errorText: _fieldError('admission_year'),
          ),
        ),
      if (widget.showStudy)
        TextField(
          controller: track,
          enabled: !widget.disabled,
          maxLength: 64,
          decoration: InputDecoration(
            labelText: '이수 경로',
            errorText: _fieldError('track'),
            helperText: '학교에서 등록한 이수 경로를 입력하세요.',
          ),
        ),
      if (widget.showDate)
        TextField(
          controller: date,
          enabled: !widget.disabled,
          decoration: InputDecoration(
            labelText: '기준일 (YYYY-MM-DD)',
            errorText: _fieldError('as_of'),
            helperText: '미래 날짜는 사용할 수 없습니다.',
          ),
        ),
      if (!_loading && _error == null && _schools.isEmpty)
        const Text('등록된 학교가 없습니다. 학교 기준 등록 후 이용할 수 있습니다.'),
    ],
  );
}
