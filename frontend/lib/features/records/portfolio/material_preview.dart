import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/app_tones.dart';
import '../../auth/auth_api.dart';
import 'material_repository.dart';

/// Shows a saved 내 자료 PDF in the app, page by page (the server renders each page).
Future<void> showMaterialPreview(
  BuildContext context, {
  required MaterialRepository repository,
  required PersonalMaterial material,
  VoidCallback? onExport,
}) => showDialog<void>(
  context: context,
  builder: (context) => MaterialPreviewDialog(
    repository: repository,
    material: material,
    onExport: onExport,
  ),
);

class MaterialPreviewDialog extends StatefulWidget {
  const MaterialPreviewDialog({
    super.key,
    required this.repository,
    required this.material,
    this.onExport,
  });
  final MaterialRepository repository;
  final PersonalMaterial material;
  final VoidCallback? onExport;

  @override
  State<MaterialPreviewDialog> createState() => _MaterialPreviewDialogState();
}

class _MaterialPreviewDialogState extends State<MaterialPreviewDialog> {
  static const _zooms = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// Page images kept while the dialog is open; far pages are dropped and read again.
  static const _keptImages = 40;

  late Future<MaterialPages> _pages;
  final _images = <int, Future<Uint8List>>{};
  var _zoom = 1.0;

  @override
  void initState() {
    super.initState();
    _pages = widget.repository.pages(widget.material);
  }

  Future<Uint8List> _image(int number) {
    final found = _images.remove(number);
    final image = found ?? widget.repository.pageImage(widget.material, number);
    _images[number] = image;
    while (_images.length > _keptImages) {
      _images.remove(_images.keys.first);
    }
    return image;
  }

  void _setZoom(double value) => setState(() => _zoom = value);

  String _message(Object? error) =>
      error is AuthFailure ? error.message : 'PDF를 불러오지 못했습니다. 다시 시도하세요.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final screen = MediaQuery.sizeOf(context);
    final index = _zooms.indexOf(_zoom);
    return Dialog(
      key: const ValueKey('material-preview'),
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(screen.width - 48, 1180),
        height: screen.height - 48,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.picture_as_pdf_outlined,
                    color: AppTone.danger.color(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.material.title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        FutureBuilder<MaterialPages>(
                          future: _pages,
                          builder: (context, snapshot) => Text(
                            [
                              widget.material.fileName,
                              if (snapshot.data case final pages?) ...[
                                '${pages.count}쪽',
                                if (pages.sizes.length < pages.count)
                                  '앞 ${pages.sizes.length}쪽까지 표시',
                              ],
                            ].join(' · '),
                            key: const ValueKey('material-preview-summary'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '축소',
                    onPressed: index > 0
                        ? () => _setZoom(_zooms[index - 1])
                        : null,
                    icon: const Icon(Icons.zoom_out),
                  ),
                  TextButton(
                    key: const ValueKey('material-preview-zoom'),
                    onPressed: _zoom == 1 ? null : () => _setZoom(1),
                    child: Text('${(_zoom * 100).round()}%'),
                  ),
                  IconButton(
                    tooltip: '확대',
                    onPressed: index < _zooms.length - 1
                        ? () => _setZoom(_zooms[index + 1])
                        : null,
                    icon: const Icon(Icons.zoom_in),
                  ),
                  if (widget.onExport != null) ...[
                    const SizedBox(width: 4),
                    TextButton.icon(
                      key: const ValueKey('material-preview-export'),
                      onPressed: widget.onExport,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('PDF 내보내기'),
                    ),
                  ],
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: FutureBuilder<MaterialPages>(
                  future: _pages,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _failure(
                        context,
                        _message(snapshot.error),
                        () => setState(
                          () =>
                              _pages = widget.repository.pages(widget.material),
                        ),
                      );
                    }
                    final pages = snapshot.data;
                    if (pages == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _pageList(context, pages);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageList(BuildContext context, MaterialPages pages) => LayoutBuilder(
    builder: (context, constraints) {
      // 100% fits the page to a comfortable reading width; zoom scales from there.
      final fit = math.min(constraints.maxWidth - 48, 960.0);
      final width = fit * _zoom;
      final contentWidth = math.max(constraints.maxWidth, width + 48);
      final list = ListView.builder(
        key: const ValueKey('material-preview-pages'),
        padding: const EdgeInsets.symmetric(vertical: 20),
        itemCount: pages.sizes.length,
        itemBuilder: (context, i) {
          final size = pages.sizes[i];
          return Column(
            children: [
              SizedBox(
                width: width,
                height: width * size.height / size.width,
                child: _page(context, i + 1),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 20),
                child: Text(
                  '${i + 1} / ${pages.count}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      );
      if (contentWidth <= constraints.maxWidth) return Scrollbar(child: list);
      return Scrollbar(
        notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            child: Scrollbar(child: list),
          ),
        ),
      );
    },
  );

  Widget _page(BuildContext context, int number) => DecoratedBox(
    key: ValueKey('material-preview-page-$number'),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: FutureBuilder<Uint8List>(
      future: _image(number),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _failure(
            context,
            '$number쪽을 불러오지 못했습니다.',
            () => setState(() => _images.remove(number)),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          semanticLabel: '${widget.material.title} $number쪽',
        );
      },
    ),
  );

  Widget _failure(BuildContext context, String message, VoidCallback retry) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
}
