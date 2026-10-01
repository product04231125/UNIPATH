import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/surface_card.dart';
import 'graduation_mock_fixture.dart';

/// Owns the graduation-screen mock state until the audit API contract exists.
class GraduationPage extends StatefulWidget {
  const GraduationPage({
    super.key,
    this.profileLabel,
    this.isPersonalMode,
    this.onConfigurePersonalRules,
    this.personalContent,
    this.officialContent,
  });

  /// Transitional compatibility inputs for `_legacyBuild`; the active screen
  /// owns all graduation state in [_GraduationPageState].
  final String? profileLabel;
  final bool? isPersonalMode;
  final VoidCallback? onConfigurePersonalRules;
  final Widget? personalContent;
  final Widget? officialContent;

  @override
  State<GraduationPage> createState() => _GraduationPageState();
}

class _GraduationPageState extends State<GraduationPage> {
  final _curriculumScrollController = ScrollController();
  final _personalRules = <_PersonalRule>[];
  var _tab = '대학 공통';
  var _isPersonalMode = false;
  var _personalSchool = '';
  var _personalDepartment = '';
  var _personalAdmissionYear = '';

  @override
  void dispose() {
    _curriculumScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _isPersonalMode
            ? '$_personalSchool $_personalDepartment · $_personalAdmissionYear학번 · 개인 기준'
            : '경동대학교 컴퓨터공학과 · 2024학번',
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xff946c2e),
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            '졸업 요건',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          OutlinedButton.icon(
            onPressed: _showPersonalAcademicSetup,
            icon: const Icon(Icons.tune, size: 18),
            label: Text(_isPersonalMode ? '개인 기준 수정' : '내 학교·학과 기준 설정'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Expanded(
        child: _isPersonalMode
            ? SingleChildScrollView(child: _personalContent())
            : _officialContent(),
      ),
    ],
  );

  Widget _officialContent() => Column(
    children: [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '기준 선택',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const Text(
              '대학 공통 기준부터 봅니다. 탭을 누르면 해당 기준의 상세 표로 전환됩니다.',
              style: TextStyle(fontSize: 12, color: Color(0xff607386)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: ['대학 공통', '내 교육과정', '학과 기준']
                  .map(
                    (value) => OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _tab == value
                            ? const Color(0xffe5f0f5)
                            : Colors.white,
                      ),
                      onPressed: () => setState(() => _tab = value),
                      child: Text(value),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Expanded(child: SingleChildScrollView(child: _officialTable())),
    ],
  );

  Widget _officialTable() {
    switch (_tab) {
      case '대학 공통':
        return _section(
          '대학 공통 기준',
          '경동대학교 일반 학부생에게 공통으로 적용되는 기준입니다. 개인 예외는 학교 학사 시스템에서 확인합니다.',
          commonRuleHeaders,
          commonRuleRows,
          firstColumnWidth: 260,
        );
      case '내 교육과정':
        return _section(
          '내 교육과정 학점 현황',
          '학교 화면의 학점 항목과 적용 교육과정 기준을 나란히 보여줍니다. 이 표 자체에는 판정 행을 넣지 않습니다.',
          curriculumHeaders,
          curriculumRows,
          firstColumnWidth: 92,
          compact: true,
        );
      default:
        return _section(
          '규칙 엔진 판정 · 학과 졸업인증',
          '창의영역 택 1과 전공영역 택 1을 함께 충족해야 합니다. 택 1 안에서는 한 경로만 채우면 됩니다.',
          departmentHeaders,
          departmentRows,
          firstColumnWidth: 130,
        );
    }
  }

  Widget _personalContent() {
    final unmet = _personalRules
        .where((rule) => rule.currentValue < rule.requiredValue)
        .length;
    final rows = [
      for (final rule in _personalRules)
        [
          rule.name,
          '${rule.currentValue}',
          rule.currentValue >= rule.requiredValue ? '충족' : '미충족',
          '최소 ${rule.requiredValue}',
        ],
    ];
    return Column(
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.person_outline, color: Color(0xff315a77)),
                  SizedBox(width: 8),
                  Text(
                    '내 학교·학과 기준',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$_personalSchool · $_personalDepartment · $_personalAdmissionYear학번',
                style: const TextStyle(color: Color(0xff607386)),
              ),
              const SizedBox(height: 10),
              const Text(
                '지원되지 않는 학교·학과용 개인 규칙 세트입니다. 입력한 기준과 내 기록으로 계산하지만, 학교의 공식 졸업 판정은 아닙니다.',
                style: TextStyle(fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showPersonalAcademicSetup(addRule: true),
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('개인 기준 항목 추가'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _isPersonalMode = false),
                    child: const Text('기본 학교 기준 보기'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _section(
          '개인 기준 계산',
          unmet == 0
              ? '입력한 개인 기준을 모두 충족했습니다. 학교 공식 시스템에서 최종 결과를 확인해 주세요.'
              : '입력한 개인 기준 중 $unmet개 항목을 더 확인하거나 채워야 합니다. 학교 공식 판정과는 별개입니다.',
          const ['개인 기준', '현재 값', '계산', '내가 입력한 기준'],
          rows,
          firstColumnWidth: 220,
        ),
      ],
    );
  }

  Widget _section(
    String title,
    String description,
    List<String> headers,
    List<List<String>> rows, {
    required double firstColumnWidth,
    bool compact = false,
  }) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          description,
          style: const TextStyle(fontSize: 12, color: Color(0xff607386)),
        ),
        const SizedBox(height: 14),
        _auditTable(
          headers,
          rows,
          firstColumnWidth: firstColumnWidth,
          compact: compact,
        ),
      ],
    ),
  );

  Future<void> _showPersonalAcademicSetup({bool addRule = false}) async {
    final school = TextEditingController(text: _personalSchool);
    final department = TextEditingController(text: _personalDepartment);
    final admissionYear = TextEditingController(text: _personalAdmissionYear);
    final ruleName = TextEditingController(text: addRule ? '' : '최소 총 취득학점');
    final requiredValue = TextEditingController(text: addRule ? '' : '120');
    final currentValue = TextEditingController(text: addRule ? '' : '88');
    var showErrors = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(addRule ? '개인 기준 항목 추가' : '내 학교·학과 기준 설정'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '학교가 지원되지 않아도 내 기준으로 학업 현황을 계산할 수 있습니다. 이 결과는 개인용이며 학교 공식 졸업 판정을 대체하지 않습니다.',
                    style: TextStyle(fontSize: 13, height: 1.45),
                  ),
                  if (!addRule) ...[
                    const SizedBox(height: 18),
                    _field(school, '학교명', '예: OO대학교', showErrors),
                    const SizedBox(height: 12),
                    _field(department, '학과', '예: 컴퓨터공학과', showErrors),
                    const SizedBox(height: 12),
                    _field(
                      admissionYear,
                      '입학연도',
                      '예: 2024',
                      showErrors,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    '개인 규칙 항목',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _field(ruleName, '기준 이름', '예: 전공 필수 학점', showErrors),
                  const SizedBox(height: 12),
                  _field(
                    requiredValue,
                    '필요한 값',
                    '예: 120',
                    showErrors,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    currentValue,
                    '현재 값',
                    '예: 88',
                    showErrors,
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final invalid =
                    (!addRule &&
                        (school.text.trim().isEmpty ||
                            department.text.trim().isEmpty ||
                            admissionYear.text.trim().isEmpty)) ||
                    ruleName.text.trim().isEmpty ||
                    int.tryParse(requiredValue.text.trim()) == null ||
                    int.tryParse(currentValue.text.trim()) == null;
                if (invalid) {
                  setDialogState(() => showErrors = true);
                  return;
                }
                setState(() {
                  final rule = _PersonalRule(
                    ruleName.text.trim(),
                    int.parse(requiredValue.text.trim()),
                    int.parse(currentValue.text.trim()),
                  );
                  if (addRule) {
                    _personalRules.add(rule);
                  } else {
                    _personalSchool = school.text.trim();
                    _personalDepartment = department.text.trim();
                    _personalAdmissionYear = admissionYear.text.trim();
                    _personalRules
                      ..clear()
                      ..add(rule);
                    _isPersonalMode = true;
                  }
                });
                Navigator.pop(dialogContext);
              },
              child: Text(addRule ? '항목 추가' : '개인 기준으로 저장'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(kThemeAnimationDuration);
    school.dispose();
    department.dispose();
    admissionYear.dispose();
    ruleName.dispose();
    requiredValue.dispose();
    currentValue.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint,
    bool showErrors, {
    TextInputType? keyboardType,
  }) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      errorText: !showErrors
          ? null
          : controller.text.trim().isEmpty
          ? '$label을 입력해 주세요.'
          : keyboardType == TextInputType.number &&
                int.tryParse(controller.text.trim()) == null
          ? '$label에는 숫자를 입력해 주세요.'
          : null,
    ),
  );

  Widget _auditTable(
    List<String> headers,
    List<List<String>> rows, {
    required double firstColumnWidth,
    bool compact = false,
  }) {
    final border = TableBorder(
      horizontalInside: const BorderSide(color: Color(0xffd8e1e7)),
      verticalInside: const BorderSide(color: Color(0xffe6ecef)),
      top: const BorderSide(color: Color(0xffd8e1e7)),
      bottom: const BorderSide(color: Color(0xffd8e1e7)),
    );
    if (!compact) {
      return Table(
        border: border,
        columnWidths: {
          0: const FlexColumnWidth(1.9),
          for (var i = 1; i < headers.length; i++) i: const FlexColumnWidth(),
        },
        children: _tableRows(headers, rows),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = math.max(
          58.0,
          (constraints.maxWidth - firstColumnWidth) / (headers.length - 1),
        );
        final tableWidth = firstColumnWidth + cellWidth * (headers.length - 1);
        return Scrollbar(
          controller: _curriculumScrollController,
          thumbVisibility: tableWidth > constraints.maxWidth,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: _curriculumScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Table(
                border: border,
                columnWidths: {
                  0: FixedColumnWidth(firstColumnWidth),
                  for (var i = 1; i < headers.length; i++)
                    i: FixedColumnWidth(cellWidth),
                },
                children: _tableRows(headers, rows, compact: true),
              ),
            ),
          ),
        );
      },
    );
  }

  List<TableRow> _tableRows(
    List<String> headers,
    List<List<String>> rows, {
    bool compact = false,
  }) => [
    TableRow(
      decoration: const BoxDecoration(color: Color(0xffe9f0f4)),
      children: [
        for (final header in headers)
          _tableCell(header, header: true, compact: compact),
      ],
    ),
    for (final row in rows)
      TableRow(
        children: [
          for (var i = 0; i < row.length; i++)
            _tableCell(
              row[i],
              compact: compact,
              status: !compact && (headers[i] == '판정' || headers[i] == '상태')
                  ? row[i]
                  : null,
            ),
        ],
      ),
  ];

  Widget _tableCell(
    String value, {
    bool header = false,
    bool compact = false,
    String? status,
  }) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 6 : 10,
      vertical: compact ? 9 : 12,
    ),
    child: status == null
        ? Text(
            value,
            textAlign: compact ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              color: header ? const Color(0xff28465f) : const Color(0xff314b60),
              fontWeight: header ? FontWeight.w800 : FontWeight.w500,
            ),
          )
        : Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(status: status),
          ),
  );
}

class _PersonalRule {
  const _PersonalRule(this.name, this.requiredValue, this.currentValue);
  final String name;
  final int requiredValue;
  final int currentValue;
}
