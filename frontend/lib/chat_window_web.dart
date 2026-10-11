Future<bool> isDetachedChatWindow() async => false;
void bindSchoolProfile(
  Map<String, dynamic> Function()? read,
  Future<void> Function(Map<String, dynamic>)? save,
) {}
Stream<Map<String, dynamic>> schoolProfileChanges() => const Stream.empty();
Future<Map<String, dynamic>> requestSchoolProfile([
  Map<String, dynamic>? update,
]) async => throw UnsupportedError('No native school profile bridge');
Future<void> publishSchoolProfile(Map<String, dynamic> profile) async {}
Future<void> closeDetachedChatWindow() async {}

Future<void> initializeDetachedChatWindow() async {}

Future<void> initializeMainWindowCloseBehavior() async {}

Future<bool> hasDetachedChatWindow() async => false;

Stream<bool> detachedChatWindowChanges() => const Stream<bool>.empty();

Future<bool> isMainWindowMaximized() async => false;

Stream<bool> mainWindowMaximizeChanges() => const Stream<bool>.empty();

bool get supportsDetachedChatWindow => false;

Future<void> openDetachedChatWindow({double width = 360}) =>
    throw UnsupportedError(
      'Independent chat windows are not supported on Web.',
    );
