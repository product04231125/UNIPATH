import 'package:flutter/material.dart';

import 'chat_window.dart' as chat_window;
import 'features/assistant/detached_chat_page.dart';
import 'features/assistant/assistant_api.dart';
import 'shared/app_style.dart';
import 'app_navigation.dart';
import 'shared/widgets/task_focus_group.dart';

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

ThemeData universityPathTheme({AppPalette palette = AppPalette.cream}) =>
    buildAppTheme(palette);

class UniversityPathApp extends StatefulWidget {
  const UniversityPathApp({
    super.key,
    this.startAuthenticated = false,
    this.routeInformationProvider,
    this.assistantFactory,
  });

  /// Used by workspace widget tests until a real authentication contract exists.
  final bool startAuthenticated;
  final RouteInformationProvider? routeInformationProvider;
  final AssistantGateway Function()? assistantFactory;

  @override
  State<UniversityPathApp> createState() => _UniversityPathAppState();
}

class _UniversityPathAppState extends State<UniversityPathApp> {
  late final _navigation = AppNavigation(
    authenticated: widget.startAuthenticated,
    assistantFactory: widget.assistantFactory,
  );
  late final RouteInformationProvider _information =
      widget.routeInformationProvider ??
      PlatformRouteInformationProvider(
        initialRouteInformation: RouteInformation(
          uri: Uri.parse(
            WidgetsBinding.instance.platformDispatcher.defaultRouteName,
          ),
        ),
      );

  @override
  void dispose() {
    _navigation.dispose();
    if (widget.routeInformationProvider == null) {
      (_information as PlatformRouteInformationProvider).dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPaletteHost(
    builder: (theme, preview) => MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'UniversityPath',
      theme: theme,
      builder: (context, child) =>
          preview(context, TaskFocusGroup(child: child!)),
      routeInformationProvider: _information,
      routeInformationParser: const AppLocationParser(),
      routerDelegate: _navigation,
    ),
  );
}

class DetachedChatApp extends StatelessWidget {
  const DetachedChatApp({super.key});

  @override
  Widget build(BuildContext context) => AppPaletteHost(
    builder: (theme, preview) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UniversityPath AI 도우미',
      theme: theme,
      builder: (context, child) =>
          preview(context, TaskFocusGroup(child: child!)),
      home: const DetachedChatWindow(),
    ),
  );
}
