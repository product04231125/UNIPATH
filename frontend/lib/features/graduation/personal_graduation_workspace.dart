import 'package:flutter/material.dart';

import '../records/personal_record_repository.dart';
import '../records/record_menu_page.dart';
import 'personal_graduation_fields.dart';

class PersonalGraduationWorkspace extends StatefulWidget {
  const PersonalGraduationWorkspace({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<PersonalGraduationWorkspace> createState() =>
      _PersonalGraduationWorkspaceState();
}

class _PersonalGraduationWorkspaceState
    extends State<PersonalGraduationWorkspace> {
  PersonalRecordKind _kind = PersonalRecordKind.personalCurriculum;
  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final (title, add) = switch (_kind) {
      PersonalRecordKind.personalCurriculum => ('개인 교육과정', '교육과정 추가'),
      PersonalRecordKind.personalCurriculumCourse => ('교육과정 과목', '교육과정 과목 추가'),
      _ => ('개인 졸업 규칙', '개인 규칙 추가'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (kind, label) in [
              (PersonalRecordKind.personalCurriculum, '교육과정'),
              (PersonalRecordKind.personalCurriculumCourse, '교육과정 과목'),
              (PersonalRecordKind.personalGraduationRule, '개인 규칙'),
            ])
              OutlinedButton(
                onPressed: () => setState(() => _kind = kind),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _kind == kind
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null,
                ),
                child: Text(label),
              ),
            TextButton(
              onPressed: widget.onBack,
              child: const Text('졸업 요건으로 돌아가기'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RecordMenuPage(
            key: ValueKey(_kind),
            kind: _kind,
            contextLabel: '개인 학업 작업 공간',
            title: title,
            description: '학교 연동 없이 내 교육과정과 규칙을 기기에 기록합니다.',
            notice: '개인 자료 · 학교 공식 규칙이나 판정이 아닙니다. 현재 값은 직접 기록한 값이며 충족 여부를 계산하지 않습니다.',
            listTitle: title,
            fixture: const [],
            guideTitle: '입력과 연결 안내',
            guides: const [
              '교육과정을 먼저 만들고 과목·규칙에 연결하세요.',
              '규칙 종류·단위·조건은 직접 기록합니다. 서버 규칙이나 enum이 아닙니다.',
              '연결 대상 삭제 시 원본을 연쇄 삭제하지 않습니다. 연결 대상 없음 표시를 확인하고 수정에서 다시 선택하세요.',
              '설정의 학업과 계획 프로필과 별도인 교육과정별 적용 범위입니다. 수정해도 기존 규칙은 지워지지 않습니다.',
            ],
            addLabel: add,
            detailLabel: '개인 기준',
            showMockData: false,
            fieldsLoader: () => personalGraduationFields(kind),
            validateValues: (values) =>
                validatePersonalGraduationLinks(kind, values),
          ),
        ),
      ],
    );
  }
}
