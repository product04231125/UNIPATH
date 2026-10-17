import 'package:flutter/material.dart';

import '../fixtures/portfolio_fixture.dart';
import '../record_menu_page.dart';
import '../personal_record_repository.dart';
import 'portfolio_drafts_page.dart';
import 'materials_page.dart';
import 'material_repository.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({
    super.key,
    required this.showMockData,
    this.active = true,
    this.materialRepository,
  });

  final bool showMockData;
  final bool active;
  final MaterialRepository? materialRepository;

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  int _stage = 3;
  final _materials = GlobalKey<MaterialsPageState>();
  Future<void> _select(int stage) async {
    if (stage == _stage) return;
    if (_stage == 3 &&
        !await (_materials.currentState?.allowLeave() ?? Future.value(true))) {
      return;
    }
    if (mounted) setState(() => _stage = stage);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (index, label) in [
            (3, '내 자료'),
            (0, '성과 기록'),
            (1, '기존 구성'),
            (2, '기존 지원 문서'),
          ])
            OutlinedButton(
              onPressed: () => _select(index),
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
        child: _stage == 3
            ? MaterialsPage(
                key: _materials,
                repository: widget.materialRepository,
              )
            : _stage == 0
            ? _records()
            : PortfolioDraftsPage(
                active: widget.active,
                key: ValueKey(_stage),
                isDocument: _stage == 2,
                onOpenAchievements: () => setState(() => _stage = 0),
              ),
      ),
    ],
  );

  Widget _records() => RecordMenuPage(
    key: const ValueKey(PersonalRecordKind.portfolio),
    kind: PersonalRecordKind.portfolio,
    title: '성과 기록',
    description: '프로젝트, 논문, 수상과 산출물을 포트폴리오로 구성합니다.',
    notice: '내 프로젝트·논문·수상과 산출물을 직접 기록합니다. 완성 파일이나 짧은 설명은 내 자료에 등록할 수 있습니다.',
    listTitle: '성과 목록',
    fixture: portfolioMockEntries,
    guideTitle: '성과 구성',
    guides: const [
      '설명·역할·결과·링크를 함께 보관',
      '논문·캡스톤은 유형·상태·원 성적·확인한 승인일을 선택 기록 · 학교 승인 처리 아님',
      '파일은 올리지 않으며 공개 가능한 링크만 기록',
      '기존 구성에서 항목·순서·사용 의도 확인',
      '기존 지원 문서 초안도 계속 편집할 수 있습니다.',
    ],
    addLabel: '성과 직접 기록',
    detailLabel: '유형 · 역할 · 결과 또는 링크',
    showMockData: widget.showMockData,
  );
}
