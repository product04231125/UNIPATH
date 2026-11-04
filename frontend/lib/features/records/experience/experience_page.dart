import 'package:flutter/material.dart';

import '../record_menu_page.dart';
import '../personal_record_repository.dart';

class ExperiencePage extends StatelessWidget {
  const ExperiencePage({super.key});
  @override
  Widget build(BuildContext context) => RecordMenuPage(
    key: const ValueKey(PersonalRecordKind.experience),
    kind: PersonalRecordKind.experience,
    title: '경험',
    description: '프로젝트·인턴·동아리 경험을 이력 문장과 강점으로 정리합니다.',
    listTitle: '경험 타임라인',
    guideTitle: '이력 정리',
    guides: const ['내 역할과 결과를 분리해 기록', '증빙 링크·자료 위치 보관', '자기소개서 문장 초안 만들기'],
    addLabel: '경험 직접 기록',
    detailLabel: '기간 · 역할 · 결과',
  );
}
