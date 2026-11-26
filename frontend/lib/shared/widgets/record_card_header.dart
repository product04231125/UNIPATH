import 'package:flutter/material.dart';

import '../app_typography.dart';

class RecordCardHeader extends StatelessWidget {
  const RecordCardHeader({
    super.key,
    required this.title,
    this.reload,
    required this.actions,
  });
  final String title;
  final Widget? reload;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final heading = Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge
              ?.merge(AppTypography.sectionStyle),
        ),
        ?reload,
      ],
    );
    final controls = Wrap(spacing: 8, runSpacing: 8, children: actions);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 650 ||
            MediaQuery.textScalerOf(context).scale(14) > 18) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              if (actions.isNotEmpty) ...[const SizedBox(height: 12), controls],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            controls,
          ],
        );
      },
    );
  }
}
