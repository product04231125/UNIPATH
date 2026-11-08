import '../../shared/app_style.dart';

import 'package:flutter/material.dart';

import '../../shared/drafts/form_draft_picker.dart';
import '../../shared/drafts/form_draft_store.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/surface_card.dart';
import 'fixtures/record_mock_entry.dart';
import 'course/course_term.dart';
import 'personal_record_repository.dart';
import 'personal_record_fields.dart';
import 'personal_record_form.dart';
import 'personal_repository_scope.dart';
import '../auth/auth_api.dart';
import '../auth/guest_preview_scope.dart';
import '../api/student_api.dart';
import '../api/student_academic_api.dart';
import '../graduation/student_academic_course_link.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/external_link_button.dart';
import '../planning/planning_profile_cta.dart';
import '../planning/planning_repository.dart';

/// Temporary shared presentation only. Each feature entry owns its own
/// configuration and mounted local input state.
class RecordMenuPage extends StatefulWidget {
  const RecordMenuPage({
    super.key,
    this.contextLabel,
    required this.kind,
    required this.title,
    required this.description,
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
  final String description;
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

  Widget _personalEntry(PersonalRecord record) {
    final isCourse = widget.kind == PersonalRecordKind.course;
    final entry = RecordMockEntry(
      title: record.value('title'),
      detail: _fields
          .where(
            (f) =>
                f.key != 'title' &&
                record.value(f.key).isNotEmpty &&
                (widget.kind != PersonalRecordKind.activity ||
                    activityVisibleKeys.contains(f.key)),
          )
          .map(
            (f) => f.key == 'term' && isCourse
                ? '수강 기간: ${CourseTerm.parse(record.value('term')).label}'
                : '${f.label}: ${f.optionLabels[record.value(f.key)] ?? (f.options.isNotEmpty && !f.options.contains(record.value(f.key)) ? '연결 대상 없음 · 수정에서 다시 선택하세요' : record.value(f.key))}',
          )
          .join(' · '),
      status: '개인 기록',
    );
    return FeatureLine.two(
      primary: entry.title,
      secondary: entry.detail,
      leading: Icon(
        Icons.description_outlined,
        size: 19,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Course ownership is settings/profile context; keep the badge on
          // activity/credential/experience menus only.
          if (!isCourse) StatusBadge(status: entry.status),
          if (isCourse &&
              widget.studentApi != null &&
              _repository.isServerBacked &&
              !GuestPreviewScope.isActive(context))
            TextButton(
              onPressed: () => editStudentAcademicCourseLink(
                context,
                StudentAcademicApi.fromStudent(widget.studentApi!),
                recordId: record.id,
              ),
              child: const Text('학점 산입 연결'),
            ),
          for (final field in _fields.where(
            (f) =>
                f.type == PersonalFieldType.url &&
                record.value(f.key).isNotEmpty,
          ))
            ExternalLinkButton(
              url: record.value(field.key),
              label: field.label,
            ),
          TextButton(
            onPressed: () => _showForm(record: record),
            child: Text('수정'),
          ),
          TextButton(
            style: destructiveButtonStyle(context),
            onPressed: () => _delete(record),
            child: Text('삭제'),
          ),
        ],
      ),
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
    final canAdd =
        !isCourse ||
        widget.planning == null ||
        (profile?.isConfigured ?? false);
    return FeaturePage(
      title: widget.title,
      contextLabel: widget.contextLabel,
      description: widget.description,
      body: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FeatureLine.section(
                text: widget.listTitle,
                padTop: false,
                padBottom: false,
                trailing: _repository.isServerBacked
                    ? FeatureLine.reload(onPressed: _loading ? null : _load)
                    : null,
              ),
              if (isCourse && !canAdd && widget.onOpenSettings != null) ...[
                const SizedBox(height: 16),
                PlanningProfileSettingsCta(
                  need: PlanningProfileNeed.configured,
                  profile: profile,
                  onOpenSettings: widget.onOpenSettings!,
                ),
              ],
              if (widget.kind == PersonalRecordKind.course) ...[
                const SizedBox(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 240,
                      child: AnchoredSelectField<String>(
                        key: const ValueKey('record-course-year-filter'),
                        value: _year,
                        label: '수강 연도 필터',
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
                      width: 240,
                      child: AnchoredSelectField<String>(
                        key: const ValueKey('record-course-term-filter'),
                        value: _term,
                        label: '학기 필터',
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
                FeatureLine.one(
                  text:
                      '개인 입력 합계 ${personal.fold<double>(0, (sum, r) => sum + (double.tryParse(r.value('credits')) ?? 0))}학점',
                ),
              ],
              if (widget.kind == PersonalRecordKind.activity)
                FeatureLine.one(
                  text:
                      '기록한 시간 합계 ${personal.fold<double>(0, (sum, r) => sum + (double.tryParse(r.value('reportedHours')) ?? 0))}시간',
                ),
              if (personal.isEmpty)
                FeatureLine.one(
                  text: isCourse && (_year.isNotEmpty || _term.isNotEmpty)
                      ? '선택한 연도·학기에 맞는 개인 기록이 없습니다. 필터를 변경해 주세요.'
                      : '개인 기록이 없습니다. 직접 입력해 주세요.',
                ),
              for (final record in personal) _personalEntry(record),
            ],
          ),
        ),
      ],
      actions: [
        if (canAdd) ...[
          FilledButton.icon(
            onPressed: _showForm,
            icon: const Icon(Icons.add),
            label: Text(widget.addLabel),
          ),
          OutlinedButton(
            key: const Key('record-menu-load-draft'),
            onPressed: _loadDraft,
            child: const Text('불러오기'),
          ),
        ],
      ],
      below: [
        ExpansionTile(
          title: Text(widget.guideTitle),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in widget.guides)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• $line'),
              ),
          ],
        ),
        ...widget.guideActions,
      ],
    );
  }

  Widget _statePage({required Widget child}) => FeaturePage(
    title: widget.title,
    contextLabel: widget.contextLabel,
    description: widget.description,
    body: [child],
  );
}
