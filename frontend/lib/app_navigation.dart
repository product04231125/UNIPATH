import 'package:flutter/material.dart';

import 'features/auth/login_page.dart';
import 'features/assistant/assistant_api.dart';
import 'workspace.dart';
import 'features/auth/app_role.dart';
import 'features/admin/admin_workspace.dart';
import 'features/admin/admin_repository.dart';
import 'app_shell/workspace_title_bar.dart';

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
  AppNavigation({required this.authenticated, this.assistantFactory});
  final AssistantGateway Function()? assistantFactory;

  bool authenticated;
  AppRole _role = AppRole.user;
  AdminRepository? _adminRepository;
  @override
  void dispose() {
    _adminRepository?.dispose();
    super.dispose();
  }

  AppLocation _location = const AppLocation('/');
  final List<AppLocation> _history = [];
  int _historyIndex = -1;
  bool _sidebarVisible = true;

  void _remember(AppLocation location) {
    if (_historyIndex >= 0 && _history[_historyIndex].path == location.path) {
      return;
    }
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(location);
    _historyIndex = _history.length - 1;
  }

  void _go(BuildContext context, String path) => Router.navigate(context, () {
    _remember(_location);
    _location = AppLocation(path);
    _remember(_location);
    notifyListeners();
  });
  void _travel(BuildContext context, int delta) => Router.neglect(context, () {
    _historyIndex += delta;
    _location = _history[_historyIndex];
    notifyListeners();
  });
  @override
  final navigatorKey = GlobalKey<NavigatorState>();
  @override
  AppLocation get currentConfiguration => _location;

  @override
  Future<void> setNewRoutePath(AppLocation configuration) async {
    _location = configuration;
    if (authenticated) _remember(configuration);
    notifyListeners();
  }

  void _select(BuildContext context, int menu) =>
      _go(context, AppLocation.menuPaths[menu]);

  void _signedIn(BuildContext context, [AppRole role = AppRole.user]) =>
      Router.neglect(context, () {
        authenticated = true;
        _role = role;
        if (role != AppRole.user) {
          _location = const AppLocation('/admin/overview');
        }
        if (_location.path == '/login') _location = const AppLocation('/home');
        _history.clear();
        _historyIndex = -1;
        _remember(_location);
        notifyListeners();
      });

  void _signedOut(BuildContext context) => Router.neglect(context, () {
    authenticated = false;
    _role = AppRole.user;
    _location = const AppLocation('/login');
    _history.clear();
    _historyIndex = -1;
    _sidebarVisible = true;
    notifyListeners();
  });

  @override
  Widget build(BuildContext context) {
    final menu = _location.menu;
    final Widget page;
    final String key;
    if (_location.path.startsWith('/admin') && authenticated) {
      key = 'admin';
      page = AdminWorkspace(
        repository: _adminRepository ??= FakeAdminRepository(),
        role: _role,
        path: _location.path,
        sidebarVisible: _sidebarVisible,
        onNavigate: (path) => _go(context, path),
        onSignedOut: () => _signedOut(context),
      );
    } else if (menu == null &&
        _location.path != '/login' &&
        !_location.path.startsWith('/admin')) {
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
      page = LoginPage(
        onSignedIn: () => _signedIn(context),
        onSampleSignedIn: (role) => _signedIn(context, role),
      );
    } else if (_role != AppRole.user) {
      key = 'admin';
      page = AdminWorkspace(
        repository: _adminRepository ??= FakeAdminRepository(),
        role: _role,
        path: '/admin/overview',
        sidebarVisible: _sidebarVisible,
        onNavigate: (path) => _go(context, path),
        onSignedOut: () => _signedOut(context),
      );
    } else {
      key = 'workspace';
      page = Workspace(
        sidebarVisible: _sidebarVisible,
        integratedTitleBar: true,
        assistantFactory: assistantFactory,
        selectedPage: menu!,
        onPageChanged: (value) => _select(context, value),
        onSignedOut: () => _signedOut(context),
      );
    }
    return Navigator(
      key: navigatorKey,
      onDidRemovePage: (_) {},
      pages: [
        MaterialPage<void>(
          key: ValueKey(key),
          child: Column(
            children: [
              WorkspaceTitleBar(
                title: _role == AppRole.user
                    ? 'UniversityPath'
                    : '${_role.label} · UniversityPath',
                sidebarVisible: _sidebarVisible,
                onToggleSidebar: authenticated
                    ? () {
                        _sidebarVisible = !_sidebarVisible;
                        notifyListeners();
                      }
                    : null,
                onBack: authenticated && _historyIndex > 0
                    ? () => _travel(context, -1)
                    : null,
                onForward: authenticated && _historyIndex < _history.length - 1
                    ? () => _travel(context, 1)
                    : null,
              ),
              Expanded(child: page),
            ],
          ),
        ),
      ],
    );
  }
}
