import 'package:flutter/material.dart';

import '../personal_repository_scope.dart';

import '../fixtures/course_fixture.dart';
import '../record_menu_page.dart';
import '../personal_record_repository.dart';

class CoursePage extends StatelessWidget {
  const CoursePage({super.key, required this.showMockData});
  final bool showMockData;
  @override
  Widget build(BuildContext context) => RecordMenuPage(
    key: const ValueKey(PersonalRecordKind.course),
    kind: PersonalRecordKind.course,
    title: '수강 관리',
    description: '학기별 수강 계획과 개인 이수 기록을 정리합니다.',
    notice: PersonalRepositoryScope.read(context) == null
        ? '기기 로컬 개인 기록 · 졸업 반영은 학교의 확정 기록으로 확인하세요.'
        : '계정 서버 개인 기록 · 졸업 반영은 학교의 확정 기록으로 확인하세요.',
    listTitle: '내 수강 과목',
    fixture: courseMockEntries,
    guideTitle: '교육과정 확인',
    guides: const ['인정 영역과 학점 분류 확인', '다음 학기 수강 계획 정리', '학과 공지의 변경 사항 확인'],
    addLabel: '수강 과목 직접 입력',
    detailLabel: '구분 · 학점',
    showMockData: showMockData,
  );
}
