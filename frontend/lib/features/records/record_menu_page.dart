import '../../shared/app_style.dart';

import 'package:flutter/material.dart';

import 'package:university_path_frontend/shared/app_typography.dart';

import '../../shared/widgets/content_scroll_view.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/surface_card.dart';
import 'fixtures/record_mock_entry.dart';
import 'course/course_term.dart';
import 'personal_record_repository.dart';
import 'personal_record_fields.dart';
import 'personal_record_form.dart';
import 'personal_repository_scope.dart';
import '../auth/auth_api.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/external_link_button.dart';

/// Temporary shared presentation only. Each feature entry owns its own
/// configuration, fixture and mounted local input state.
class RecordMenuPage extends StatefulWidget {
  const RecordMenuPage({
    super.key,
    this.contextLabel,
    required this.kind,
    required this.title,
    required this.description,
    required this.notice,
    required this.listTitle,
    required this.fixture,
    required this.guideTitle,
    required this.guides,
    required this.addLabel,
    required this.detailLabel,
    required this.showMockData,
    this.fieldsLoader,
    this.validateValues,
    this.guideActions = const [],
  });

  final PersonalRecordKind kind;
  final String? contextLabel;
  final String title;
  final String description;
  final String notice;
  final String listTitle;
  final List<RecordMockEntry> fixture;
  final String guideTitle;
  final List<String> guides;
  final String addLabel;
  final String detailLabel;
  final bool showMockData;
  final Future<List<PersonalRecordField>> Function()? fieldsLoader;
  final Future<String?> Function(Map<String, String>)? validateValues;
  final List<Widget> guideActions;

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

  Future<void> _showForm([PersonalRecord? record]) async {
    await showPersonalRecordForm(
      context: context,
      kind: widget.kind,
      repository: _repository,
      addLabel: widget.addLabel,
      record: record,
      fieldsLoader: widget.fieldsLoader,
      validateValues: widget.validateValues,
      onFieldsReady: (fields) {
        if (mounted) setState(() => _fields = fields);
      },
      onSaved: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _delete(PersonalRecord record) async {
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
    if (confirmed != true) return;
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

  Widget _personalEntry(PersonalRecord record) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _entry(
        RecordMockEntry(
          title: record.value('title'),
          detail: _fields
              .where((f) => f.key != 'title' && record.value(f.key).isNotEmpty)
              .map(
                (f) =>
                    f.key == 'term' && widget.kind == PersonalRecordKind.course
                    ? '수강 기간: ${CourseTerm.parse(record.value('term')).label}'
                    : '${f.label}: ${f.optionLabels[record.value(f.key)] ?? (f.options.isNotEmpty && !f.options.contains(record.value(f.key)) ? '연결 대상 없음 · 수정에서 다시 선택하세요' : record.value(f.key))}',
              )
              .join(' · '),
          status: '개인 기록',
        ),
      ),
      Wrap(
        children: [
          for (final field in _fields.where(
            (f) =>
                f.type == PersonalFieldType.url &&
                record.value(f.key).isNotEmpty,
          ))
            ExternalLinkButton(
              url: record.value(field.key),
              label: field.label,
            ),
          TextButton(onPressed: () => _showForm(record), child: Text('수정')),
          TextButton(
            style: destructiveButtonStyle(context),
            onPressed: () => _delete(record),
            child: Text('삭제'),
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return _statePage(child: const CircularProgressIndicator());
    if (_loadFailed) {
      return _statePage(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('개인 기록을 읽지 못했습니다. 기존 저장 내용은 덮어쓰지 않습니다.'),
            TextButton(onPressed: _load, child: Text('다시 시도')),
          ],
        ),
      );
    }
    final personal = _repository.records.where((r) {
      if (widget.kind != PersonalRecordKind.course) return true;
      final period = CourseTerm.parse(r.value('term'));
      return (_year.isEmpty || period.yearFilter == _year) &&
          (_term.isEmpty || period.semester == _term);
    }).toList();
    final entries = [if (widget.showMockData) ...widget.fixture];
    final isCourse = widget.kind == PersonalRecordKind.course;
    return ContentScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          if (!isCourse)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Text(
                widget.notice,
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          if (!isCourse) const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final records = SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.listTitle,
                      style: TextStyle(
                        fontSize: AppTypography.section,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (!isCourse) const SizedBox(height: 4),
                    if (!isCourse)
                      Text(
                        '학교에서 확인한 정보가 없으면 내 기록을 직접 추가할 수 있습니다.',
                        style: TextStyle(
                          fontSize: AppTypography.caption,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _showForm,
                      icon: Icon(Icons.add),
                      label: Text(widget.addLabel),
                    ),
                    const SizedBox(height: 10),
                    if (widget.kind == PersonalRecordKind.course) ...[
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
                                        CourseTerm.parse(r.value('term'))
                                            .yearFilter,
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
                              onChanged: (value) =>
                                  setState(() => _year = value),
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
                                    (r) =>
                                        CourseTerm.parse(r.value('term'))
                                            .semester,
                                  ),
                                  if (_term.isNotEmpty) _term,
                                }.toList()..sort())
                                  SelectOption(term, term),
                              ],
                              onChanged: (value) =>
                                  setState(() => _term = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '개인 입력 합계 ${personal.fold<double>(0, (sum, r) => sum + (double.tryParse(r.value('credits')) ?? 0))}학점 · 공식 이수학점 아님',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.notice,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (widget.kind == PersonalRecordKind.activity)
                      Text(
                        '사용자가 승인됨으로 기록한 봉사 시간 합계 ${personal.where((r) => r.value('approval') == 'approved').fold<double>(0, (sum, r) => sum + (double.tryParse(r.value('approvedHours')) ?? 0))}시간 · 학교 검증 아님',
                      ),
                    if (personal.isEmpty)
                      Text(
                        isCourse && (_year.isNotEmpty || _term.isNotEmpty)
                            ? '선택한 연도·학기에 맞는 개인 기록이 없습니다. 필터를 변경해 주세요.'
                            : '개인 기록이 없습니다. 직접 입력해 주세요.',
                      ),
                    for (final record in personal) _personalEntry(record),
                    if (entries.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),

                      for (final entry in entries) _entry(entry),
                    ],
                  ],
                ),
              );
              {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    records,
                    const SizedBox(height: 12),
                    ExpansionTile(
                      title: Text(widget.guideTitle),
                      childrenPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
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
            },
          ),
        ],
      ),
    );
  }

  Widget _header() => PageHeader(
    title: widget.title,
    contextLabel: widget.contextLabel,
    description: widget.description,
    actions: [
      if (_repository.isServerBacked)
        TextButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('서버 기록 다시 불러오기'),
        ),
    ],
  );

  Widget _statePage({required Widget child}) => ContentScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_header(), child],
    ),
  );

  Widget _entry(RecordMockEntry entry) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Row(
      children: [
        Icon(
          Icons.description_outlined,
          size: 19,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: TextStyle(
                  fontSize: AppTypography.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.detail,
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        StatusBadge(status: entry.status),
      ],
    ),
  );
}
