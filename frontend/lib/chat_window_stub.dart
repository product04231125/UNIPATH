Future<bool> isDetachedChatWindow() async => false;

Future<void> initializeDetachedChatWindow() async {}

Future<void> initializeMainWindowCloseBehavior() async {}

Future<bool> hasDetachedChatWindow() async => false;

Stream<bool> detachedChatWindowChanges() => const Stream<bool>.empty();

Future<bool> isMainWindowMaximized() async => false;

Stream<bool> mainWindowMaximizeChanges() => const Stream<bool>.empty();

Future<void> openDetachedChatWindow({double width = 360}) {
  throw UnsupportedError('Independent chat windows are not supported here.');
}
