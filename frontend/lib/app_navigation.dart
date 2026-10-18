import 'dart:async';

import 'package:flutter/material.dart';

import 'features/auth/login_page.dart';
import 'features/assistant/assistant_api.dart';
import 'workspace.dart';
import 'features/auth/app_role.dart';
import 'features/admin/admin_workspace.dart';
import 'features/admin/admin_repository.dart';
import 'app_shell/workspace_title_bar.dart';
import 'shared/widgets/task_focus_group.dart';
import 'features/auth/auth_api.dart';
import 'features/auth/account_access_page.dart';
import 'features/auth/local_data_owner.dart';

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

/// Server identity owns live navigation; development samples remain isolated.
class AppNavigation extends RouterDelegate<AppLocation>
    with
        ChangeNotifier,
        PopNavigatorRouterDelegateMixin<AppLocation>,
        WidgetsBindingObserver {
  AppNavigation({
    required this.authenticated,
    this.assistantFactory,
    AuthGateway? authGateway,
  }) : _auth = authGateway ?? AuthApi(),
       _ownsAuth = authGateway == null {
    WidgetsBinding.instance.addObserver(this);
    if (!authenticated) unawaited(_refreshSession());
  }
  final AssistantGateway Function()? assistantFactory;
  final AuthGateway _auth;
  final bool _ownsAuth;
  AuthIdentity? _identity;
  Timer? _sessionTimer;
  bool _closed = false;
  int _authEpoch = 0;

  void _startSessionChecks() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_refreshSession()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _identity != null) {
      unawaited(_refreshSession());
    }
  }

  Future<void> _refreshSession() async {
    final epoch = _authEpoch;
    try {
      final next = await _auth.me();
      if (_closed || epoch != _authEpoch) return;
      if (next == null) {
        if (_identity == null) return;
        _identity = null;
        authenticated = false;
        _role = AppRole.user;
        LocalDataOwner.currentUserId = null;
        _sessionTimer?.cancel();
        _location = const AppLocation('/login');
      } else {
        final wasAuthenticated = authenticated;
        final previousRole = _role;
        final accountChanged = _identity != null && _identity!.id != next.id;
        if (accountChanged) {
          _authEpoch++;
          _history.clear();
          _historyIndex = -1;
          _sidebarVisible = true;
          _location = const AppLocation('/home');
        }
        _identity = next;
        authenticated = true;
        _role = next.role;
        LocalDataOwner.currentUserId = next.id;
        if (!wasAuthenticated || accountChanged || previousRole != _role) {
          if (_role != AppRole.user) {
            _location = const AppLocation('/admin/overview');
          } else if (previousRole != AppRole.user ||
              _location.path == '/login') {
            _location = const AppLocation('/home');
          }
        }
        if (_sessionTimer == null || !_sessionTimer!.isActive) {
          _startSessionChecks();
        }
      }
      notifyListeners();
    } catch (_) {
      /* Do not treat a transport failure as a confirmed session revocation. */
    }
  }

  Future<void> _authenticate({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final epoch = ++_authEpoch;
    final next = await _auth.authenticate(
      email: email,
      password: password,
      displayName: displayName,
    );
    if (_closed || epoch != _authEpoch) return;
    _identity = next;
    LocalDataOwner.currentUserId = next.id;
    _startSessionChecks();
  }

  bool authenticated;
  AppRole _role = AppRole.user;
  AdminRepository? _adminRepository;
  @override
  void dispose() {
    _closed = true;
    _authEpoch++;
    _sessionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (LocalDataOwner.currentUserId == _identity?.id) {
      LocalDataOwner.currentUserId = null;
    }
    if (_ownsAuth) _auth.close();
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
    _authEpoch++;
    _sessionTimer?.cancel();
    _identity = null;
    LocalDataOwner.currentUserId = null;
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
    if (_identity != null && authenticated && _role != AppRole.user) {
      key = 'live-access';
      page = AccountAccessPage(
        identity: _identity!,
        api: _auth,
        onSignedOut: () async {
          await _auth.logout();
          if (!_closed && context.mounted) _signedOut(context);
        },
      );
    } else if (_identity != null &&
        authenticated &&
        _location.path.startsWith('/admin')) {
      key = 'forbidden';
      page = Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('관리자 화면에 접근할 권한이 없습니다.'),
              TextButton(
                onPressed: () => _select(context, 0),
                child: const Text('홈으로 이동'),
              ),
            ],
          ),
        ),
      );
    } else if (_location.path.startsWith('/admin') && authenticated) {
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
        authenticate: _authenticate,
        onSignedIn: () => _signedIn(context, _identity?.role ?? AppRole.user),
        onSampleSignedIn: (role) {
          _authEpoch++;
          _identity = null;
          _sessionTimer?.cancel();
          LocalDataOwner.currentUserId = null;
          _signedIn(context, role);
        },
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
        beforeSignedOut: _identity == null ? null : _auth.logout,
      );
    }
    return Navigator(
      key: navigatorKey,
      onDidRemovePage: (_) {},
      pages: [
        MaterialPage<void>(
          key: ValueKey('$key:${_identity?.id ?? "sample"}'),
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              children: [
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: TaskFocusGroup(
                    child: WorkspaceTitleBar(
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
                      onForward:
                          authenticated && _historyIndex < _history.length - 1
                          ? () => _travel(context, 1)
                          : null,
                    ),
                  ),
                ),
                Expanded(
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(0),
                    child: TaskFocusGroup(child: page),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
