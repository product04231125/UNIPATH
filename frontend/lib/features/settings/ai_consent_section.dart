import 'package:flutter/material.dart';

import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/work_layout.dart';
import 'ai_consent_preferences.dart';

/// Returns a one-request permission, or persists an explicitly selected choice.
Future<bool> requestAiConsent(
  BuildContext context,
  AiConsentPreferences preferences,
  AiConsentFeature feature, {
  bool review = false,
  bool persistent = false,
}) async {
  await preferences.load();
  if (!context.mounted || preferences.loadFailed || preferences.saving) {
    return false;
  }
  if (!review && preferences.allows(feature)) return true;
  final remember = await chooseAiConsent(
    context,
    feature,
    persistent: persistent,
  );
  if (remember == null || !context.mounted) return false;
  return remember ? preferences.setAllowed(feature, true) : true;
}

/// null = cancel, false = this request, true = remember on this device.
Future<bool?> chooseAiConsent(
  BuildContext context,
  AiConsentFeature feature, {
  bool persistent = false,
}) async {
  var remember = persistent;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('${feature.label} 외부 전송'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${feature.transferredData}을 Google의 Gemini(Vertex AI)로 보내 '
                '답변 또는 비교 설명을 생성합니다.',
              ),
              const SizedBox(height: 12),
              const Text(
                '서버는 식별 정보 제거 처리를 하지만, 자유롭게 작성한 내용에 '
                '민감한 정보가 없는지 전송 전에 확인해 주세요.',
              ),
              if (!persistent)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('이 기기에서 이후 요청에도 적용'),
                  value: remember,
                  onChanged: (v) => setState(() => remember = v == true),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(remember ? '허용하고 저장' : '이번만 허용'),
          ),
        ],
      ),
    ),
  );
  return accepted == true ? remember : null;
}

class AiConsentSection extends StatelessWidget {
  const AiConsentSection({super.key, required this.preferences});
  final AiConsentPreferences preferences;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: preferences,
    builder: (context, _) => SurfaceCard(
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FeatureLine.section(
              text: 'AI와 데이터',
              padTop: false,
              padBottom: false,
            ),
            const SizedBox(height: 8),
            const NoteLine(
              icon: Icons.cloud_upload_outlined,
              text: '허용은 이 계정·기기에 저장되고, 해제는 다음 요청부터 적용됩니다.',
              detail:
                  '외부 AI 전송 허용을 이 계정·현재 기기에 저장합니다. '
                  '해제는 다음 요청부터 적용되며 이미 전송한 내용을 회수하지 않습니다.',
            ),
            const SizedBox(height: 4),
            const NoteLine(
              icon: Icons.school_outlined,
              text: '학교 안내는 버튼으로 조회하며 외부 AI에 전송하지 않습니다.',
            ),
            const SizedBox(height: 8),
            if (preferences.loading) const LinearProgressIndicator(),
            if (preferences.loadFailed)
              TextButton(
                onPressed: preferences.retry,
                child: const Text('전송 설정 다시 읽기'),
              ),
            for (final feature in AiConsentFeature.values.where(
              (f) => f != AiConsentFeature.schoolQuestion,
            ))
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(feature.label),
                subtitle: Text(
                  preferences.allows(feature) ? 'Google 전송 허용 중' : '전송 전 확인',
                ),
                value: preferences.allows(feature),
                onChanged:
                    preferences.loading ||
                        preferences.loadFailed ||
                        preferences.saving
                    ? null
                    : (allowed) async {
                        if (!allowed) {
                          await preferences.setAllowed(feature, false);
                        } else {
                          await requestAiConsent(
                            context,
                            preferences,
                            feature,
                            review: true,
                            persistent: true,
                          );
                        }
                      },
              ),
            if (preferences.error != null)
              Text(
                preferences.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
  );
}
