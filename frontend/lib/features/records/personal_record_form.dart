import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/input_dialog.dart';
import '../auth/auth_api.dart';
import 'course/course_term.dart';
import 'personal_record_fields.dart';
import 'personal_record_repository.dart';

Future<void> showPersonalRecordForm({
  required BuildContext context,
  required PersonalRecordKind kind,
  required PersonalRecordRepository repository,
  required String addLabel,
  PersonalRecord? record,
  List<PersonalRecordField>? initialFields,
  Future<List<PersonalRecordField>> Function()? fieldsLoader,
  Future<String?> Function(Map<String, String>)? validateValues,
  ValueChanged<List<PersonalRecordField>>? onFieldsReady,
  VoidCallback? onSaved,
}) async {
  List<PersonalRecordField> fields;
  try {
    fields =
        initialFields ??
        await fieldsLoader?.call() ??
        personalRecordFields(kind);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연결할 개인 기록을 읽지 못했습니다. 다시 시도하세요.')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  onFieldsReady?.call(fields);
  final controllers = {
    for (final field in fields)
      field.key: TextEditingController(text: record?.value(field.key) ?? ''),
  };
  final isCourse = kind == PersonalRecordKind.course;
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
  var saving = false;
  String? error;
  await showInputDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, updateDialog) => InputDialog(
        changes: Listenable.merge([...controllers.values, if (isCourse) year]),
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
        title: Text(record == null ? addLabel : '개인 기록 수정'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                repository.isServerBacked
                    ? '계정 서버 개인 기록 · 학교 공식 데이터나 졸업 판정이 아닙니다. 파일 업로드는 하지 않습니다.'
                    : '기기 로컬 개인 기록 · 학교 공식 데이터나 졸업 판정이 아닙니다. 파일 업로드·서버 전송은 하지 않습니다.',
              ),
              const SizedBox(height: 16),
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
                                    color: Theme.of(context).colorScheme.error,
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving
                ? null
                : () => InputDialog.cancel<void>(dialogContext),
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
                      final linkError = await validateValues?.call(values);
                      if (!dialogContext.mounted) return;
                      if (linkError != null) {
                        updateDialog(() {
                          saving = false;
                          error = linkError;
                        });
                        return;
                      }
                      await repository.save(
                        PersonalRecord(
                          id: operationId,
                          version: record?.version,
                          values: values,
                        ),
                      );
                      onSaved?.call();
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } catch (failure) {
                      if (dialogContext.mounted) {
                        updateDialog(() {
                          saving = false;
                          error = failure is AuthFailure
                              ? '${failure.message} 입력은 유지됩니다.'
                              : '${repository.isServerBacked ? '서버' : '기기'}에 저장하지 못했습니다. 입력을 유지했으니 다시 시도하세요.';
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
