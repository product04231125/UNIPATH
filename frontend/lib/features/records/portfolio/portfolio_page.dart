import 'package:flutter/material.dart';

import '../fixtures/portfolio_fixture.dart';
import '../record_menu_page.dart';

class PortfolioPage extends StatelessWidget {
  const PortfolioPage({super.key, required this.showMockData});

  final bool showMockData;

  @override
  Widget build(BuildContext context) => RecordMenuPage(
    kicker: 'PORTFOLIO & OUTCOMES',
    title: '포트폴리오·성과',
    description: '프로젝트, 논문, 수상과 산출물을 포트폴리오로 구성합니다.',
    notice: '학교 정보가 없어도 내 프로젝트·논문·수상과 산출물을 직접 기록할 수 있습니다. 파일은 증빙용으로, 핵심 내용은 설명으로 함께 적어 주세요.',
    listTitle: '포트폴리오 초안',
    fixture: portfolioMockEntries,
    guideTitle: '성과 구성',
    guides: const ['설명·역할·결과·링크를 함께 보관', '공개 가능한 파일만 첨부', '지원 목적에 맞게 항목 순서 구성'],
    addLabel: '성과 직접 기록',
    detailLabel: '유형 · 역할 · 결과 또는 링크',
    showMockData: showMockData,
  );
}
