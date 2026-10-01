import 'package:flutter/material.dart';

/// Graduation page frame. Its current content callbacks keep the existing mock
/// behavior intact while the detailed rule sections are moved incrementally.
class GraduationPage extends StatelessWidget {
  const GraduationPage({
    super.key,
    required this.profileLabel,
    required this.isPersonalMode,
    required this.onConfigurePersonalRules,
    required this.personalContent,
    required this.officialContent,
  });

  final String profileLabel;
  final bool isPersonalMode;
  final VoidCallback onConfigurePersonalRules;
  final Widget personalContent;
  final Widget officialContent;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        profileLabel,
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
            onPressed: onConfigurePersonalRules,
            icon: const Icon(Icons.tune, size: 18),
            label: Text(isPersonalMode ? '개인 기준 수정' : '내 학교·학과 기준 설정'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Expanded(
        child: isPersonalMode
            ? SingleChildScrollView(child: personalContent)
            : officialContent,
      ),
    ],
  );
}
