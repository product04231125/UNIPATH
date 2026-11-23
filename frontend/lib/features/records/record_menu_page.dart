import '../../shared/app_style.dart';
import '../../shared/credits_format.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/guide_card.dart';
import '../../shared/widgets/record_tile.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/tone_chip.dart';
import 'record_display.dart';

import 'package:flutter/material.dart';

import '../../shared/drafts/form_draft_picker.dart';
import '../../shared/drafts/form_draft_store.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/surface_card.dart';
import 'course/course_term.dart';
import 'personal_record_repository.dart';
import 'personal_record_fields.dart';
import 'personal_record_form.dart';
import 'personal_repository_scope.dart';
import '../auth/auth_api.dart';
import '../auth/guest_preview_scope.dart';
import '../api/student_api.dart';
import 'course/course_status.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/external_link_button.dart';
import '../planning/planning_profile_cta.dart';
import '../planning/planning_repository.dart';
import '../../shared/widgets/page_actions.dart';

/// Temporary shared presentation only. Each feature entry owns its own
/// configuration and mounted local input state.
class RecordMenuPage extends StatefulWidget {
  const RecordMenuPage({
    super.key,
    this.contextLabel,
    required this.kind,
    required this.title,
    this.description,
    required this.listTitle,
    required this.guideTitle,
    required this.guides,
    required this.addLabel,
    required this.detailLabel,
    this.fieldsLoader,
    this.validateValues,
    this.guideActions = const [],
    this.studentApi,
    this.institutionId,
    this.planning,
    this.onOpenSettings,
  });

  final PersonalRecordKind kind;
  final String? contextLabel;
  final String title;

  /// Kept for callers; pages no longer render a description line.
  final String? description;
  final String listTitle;
  final String guideTitle;
  final List<String> guides;
  final String addLabel;
  final String detailLabel;
  final Future<List<PersonalRecordField>> Function()? fieldsLoader;
  final Future<String?> Function(Map<String, String>)? validateValues;
  final List<Widget> guideActions;
  final StudentApi? studentApi;
  final String? institutionId;
  final PlanningRepository? planning;
  final VoidCallback? onOpenSettings;

  @override
  State<RecordMenuPage> createState() => _RecordMenuPageState();
}

class _RecordMenuPageState extends State<RecordMenuPage> {
  late final PersonalRecordRepository _repository;
  bool _loading = true;
  bool _loadFailed = false;
  String _term = '';
  String _year = '';
  List<PersonalRecordField> _fields = [];
  Listenable? _importChanges;
  int _loadRevision = 0;
  bool _formOpen = false;
  @override
  void initState() {
    super.initState();
    _repository =
        PersonalRepositoryScope.read(context)?.records(widget.kind) ??
        PersonalRecordRepository(widget.kind);
    _importChanges = PersonalRepositoryScope.read(context)
        ?.importer
        ?.importedRevision;
    _importChanges?.addListener(_reloadAfterImport);
    _load();
  }

  void _reloadAfterImport() {
    _load();
  }

  @override
  void dispose() {
    _importChanges?.removeListener(_reloadAfterImport);
    _loadRevision++;
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      await _repository.load();
      final fields =
          await widget.fieldsLoader?.call() ??
          personalRecordFields(widget.kind);
      if (mounted && revision == _loadRevision) _fields = fields;
    } catch (_) {
      if (mounted && revision == _loadRevision) {
        setState(() => _loadFailed = true);
      }
    } finally {
      if (mounted && revision == _loadRevision) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showForm({
    PersonalRecord? record,
    Map<String, String>? draftValues,
    String? appliedDraftId,
  }) async {
    if (_formOpen) return;
    _formOpen = true;
    try {
      await showPersonalRecordForm(
        context: context,
        kind: widget.kind,
        repository: _repository,
        addLabel: widget.addLabel,
        record: record,
        draftValues: draftValues,
        appliedDraftId: appliedDraftId,
        fieldsLoader: widget.fieldsLoader,
        validateValues: widget.validateValues,
        onFieldsReady: (fields) {
          if (mounted) setState(() => _fields = fields);
        },
        onSaved: () {
          if (mounted) setState(() {});
        },
        studentApi: widget.studentApi,
        institutionId:
            widget.planning?.profile.institutionId ?? widget.institutionId,
        departmentId: widget.planning?.profile.departmentId,
        curriculumId: widget.planning?.profile.curriculumId,
      );
    } finally {
      _formOpen = false;
    }
  }

  Future<void> _loadDraft() async {
    if (_formOpen || GuestPreviewScope.isActive(context)) {
      if (GuestPreviewScope.isActive(context)) {
        GuestPreviewScope.showBlockedMessage(context);
      }
      return;
    }
    final entry = await showFormDraftPicker(
      context: context,
      collectionKey: formDraftCollectionKey(
        personalRecordDraftScreenId(widget.kind),
      ),
    );
    if (!mounted || entry == null) return;
    final values = {
      for (final item in entry.payload.entries) item.key: '${item.value ?? ''}',
    };
    await _showForm(draftValues: values, appliedDraftId: entry.id);
  }

  Future<void> _delete(PersonalRecord record) async {
    if (GuestPreviewScope.isActive(context)) {
      GuestPreviewScope.showBlockedMessage(context);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('개인 기록 삭제'),
        content: Text(
          '${record.value('title')} 기록을 ${_repository.isServerBacked ? '계정 서버' : '이 기기'}에서 삭제할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          FilledButton(
            style: destructiveButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (GuestPreviewScope.isActive(context)) {
      GuestPreviewScope.showBlockedMessage(context);
      return;
    }
    try {
      await _repository.delete(record.id, expectedVersion: record.version);
      if (mounted) setState(() {});
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure is AuthFailure && failure.status == 409
                  ? '연결된 자료가 있거나 기록이 변경되었습니다. 연결을 정리하거나 서버 기록을 다시 불러와 주세요.'
                  : '삭제하지 못했습니다. 기록은 유지됩니다.',
            ),
          ),
        );
      }
    }
  }

  String _display(PersonalRecord record, String key) {
    final raw = record.value(key);
    if (raw.isEmpty) return raw;
    final field = _fields.where((f) => f.key == key).firstOrNull;
    if (field == null) return raw;
    if (field.optionLabels[raw] case final label?) return label;
    if (field.options.isNotEmpty && !field.options.contains(raw)) {
      return '연결 대상 없음 · 수정에서 다시 선택하세요';
    }
    return raw;
  }

  String _date(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null
        ? iso
        : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

  void _showCourseDetail(PersonalRecord record) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(record.value('title')),
      content: SingleChildScrollView(
        child: SelectableText(
          _fields
              .where(
                (f) =>
                    !{
                      'title',
                      'academicContextId',
                      'academicEntryId',
                    }.contains(f.key) &&
                    record.value(f.key).isNotEmpty,
              )
              .map(
                (f) =>
                    '${f.label}: ${f.key == 'completion' ? courseStatusLabel(record.value(f.key)) : f.optionLabels[record.value(f.key)] ?? record.value(f.key)}',
              )
              .join('\n'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    ),
  );

  Widget _personalEntry(PersonalRecord record) {
    final kind = widget.kind;
    final isCourse = kind == PersonalRecordKind.course;
    final IconData icon;
    final AppTone tone;
    final badges = <Widget>[];
    final facts = <RecordFact>[];
    final lines = <String>[];
    if (isCourse) {
      final completion = record.value('completion');
      final status = courseStatusLabel(completion);
      tone = switch (status) {
        '이수 완료' => AppTone.success,
        '수강 중' => AppTone.info,
        '미이수' => AppTone.warning,
        _ => AppTone.accent,
      };
      icon = Icons.menu_book_outlined;
      badges.addAll([
        ToneChip(label: status, tone: tone),
        if (record.value('category').isNotEmpty)
          ToneChip(label: record.value('category')),
      ]);
      final result = [
        if (record.value('credits').isNotEmpty)
          '${recordNumber(record.value('credits'))}학점',
        if (record.value('gradingBasis') == 'pass_fail') 'P/F',
        if (record.value('grade').isNotEmpty) '성적 ${record.value('grade')}',
      ].join(' · ');
      facts.addAll([
        RecordFact(
          Icons.calendar_today_outlined,
          CourseTerm.parse(record.value('term')).label,
        ),
        if (result.isNotEmpty) RecordFact(Icons.grading_outlined, result),
      ]);
    } else if (kind == PersonalRecordKind.credential) {
      final status = _display(record, 'status');
      final earned = record.value('earnedOn');
      tone = status.contains('준비') || status.contains('응시')
          ? AppTone.warning
          : earned.isNotEmpty || status.contains('취득') || status.contains('합격')
          ? AppTone.success
          : AppTone.accent;
      icon = Icons.workspace_premium_outlined;
      badges.addAll([
        if (status.isNotEmpty) ToneChip(label: status, tone: tone),
        if (_display(record, 'level') case final level when level.isNotEmpty)
          ToneChip(label: level, tone: AppTone.info),
      ]);
      facts.addAll([
        if (_display(record, 'provider') case final provider
            when provider.isNotEmpty)
          RecordFact(Icons.apartment_outlined, provider),
        if (earned.isNotEmpty)
          RecordFact(Icons.calendar_today_outlined, '취득 ${_date(earned)}'),
        if (record.value('expiresOn') case final expires
            when expires.isNotEmpty)
          RecordFact(Icons.event_busy, '만료 ${_date(expires)}'),
      ]);
    } else {
      final type = _display(record, 'type');
      (icon, tone) = experienceVisual(type);
      final period = recordPeriodLabel(
        record.value('startedOn'),
        record.value('endedOn'),
      );
      badges.addAll([
        if (type.isNotEmpty) ToneChip(label: type, tone: tone),
        if (_display(record, 'status') case final status when status.isNotEmpty)
          ToneChip(label: status),
      ]);
      facts.addAll([
        if (period != null) RecordFact(Icons.calendar_today_outlined, period),
        if (_display(record, 'organization') case final org when org.isNotEmpty)
          RecordFact(Icons.apartment_outlined, org),
        if (_display(record, 'role') case final role when role.isNotEmpty)
          RecordFact(Icons.person_outline, role),
      ]);
      if (_display(record, 'result') case final result when result.isNotEmpty) {
        lines.add(result);
      }
    }
    if (_display(record, 'detail') case final detail when detail.isNotEmpty) {
      lines.add(detail);
    }
    return RecordTile(
      key: ValueKey('record-${kind.name}-${record.id}'),
      icon: icon,
      tone: tone,
      title: record.value('title'),
      badges: badges,
      facts: facts,
      lines: lines,
      onTap: () => _showForm(record: record),
      footer: [
        for (final field in _fields.where(
          (f) =>
              f.type == PersonalFieldType.url && record.value(f.key).isNotEmpty,
        ))
          ExternalLinkButton(url: record.value(field.key), label: field.label),
      ],
      actions: [
        if (isCourse)
          RecordAction(
            '상세 보기',
            Icons.info_outline,
            () => _showCourseDetail(record),
          ),
        RecordAction(
          '수정',
          Icons.edit_outlined,
          () => _showForm(record: record),
        ),
        RecordAction(
          '삭제',
          Icons.delete_outline,
          () => _delete(record),
          destructive: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _statePage(child: const CircularProgressIndicator());
    if (_loadFailed) {
      return _statePage(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FeatureLine.one(
              text: '개인 기록을 읽지 못했습니다. 기존 저장 내용은 덮어쓰지 않습니다.',
            ),
            FeatureLine.reload(onPressed: _load, label: '다시 시도'),
          ],
        ),
      );
    }
    final planning = widget.planning;
    if (planning == null) return _loadedPage();
    return AnimatedBuilder(
      animation: planning,
      builder: (context, _) => _loadedPage(),
    );
  }

  Widget _loadedPage() {
    final personal = _repository.records.where((r) {
      if (widget.kind != PersonalRecordKind.course) return true;
      final period = CourseTerm.parse(r.value('term'));
      return (_year.isEmpty || period.yearFilter == _year) &&
          (_term.isEmpty || period.semester == _term);
    }).toList();
    final isCourse = widget.kind == PersonalRecordKind.course;
    final profile = widget.planning?.profile;
    int creditUnits(String status) => personal
        .where((r) => courseStatusLabel(r.value('completion')) == status)
        .fold(
          0,
          (sum, r) =>
              sum + ((num.tryParse(r.value('credits')) ?? 0) * 1000).round(),
        );
    final earned = creditUnits('이수 완료');
    final ongoing = creditUnits('수강 중');
    String creditLabel(int units) =>
        formatCreditsLabel((units / 1000).toString());
    final needsProfile =
        isCourse &&
        widget.planning != null &&
        !(profile?.isConfigured ?? false) &&
        widget.onOpenSettings != null;
    final filtered = isCourse && (_year.isNotEmpty || _term.isNotEmpty);
    return FeaturePage(
      title: widget.title,
      contextLabel: widget.contextLabel,
      trailing: _headerActions(),
      body: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (needsProfile) ...[
                InfoBanner(
                  key: planningProfileSettingsCtaKey,
                  icon: Icons.school_outlined,
                  message: '학업 프로필을 등록하면 학교 교육과정 과목을 골라 추가할 수 있습니다.',
                  action: TextButton(
                    onPressed: widget.onOpenSettings,
                    child: const Text('설정 열기'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (isCourse) ...[
                StatStrip(
                  items: [
                    ('취득 학점', creditLabel(earned)),
                    ('수강 중', creditLabel(ongoing)),
                    ('총 학점', creditLabel(earned + ongoing)),
                    ('과목', '${_repository.records.length}개'),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 200,
                      child: AnchoredSelectField<String>(
                        key: const ValueKey('record-course-year-filter'),
                        value: _year,
                        label: '수강 연도',
                        options: [
                          const SelectOption('', '전체 연도'),
                          for (final year in {
                            ..._repository.records.map(
                              (r) =>
                                  CourseTerm.parse(r.value('term')).yearFilter,
                            ),
                            if (_year.isNotEmpty) _year,
                          }.toList()..sort((a, b) => b.compareTo(a)))
                            SelectOption(
                              year,
                              year == CourseTerm.unspecified
                                  ? '연도 미지정'
                                  : '$year년',
                            ),
                        ],
                        onChanged: (value) => setState(() => _year = value),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: AnchoredSelectField<String>(
                        key: const ValueKey('record-course-term-filter'),
                        value: _term,
                        label: '학기',
                        options: [
                          const SelectOption('', '전체 학기'),
                          for (final term in {
                            ..._repository.records.map(
                              (r) => CourseTerm.parse(r.value('term')).semester,
                            ),
                            if (_term.isNotEmpty) _term,
                          }.toList()..sort())
                            SelectOption(term, term),
                        ],
                        onChanged: (value) => setState(() => _term = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (personal.isEmpty)
                filtered
                    ? EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: '선택한 연도·학기에 맞는 과목이 없습니다',
                        action: OutlinedButton(
                          onPressed: () => setState(() {
                            _year = '';
                            _term = '';
                          }),
                          child: const Text('필터 초기화'),
                        ),
                      )
                    : EmptyState(
                        icon: isCourse
                            ? Icons.menu_book_outlined
                            : widget.kind == PersonalRecordKind.credential
                            ? Icons.workspace_premium_outlined
                            : Icons.star_outline,
                        title: '아직 등록한 기록이 없습니다',
                        action: OutlinedButton.icon(
                          onPressed: _showForm,
                          icon: const Icon(Icons.add),
                          label: const Text('첫 기록 추가'),
                        ),
                      )
              else
                ResponsiveGrid(
                  children: [
                    for (final record in personal) _personalEntry(record),
                  ],
                ),
            ],
          ),
        ),
      ],
      below: [
        GuideCard(
          title: widget.guideTitle,
          lines: widget.guides,
          links: widget.guideActions,
        ),
      ],
    );
  }

  /// Same header in loading, failure and loaded states so the title never
  /// shifts; actions stay disabled until the list is ready.
  List<Widget> _headerActions() {
    final ready = !_loading && !_loadFailed;
    return [
      PageMoreMenu(
        key: const Key('record-menu-more'),
        enabled: ready,
        itemBuilder: (context) => [
          PopupMenuItem<void>(
            key: const Key('record-menu-load-draft'),
            onTap: _loadDraft,
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.inventory_2_outlined),
              title: Text('임시저장 불러오기'),
            ),
          ),
          if (_repository.isServerBacked)
            PopupMenuItem<void>(
              onTap: _load,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.refresh),
                title: Text('다시 읽기'),
              ),
            ),
        ],
      ),
      PageAddButton(
        label: widget.addLabel,
        onPressed: ready ? _showForm : null,
      ),
    ];
  }

  Widget _statePage({required Widget child}) => FeaturePage(
    title: widget.title,
    contextLabel: widget.contextLabel,
    trailing: _headerActions(),
    body: [child],
  );
}
