import 'package:flutter/material.dart';

import '../fixtures/activity_fixture.dart';
import '../record_menu_page.dart';

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.showMockData});
  final bool showMockData;
  @override
  Widget build(BuildContext context) => RecordMenuPage(
    kicker: 'ACTIVITY RECORDS',
    title: '활동',
    description: '교내외 활동과 봉사 내역을 한곳에 기록합니다.',
    notice: '학교 정보가 없어도 내 활동을 직접 기록할 수 있습니다. 졸업 반영이 필요한 활동은 학교 승인 후 확인해 주세요.',
    listTitle: '등록한 활동',
    fixture: activityMockEntries,
    guideTitle: '활동 준비',
    guides: const ['봉사 시간·증빙 자료 점검', '교내 활동 인정 절차 확인', '필요할 때 외부 봉사 사이트 안내'],
    addLabel: '활동 직접 기록',
    detailLabel: '기관 · 기간 · 역할',
    showMockData: showMockData,
  );
}
