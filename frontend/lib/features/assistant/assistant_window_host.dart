import '../../chat_window.dart' as native;

/// Native window boundary; tests supply a host without platform channels.
class AssistantWindowHost {
  const AssistantWindowHost();

  bool get supportsDetached => native.supportsDetachedChatWindow;
  Future<bool> isMaximized() => native.isMainWindowMaximized();
  Stream<bool> get maximizeChanges => native.mainWindowMaximizeChanges();
  Stream<bool> get detachedChanges => native.detachedChatWindowChanges();
  Future<bool> hasDetached() => native.hasDetachedChatWindow();
  Future<void> openDetached(double width) =>
      native.openDetachedChatWindow(width: width);
}
