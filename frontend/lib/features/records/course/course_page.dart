import 'package:flutter/material.dart';

import '../../api/student_api.dart';
import '../../planning/planning_repository.dart';
import '../record_menu_page.dart';
import '../personal_record_repository.dart';

class CoursePage extends StatelessWidget {
  const CoursePage({
    super.key,
    this.studentApi,
    this.planning,
    this.onOpenSettings,
  });
  final StudentApi? studentApi;
  final PlanningRepository? planning;
  final VoidCallback? onOpenSettings;
  @override
  Widget build(BuildContext context) => RecordMenuPage(
    key: const ValueKey(PersonalRecordKind.course),
    kind: PersonalRecordKind.course,
    title: '수강 관리',
    description: '학기별 수강 계획과 개인 이수 기록을 정리합니다.',
    listTitle: '내 수강 과목',
    guideTitle: '교육과정 확인',
    guides: const ['다음 학기 수강 계획 정리', '학과 공지의 변경 사항 확인'],
    addLabel: '수강 과목 추가',
    detailLabel: '구분 · 학점',
    studentApi: studentApi,
    institutionId: planning?.profile.institutionId,
    planning: planning,
    onOpenSettings: onOpenSettings,
  );
}
