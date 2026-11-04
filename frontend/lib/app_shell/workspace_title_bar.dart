import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../shared/app_style.dart';

class WorkspaceTitleBar extends StatelessWidget {
  const WorkspaceTitleBar({
    super.key,
    this.onBack,
    this.onForward,
    this.onToggleSidebar,
    this.sidebarVisible = true,
    this.statusLabel,

    /// Phone portrait: hide back/forward/sidebar/status; keep window controls only.
    this.phoneChrome = false,
  });
  final VoidCallback? onBack, onForward, onToggleSidebar;
  final bool sidebarVisible;

  /// Account role / current status shown trailing (before OS window controls).
  final String? statusLabel;
  final bool phoneChrome;

  bool get native => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  Future<void> _maximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (phoneChrome && !native) return const SizedBox.shrink();
    final status = statusLabel?.trim();
    final showStatus = !phoneChrome && status != null && status.isNotEmpty;
    return Material(
      color: titleBarColor(Theme.of(context).colorScheme),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (!phoneChrome && onToggleSidebar != null) ...[
              IconButton(
                tooltip: '뒤로 가기',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              IconButton(
                tooltip: '앞으로 가기',
                onPressed: onForward,
                icon: const Icon(Icons.arrow_forward),
              ),
              IconButton(
                tooltip: sidebarVisible ? '사이드바 축소' : '사이드바 펼치기',
                onPressed: onToggleSidebar,
                icon: Icon(sidebarVisible ? Icons.menu_open : Icons.menu),
              ),
            ],
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: native
                    ? (_) => windowManager.startDragging()
                    : null,
                onDoubleTap: native ? _maximize : null,
                child: const SizedBox(height: 48),
              ),
            ),
            if (showStatus)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (native) ...[
              IconButton(
                tooltip: '최소화',
                onPressed: windowManager.minimize,
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                tooltip: '최대화 또는 복원',
                onPressed: _maximize,
                icon: const Icon(Icons.crop_square),
              ),
              IconButton(
                tooltip: '창 닫기',
                onPressed: windowManager.close,
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
