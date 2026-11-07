import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_shell/phone_shell.dart';
import '../../shared/credits_format.dart';
import '../../shared/year_options.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/digits_only_hint.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/field_requirement.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/drafts/form_draft_store.dart';
import '../../shared/widgets/input_dialog.dart';
import '../api/student_api.dart';
import '../auth/auth_api.dart';
import '../auth/guest_preview_scope.dart';
import 'course/course_pick_options.dart';
import 'course/course_term.dart';
import 'personal_record_fields.dart';
import 'personal_record_repository.dart';
import 'personal_repository_scope.dart';

String personalRecordDraftScreenId(PersonalRecordKind kind) =>
    'personal_record.${kind.name}';

const _courseIdentityKeys = {'title', 'courseCode', 'credits', 'category'};
// Plan: course form shows searchable pick + term/grade/completion/section only.
// Keep `detail` in field schema/wire as empty (or existing) value; hide free-text UI.
const _courseHiddenInputKeys = {..._courseIdentityKeys, 'detail'};

Future<void> showPersonalRecordForm({
  required BuildContext context,
  required PersonalRecordKind kind,
  required PersonalRecordRepository repository,
  required String addLabel,
  PersonalRecord? record,
  Map<String, String>? draftValues,
  String? appliedDraftId,
  List<PersonalRecordField>? initialFields,
  Future<List<PersonalRecordField>> Function()? fieldsLoader,
  Future<String?> Function(Map<String, String>)? validateValues,
  ValueChanged<List<PersonalRecordField>>? onFieldsReady,
  VoidCallback? onSaved,
  StudentApi? studentApi,
  String? institutionId,
  String? departmentId,
  String? curriculumId,
  FormDraftStore? draftStore,
}) async {
  bool blocked() {
    if (!context.mounted) return true;
    if (!GuestPreviewScope.isActive(context)) return false;
    GuestPreviewScope.showBlockedMessage(context);
    return true;
  }

  if (blocked()) return;
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
  if (!context.mounted || blocked()) return;
  onFieldsReady?.call(fields);
  String seed(String key) =>
      draftValues?[key] ?? record?.value(key) ?? '';
  final controllers = {
    for (final field in fields)
      field.key: TextEditingController(text: seed(field.key)),
  };
  final isCourse = kind == PersonalRecordKind.course;
  final originalTerm = record?.value('term') ?? '';
  final period = CourseTerm.parse(
    draftValues?['term'] ?? originalTerm,
  );
  final initialYear = record == null && draftValues == null
      ? '${DateTime.now().year}'
      : period.year;
  final year = TextEditingController(
    text: draftValues != null && period.year.isNotEmpty
        ? period.year
        : initialYear,
  );
  if (isCourse) controllers['term']!.text = period.semester;
  final initialSemester = controllers['term']?.text ?? '';
  final drafts = draftStore ?? FormDraftStore.instance;
  final collectionKey = formDraftCollectionKey(
    personalRecordDraftScreenId(kind),
  );
  var loadedDraftId = appliedDraftId;
  var courseOptions = const <CoursePickOption>[];
  String? selectedCourseId;
  if (isCourse) {
    final scope = PersonalRepositoryScope.read(context);
    try {
      courseOptions = await loadCoursePickOptions(
        courseRepository: repository,
        curriculumCourseRepository: scope?.records(
          PersonalRecordKind.personalCurriculumCourse,
        ),
        studentApi: studentApi,
        institutionId: institutionId,
        departmentId: departmentId,
        curriculumId: curriculumId,
      );
    } catch (_) {
      year.dispose();
      for (final controller in controllers.values) {
        controller.dispose();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('과목 후보를 읽지 못했습니다. 다시 시도하세요.')),
        );
      }
      return;
    }
    if (!context.mounted) {
      year.dispose();
      for (final controller in controllers.values) {
        controller.dispose();
      }
      return;
    }
    if (record != null) {
      selectedCourseId = courseOptions
          .where((option) => option.matches(record))
          .firstOrNull
          ?.id;
      if (selectedCourseId == null && record.value('title').isNotEmpty) {
        final current = CoursePickOption(
          id: 'current:${record.id}',
          title: record.value('title'),
          courseCode: record.value('courseCode'),
          credits: record.value('credits'),
          category: record.value('category'),
          sourceLabel: '현재 기록',
        );
        courseOptions = [...courseOptions, current];
        selectedCourseId = current.id;
      }
    }
    final restoredId = draftValues?['_courseSelectionId'];
    if (restoredId != null && courseOptions.any((option) => option.id == restoredId)) {
      selectedCourseId = restoredId;
    }
  }
  if (!context.mounted || blocked()) {
    year.dispose();
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return;
  }
  final initialCourseId = selectedCourseId;
  CoursePickOption? selectedCourse() => courseOptions
      .where((option) => option.id == selectedCourseId).firstOrNull;
  void applyCourse(CoursePickOption option) {
    controllers['title']?.text = option.title;
    controllers['courseCode']?.text = option.courseCode;
    controllers['credits']?.text = option.credits;
    controllers['category']?.text = option.category;
  }
  if (draftValues != null && selectedCourse() != null) applyCourse(selectedCourse()!);

  bool periodChanged() =>
      isCourse &&
      (year.text != initialYear ||
          controllers['term']!.text != initialSemester);
  final form = GlobalKey<FormState>();
  final operationId = record?.id ?? PersonalRecord.newId();
  var saving = false;
  String? error;
  Map<String, String> currentValues() {
    final values = {
      for (final field in fields) field.key: controllers[field.key]!.text.trim(),
    };
    if (isCourse) {
      values['term'] = record != null && !periodChanged()
          ? originalTerm
          : CourseTerm.encode(year.text, controllers['term']!.text);
    }
    return values;
  }

  Future<bool> saveDraft([BuildContext? host]) async {
    if (blocked()) return false;
    final messengerContext = host ?? context;
    try {
      final values = currentValues();
      final entry = await drafts.add(
        collectionKey,
        summary: formDraftSummaryFromValues(values),
        payload: {...values, if (isCourse) '_courseSelectionId': selectedCourseId},
      );
      loadedDraftId = entry.id;
      if (messengerContext.mounted) {
        ScaffoldMessenger.of(messengerContext).showSnackBar(
          const SnackBar(content: Text('임시저장했습니다.')),
        );
      }
      return true;
    } catch (_) {
      if (messengerContext.mounted) {
        ScaffoldMessenger.of(messengerContext).showSnackBar(
          const SnackBar(content: Text('임시저장하지 못했습니다. 입력은 유지됩니다.')),
        );
      }
      return false;
    }
  }

  await showInputDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, updateDialog) => InputDialog(
        changes: Listenable.merge([...controllers.values, if (isCourse) year]),
        editing: record != null,
        saving: saving,
        onTempSave: () => saveDraft(dialogContext),
        hasUnsavedChanges: () =>
            selectedCourseId != initialCourseId ||
            (isCourse &&
                year.text.trim() != initialYear.trim() &&
                (record != null ||
                    draftValues != null ||
                    year.text.trim().isNotEmpty)) ||
            fields.any(
              (field) =>
                  controllers[field.key]!.text !=
                      (isCourse && field.key == 'term'
                          ? initialSemester
                          : (draftValues?[field.key] ??
                                record?.value(field.key) ??
                                '')) &&
                  (record != null ||
                      draftValues != null ||
                      controllers[field.key]!.text.trim().isNotEmpty),
            ),
        hasContent: () =>
            selectedCourseId != null ||
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
              if (!PhoneChromeScope.of(context)) ...[
                Text(
                  repository.isServerBacked
                      ? '계정 서버 개인 기록 · 파일 업로드는 하지 않습니다.'
                      : '기기 로컬 개인 기록 · 파일 업로드·서버 전송은 하지 않습니다.',
                ),
                const SizedBox(height: 16),
              ],
              if (isCourse) ...[
                if (courseOptions.isEmpty)
                  const FeatureLine.one(text: '설정·교육과정에서 과목을 먼저 등록하세요')
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: FormField<String>(
                      initialValue: selectedCourseId ?? '',
                      validator: (value) => (value == null || value.isEmpty)
                          ? '과목을 선택하세요.'
                          : selectedCourse()?.id.startsWith('catalog:') == true &&
                              selectedCourse()?.curriculumCourseId == null
                          ? '학교 교육과정의 분류 연결이 필요합니다.'
                          : null,
                      builder: (state) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IgnorePointer(
                            ignoring: saving,
                            child: AnchoredSelectField<String>(
                              key: const ValueKey('record-select-course'),
                              searchable: true,
                              searchLabel: '과목 이름·코드 검색',
                              value: selectedCourseId ?? '',
                              label: fieldRequirementLabel(
                                '과목',
                                required: true,
                              ),
                              options: [
                                const SelectOption('', '선택하세요'),
                                for (final option in courseOptions)
                                  SelectOption(option.id, option.label),
                              ],
                              onChanged: (value) {
                                final option = courseOptions
                                    .where((item) => item.id == value)
                                    .firstOrNull;
                                updateDialog(() {
                                  selectedCourseId = value.isEmpty
                                      ? null
                                      : value;
                                  if (option != null) applyCourse(option);
                                });
                                state.didChange(value);
                              },
                            ),
                          ),
                          if (selectedCourseId != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                [
                                  controllers['title']?.text ?? '',
                                  if ((controllers['courseCode']?.text ?? '')
                                      .isNotEmpty)
                                    controllers['courseCode']!.text,
                                  if ((controllers['credits']?.text ?? '')
                                      .isNotEmpty)
                                    formatCreditsLabel(
                                      controllers['credits']!.text,
                                    ),
                                  if ((controllers['category']?.text ?? '')
                                      .isNotEmpty)
                                    selectedCourse()?.categoryLabel ?? controllers['category']!.text,
                                  if (selectedCourse()?.requiredCourse != null)
                                    selectedCourse()!.requirementLabel,
                                ].where((part) => part.isNotEmpty).join(' · '),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (selectedCourse()?.id.startsWith('catalog:') == true)
                            Text(selectedCourse()!.curriculumCourseId == null
                                ? '교육과정의 분류 연결을 확인하지 못했습니다. 학업 프로필의 교육과정을 선택하거나 관리자에게 연결을 요청하세요.'
                                : '이수구분과 필수 여부는 학교 교육과정에 연결된 기준을 사용합니다.'),
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
              for (final field in fields) ...[
                if ((isCourse && _courseHiddenInputKeys.contains(field.key)) ||
                    (kind == PersonalRecordKind.activity &&
                        !activityVisibleKeys.contains(field.key)) ||
                    (kind == PersonalRecordKind.portfolio &&
                        portfolioHiddenKeys.contains(field.key)))
                  const SizedBox.shrink()
                else ...[
                  if (isCourse && field.key == 'term') ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: FormField<String>(
                        key: const ValueKey('record-field-course-year'),
                        initialValue: year.text,
                        validator: (value) => CourseTerm.validateYear(
                          value,
                          required: record == null || period.year.isNotEmpty,
                          allowYear: int.tryParse(period.year),
                        ),
                        builder: (state) {
                          final currentYear = DateTime.now().year;
                          final selected = year.text.trim();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              IgnorePointer(
                                ignoring: saving,
                                child: AnchoredSelectField<String>(
                                  key: const ValueKey(
                                    'record-select-course-year',
                                  ),
                                  searchable: true,
                                  searchLabel: '수강 연도 검색',
                                  value: selected,
                                  label: fieldRequirementLabel(
                                    '수강 연도 (학년도)',
                                    required:
                                        record == null ||
                                        period.year.isNotEmpty,
                                  ),
                                  options: [
                                    if (record != null && period.year.isEmpty)
                                      const SelectOption('', '연도 미지정'),
                                    for (final optionYear in yearOptions(
                                      maxYear: currentYear + 1,
                                      include: int.tryParse(period.year),
                                    ))
                                      SelectOption(
                                        '$optionYear',
                                        '$optionYear년',
                                      ),
                                  ],
                                  onChanged: (value) {
                                    year.text = value;
                                    state.didChange(value);
                                  },
                                ),
                              ),
                              if (record != null && period.year.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '기존 기록은 연도 미지정입니다. 확인한 연도만 선택하세요.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
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
                          );
                        },
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: isCourse && field.key == 'term'
                        ? FormField<String>(
                            key: ValueKey('record-field-${field.key}'),
                            initialValue: controllers[field.key]!.text,
                            validator: (value) {
                              final error = field.validate(value);
                              if (error != null) return error;
                              if (periodChanged() || record == null) {
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
                            builder: (state) {
                              final selected = controllers[field.key]!.text;
                              // Keep the exact stored semester (incl. odd spacing)
                              // so AnchoredSelectField can resolve the value, and
                              // so switching away mid-edit does not drop the option.
                              final originalSemester = period.semester;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  IgnorePointer(
                                    ignoring: saving,
                                    child: AnchoredSelectField<String>(
                                      key: ValueKey(
                                        'record-select-${field.key}',
                                      ),
                                      searchable: true,
                                      searchLabel: '학기 검색',
                                      value: selected,
                                      label: fieldRequirementLabel(
                                        field.label,
                                        required: field.required,
                                      ),
                                      options: [
                                        const SelectOption('', '선택하세요'),
                                        for (final option
                                            in CourseTerm.standardSemesters)
                                          SelectOption(option, option),
                                        if (originalSemester
                                                .trim()
                                                .isNotEmpty &&
                                            !CourseTerm.standardSemesters
                                                .contains(originalSemester))
                                          SelectOption(
                                            originalSemester,
                                            originalSemester.trim(),
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
                              );
                            },
                          )
                        : field.options.isEmpty
                        ? () {
                            final above =
                                kind == PersonalRecordKind.activity &&
                                activityVisibleKeys.contains(field.key);
                            final caption = fieldRequirementLabel(
                              field.label,
                              required: field.required,
                            );
                            final input = TextFormField(
                              key: ValueKey('record-field-${field.key}'),
                              controller: controllers[field.key],
                              enabled: !saving,
                              maxLines: field.multiline ? 3 : 1,
                              keyboardType: isCourse && field.key == 'section'
                                  ? TextInputType.number
                                  : field.type == PersonalFieldType.number
                                  ? const TextInputType.numberWithOptions(
                                      decimal: true,
                                    )
                                  : TextInputType.text,
                              inputFormatters:
                                  isCourse && field.key == 'section'
                                  ? [FilteringTextInputFormatter.digitsOnly]
                                  : null,
                              decoration: isCourse && field.key == 'section'
                                  ? digitsOnlyDecoration(
                                      context,
                                      base: InputDecoration(
                                        labelText: above ? null : caption,
                                      ),
                                    )
                                  : InputDecoration(
                                      labelText: above ? null : caption,
                                    ),
                              validator: field.validate,
                            );
                            return above
                                ? FieldLabel(label: caption, child: input)
                                : input;
                          }()
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
                                    label: fieldRequirementLabel(
                                      field.label,
                                      required: field.required,
                                    ),
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
          TextButton(
            key: const Key('personal-record-temp-save'),
            onPressed: saving
                ? null
                : () async {
                    await saveDraft(dialogContext);
                  },
            child: const Text('임시저장'),
          ),
          FilledButton(
            onPressed: saving || (isCourse && courseOptions.isEmpty)
                ? null
                : () async {
                    if (saving || blocked()) return;
                    if (!form.currentState!.validate()) return;
                    final values = currentValues();
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
                      if (blocked()) {
                        updateDialog(() => saving = false);
                        return;
                      }
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
                      final draftId = loadedDraftId;
                      if (draftId != null) {
                        await drafts.delete(collectionKey, draftId);
                      }
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
