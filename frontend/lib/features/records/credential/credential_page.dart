import 'package:flutter/material.dart';

import '../fixtures/credential_fixture.dart';
import '../record_menu_page.dart';
import '../personal_record_repository.dart';

class CredentialPage extends StatelessWidget {
  const CredentialPage({super.key, required this.showMockData});

  final bool showMockData;

  @override
  Widget build(BuildContext context) => RecordMenuPage(
    key: const ValueKey(PersonalRecordKind.credential),
    kind: PersonalRecordKind.credential,
    kicker: 'CERTIFICATE RECORDS',
    title: '자격',
    description: '자격증·어학·교육 이수 내역을 관리합니다.',
    notice: '학교 정보가 없어도 내 자격·어학·교육 이수 내역을 직접 등록할 수 있습니다. 발급 정보는 원문 또는 발급 기관 기준으로 확인해 주세요.',
    listTitle: '등록한 자격',
    fixture: credentialMockEntries,
    guideTitle: '자격 준비',
    guides: const [
      '희망 직무와 자격의 연관성 탐색',
      'Q-Net 시험 일정·발급 정보 안내',
      '성적·자격 유효기간 점검',
    ],
    addLabel: '자격 직접 등록',
    detailLabel: '발급 기관 · 취득일 · 유효기간',
    showMockData: showMockData,
  );
}
