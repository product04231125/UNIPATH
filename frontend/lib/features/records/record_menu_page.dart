import 'package:flutter/material.dart';

import 'package:university_path_frontend/shared/app_typography.dart';

import '../../shared/widgets/equal_height_row.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/surface_card.dart';
import 'fixtures/record_mock_entry.dart';
import 'personal_record_repository.dart';
import 'personal_record_fields.dart';
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
  List<PersonalRecordField> _fields = [];

  @override
  void initState() {
    super.initState();
    _repository = PersonalRecordRepository(widget.kind);
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      await _repository.load();
      _fields =
          await widget.fieldsLoader?.call() ??
          personalRecordFields(widget.kind);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final form = GlobalKey<FormState>();
    bool saving = false;
    String? error;
    await showInputDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => InputDialog(
          changes: Listenable.merge(controllers.values.toList()),
          editing: record != null,
          saving: saving,
          hasContent: () =>
              controllers.values.any((c) => c.text.trim().isNotEmpty),
          title: Text(record == null ? widget.addLabel : '개인 기록 수정'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '기기 로컬 개인 기록 · 학교 공식 데이터나 졸업 판정이 아닙니다. 파일 업로드·서버 전송은 하지 않습니다.',
                ),
                const SizedBox(height: 16),
                for (final field in fields)
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
                            ),
                            validator: field.validate,
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
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('취소'),
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
                            id: record?.id ?? PersonalRecord.newId(),
                            values: values,
                          ),
                        );
                        if (mounted) setState(() {});
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (_) {
                        if (dialogContext.mounted) {
                          updateDialog(() {
                            saving = false;
                            error = '기기에 저장하지 못했습니다. 입력을 유지했으니 다시 시도하세요.';
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
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _delete(PersonalRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('개인 기록 삭제'),
        content: Text('${record.value('title')} 기록을 이 기기에서 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.delete(record.id);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('삭제하지 못했습니다. 기록은 유지됩니다.')));
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
                    '${f.label}: ${f.optionLabels[record.value(f.key)] ?? (f.options.isNotEmpty && !f.options.contains(record.value(f.key)) ? '연결 대상 없음 · 수정에서 다시 선택하세요' : record.value(f.key))}',
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
          TextButton(
            onPressed: () => _showForm(record),
            child: const Text('수정'),
          ),
          TextButton(onPressed: () => _delete(record), child: const Text('삭제')),
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
            const Text('개인 기록을 읽지 못했습니다. 기존 저장 내용은 덮어쓰지 않습니다.'),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    final personal = _repository.records
        .where((r) => _term.isEmpty || r.value('term') == _term)
        .toList();
    final entries = [if (widget.showMockData) ...widget.fixture];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xfffff7e5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xffefdba7)),
            ),
            child: Text(
              widget.notice,
              style: const TextStyle(
                fontSize: AppTypography.caption,
                color: Color(0xff795a22),
              ),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final records = SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.listTitle,
                      style: const TextStyle(
                        fontSize: AppTypography.section,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '학교에서 확인한 정보가 없으면 내 기록을 직접 추가할 수 있습니다.',
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: Color(0xff607386),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _showForm,
                      icon: const Icon(Icons.add),
                      label: Text(widget.addLabel),
                    ),
                    const SizedBox(height: 10),
                    if (widget.kind == PersonalRecordKind.course) ...[
                      AnchoredSelectField<String>(
                        value: _term,
                        label: '학기 필터',
                        options: [
                          const SelectOption('', '전체 학기'),
                          for (final term
                              in _repository.records
                                  .map((r) => r.value('term'))
                                  .toSet())
                            SelectOption(term, term),
                        ],
                        onChanged: (value) => setState(() => _term = value),
                      ),
                      Text(
                        '개인 입력 합계 ${personal.fold<double>(0, (sum, r) => sum + (double.tryParse(r.value('credits')) ?? 0))}학점 · 공식 이수학점 아님',
                      ),
                    ],
                    if (widget.kind == PersonalRecordKind.activity)
                      Text(
                        '사용자가 승인됨으로 기록한 봉사 시간 합계 ${personal.where((r) => r.value('approval') == 'approved').fold<double>(0, (sum, r) => sum + (double.tryParse(r.value('approvedHours')) ?? 0))}시간 · 학교 검증 아님',
                      ),
                    if (entries.isEmpty && personal.isEmpty)
                      const Text('개인 기록이 없습니다. 직접 입력해 주세요.'),
                    for (final entry in entries) _entry(entry),
                    for (final record in personal) _personalEntry(record),
                  ],
                ),
              );
              final guide = SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.guideTitle,
                      style: const TextStyle(
                        fontSize: AppTypography.section,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final guide in widget.guides)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: Text(
                          '• $guide',
                          style: const TextStyle(
                            fontSize: AppTypography.body,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ...widget.guideActions,
                  ],
                ),
              );
              return SingleChildScrollView(
                child: constraints.maxWidth >= 760
                    ? EqualHeightRow(
                        children: [
                          Expanded(flex: 6, child: records),
                          const SizedBox(width: 14),
                          Expanded(flex: 4, child: guide),
                        ],
                      )
                    : Column(
                        children: [records, const SizedBox(height: 14), guide],
                      ),
              );
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
  );

  Widget _statePage({required Widget child}) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_header(), child],
    ),
  );

  Widget _entry(RecordMockEntry entry) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xffe4ebef))),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.description_outlined,
          size: 19,
          color: Color(0xff315a77),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: const TextStyle(
                  fontSize: AppTypography.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.detail,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: Color(0xff607386),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        StatusBadge(status: entry.status == '기록됨' ? '충족' : entry.status),
      ],
    ),
  );
}
