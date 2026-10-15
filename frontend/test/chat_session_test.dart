import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/chat_window_desktop.dart' as native;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('session end hides only chat children and accepts a lost close reply only after native absence', () async {
    const windows = MethodChannel('mixin.one/desktop_multi_window');
    const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    var childExists = true;
    messenger.setMockMethodCallHandler(windows, (call) async {
      if (call.method == 'getAllWindows')
        return [
          {'windowId': 'main', 'windowArgument': ''},
          if (childExists)
            {
              'windowId': 'chat',
              'windowArgument': 'university_path_ai_detached_chat',
            },
        ];
      if (call.method == 'window_hide')
        calls.add('hide:${call.arguments['windowId']}');
      return null;
    });
    messenger.setMockMethodCallHandler(channels, (call) async {
      calls.add('${call.arguments['channel']}:${call.arguments['method']}');
      childExists = false;
      throw PlatformException(code: 'CHANNEL_NOT_FOUND');
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(windows, null);
      messenger.setMockMethodCallHandler(channels, null);
    });
    await native.endDetachedChatSession();
    expect(calls, [
      'hide:chat',
      'mixin.one/window_controller/chat:end_chat_session',
    ]);
    expect(childExists, isFalse);
  });
}
