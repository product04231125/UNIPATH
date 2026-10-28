import '../../shared/widgets/responsive_columns.dart';

import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../planning/planning_import_section.dart';
import '../records/personal_repository_scope.dart';
import '../records/personal_workspace_import_section.dart';

import 'package:university_path_frontend/shared/app_typography.dart';

import '../api/student_api.dart';
import '../graduation/school_context_form.dart';
import '../planning/planning_repository.dart';
import '../planning/planning_storage_state.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/content_scroll_view.dart';
import 'chat_preferences.dart';
import 'chat_settings_section.dart';
import 'appearance_settings_section.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    this.chatPreferences,
    this.studentApi,
  });

  final PlanningRepository repository;
  final ChatPreferences? chatPreferences;
  final StudentApi? studentApi;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _schoolForm = GlobalKey<SchoolContextFormState>();
  late final TextEditingController _school;
  late final TextEditingController _department;
  late final TextEditingController _admissionYear;
  int? _academicYearOverride;
  late WeekStartDay _weekStartsOn;
  bool _saved = false;
  bool _saving = false;
  String? _error;
  bool _profileInitialized = false;
  PlanningProfile? _displayedProfile;
  String? _track;
  bool _dirty = false;
  bool _useCatalog = false;
  String? _pendingInstitutionId;
  String? _pendingDepartmentId;
  String? _pendingCurriculumId;

  @override
  void initState() {
    super.initState();
    final profile = widget.repository.profile;
    _school = TextEditingController(text: profile.school);
    _department = TextEditingController(text: profile.department);
    _admissionYear = TextEditingController(
      text: profile.admissionYear?.toString() ?? '',
    );
    _academicYearOverride = profile.academicYearOverride;
    _weekStartsOn = profile.weekStartsOn;
    _track = profile.track;
    _displayedProfile = profile;
    _pendingInstitutionId = profile.institutionId;
    _pendingDepartmentId = profile.departmentId;
    _pendingCurriculumId = profile.curriculumId;
    _useCatalog = _catalogModeFor(profile);
    _profileInitialized =
        !widget.repository.isLoading && !widget.repository.loadFailed;
  }

  bool get _canUseCatalog => widget.studentApi != null;

  bool _catalogModeFor(PlanningProfile profile) {
    if (!_canUseCatalog) {
      return false;
    }
    if (profile.hasCatalogSchool) {
      return true;
    }
    if (profile.school.trim().isNotEmpty ||
        profile.department.trim().isNotEmpty) {
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _school.dispose();
    _department.dispose();
    _admissionYear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      if (widget.repository.isLoading || widget.repository.loadFailed) {
        return ContentScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(title: '설정', contextLabel: '일반'),
              PlanningStorageState(repository: widget.repository),
              const AppearanceSettingsSection(),
              if (widget.chatPreferences != null)
                ChatSettingsSection(preferences: widget.chatPreferences!),
            ],
          ),
        );
      }
      if (!_profileInitialized ||
          (!_dirty &&
              !identical(_displayedProfile, widget.repository.profile))) {
        final profile = widget.repository.profile;
        _school.text = profile.school;
        _department.text = profile.department;
        _admissionYear.text = profile.admissionYear?.toString() ?? '';
        _academicYearOverride = profile.academicYearOverride;
        _weekStartsOn = profile.weekStartsOn;
        _track = profile.track;
        _displayedProfile = profile;
        _pendingInstitutionId = profile.institutionId;
        _pendingDepartmentId = profile.departmentId;
        _pendingCurriculumId = profile.curriculumId;
        _useCatalog = _catalogModeFor(profile);
        _profileInitialized = true;
      }
      final suggestedYear = _suggestedYear();
      return Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 1120),
          child: ContentScrollView(
            padding: const EdgeInsets.only(bottom: 28),
            child: Form(
              key: _formKey,
              child: ResponsiveColumns(
                enabled: true,
                first: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PageHeader(title: '설정', contextLabel: '일반'),
                    Text(
                      '학업과 계획',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '이 정보와 개인 일정은 ${widget.repository.isServerBacked ? '본인 계정 서버에' : '현재 기기에만'} 저장됩니다. 학교 공식 학적이나 졸업 판정을 변경하지 않습니다.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (widget.repository.isServerBacked)
                      PlanningImportSection(repository: widget.repository),
                    if (PersonalRepositoryScope.read(context)?.importer
                        case final importer?)
                      PersonalWorkspaceImportSection(importer: importer),
                    IgnorePointer(
                      ignoring: _saving,
                      child: _settingsCard(
                        child: ResponsiveColumns(
                          enabled: false,
                          first: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '학업 프로필',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 18),
                              if (_canUseCatalog) ...[
                                AnchoredSelectField<bool>(
                                  key: const Key('school-source-select'),
                                  value: _useCatalog,
                                  label: '학교 등록',
                                  options: const [
                                    SelectOption(true, '등록된 학교 목록에서 고르기'),
                                    SelectOption(false, '목록에 없는 학교 직접 입력'),
                                  ],
                                  onChanged: _setCatalogMode,
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _useCatalog
                                        ? '목록에서 고른 학교·학과·교육과정의 ID가 서버 프로필에 저장됩니다. 공식 학적 증명은 아닙니다.'
                                        : '직접 입력한 이름은 개인 계획용이며 공식 감사의 학교 ID가 아닙니다.',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontSize: AppTypography.caption,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                              if (_useCatalog && widget.studentApi != null)
                                SchoolContextForm(
                                  key: _schoolForm,
                                  api: widget.studentApi!.api,
                                  showStudy: false,
                                  showDate: false,
                                  initialInstitutionId: _pendingInstitutionId,
                                  initialDepartmentId: _pendingDepartmentId,
                                  initialCurriculumId: _pendingCurriculumId,
                                  onChanged: _captureCatalogSelection,
                                )
                              else ...[
                                TextFormField(
                                  controller: _school,
                                  maxLength: 128,
                                  onChanged: (_) => setState(() {
                                    _saved = false;
                                    _dirty = true;
                                  }),
                                  decoration: const InputDecoration(
                                    labelText: '학교',
                                    hintText: '예: 경동대학교',
                                  ),
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _department,
                                  maxLength: 128,
                                  onChanged: (_) => setState(() {
                                    _saved = false;
                                    _dirty = true;
                                  }),
                                  decoration: const InputDecoration(
                                    labelText: '학과',
                                    hintText: '예: 컴퓨터공학과',
                                  ),
                                  textInputAction: TextInputAction.next,
                                ),
                              ],
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _admissionYear,
                                onChanged: (_) => setState(() {
                                  _saved = false;
                                  _dirty = true;
                                }),
                                decoration: const InputDecoration(
                                  labelText: '입학연도',
                                  hintText: '예: 2024',
                                ),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return null;
                                  }
                                  final year = int.tryParse(value.trim());
                                  final current = DateTime.now().year + 1;
                                  if (year == null ||
                                      year < 1900 ||
                                      year > current) {
                                    return '1900년부터 $current년 사이의 연도를 입력해 주세요.';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                          second: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '개인 계획',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 18),
                              AnchoredSelectField<String?>(
                                value: _track,
                                label: '이수경로',
                                options: [
                                  const SelectOption(null, '미입력'),
                                  const SelectOption('single_major', '단일전공'),
                                  const SelectOption('double_major', '복수전공'),
                                  if (_track != null &&
                                      _track != 'single_major' &&
                                      _track != 'double_major')
                                    SelectOption(_track, _track!),
                                ],
                                onChanged: (value) => setState(() {
                                  _track = value;
                                  _saved = false;
                                  _dirty = true;
                                }),
                              ),
                              const SizedBox(height: 18),
                              AnchoredSelectField<int?>(
                                value: _academicYearOverride,
                                label: '개인 계획 학년',
                                options: [
                                  SelectOption<int?>(
                                    null,
                                    suggestedYear == null
                                        ? '자동 계산 (입학연도 필요)'
                                        : '자동 계산 ($suggestedYear학년 제안)',
                                  ),
                                  for (var year = 1; year <= 4; year++)
                                    SelectOption<int?>(year, '$year학년으로 직접 설정'),
                                ],
                                onChanged: (value) => setState(() {
                                  _academicYearOverride = value;
                                  _saved = false;
                                  _dirty = true;
                                }),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '개인 계획을 위한 안내값입니다. 공식 학적 상태나 서버 추천이 아닙니다.',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: AppTypography.caption,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              AnchoredSelectField<WeekStartDay>(
                                key: const Key('week-start-select'),
                                value: _weekStartsOn,
                                label: '주 시작 요일',
                                options: [
                                  for (final day in WeekStartDay.values)
                                    SelectOption(day, day.label),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _weekStartsOn = value;
                                    _saved = false;
                                    _dirty = true;
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '홈과 일정의 7일 표는 일요일부터 시작하며, 원하는 요일로 바꿀 수 있습니다.',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: AppTypography.caption,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(
                            _saving
                                ? '저장 중…'
                                : widget.repository.isServerBacked
                                ? '서버에 저장'
                                : '기기에 저장',
                          ),
                        ),
                        if (_saved) ...[
                          const SizedBox(width: 12),
                          Icon(
                            Icons.check_circle_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text('저장되었습니다.'),
                        ],
                      ],
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
                second: SizedBox(
                  key: const Key('settings-expansion-space'),
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppearanceSettingsSection(),
                      if (widget.chatPreferences != null)
                        ChatSettingsSection(
                          preferences: widget.chatPreferences!,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _settingsCard({required Widget child}) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );

  int? _suggestedYear() {
    final admissionYear = int.tryParse(_admissionYear.text.trim());
    return PlanningProfile(admissionYear: admissionYear)
        .academicYearFor(DateTime.now());
  }

  void _setCatalogMode(bool value) {
    final form = _schoolForm.currentState;
    setState(() {
      if (!value && form != null) {
        final schoolName = form.institutionName;
        final departmentName = form.departmentName;
        if (schoolName != null && schoolName.isNotEmpty) {
          _school.text = schoolName;
        }
        if (departmentName != null && departmentName.isNotEmpty) {
          _department.text = departmentName;
        }
        _pendingInstitutionId = form.selectedInstitutionId;
        _pendingDepartmentId = form.selectedDepartmentId;
        _pendingCurriculumId = form.selectedCurriculumId;
      }
      _useCatalog = value;
      _saved = false;
      _dirty = true;
      _error = null;
    });
  }

  void _captureCatalogSelection() {
    final form = _schoolForm.currentState;
    if (form == null) {
      return;
    }
    _pendingInstitutionId = form.selectedInstitutionId;
    _pendingDepartmentId = form.selectedDepartmentId;
    _pendingCurriculumId = form.selectedCurriculumId;
    setState(() {
      _saved = false;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final catalog = _useCatalog ? _schoolForm.currentState : null;
    if (_useCatalog &&
        (catalog == null ||
            !catalog.isReady ||
            catalog.institutionId == null)) {
      setState(() {
        _error = '목록에서 학교를 고르거나, 목록에 없는 학교로 바꿔 주세요.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      await widget.repository.saveProfile(
        PlanningProfile(
          version: _displayedProfile?.version,
          school: _useCatalog
              ? (catalog?.institutionName ?? '').trim()
              : _school.text.trim(),
          department: _useCatalog
              ? (catalog?.departmentName ?? '').trim()
              : _department.text.trim(),
          admissionYear: int.tryParse(_admissionYear.text.trim()),
          track: _track,
          academicYearOverride: _academicYearOverride,
          weekStartsOn: _weekStartsOn,
          institutionId: _useCatalog ? catalog?.institutionId : null,
          departmentId: _useCatalog ? catalog?.departmentId : null,
          curriculumId: _useCatalog ? catalog?.curriculumId : null,
        ),
      );
      if (mounted) {
        setState(() {
          _saved = true;
          _dirty = false;
          _displayedProfile = widget.repository.profile;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AuthFailure
              ? '${error.message} 입력은 유지됩니다.'
              : '${widget.repository.isServerBacked ? '서버' : '기기'}에 저장하지 못했습니다. 입력을 유지했으니 다시 시도하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
