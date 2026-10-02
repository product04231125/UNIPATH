import 'package:flutter/material.dart';
import 'package:university_path_frontend/shared/app_typography.dart';

import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/surface_card.dart';
import 'fixtures/record_mock_entry.dart';

/// Temporary shared presentation only. Each feature entry owns its own
/// configuration, fixture and mounted local input state.
class RecordMenuPage extends StatefulWidget {
  const RecordMenuPage({
    super.key,
    required this.kicker,
    required this.title,
    required this.description,
    required this.notice,
    required this.listTitle,
    required this.fixture,
    required this.guideTitle,
    required this.guides,
    required this.addLabel,
    required this.detailLabel,
    required this.showMockData,
  });

  final String kicker;
  final String title;
  final String description;
  final String notice;
  final String listTitle;
  final List<RecordMockEntry> fixture;
  final String guideTitle;
  final List<String> guides;
  final String addLabel;
  final String detailLabel;
  final bool showMockData;

  @override
  State<RecordMenuPage> createState() => _RecordMenuPageState();
}

class _RecordMenuPageState extends State<RecordMenuPage> {
  final _manualEntries = <RecordMockEntry>[];

  Future<void> _showForm() async {
    final title = TextEditingController();
    final detail = TextEditingController();
    var showErrors = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(widget.addLabel),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.title} 메뉴에 내 기록을 추가합니다. 학교 공식 기준이나 졸업 판정은 바꾸지 않습니다.',
                    style: const TextStyle(
                      fontSize: AppTypography.body,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: title,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '${widget.title} 이름',
                      errorText: showErrors && title.text.trim().isEmpty
                          ? '이름을 입력해 주세요.'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: detail,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: widget.detailLabel,
                      errorText: showErrors && detail.text.trim().isEmpty
                          ? '${widget.detailLabel} 정보를 입력해 주세요.'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
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
                if (title.text.trim().isEmpty || detail.text.trim().isEmpty) {
                  setDialogState(() => showErrors = true);
                  return;
                }
                setState(
                  () => _manualEntries.add(
                    RecordMockEntry(
                      title: title.text.trim(),
                      detail: detail.text.trim(),
                      status: '직접 입력',
                    ),
                  ),
                );
                Navigator.pop(dialogContext);
              },
              child: const Text('내 기록에 저장'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(kThemeAnimationDuration);
    title.dispose();
    detail.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = [
      if (widget.showMockData) ...widget.fixture,
      ..._manualEntries,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.kicker,
          style: const TextStyle(
            fontSize: AppTypography.caption,
            letterSpacing: .5,
            fontWeight: FontWeight.w800,
            color: Color(0xff738ba0),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.title,
          style: const TextStyle(
            fontSize: AppTypography.page,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          widget.description,
          style: const TextStyle(color: Color(0xff607386)),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xfffff7e5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xffefdba7)),
          ),
          child: Text(
            widget.notice,
            style: const TextStyle(
              fontSize: AppTypography.caption,
              color: Color(0xff795a22),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final records = SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.listTitle,
                      style: const TextStyle(
                        fontSize: AppTypography.section,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '학교에서 확인한 정보가 없으면 내 기록을 직접 추가할 수 있습니다.',
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: Color(0xff607386),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _showForm,
                      icon: const Icon(Icons.add),
                      label: Text(widget.addLabel),
                    ),
                    const SizedBox(height: 10),
                    for (final entry in entries) _entry(entry),
                  ],
                ),
              );
              final guide = SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.guideTitle,
                      style: const TextStyle(
                        fontSize: AppTypography.section,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final guide in widget.guides)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: Text(
                          '• $guide',
                          style: const TextStyle(
                            fontSize: AppTypography.body,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              );
              return SingleChildScrollView(
                child: constraints.maxWidth >= 760
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: records),
                          const SizedBox(width: 14),
                          Expanded(flex: 4, child: guide),
                        ],
                      )
                    : Column(
                        children: [records, const SizedBox(height: 14), guide],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _entry(RecordMockEntry entry) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xffe4ebef))),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.description_outlined,
          size: 19,
          color: Color(0xff315a77),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: const TextStyle(
                  fontSize: AppTypography.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.detail,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: Color(0xff607386),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        StatusBadge(status: entry.status == '기록됨' ? '충족' : entry.status),
      ],
    ),
  );
}
