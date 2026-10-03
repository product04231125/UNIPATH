import 'package:flutter/material.dart';

import '../fixtures/activity_fixture.dart';
import '../record_menu_page.dart';
import '../personal_record_repository.dart';
import '../../../shared/widgets/external_link_button.dart';

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.showMockData});
  final bool showMockData;
  @override
  Widget build(BuildContext context) => RecordMenuPage(
    key: const ValueKey(PersonalRecordKind.activity),
    kind: PersonalRecordKind.activity,
    kicker: 'ACTIVITY RECORDS',
    title: '활동',
    description: '교내외 활동과 봉사 내역을 한곳에 기록합니다.',
    notice: '학교 정보가 없어도 내 활동을 직접 기록할 수 있습니다. 졸업 반영이 필요한 활동은 학교 승인 후 확인해 주세요.',
    listTitle: '등록한 활동',
    fixture: activityMockEntries,
    guideTitle: '활동 준비',
    guides: const ['봉사 시간·증빙 자료 점검', '교내 활동 인정 절차 확인', '필요할 때 외부 봉사 사이트 안내'],
    guideActions: const [
      ExternalLinkButton(
        url: 'https://www.1365.go.kr/',
        label: '1365 봉사 찾기',
        description: '1365에서 활동을 찾아 직접 신청하고, 학교 인정이 필요한 활동은 학교에 등록·승인받으세요. 링크 열기로 봉사 시간이나 승인 상태를 자동 변경하지 않습니다.',
      ),
    ],
    addLabel: '활동 직접 기록',
    detailLabel: '기관 · 기간 · 역할',
    showMockData: showMockData,
  );
}
