import 'package:flutter/material.dart';

import 'job_analysis_page.dart';
import 'materials_page.dart';
import 'material_repository.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({
    super.key,
    this.showMockData = true,
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
  var _stage = 0;
  final _materials = GlobalKey<MaterialsPageState>();

  Future<void> _select(int stage) async {
    if (stage == _stage) return;
    if (_stage == 0 &&
        !await (_materials.currentState?.allowLeave() ?? Future.value(true))) {
      return;
    }
    if (mounted) setState(() => _stage = stage);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (index, label) in [(0, '내 자료'), (1, '채용공고 분석')])
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
          child: IndexedStack(
            index: _stage,
            children: [
              MaterialsPage(
                key: _materials,
                repository: widget.materialRepository,
              ),
              const JobAnalysisPage(),
            ],
          ),
        ),
      ],
    );
  }
}
