import '../../chat_window.dart' as native;

import 'package:flutter/foundation.dart';

/// Native window boundary; tests supply a host without platform channels.
class AssistantWindowHost {
  const AssistantWindowHost();

  bool get supportsDetached =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      native.supportsDetachedChatWindow;
  Future<bool> isMaximized() =>
      supportsDetached ? native.isMainWindowMaximized() : Future.value(false);
  Stream<bool> get maximizeChanges => supportsDetached
      ? native.mainWindowMaximizeChanges()
      : const Stream.empty();
  Stream<bool> get detachedChanges => supportsDetached
      ? native.detachedChatWindowChanges()
      : const Stream.empty();
  Future<bool> hasDetached() => native.hasDetachedChatWindow();
  Future<void> openDetached(double width) =>
      native.openDetachedChatWindow(width: width);
}
