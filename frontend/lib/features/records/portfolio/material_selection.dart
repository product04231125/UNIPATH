import 'package:flutter/material.dart';

import '../../assistant/ai_record_catalog.dart';

/// Lets the student pick 내 자료 (kept on this device) to send with one analysis request.
/// Nothing is sent from here; the caller converts the selected IDs when the request starts.
class MaterialSelection extends StatefulWidget {
  const MaterialSelection({
    super.key,
    required this.load,
    required this.selected,
    required this.onChanged,
    required this.keyPrefix,
    this.enabled = true,
    this.title = '함께 비교할 내 자료 (선택)',
  });
  final Future<List<AssistantMaterial>> Function() load;
  final Set<String> selected;
  final void Function(String id, bool selected) onChanged;
  final String keyPrefix;
  final bool enabled;
  final String title;

  @override
  State<MaterialSelection> createState() => _MaterialSelectionState();
}

class _MaterialSelectionState extends State<MaterialSelection> {
  List<AssistantMaterial> _materials = const [];
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final materials = await widget.load();
      if (!mounted || request != _request) return;
      setState(() {
        _materials = materials;
        _loading = false;
      });
      // A material deleted on this device can no longer be sent.
      for (final id in widget.selected.toList()) {
        if (!materials.any((m) => m.id == id)) widget.onChanged(id, false);
      }
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = '내 자료를 읽지 못했습니다. 다시 읽어 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.title),
      const Text(
        '고른 자료의 설명·PDF를 서버에서 읽고, 추출한 내용을 Google 외부 AI로 전송합니다. '
        '스캔 PDF는 OCR 처리하며 원본 대조가 필요합니다. 설명과 PDF는 합계 5개·8MiB까지 보낼 수 있습니다.',
      ),
      TextButton(
        key: ValueKey('${widget.keyPrefix}-materials-refresh'),
        onPressed: _loading ? null : _refresh,
        child: const Text('내 자료 다시 읽기'),
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (!_loading && _error == null && _materials.isEmpty)
        const Text('이 기기에 등록한 자료가 없습니다. 자료 메뉴에서 등록해 주세요.'),
      for (final material in _materials)
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            key: ValueKey('${widget.keyPrefix}-material-${material.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(material.title),
            subtitle: Text(material.type),
            value: widget.selected.contains(material.id),
            onChanged: widget.enabled
                ? (value) => widget.onChanged(material.id, value ?? false)
                : null,
          ),
        ),
    ],
  );
}
