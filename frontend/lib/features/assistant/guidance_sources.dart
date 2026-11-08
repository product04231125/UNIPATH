import 'package:flutter/material.dart';

import '../api/academic_guidance_models.dart';
import '../../shared/widgets/external_link_button.dart';
import 'assistant_conversation.dart';
import 'guidance_asset_button.dart';

List<GuidanceSource> uniqueGuidanceSources(Iterable<GuidanceSource> sources) {
  final seen = <(String?, String?, String?, int?, String?), GuidanceSource>{};
  for (final source in sources) {
    final key = (
      source.sourceUrl,
      source.assetId,
      source.documentId,
      source.page,
      source.sourceUrl == null && source.assetId == null ? source.title : null,
    );
    seen.putIfAbsent(key, () => source);
  }
  return seen.values.toList(growable: false);
}

class GuidanceSources extends StatelessWidget {
  const GuidanceSources({
    super.key,
    required this.sources,
    required this.conversation,
  });
  final Iterable<GuidanceSource> sources;
  final AssistantConversation conversation;

  @override
  Widget build(BuildContext context) {
    final unique = uniqueGuidanceSources(sources);
    if (unique.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final source in unique) ...[
            if (unique.length > 1 && source.title != null)
              Text(
                source.title!,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            if (source.page != null) Text('원문 ${source.page}페이지'),
            if (source.assetId != null)
              GuidanceAssetButton(
                conversation: conversation,
                id: source.assetId!,
              ),
            if (source.sourceUrl != null)
              ExternalLinkButton(
                url: source.sourceUrl!,
                label: unique.length == 1 ? '원문 보기' : source.title ?? '원문 보기',
              ),
          ],
        ],
      ),
    );
  }
}
