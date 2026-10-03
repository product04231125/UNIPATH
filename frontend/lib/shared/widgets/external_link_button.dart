import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../external_links.dart';

class ExternalLinkButton extends StatelessWidget {
  const ExternalLinkButton({
    super.key,
    required this.url,
    required this.label,
    this.opener = openBrowserLink,
    this.description,
  });
  final String url;
  final String label;
  final BrowserLinkOpener opener;
  final String? description;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.open_in_new, size: 18),
    label: Text('$label · 외부 열기'),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => _ExternalLinkDialog(
        url: url,
        opener: opener,
        description: description,
      ),
    ),
  );
}

class _ExternalLinkDialog extends StatefulWidget {
  const _ExternalLinkDialog({
    required this.url,
    required this.opener,
    this.description,
  });
  final String url;
  final BrowserLinkOpener opener;
  final String? description;
  @override
  State<_ExternalLinkDialog> createState() => _ExternalLinkDialogState();
}

class _ExternalLinkDialogState extends State<_ExternalLinkDialog> {
  bool _opening = false;
  String? _message;

  Future<void> _open(Uri uri) async {
    setState(() {
      _opening = true;
      _message = null;
    });
    try {
      // Invoke directly from this button click, before any other async work.
      // Browsers require a user gesture for opening a new tab.
      final opened = await widget.opener(uri);
      if (!mounted) return;
      if (opened) {
        Navigator.pop(context);
      } else {
        setState(
          () => _message = '열지 못했습니다. 새 탭 차단이나 기본 브라우저 설정을 확인하거나 링크를 복사하세요.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = '열지 못했습니다. 다시 시도하거나 링크를 복사하세요.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _copy(Uri uri) async {
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (mounted) setState(() => _message = '링크를 복사했습니다.');
    } catch (_) {
      if (mounted) {
        setState(() => _message = '복사하지 못했습니다. 아래 링크를 직접 선택해 복사하세요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = browserLink(widget.url);
    return AlertDialog(
      title: const Text('외부 사이트 열기'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('새 탭 또는 기본 브라우저에서 엽니다. 외부 사이트의 공개 범위와 내용을 직접 확인하세요.'),
              if (widget.description != null) ...[
                const SizedBox(height: 12),
                Text(widget.description!),
              ],
              const SizedBox(height: 12),
              if (uri != null)
                SelectableText(uri.toString())
              else
                const Text('열 수 없는 링크입니다. 로그인 정보 없는 http/https 주소로 수정하세요.'),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, semanticsLabel: _message),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _opening ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: uri == null || _opening ? null : () => _copy(uri),
          child: const Text('링크 복사'),
        ),
        FilledButton(
          onPressed: uri == null || _opening ? null : () => _open(uri),
          child: Text(_opening ? '여는 중…' : '외부 사이트 열기'),
        ),
      ],
    );
  }
}
