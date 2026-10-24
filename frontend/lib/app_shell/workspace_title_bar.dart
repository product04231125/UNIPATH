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
    this.onAccountSecurity,
    this.onApplications,
    this.applicationLabel = '학교 관리 권한·신청 이력',
    this.sidebarVisible = true,
    this.title = 'UniversityPath',
  });
  final VoidCallback? onBack, onForward, onToggleSidebar, onAccountSecurity;
  final VoidCallback? onApplications;
  final String applicationLabel;
  final bool sidebarVisible;
  final String title;

  bool get native => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  Future<void> _maximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: titleBarColor(Theme.of(context).colorScheme),
    child: SafeArea(
      bottom: false,
      child: Row(
        children: [
          if (onToggleSidebar != null) ...[
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
              onPanStart: native ? (_) => windowManager.startDragging() : null,
              onDoubleTap: native ? _maximize : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          if (onApplications != null)
            IconButton(
              tooltip: applicationLabel,
              onPressed: onApplications,
              icon: const Icon(Icons.school_outlined),
            ),
          if (onAccountSecurity != null)
            IconButton(
              tooltip: '계정 보안',
              onPressed: onAccountSecurity,
              icon: const Icon(Icons.manage_accounts_outlined),
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
