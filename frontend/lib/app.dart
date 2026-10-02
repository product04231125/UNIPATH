import 'package:flutter/material.dart';

import 'chat_window.dart' as chat_window;
import 'features/auth/login_page.dart';
import 'features/assistant/detached_chat_page.dart';
import 'workspace.dart';

Future<void> runUniversityPathApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  final detached = await chat_window.isDetachedChatWindow();
  if (detached) {
    await chat_window.initializeDetachedChatWindow();
  } else {
    await chat_window.initializeMainWindowCloseBehavior();
  }
  runApp(detached ? const DetachedChatApp() : const UniversityPathApp());
}

ThemeData universityPathTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Malgun Gothic',
  scaffoldBackgroundColor: const Color(0xfff7f8f8),
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff193f59)),
);

class UniversityPathApp extends StatefulWidget {
  const UniversityPathApp({super.key, this.startAuthenticated = false});

  /// Used by workspace widget tests until a real authentication contract exists.
  final bool startAuthenticated;

  @override
  State<UniversityPathApp> createState() => _UniversityPathAppState();
}

class _UniversityPathAppState extends State<UniversityPathApp> {
  late bool authenticated = widget.startAuthenticated;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'UniversityPath',
    theme: universityPathTheme(),
    home: authenticated
        ? Workspace(onSignedOut: () => setState(() => authenticated = false))
        : LoginPage(onSignedIn: () => setState(() => authenticated = true)),
  );
}

class DetachedChatApp extends StatelessWidget {
  const DetachedChatApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'UniversityPath AI 도우미',
    theme: universityPathTheme(),
    home: const DetachedChatWindow(),
  );
}
