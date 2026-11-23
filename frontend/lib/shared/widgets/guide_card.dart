import 'package:flutter/material.dart';

import '../app_tones.dart';
import 'surface_card.dart';
import 'tone_chip.dart';

/// Collapsed tips and outside links under a list, so they never compete
/// with the list itself.
class GuideCard extends StatefulWidget {
  const GuideCard({
    super.key,
    required this.title,
    this.lines = const [],
    this.links = const [],
  });

  final String title;
  final List<String> lines;
  final List<Widget> links;

  @override
  State<GuideCard> createState() => _GuideCardState();
}

class _GuideCardState extends State<GuideCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const IconBadge(
                      icon: Icons.lightbulb_outline,
                      tone: AppTone.warning,
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (widget.links.isNotEmpty) ...[
                      Flexible(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: widget.links,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (widget.lines.isNotEmpty)
                      Icon(_open ? Icons.expand_less : Icons.expand_more),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            for (final line in widget.lines)
              Padding(
                padding: const EdgeInsets.only(left: 42, bottom: 6),
                child: Text('• $line'),
              ),
        ],
      ),
    );
  }
}
