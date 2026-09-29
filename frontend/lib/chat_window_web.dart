// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

Future<bool> isDetachedChatWindow() async =>
    Uri.base.queryParameters['detached_chat'] == '1';

Future<void> initializeDetachedChatWindow() async {}

Future<void> initializeMainWindowCloseBehavior() async {}

Future<bool> hasDetachedChatWindow() async => false;

Stream<bool> detachedChatWindowChanges() => const Stream<bool>.empty();

Future<bool> isMainWindowMaximized() async => false;

Stream<bool> mainWindowMaximizeChanges() => const Stream<bool>.empty();

Future<void> openDetachedChatWindow({double width = 360}) async {
  final currentUrl = html.window.location.href;
  final baseUrl = currentUrl.split('?').first;
  html.window.open(
    '$baseUrl?detached_chat=1',
    'UniversityPath AI Chat',
    'popup=yes,width=${width.round()},height=720',
  );
}
