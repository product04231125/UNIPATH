import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/app_typography.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/content_scroll_view.dart';
import 'graduation_mock_fixture.dart';
import 'personal_graduation_workspace.dart';

class GraduationPage extends StatefulWidget {
  const GraduationPage({
    super.key,
    this.showMockData = true,
    this.onMinimumWidthChanged,
  });
  final bool showMockData;
  final ValueChanged<double>? onMinimumWidthChanged;
  @override
  State<GraduationPage> createState() => _GraduationPageState();
}

class _GraduationPageState extends State<GraduationPage> {
  final _curriculumScrollController = ScrollController();
  var _tab = '대학 공통';
  bool _personal = false;
  @override
  void dispose() {
    _curriculumScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_personal) {
      return PersonalGraduationWorkspace(
        onBack: () {
          setState(() => _personal = false);
          _reportMinimumWidth();
        },
      );
    }
    return ContentScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: '졸업 요건',
            contextLabel: widget.showMockData
                ? '예시 데이터 · 학교 연동·공식 판정 API 미연결'
                : '학교 연동·공식 판정 API 미연결',
            actions: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _personal = true);
                  _reportMinimumWidth();
                },
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('내 학교·학과 기준 설정'),
              ),
            ],
          ),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '기준 선택',
                  style: TextStyle(
                    fontSize: AppTypography.section,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  '아래 표는 화면 설명용 예시입니다. 실제 졸업 결과가 아닙니다. 내 자료는 개인 기준 설정에서 입력하세요.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final value in ['대학 공통', '내 교육과정', '학과 기준'])
                      OutlinedButton(
                        onPressed: () {
                          setState(() => _tab = value);
                          _reportMinimumWidth();
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _tab == value
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                        ),
                        child: Text(value),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (widget.showMockData)
            _table()
          else
            const SurfaceCard(
              child: Text(
                '학교 기준을 가져오는 API가 아직 연결되지 않았습니다. 내 학교·학과 기준 설정에서 개인 자료를 기록하세요.',
              ),
            ),
        ],
      ),
    );
  }

  void _reportMinimumWidth() => widget.onMinimumWidthChanged?.call(
    !_personal && _tab == '내 교육과정'
        ? 92 +
              58.0 * (curriculumHeaders.length - 1) +
              SurfaceCard.horizontalInsets
        : 0,
  );

  Widget _table() {
    final (title, headers, rows) = switch (_tab) {
      '대학 공통' => ('대학 공통 기준 · 예시', commonRuleHeaders, commonRuleRows),
      '내 교육과정' => ('내 교육과정 학점 현황 · 예시', curriculumHeaders, curriculumRows),
      _ => ('학과 졸업인증 · 예시', departmentHeaders, departmentRows),
    };
    final compact = _tab == '내 교육과정';
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: AppTypography.section,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = math.max(
                58.0,
                (constraints.maxWidth - 92) / (headers.length - 1),
              );
              final table = Table(
                border: TableBorder.all(color: Theme.of(context).dividerColor),
                columnWidths: compact
                    ? {
                        0: const FixedColumnWidth(92),
                        for (var i = 1; i < headers.length; i++)
                          i: FixedColumnWidth(cellWidth),
                      }
                    : {
                        0: const FlexColumnWidth(1.9),
                        for (var i = 1; i < headers.length; i++)
                          i: const FlexColumnWidth(),
                      },
                children: [
                  TableRow(
                    children: [
                      for (final header in headers)
                        _cell(header, header: true, compact: compact),
                    ],
                  ),
                  for (final row in rows)
                    TableRow(
                      children: [
                        for (var i = 0; i < row.length; i++)
                          _cell(
                            row[i],
                            compact: compact,
                            status: headers[i] == '판정' || headers[i] == '상태',
                          ),
                      ],
                    ),
                ],
              );
              if (!compact) return table;
              final width = 92 + cellWidth * (headers.length - 1);
              return Scrollbar(
                controller: _curriculumScrollController,
                thumbVisibility: width > constraints.maxWidth,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  controller: _curriculumScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: width, child: table),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cell(
    String value, {
    bool header = false,
    bool compact = false,
    bool status = false,
  }) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 6 : 10,
      vertical: compact ? 9 : 12,
    ),
    child: status
        ? Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(status: value),
          )
        : Text(
            value,
            textAlign: compact ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              fontSize: AppTypography.caption,
              fontWeight: header ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
  );
}
