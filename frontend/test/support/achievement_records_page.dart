import 'package:flutter/material.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/record_menu_page.dart';

Widget achievementRecordsPage() => const RecordMenuPage(
  kind: PersonalRecordKind.portfolio,
  title: '성과 기록',
  description: '프로젝트, 논문, 수상과 산출물을 포트폴리오로 구성합니다.',
  listTitle: '성과 목록',
  guideTitle: '성과 구성',
  guides: [
    '설명·역할·결과·링크를 함께 보관',
    '논문·캡스톤은 유형·상태·원 성적을 선택 기록',
    '파일은 올리지 않으며 공개 가능한 링크만 기록',
  ],
  addLabel: '성과 직접 기록',
  detailLabel: '유형 · 역할 · 결과 또는 링크',
);
