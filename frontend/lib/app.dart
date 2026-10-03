import 'package:flutter/material.dart';

import 'chat_window.dart' as chat_window;
import 'features/assistant/detached_chat_page.dart';
import 'shared/app_typography.dart';
import 'app_navigation.dart';

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

ThemeData universityPathTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Malgun Gothic',
    scaffoldBackgroundColor: const Color(0xfff7f8f8),
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff193f59)),
  );
  final textTheme = AppTypography.apply(base.textTheme);
  return base.copyWith(
    textTheme: textTheme,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    ),
    dialogTheme: DialogThemeData(
      alignment: Alignment.center,
      constraints: const BoxConstraints(maxWidth: 640),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: textTheme.bodyMedium,
      subtitleTextStyle: textTheme.bodySmall,
    ),
  );
}

class UniversityPathApp extends StatefulWidget {
  const UniversityPathApp({
    super.key,
    this.startAuthenticated = false,
    this.routeInformationProvider,
  });

  /// Used by workspace widget tests until a real authentication contract exists.
  final bool startAuthenticated;
  final RouteInformationProvider? routeInformationProvider;

  @override
  State<UniversityPathApp> createState() => _UniversityPathAppState();
}

class _UniversityPathAppState extends State<UniversityPathApp> {
  late final _navigation = AppNavigation(
    authenticated: widget.startAuthenticated,
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
  Widget build(BuildContext context) => MaterialApp.router(
    debugShowCheckedModeBanner: false,
    title: 'UniversityPath',
    theme: universityPathTheme(),
    routeInformationProvider: _information,
    routeInformationParser: const AppLocationParser(),
    routerDelegate: _navigation,
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
