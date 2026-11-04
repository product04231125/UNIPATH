import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/guest_preview_scope.dart';
import '../api/graduation_api.dart';
import '../planning/planning_profile_cta.dart';
import '../planning/planning_repository.dart';
import '../records/personal_record_repository.dart';
import '../../shared/widgets/external_link_button.dart';
import '../../shared/widgets/feature_actions.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/surface_card.dart';

String auditStatus(String value) => switch (value) {
  'satisfied' => '충족',
  'not_satisfied' => '미충족',
  'needs_review' => '확인 필요',
  'not_applicable' => '적용 기준 없음',
  _ => '상태 확인 필요',
};
String auditIssueLabel(AuditIssue issue) =>
    const {
      'catalog_review_required': '전체 적용 규정의 검토가 필요합니다.',
      'catalog_review_unavailable': '검토된 전체 적용 규정을 확인할 수 없습니다.',
      'catalog_integrity_unavailable': '규정 근거의 무결성을 확인할 수 없습니다.',
      'approved_records_changed': '승인된 학생 기록이 변경됐습니다.',
      'record_integrity_unavailable': '학생 기록 근거의 무결성을 확인할 수 없습니다.',
      'manual_requirement': '학교 담당자의 수동 확인이 필요한 요건입니다.',
    }[issue.reason] ??
    '${const {'catalog': '적용 규정', 'records': '승인 기록', 'academics': '성적', 'volunteers': '봉사', 'certificates': '자격', 'theses': '논문'}[issue.kind] ?? '근거'} 검토가 필요합니다.';

String officialAuditTrackLabel(String? track) => switch (track) {
  'single_major' => '단일전공',
  'double_major' => '복수전공',
  null || '' => '미입력',
  _ => track,
};

String officialAuditProfileSummary(PlanningProfile? profile) {
  if (profile == null) return '학업 프로필이 없습니다.';
  final school = profile.school.trim();
  final department = profile.department.trim();
  if (school.isEmpty && department.isEmpty && profile.admissionYear == null) {
    return '학업 프로필이 없습니다.';
  }
  return [
    if (school.isNotEmpty) school else '학교 미입력',
    if (department.isNotEmpty) department else '학과 미입력',
    if (profile.admissionYear != null)
      '${profile.admissionYear}'
    else
      '입학연도 미입력',
    officialAuditTrackLabel(profile.track),
  ].join(' · ');
}

GraduationContext? officialAuditContext(PlanningProfile? profile) {
  if (profile == null || !profile.hasCatalogSchool) return null;
  final departmentId = profile.departmentId;
  final curriculumId = profile.curriculumId;
  final year = profile.admissionYear;
  final track = profile.track?.trim();
  if (departmentId == null ||
      departmentId.isEmpty ||
      curriculumId == null ||
      curriculumId.isEmpty ||
      year == null ||
      year < 1000 ||
      year > 9999 ||
      track == null ||
      track.isEmpty ||
      track.length > 64) {
    return null;
  }
  return GraduationContext(
    institutionId: profile.institutionId!,
    departmentId: departmentId,
    curriculumId: curriculumId,
    admissionYear: year,
    track: track,
  );
}

String? officialAuditAsOf(String raw) {
  final value = raw.trim();
  final parsed = DateTime.tryParse(value);
  final today = DateTime.now();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
      parsed == null ||
      parsed.toIso8601String().split('T').first != value ||
      parsed.isAfter(DateTime(today.year, today.month, today.day))) {
    return null;
  }
  return value;
}

class OfficialGraduationPage extends StatefulWidget {
  const OfficialGraduationPage({
    super.key,
    required this.auth,
    required this.ownerId,
    this.profile,
    this.onOpenSettings,
  });
  final AuthApi auth;
  final String ownerId;
  final PlanningProfile? profile;
  final VoidCallback? onOpenSettings;
  @override
  State<OfficialGraduationPage> createState() => _OfficialGraduationState();
}

class _OfficialGraduationState extends State<OfficialGraduationPage> {
  late final _api = GraduationApi.forOwner(widget.auth, widget.ownerId);
  final _date = TextEditingController(
    text: DateTime.now().toIso8601String().split('T').first,
  );
  List<GraduationAuditHeader> _history = [];
  GraduationAuditView? _result;
  String? _cursor, _error, _fingerprint;
  String _clientId = PersonalRecord.newId();
  List<String> _fields = [];
  bool _busy = false, _loading = true, _uncertain = false;
  GraduationContext? get _context => officialAuditContext(widget.profile);
  bool get _ready => _context != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.list(cursor: more ? _cursor : null);
      if (mounted) {
        setState(() {
          _history = [if (more) ..._history, ...page.items];
          _cursor = page.nextCursor;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is AuthFailure
              ? e.message
              : '감사 이력을 읽지 못했습니다. 다시 읽기를 눌러 확인하세요.';
          if (e is AuthFailure && {401, 403, 404}.contains(e.status)) {
            _history = [];
            _result = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run() async {
    if (GuestPreviewScope.isActive(context)) {
      GuestPreviewScope.showBlockedMessage(context);
      return;
    }
    if (_busy) return;
    _fields = [];
    final selected = _context;
    final date = officialAuditAsOf(_date.text);
    if (selected == null || date == null) {
      setState(
        () => _error = selected == null
            ? '설정에서 등록 학교·학과·교육과정·입학연도·이수 경로를 확인하세요.'
            : '올바른 기준일을 확인하세요.',
      );
      return;
    }
    final fingerprint = '${selected.toJson()}|$date';
    if (_fingerprint != null && _fingerprint != fingerprint) {
      if (_uncertain) {
        setState(
          () => _error = '앞선 감사 결과를 확인하지 못했습니다. 원래 기준으로 다시 시도하거나 이력을 확인하세요.',
        );
        return;
      }
      _clientId = PersonalRecord.newId();
    }
    _fingerprint = fingerprint;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _api.create(
        GraduationAuditCreate(
          context: selected,
          asOf: date,
          clientId: _clientId,
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _uncertain = false;
        _fingerprint = null;
        _clientId = PersonalRecord.newId();
      });
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is AuthFailure) _fields = e.fields;
          _uncertain =
              e is! AuthFailure || e.status == null || e.status! >= 500;
          _error = e is AuthFailure
              ? '${e.message}\n선택한 기준과 입력을 유지했습니다.'
              : '결과를 확인하지 못했습니다. 같은 기준으로 재시도하거나 이력을 확인하세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detail(String id) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _api.get(id);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AuthFailure
              ? e.message
              : '이력의 상세와 현재 사용 가능 여부를 확인하지 못했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '졸업 요건',
    description: '학교가 검토한 규정과 승인 기록을 비교합니다.',
    body: [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FeatureLine.section(
              text: '학업 프로필',
              padTop: false,
              padBottom: false,
            ),
            FeatureLine.two(
              primary: officialAuditProfileSummary(widget.profile),
              secondary: _ready
                  ? '이수 경로를 포함한 감사 기준은 설정 프로필입니다. 기준일만 이 화면에서 입력합니다.'
                  : '설정에서 등록 학교와 이수 경로를 저장하면 감사를 실행할 수 있습니다.',
            ),
            if (widget.onOpenSettings != null)
              PlanningProfileSettingsCta(
                onOpenSettings: widget.onOpenSettings!,
                need: PlanningProfileNeed.catalogSchool,
                profile: widget.profile,
              ),
            const FeatureLine.section(text: '기준일'),
            TextField(
              controller: _date,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: '기준일 (YYYY-MM-DD)',
                errorText:
                    _fields.any(
                      (field) => field == 'as_of' || field.endsWith('.as_of'),
                    )
                    ? '이 입력을 확인하세요.'
                    : null,
                helperText: '미래 날짜는 사용할 수 없습니다.',
              ),
            ),
          ],
        ),
      ),
      FeatureActions(
        children: [
          FilledButton(
            onPressed: _busy ||
                    _loading ||
                    !_ready ||
                    GuestPreviewScope.isActive(context)
                ? null
                : _run,
            child: Text(_busy ? '처리 중…' : '졸업요건 감사 실행'),
          ),
        ],
      ),
      if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
      if (_loading || _busy) const LinearProgressIndicator(),
      if (_result case final r?) ...[
        const SizedBox(height: 16),
        Text(
          '감사 결과 · ${auditStatus(r.status)}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          '기준일 ${r.evaluatedOn} · 입학연도 ${r.context.admissionYear} · ${officialAuditTrackLabel(r.context.track)}',
        ),
        Text(
          r.catalogComplete ? '전체 적용 규정 검토 확인됨' : '전체 적용 규정 검토가 완료되지 않았습니다.',
        ),
        Text(
          r.eligibleAsOf
              ? '당시 기준일에 요건 충족이 확인됐습니다.'
              : '당시 기준일의 전체 요건 충족으로 확인되지 않았습니다.',
        ),
        Text(
          r.currentUsable
              ? '현재 사용할 수 있는 근거입니다.'
              : '현재 사용할 수 없는 근거입니다. 재검토 후 새 감사를 실행하세요.',
        ),
        if (r.issues.isNotEmpty) const Text('감사 당시 확인 필요 사항'),
        for (final issue in r.issues) Text(auditIssueLabel(issue)),
        if (r.currentIssues.isNotEmpty) const Text('현재 재검토 사유'),
        for (final issue in r.currentIssues) Text(auditIssueLabel(issue)),
        for (final row in r.results)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${row.title} · ${auditStatus(row.status)}'),
                  if (row.current != null)
                    Text(
                      '확인 값 ${row.current} · 필요 값 ${row.required ?? '미확인'} · 부족 값 ${row.deficit ?? '미확인'}',
                    ),
                  if (row.missingCourseIds.isNotEmpty)
                    Text('미이수 확인 과목 ${row.missingCourseIds.length}개'),
                  if (row.uncertainCourseIds.isNotEmpty)
                    Text('확인 필요 과목 ${row.uncertainCourseIds.length}개'),
                ],
              ),
            ),
          ),
        Text('판정 근거', style: Theme.of(context).textTheme.titleMedium),
        for (final program in r.criteria) ...[
          Text('${program.name} · 판 ${program.sourceVersion}'),
          for (final rule in program.rules) ...[
            Text(rule.title),
            for (final source in rule.evidence) ...[
              Text(
                '${source.title} · ${source.page}쪽 · 문서 판 ${source.documentVersion}',
              ),
              ExternalLinkButton(url: source.sourceUrl, label: '규정 원문 확인'),
            ],
          ],
        ],
        for (final evidence in r.recordEvidence)
          Text('승인 기록 근거 · 원본 ${evidence.sourcePage}쪽'),
        if (r.criteria.isEmpty) const Text('사용한 규정 근거가 없습니다.'),
      ],
      FeatureLine.section(
        text: '감사 이력',
        trailing: FeatureLine.reload(
          onPressed: _busy || _loading ? null : _load,
        ),
      ),
      if (!_loading && _history.isEmpty)
        const FeatureLine.one(text: '저장된 감사 이력이 없습니다.'),
      for (final row in _history)
        InkWell(
          onTap: _busy ? null : () => _detail(row.id),
          child: FeatureLine.two(
            primary: '${row.evaluatedOn} · ${auditStatus(row.status)}',
            secondary: '당시 결과입니다. 상세에서 현재 사용 가능 여부를 확인하세요.',
          ),
        ),
      if (_cursor != null)
        TextButton(
          onPressed: _busy || _loading ? null : () => _load(more: true),
          child: const Text('감사 이력 더 보기'),
        ),
    ],
  );
}
