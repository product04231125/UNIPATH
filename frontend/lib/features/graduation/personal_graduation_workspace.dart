import 'package:flutter/material.dart';

import '../records/personal_record_repository.dart';
import '../records/personal_repository_scope.dart';
import '../records/local_record_workbench.dart';
import '../planning/planning_repository.dart';
import 'personal_graduation_fields.dart';
import 'personal_calculation_page.dart';

class PersonalGraduationWorkspace extends StatefulWidget {
  const PersonalGraduationWorkspace({
    super.key,
    required this.onBack,
    this.planning,
  });
  final VoidCallback onBack;
  final PlanningRepository? planning;
  @override
  State<PersonalGraduationWorkspace> createState() =>
      _PersonalGraduationWorkspaceState();
}

class _PersonalGraduationWorkspaceState
    extends State<PersonalGraduationWorkspace> {
  PersonalRecordKind _kind = PersonalRecordKind.personalCurriculum;
  bool _calculation = false;
  var _editor = GlobalKey<LocalRecordWorkbenchState>();
  static const _labels = {
    PersonalRecordKind.personalSchool: '학교',
    PersonalRecordKind.personalDepartment: '학과',
    PersonalRecordKind.personalCurriculum: '교육과정',
    PersonalRecordKind.personalCurriculumCourse: '교육과정 과목',
    PersonalRecordKind.personalGraduationRule: '개인 규칙',
  };
  Future<void> _select(
    PersonalRecordKind kind, {
    bool calculation = false,
  }) async {
    if (kind == _kind && calculation == _calculation) return;
    if (await (_editor.currentState?.allowLeave() ?? Future.value(true)) &&
        mounted) {
      setState(() {
        _kind = kind;
        _calculation = calculation;
        _editor = GlobalKey<LocalRecordWorkbenchState>();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = PersonalRepositoryScope.read(context);
    final factory = scope?.records;
    final calculation = scope?.calculations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _labels.entries.where(
              (entry) => factory == null || entry.key.hasServerContract,
            ))
              OutlinedButton(
                onPressed: () => _select(entry.key),
                style: OutlinedButton.styleFrom(
                  backgroundColor: !_calculation && _kind == entry.key
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null,
                ),
                child: Text(entry.value),
              ),
            if (calculation != null)
              OutlinedButton(
                onPressed: () => _select(_kind, calculation: true),
                child: const Text('개인 기준 계산·이력'),
              ),
            TextButton(
              onPressed: () async {
                if (await (_editor.currentState?.allowLeave() ??
                        Future.value(true)) &&
                    mounted) {
                  widget.onBack();
                }
              },
              child: const Text('졸업 요건으로 돌아가기'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _calculation && calculation != null
              ? PersonalCalculationPage(controller: calculation)
              : LocalRecordWorkbench(
                  key: _editor,
                  repository: factory?.call(_kind),
                  kind: _kind,
                  title: '개인 ${_labels[_kind]}',
                  fieldsLoader: () => personalGraduationFields(
                    _kind,
                    repositoryFactory: factory,
                  ),
                  validateValues: (values) => validatePersonalGraduationLinks(
                    _kind,
                    values,
                    repositoryFactory: factory,
                  ),
                  onUse:
                      _kind == PersonalRecordKind.personalCurriculum &&
                          widget.planning != null
                      ? (record) => widget.planning!.saveSchoolContext(
                          school: record.value('school'),
                          department: record.value('department'),
                          admissionYear: int.tryParse(
                            record.value('admissionYear'),
                          ),
                          track: record.value('title'),
                        )
                      : null,
                ),
        ),
      ],
    );
  }
}
