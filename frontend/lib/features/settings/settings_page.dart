import 'package:flutter/material.dart';

/// Placeholder for settings that have an agreed interaction and API contract.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('설정', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          const Text(
            '개인화, AI와 데이터, 접근성, 계정 관련 설정은 기능과 계약이 확정된 뒤 제공됩니다.',
            style: TextStyle(color: Color(0xff607386), height: 1.5),
          ),
        ],
      ),
    ),
  );
}
