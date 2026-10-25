import 'dart:async';

import 'package:flutter/material.dart';

import 'features/auth/login_page.dart';
import 'features/assistant/assistant_api.dart';
import 'workspace.dart';
import 'features/auth/app_role.dart';
import 'features/admin/admin_workspace.dart';
import 'features/admin/admin_repository.dart';
import 'features/admin/remote_admin_repository.dart';
import 'app_shell/workspace_title_bar.dart';
import 'shared/widgets/task_focus_group.dart';
import 'features/auth/auth_api.dart';
import 'features/api/school_signup_models.dart';
import 'features/auth/account_access_page.dart';
import 'features/auth/local_data_owner.dart';
import 'features/api/student_api.dart';
import 'features/auth/account_security_gateway.dart';
import 'features/auth/account_security_dialog.dart';
import 'shared/widgets/input_dialog.dart';
import 'features/admin/school_admin_applications_dialog.dart';
import 'features/auth/school_workflow_session.dart';

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
  bool _accountDialogOpen = false;
  String? _loginNotice;
  Future<void> _openApplications(BuildContext context) async {
    final identity = _identity;
    final auth = _auth;
    if (_accountDialogOpen ||
        identity == null ||
        !authenticated ||
        auth is! AuthApi) {
      return;
    }
    _accountDialogOpen = true;
    try {
      await showInputDialog<void>(
        context: context,
        builder: (_) =>
            SchoolAdminApplicationsDialog(auth: auth, identity: identity),
      );
      await _refreshSession();
    } finally {
      _accountDialogOpen = false;
    }
  }

  Future<void> _openAccountSecurity(BuildContext context) async {
    final identity = _identity;
    final auth = _auth;
    if (_accountDialogOpen ||
        identity == null ||
        !authenticated ||
        auth is! AuthApi) {
      return;
    }
    final epoch = _authEpoch;
    final AccountSecurityGateway gateway;
    try {
      gateway = auth.securityForOwner(identity.id);
    } on AuthFailure {
      await _refreshSession();
      return;
    }
    if (!context.mounted) return;
    _accountDialogOpen = true;
    try {
      final outcome = await showInputDialog<AccountSecurityOutcome>(
        context: context,
        builder: (_) => AccountSecurityDialog(
          identity: identity,
          gateway: gateway,
          onKnownEnd: (outcome) {
            if (_closed ||
                epoch != _authEpoch ||
                (_identity != null && _identity!.id != identity.id)) {
              return;
            }
            _loginNotice = switch (outcome) {
              AccountSecurityOutcome.passwordChanged =>
                '비밀번호가 변경되었습니다. 새 비밀번호로 다시 로그인하세요.',
              AccountSecurityOutcome.allSessionsEnded =>
                '모든 기기의 세션이 종료되었습니다. 다시 로그인하세요.',
              AccountSecurityOutcome.expired =>
                '현재 세션이 종료되었습니다. 앞선 요청의 완료 여부까지 확정된 것은 아닙니다. 다시 로그인하여 확인하세요.',
              AccountSecurityOutcome.changed => null,
            };
            // Permissions can replace the page (and remove its dialog) while
            // this request is in flight. Session termination belongs to the
            // captured account, not to the lifetime of that old dialog route.
            if (outcome != AccountSecurityOutcome.changed) {
              final navigationContext = navigatorKey?.currentContext;
              if (navigationContext != null && navigationContext.mounted) {
                _signedOut(navigationContext);
              } else if (_identity == null) {
                notifyListeners();
              }
            }
          },
        ),
      );
      if (_closed ||
          epoch != _authEpoch ||
          (_identity != null && _identity!.id != identity.id)) {
        return;
      }
      if (outcome == AccountSecurityOutcome.passwordChanged ||
          outcome == AccountSecurityOutcome.allSessionsEnded ||
          outcome == AccountSecurityOutcome.expired) {
        if (context.mounted && _identity != null) _signedOut(context);
      } else {
        await _refreshSession();
      }
    } finally {
      _accountDialogOpen = false;
    }
  }

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
        _liveAdminRepository?.dispose();
        _liveAdminRepository = null;
        _identity = null;
        authenticated = false;
        _role = AppRole.user;
        LocalDataOwner.currentUserId = null;
        _sessionTimer?.cancel();
        _location = const AppLocation('/login');
      } else {
        if (_liveAdminRepository != null &&
            (next.id != _liveAdminRepository!.userId ||
                next.role == AppRole.user)) {
          _liveAdminRepository!.dispose();
          _liveAdminRepository = null;
        }
        final wasAuthenticated = authenticated;
        final previousRole = _role;
        final accountChanged = _identity != null && _identity!.id != next.id;
        if (accountChanged) {
          _loginNotice = null;
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
    _loginNotice = null;
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

  Future<SchoolAdminSignupView> _registerSchoolAdmin({
    required String email,
    required String password,
    required String displayName,
    required SchoolAdminSignupDetails details,
  }) async {
    final gateway = _auth;
    if (gateway is! AuthApi) throw const AuthFailure('가입 접수 서버를 확인해 주세요.');
    final epoch = ++_authEpoch;
    _loginNotice = null;
    final result = await gateway.registerSchoolAdmin(
      email: email,
      password: password,
      displayName: displayName,
      details: details,
    );
    if (_closed || epoch != _authEpoch) {
      throw const AuthFailure('로그인 상태가 변경되었습니다.');
    }
    _identity = result.identity;
    LocalDataOwner.currentUserId = result.identity.id;
    _startSessionChecks();
    return result.signup;
  }

  bool authenticated;
  AppRole _role = AppRole.user;
  AdminRepository? _adminRepository;
  RemoteAdminRepository? _liveAdminRepository;
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
    _liveAdminRepository?.dispose();
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
    _liveAdminRepository?.dispose();
    _liveAdminRepository = null;
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
      if (_auth is ApiGateway) {
        if (_liveAdminRepository?.userId != _identity!.id) {
          _liveAdminRepository?.dispose();
          _liveAdminRepository = RemoteAdminRepository(
            _identity!,
            auth: _auth,
            api: _auth is AuthApi
                ? (_auth).forOwner(_identity!.id)
                : _auth as ApiGateway,
          );
        } else if (_liveAdminRepository!.permissionVersion !=
            _identity!.version) {
          _liveAdminRepository!.updateIdentity(_identity!);
        }
        key = 'live-admin:${_identity!.version}';
        page = AdminWorkspace(
          role: _role,
          path: _location.path,
          actorId: _identity!.id,
          repository: _liveAdminRepository,
          sidebarVisible: _sidebarVisible,
          onNavigate: (path) => _go(context, path),
          beforeSignedOut: _auth.logout,
          onSignedOut: () => _signedOut(context),
        );
      } else {
        key = 'live-access';
        page = AccountAccessPage(
          identity: _identity!,
          api: _auth,
          onSignedOut: () async {
            await _auth.logout();
            if (!_closed && context.mounted) _signedOut(context);
          },
        );
      }
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
        notice: _loginNotice,
        authenticate: _authenticate,
        registerSchoolAdmin: _auth is AuthApi ? _registerSchoolAdmin : null,
        onSignedIn: () {
          _signedIn(context, _identity?.role ?? AppRole.user);
        },
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
        studentApi: _identity != null && _auth is AuthApi
            ? StudentApi(
                (_auth).forOwner(_identity!.id),
                ownerId: _identity!.id,
              )
            : null,
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
                    child: Builder(
                      builder: (dialogContext) => WorkspaceTitleBar(
                        applicationLabel: _role == AppRole.superAdmin
                            ? '학교관리자 신청 접수'
                            : '학교 관리 권한·신청 이력',
                        onApplications:
                            _identity != null &&
                                authenticated &&
                                _auth is AuthApi
                            ? () => _openApplications(dialogContext)
                            : null,
                        onAccountSecurity:
                            _identity != null &&
                                authenticated &&
                                _auth is AuthApi
                            ? () => _openAccountSecurity(dialogContext)
                            : null,
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
                ),
                Expanded(
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(0),
                    child: TaskFocusGroup(
                      child:
                          authenticated && _identity != null && _auth is AuthApi
                          ? SchoolWorkflowSession(
                              auth: _auth,
                              identity: _identity!,
                              child: page,
                            )
                          : page,
                    ),
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
