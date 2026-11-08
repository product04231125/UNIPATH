import 'package:flutter/material.dart';

import '../api/academic_guidance_models.dart';

/// Presentation-only sections. Only received buttons can navigate to the API.
class GuidanceMenu extends StatefulWidget {
  const GuidanceMenu({
    super.key,
    required this.nodeId,
    required this.options,
    required this.loading,
    required this.onSelect,
  });
  final String nodeId;
  final List<GuidanceButton> options;
  final bool loading;
  final ValueChanged<String> onSelect;

  @override
  State<GuidanceMenu> createState() => _GuidanceMenuState();
}

class _GuidanceMenuState extends State<GuidanceMenu> {
  String? section;

  @override
  void didUpdateWidget(covariant GuidanceMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) section = null;
  }

  String group(GuidanceButton button) {
    if (widget.nodeId == 'home') {
      return switch (button.nodeId) {
        'graduation' ||
        'calendar' ||
        'registration' ||
        'major' ||
        'departments' => '수업·학사',
        'scholarship' || 'tuition' => '장학·등록',
        'notices' || 'dormitory' => '학교생활',
        'career' => '진로·취업',
        _ => '기타 안내',
      };
    }
    if (widget.nodeId == 'graduation') {
      return button.nodeId == 'summary' ? '내 졸업요건' : '졸업 기준 안내';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<GuidanceButton>>{};
    for (final button in widget.options) {
      groups.putIfAbsent(group(button), () => []).add(button);
    }
    // A single section adds no useful navigation step.
    final grouped = groups.length > 1;
    final active = groups.containsKey(section) ? section : null;
    final buttons = grouped && active != null
        ? groups[active]!
        : widget.options;
    Widget row(String label, VoidCallback action) => InkWell(
      onTap: widget.loading ? null : action,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
    final rows = grouped && active == null
        ? [
            for (final name in groups.keys)
              row(name, () => setState(() => section = name)),
          ]
        : [
            for (final button in buttons)
              row(
                '${button.label}${button.availability == 'content_pending' ? ' · 준비 중' : ''}',
                () => widget.onSelect(button.nodeId),
              ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (grouped && active != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(active, style: Theme.of(context).textTheme.titleSmall),
          ),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                rows[i],
              ],
            ],
          ),
        ),
        if (grouped && active != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.loading
                  ? null
                  : () => setState(() => section = null),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('분야 다시 선택'),
            ),
          ),
      ],
    );
  }
}
