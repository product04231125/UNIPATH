import 'package:flutter/material.dart';

import '../records/personal_record_repository.dart';
import '../records/local_record_workbench.dart';
import '../planning/planning_repository.dart';
import 'personal_graduation_fields.dart';

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
  var _editor = GlobalKey<LocalRecordWorkbenchState>();
  static const _labels = {
    PersonalRecordKind.personalSchool: '학교',
    PersonalRecordKind.personalDepartment: '학과',
    PersonalRecordKind.personalCurriculum: '교육과정',
    PersonalRecordKind.personalCurriculumCourse: '교육과정 과목',
    PersonalRecordKind.personalGraduationRule: '개인 규칙',
  };
  Future<void> _select(PersonalRecordKind kind) async {
    if (kind == _kind) return;
    if (await (_editor.currentState?.allowLeave() ?? Future.value(true)) &&
        mounted) {
      // A new key is required because the repository belongs to one record kind.
      setState(() {
        _kind = kind;
        _editor = GlobalKey<LocalRecordWorkbenchState>();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in _labels.entries)
            OutlinedButton(
              onPressed: () => _select(entry.key),
              style: OutlinedButton.styleFrom(
                backgroundColor: _kind == entry.key
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
              ),
              child: Text(entry.value),
            ),
          TextButton(
            onPressed: () async {
              if (await (_editor.currentState?.allowLeave() ??
                      Future.value(true)) &&
                  mounted)
                widget.onBack();
            },
            child: const Text('졸업 요건으로 돌아가기'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Expanded(
        child: KeyedSubtree(
          key: ValueKey(_kind),
          child: LocalRecordWorkbench(
            key: _editor,
            kind: _kind,
            title: '개인 ${_labels[_kind]}',
            fieldsLoader: () => personalGraduationFields(_kind),
            validateValues: (values) =>
                validatePersonalGraduationLinks(_kind, values),
            onUse:
                _kind == PersonalRecordKind.personalCurriculum &&
                    widget.planning != null
                ? (record) async {
                    await widget.planning!.saveSchoolContext(
                      school: record.value('school'),
                      department: record.value('department'),
                      admissionYear: int.tryParse(
                        record.value('admissionYear'),
                      ),
                      track: record.value('title'),
                    );
                  }
                : null,
          ),
        ),
      ),
    ],
  );
}
