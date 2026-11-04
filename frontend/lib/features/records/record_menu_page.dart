import '../../shared/app_style.dart';

import 'package:flutter/material.dart';

import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/surface_card.dart';
import 'fixtures/record_mock_entry.dart';
import 'course/course_term.dart';
import 'personal_record_repository.dart';
import 'personal_record_fields.dart';
import 'personal_repository_scope.dart';
import '../auth/auth_api.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/external_link_button.dart';

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
    List<PersonalRecordField> fields;
    try {
      fields =
          await widget.fieldsLoader?.call() ??
          personalRecordFields(widget.kind);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연결할 개인 기록을 읽지 못했습니다. 다시 시도하세요.')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _fields = fields);
    final controllers = {
      for (final field in fields)
        field.key: TextEditingController(text: record?.value(field.key) ?? ''),
    };
    final isCourse = widget.kind == PersonalRecordKind.course;
    final originalTerm = record?.value('term') ?? '';
    final period = CourseTerm.parse(originalTerm);
    final initialYear = record == null ? '${DateTime.now().year}' : period.year;
    final year = TextEditingController(text: initialYear);
    if (isCourse) controllers['term']!.text = period.semester;
    final initialSemester = controllers['term']?.text ?? '';
    bool periodChanged() =>
        isCourse &&
        (year.text != initialYear ||
            controllers['term']!.text != initialSemester);
    final form = GlobalKey<FormState>();
    final operationId = record?.id ?? PersonalRecord.newId();
    bool saving = false;
    String? error;
    await showInputDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => InputDialog(
          changes: Listenable.merge([
            ...controllers.values,
            if (isCourse) year,
          ]),
          editing: record != null,
          saving: saving,
          hasUnsavedChanges: () =>
              (isCourse &&
                  year.text.trim() != initialYear.trim() &&
                  (record != null || year.text.trim().isNotEmpty)) ||
              fields.any(
                (field) =>
                    controllers[field.key]!.text !=
                        (isCourse && field.key == 'term'
                            ? initialSemester
                            : (record?.value(field.key) ?? '')) &&
                    (record != null ||
                        controllers[field.key]!.text.trim().isNotEmpty),
              ),
          hasContent: () =>
              controllers.values.any((c) => c.text.trim().isNotEmpty) ||
              (isCourse &&
                  year.text.trim().isNotEmpty &&
                  year.text.trim() != initialYear.trim()),
          title: Text(record == null ? widget.addLabel : '개인 기록 수정'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final field in fields) ...[
                  if (isCourse && field.key == 'term') ...[
                    TextFormField(
                      key: const ValueKey('record-field-course-year'),
                      controller: year,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            '수강 연도 (학년도)${record == null || period.year.isNotEmpty ? ' *' : ' (선택)'}',
                        helperText: record != null && period.year.isEmpty
                            ? '기존 기록은 연도 미지정입니다. 확인한 연도만 입력하세요.'
                            : '예: 2026 · 과거·계획 연도도 입력할 수 있습니다.',
                      ),
                      validator: (value) => CourseTerm.validateYear(
                        value,
                        required: record == null || period.year.isNotEmpty,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: field.options.isEmpty
                        ? TextFormField(
                            key: ValueKey('record-field-${field.key}'),
                            controller: controllers[field.key],
                            enabled: !saving,
                            maxLines: field.multiline ? 3 : 1,
                            keyboardType: field.type == PersonalFieldType.number
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                  )
                                : TextInputType.text,
                            decoration: InputDecoration(
                              labelText:
                                  '${field.label}${field.required ? ' *' : ' (선택)'}',
                              helperText: isCourse && field.key == 'term'
                                  ? '예: 1학기, 2학기, 여름 계절학기 · 연도는 위 칸에 입력하세요.'
                                  : null,
                            ),
                            validator: (value) {
                              final error = field.validate(value);
                              if (error != null ||
                                  !isCourse ||
                                  field.key != 'term') {
                                return error;
                              }
                              if (periodChanged() || record == null) {
                                if (CourseTerm.parse(value ?? '')
                                    .year
                                    .isNotEmpty) {
                                  return '연도는 수강 연도 칸에, 학기는 이 칸에 나눠 입력하세요.';
                                }
                                if (CourseTerm.encode(
                                      year.text,
                                      value ?? '',
                                    ).length >
                                    128) {
                                  return '연도와 학기를 합쳐 128자 이내로 입력하세요.';
                                }
                              }
                              return null;
                            },
                          )
                        : FormField<String>(
                            initialValue: controllers[field.key]!.text,
                            validator: field.validate,
                            builder: (state) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                IgnorePointer(
                                  ignoring: saving,
                                  child: AnchoredSelectField<String>(
                                    key: ValueKey('record-select-${field.key}'),
                                    value: controllers[field.key]!.text,
                                    label: field.label,
                                    options: [
                                      const SelectOption('', '미선택'),
                                      for (final option in field.options.where(
                                        (o) => o.isNotEmpty,
                                      ))
                                        SelectOption(
                                          option,
                                          field.optionLabels[option] ?? option,
                                        ),
                                      if (controllers[field.key]!
                                              .text
                                              .isNotEmpty &&
                                          !field.options.contains(
                                            controllers[field.key]!.text,
                                          ))
                                        SelectOption(
                                          controllers[field.key]!.text,
                                          '연결 대상 없음 · 다시 선택하세요',
                                        ),
                                    ],
                                    onChanged: (value) {
                                      controllers[field.key]!.text = value;
                                      state.didChange(value);
                                    },
                                  ),
                                ),
                                if (state.hasError)
                                  Text(
                                    state.errorText!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => InputDialog.cancel<void>(dialogContext),
              child: Text('취소'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      final values = {
                        for (final field in fields)
                          field.key: controllers[field.key]!.text.trim(),
                      };
                      if (isCourse) {
                        values['term'] = record != null && !periodChanged()
                            ? originalTerm
                            : CourseTerm.encode(
                                year.text,
                                controllers['term']!.text,
                              );
                      }
                      final crossError = personalRecordCrossError(values);
                      if (crossError != null) {
                        updateDialog(() => error = crossError);
                        return;
                      }
                      updateDialog(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final linkError = await widget.validateValues?.call(
                          values,
                        );
                        if (!dialogContext.mounted) return;
                        if (linkError != null) {
                          updateDialog(() {
                            saving = false;
                            error = linkError;
                          });
                          return;
                        }
                        await _repository.save(
                          PersonalRecord(
                            id: operationId,
                            version: record?.version,
                            values: values,
                          ),
                        );
                        if (mounted) setState(() {});
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (failure) {
                        if (dialogContext.mounted) {
                          updateDialog(() {
                            saving = false;
                            error = failure is AuthFailure
                                ? '${failure.message} 입력은 유지됩니다.'
                                : '${_repository.isServerBacked ? '서버' : '기기'}에 저장하지 못했습니다. 입력을 유지했으니 다시 시도하세요.';
                          });
                        }
                      }
                    },
              child: Text(saving ? '저장 중…' : '내 기록에 저장'),
            ),
          ],
        ),
      ),
    );
    year.dispose();
    for (final controller in controllers.values) {
      controller.dispose();
    }
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

  Widget _personalEntry(PersonalRecord record) {
    final entry = RecordMockEntry(
      title: record.value('title'),
      detail: _fields
          .where((f) => f.key != 'title' && record.value(f.key).isNotEmpty)
          .map(
            (f) => f.key == 'term' && widget.kind == PersonalRecordKind.course
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
          StatusBadge(status: entry.status),
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
    final personal = _repository.records.where((r) {
      if (widget.kind != PersonalRecordKind.course) return true;
      final period = CourseTerm.parse(r.value('term'));
      return (_year.isEmpty || period.yearFilter == _year) &&
          (_term.isEmpty || period.semester == _term);
    }).toList();
    final isCourse = widget.kind == PersonalRecordKind.course;
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
                      '사용자가 승인됨으로 기록한 봉사 시간 합계 ${personal.where((r) => r.value('approval') == 'approved').fold<double>(0, (sum, r) => sum + (double.tryParse(r.value('approvedHours')) ?? 0))}시간',
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
        FilledButton.icon(
          onPressed: _showForm,
          icon: const Icon(Icons.add),
          label: Text(widget.addLabel),
        ),
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
