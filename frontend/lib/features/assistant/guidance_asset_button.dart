import 'package:flutter/material.dart';

import '../auth/guidance_asset_gateway.dart';
import 'assistant_conversation.dart';
import 'guidance_asset_open.dart';

class GuidanceAssetButton extends StatefulWidget {
  const GuidanceAssetButton({
    super.key,
    required this.conversation,
    required this.id,
    this.image = false,
  });
  final AssistantConversation conversation;
  final String id;
  final bool image;
  @override
  State<GuidanceAssetButton> createState() => _AssetState();
}

class _AssetState extends State<GuidanceAssetButton> {
  GuidanceAsset? _asset;
  bool _loading = false;
  String? _error;
  int _generation = 0;
  @override
  void didUpdateWidget(covariant GuidanceAssetButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.conversation != widget.conversation) {
      _generation++;
      _asset = null;
      _loading = false;
      _error = null;
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.conversation.loadGuidanceAsset(widget.id);
      if (mounted && generation == _generation) setState(() => _asset = value);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '원문을 읽지 못했습니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_error != null) Text(_error!),
      if (_asset == null)
        TextButton(
          onPressed: _loading ? null : _load,
          child: Text(
            _loading
                ? '원문 준비 중…'
                : widget.image
                ? '원본 이미지 읽기'
                : '원문 준비',
          ),
        ),
      if (_asset?.contentType == 'image/jpeg')
        Image.memory(
          _asset!.bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Text('이미지를 표시하지 못했습니다. 다시 읽어 주세요.'),
        ),
      if (_asset?.contentType == 'application/pdf')
        TextButton(
          onPressed: () async {
            try {
              final opened = await openGuidancePdf(_asset!, widget.id);
              if (!opened && mounted) {
                setState(
                  () => _error =
                      '원문 창이 열리지 않았다면 팝업 또는 기본 PDF 앱 설정을 확인하고 다시 시도해 주세요.',
                );
              }
            } catch (_) {
              if (mounted) setState(() => _error = '원문을 열지 못했습니다. 다시 시도해 주세요.');
            }
          },
          child: const Text('원문 PDF 열기'),
        ),
    ],
  );
}
