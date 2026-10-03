import 'package:flutter/material.dart';

import 'features/auth/login_page.dart';
import 'workspace.dart';

class AppLocation {
  const AppLocation(this.path);

  static const menuPaths = [
    '/home',
    '/schedule',
    '/courses',
    '/graduation',
    '/activities',
    '/experiences',
    '/credentials',
    '/portfolio',
    '/settings',
  ];
  final String path;
  int? get menu {
    final index = menuPaths.indexOf(path == '/' ? '/home' : path);
    return index < 0 ? null : index;
  }
}

class AppLocationParser extends RouteInformationParser<AppLocation> {
  const AppLocationParser();

  @override
  Future<AppLocation> parseRouteInformation(
    RouteInformation routeInformation,
  ) async => AppLocation(
    routeInformation.uri.path.isEmpty ? '/' : routeInformation.uri.path,
  );

  @override
  RouteInformation restoreRouteInformation(AppLocation configuration) =>
      RouteInformation(uri: Uri(path: configuration.path));
}

/// Navigation only. Authentication remains the existing in-memory mock.
class AppNavigation extends RouterDelegate<AppLocation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppLocation> {
  AppNavigation({required this.authenticated});

  bool authenticated;
  AppLocation _location = const AppLocation('/');
  @override
  final navigatorKey = GlobalKey<NavigatorState>();
  @override
  AppLocation get currentConfiguration => _location;

  @override
  Future<void> setNewRoutePath(AppLocation configuration) async {
    _location = configuration;
    notifyListeners();
  }

  void _select(BuildContext context, int menu) => Router.navigate(context, () {
    _location = AppLocation(AppLocation.menuPaths[menu]);
    notifyListeners();
  });

  void _signedIn(BuildContext context) => Router.neglect(context, () {
    authenticated = true;
    if (_location.path == '/login') _location = const AppLocation('/home');
    notifyListeners();
  });

  void _signedOut(BuildContext context) => Router.neglect(context, () {
    authenticated = false;
    _location = const AppLocation('/login');
    notifyListeners();
  });

  @override
  Widget build(BuildContext context) {
    final menu = _location.menu;
    final Widget page;
    final String key;
    if (menu == null && _location.path != '/login') {
      key = 'unknown';
      page = Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('존재하지 않는 화면입니다.'),
              TextButton(
                onPressed: () => _select(context, 0),
                child: const Text('홈으로 이동'),
              ),
            ],
          ),
        ),
      );
    } else if (!authenticated || _location.path == '/login') {
      key = 'login';
      page = LoginPage(onSignedIn: () => _signedIn(context));
    } else {
      key = 'workspace';
      page = Workspace(
        selectedPage: menu!,
        onPageChanged: (value) => _select(context, value),
        onSignedOut: () => _signedOut(context),
      );
    }
    return Navigator(
      key: navigatorKey,
      pages: [MaterialPage<void>(key: ValueKey(key), child: page)],
      onDidRemovePage: (_) {},
    );
  }
}
