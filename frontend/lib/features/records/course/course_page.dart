import 'package:flutter/material.dart';

import '../fixtures/course_fixture.dart';
import '../record_menu_page.dart';

class CoursePage extends StatelessWidget {
  const CoursePage({super.key, required this.showMockData});
  final bool showMockData;
  @override
  Widget build(BuildContext context) => RecordMenuPage(
    kicker: 'ACADEMIC RECORDS',
    title: '수강 관리',
    description: '학교 수강 내역을 기준으로 이번 학기 계획과 이수 기록을 정리합니다.',
    notice: '학교 정보가 없어도 내 수강 기록을 직접 입력할 수 있습니다. 졸업 반영은 학교의 확정 기록을 기준으로 확인합니다.',
    listTitle: '이번 학기 수강 과목',
    fixture: courseMockEntries,
    guideTitle: '교육과정 확인',
    guides: const ['인정 영역과 학점 분류 확인', '다음 학기 수강 계획 정리', '학과 공지의 변경 사항 확인'],
    addLabel: '수강 과목 직접 입력',
    detailLabel: '구분 · 학점',
    showMockData: showMockData,
  );
}
