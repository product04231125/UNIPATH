import 'package:flutter/material.dart';

import '../fixtures/portfolio_fixture.dart';
import '../record_menu_page.dart';
import '../personal_record_repository.dart';
import 'portfolio_drafts_page.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key, required this.showMockData});

  final bool showMockData;

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  int _stage = 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (index, label) in [
            (0, '1. 성과 기록'),
            (1, '2. 포트폴리오 구성'),
            (2, '3. 지원 문서'),
          ])
            OutlinedButton(
              onPressed: () => setState(() => _stage = index),
              style: OutlinedButton.styleFrom(
                backgroundColor: _stage == index
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
              ),
              child: Text(label),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Expanded(
        child: _stage == 0
            ? _records()
            : PortfolioDraftsPage(
                key: ValueKey(_stage),
                isDocument: _stage == 2,
              ),
      ),
    ],
  );

  Widget _records() => RecordMenuPage(
    key: const ValueKey(PersonalRecordKind.portfolio),
    kind: PersonalRecordKind.portfolio,
    title: '성과 기록',
    description: '프로젝트, 논문, 수상과 산출물을 포트폴리오로 구성합니다.',
    notice: '학교 정보가 없어도 내 프로젝트·논문·수상과 산출물을 직접 기록할 수 있습니다. 파일 업로드·게시 없이 역할·결과·공개 가능한 링크를 기록합니다.',
    listTitle: '포트폴리오 초안',
    fixture: portfolioMockEntries,
    guideTitle: '성과 구성',
    guides: const [
      '설명·역할·결과·링크를 함께 보관',
      '논문·캡스톤은 유형·상태·원 성적·확인한 승인일을 선택 기록 · 학교 승인 처리 아님',
      '파일은 올리지 않으며 공개 가능한 링크만 기록',
      '2단계에서 항목·순서·사용 의도 선택',
      '3단계에서 지원처별 문서 초안 직접 편집',
    ],
    addLabel: '성과 직접 기록',
    detailLabel: '유형 · 역할 · 결과 또는 링크',
    showMockData: widget.showMockData,
  );
}
