import 'package:flutter/material.dart';

import '../fixtures/experience_fixture.dart';
import '../record_menu_page.dart';

class ExperiencePage extends StatelessWidget {
  const ExperiencePage({super.key, required this.showMockData});
  final bool showMockData;
  @override
  Widget build(BuildContext context) => RecordMenuPage(
    kicker: 'EXPERIENCE RECORDS',
    title: '경험',
    description: '프로젝트·인턴·동아리 경험을 이력 문장과 강점으로 정리합니다.',
    notice:
        '학교 정보가 없어도 내 경험을 직접 기록할 수 있습니다. 사실과 역할을 먼저 적고, 표현 정리는 AI 도우미에게 물어보세요.',
    listTitle: '경험 타임라인',
    fixture: experienceMockEntries,
    guideTitle: '이력 정리',
    guides: const ['내 역할과 결과를 분리해 기록', '증빙 링크·자료 위치 보관', '자기소개서 문장 초안 만들기'],
    addLabel: '경험 직접 기록',
    detailLabel: '기간 · 역할 · 결과',
    showMockData: showMockData,
  );
}
