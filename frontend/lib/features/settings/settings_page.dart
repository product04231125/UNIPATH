import 'package:flutter/material.dart';
import 'package:university_path_frontend/shared/app_typography.dart';

import '../planning/planning_repository.dart';
import '../planning/planning_storage_state.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/page_header.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.repository});

  final PlanningRepository repository;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _school;
  late final TextEditingController _department;
  late final TextEditingController _admissionYear;
  int? _academicYearOverride;
  late WeekStartDay _weekStartsOn;
  bool _saved = false;
  bool _saving = false;
  String? _error;
  bool _profileInitialized = false;

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
    _profileInitialized =
        !widget.repository.isLoading && !widget.repository.loadFailed;
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
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(title: '설정', contextLabel: '일반'),
              PlanningStorageState(repository: widget.repository),
            ],
          ),
        );
      }
      if (!_profileInitialized) {
        final profile = widget.repository.profile;
        _school.text = profile.school;
        _department.text = profile.department;
        _admissionYear.text = profile.admissionYear?.toString() ?? '';
        _academicYearOverride = profile.academicYearOverride;
        _weekStartsOn = profile.weekStartsOn;
        _profileInitialized = true;
      }
      final suggestedYear = _suggestedYear();
      return Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PageHeader(title: '설정', contextLabel: '일반'),
                  Text('학업과 계획', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text(
                    '이 정보와 개인 일정은 현재 기기에만 저장됩니다. 학교 공식 학적이나 졸업 판정을 변경하지 않습니다.',
                    style: TextStyle(color: Color(0xff607386), height: 1.45),
                  ),
                  const SizedBox(height: 18),
                  IgnorePointer(
                    ignoring: _saving,
                    child: _settingsCard(
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _school,
                            onChanged: (_) => setState(() => _saved = false),
                            decoration: const InputDecoration(
                              labelText: '학교',
                              hintText: '예: 경동대학교',
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _department,
                            onChanged: (_) => setState(() => _saved = false),
                            decoration: const InputDecoration(
                              labelText: '학과',
                              hintText: '예: 컴퓨터공학과',
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _admissionYear,
                            onChanged: (_) => setState(() => _saved = false),
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
                            }),
                          ),
                          const SizedBox(height: 8),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '개인 계획을 위한 안내값입니다. 공식 학적 상태나 서버 추천이 아닙니다.',
                              style: TextStyle(
                                color: Color(0xff607386),
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
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '홈과 일정의 7일 표는 일요일부터 시작하며, 원하는 요일로 바꿀 수 있습니다.',
                              style: TextStyle(
                                color: Color(0xff607386),
                                fontSize: AppTypography.caption,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? '저장 중…' : '기기에 저장'),
                      ),
                      if (_saved) ...[
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.check_circle_outline,
                          color: Color(0xff356842),
                        ),
                        const SizedBox(width: 4),
                        const Text('저장되었습니다.'),
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      await widget.repository.saveProfile(
        PlanningProfile(
          school: _school.text.trim(),
          department: _department.text.trim(),
          admissionYear: int.tryParse(_admissionYear.text.trim()),
          academicYearOverride: _academicYearOverride,
          weekStartsOn: _weekStartsOn,
        ),
      );
      if (mounted) setState(() => _saved = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '기기에 저장하지 못했습니다. 입력을 유지했으니 다시 시도하세요.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
