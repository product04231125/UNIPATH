import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/app_navigation.dart';
import 'package:university_path_frontend/features/auth/login_page.dart';
import 'package:university_path_frontend/features/schedule/schedule_page.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';
import 'package:university_path_frontend/workspace.dart';

class MemoryRouteProvider extends RouteInformationProvider with ChangeNotifier {
  MemoryRouteProvider(String path)
    : _value = RouteInformation(uri: Uri.parse(path));
  RouteInformation _value;
  final reports = <String>[];
  final types = <RouteInformationReportingType>[];

  @override
  RouteInformation get value => _value;
  void browserVisit(String path) {
    _value = RouteInformation(uri: Uri.parse(path));
    notifyListeners();
  }

  @override
  void routerReportsNewRouteInformation(
    RouteInformation information, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    _value = information;
    reports.add(information.uri.path);
    types.add(type);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (var index = 0; index < AppLocation.menuPaths.length; index++) {
    testWidgets('direct menu location ${AppLocation.menuPaths[index]}', (
      tester,
    ) async {
      final provider = MemoryRouteProvider(AppLocation.menuPaths[index]);
      await tester.pumpWidget(
        UniversityPathApp(
          startAuthenticated: true,
          routeInformationProvider: provider,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Workspace>(find.byType(Workspace)).selectedPage,
        index,
      );
      expect(find.byType(InputDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    });
  }

  testWidgets(
    'menu pushes URL, browser back and forward keep workspace state',
    (tester) async {
      final provider = MemoryRouteProvider('/home');
      await tester.pumpWidget(
        UniversityPathApp(
          startAuthenticated: true,
          routeInformationProvider: provider,
        ),
      );
      await tester.pumpAndSettle();
      final workspace = tester.state(find.byType(Workspace));
      await tester.tap(find.byTooltip('일정'));
      await tester.pumpAndSettle();
      expect(provider.value.uri.path, '/schedule');
      expect(provider.types.last, RouteInformationReportingType.navigate);
      provider.browserVisit('/home');
      await tester.pumpAndSettle();
      expect(tester.widget<Workspace>(find.byType(Workspace)).selectedPage, 0);
      provider.browserVisit('/schedule');
      await tester.pumpAndSettle();
      expect(find.byType(SchedulePage), findsOneWidget);
      expect(tester.state(find.byType(Workspace)), same(workspace));
      expect(find.byType(InputDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );

  testWidgets(
    'refresh keeps requested route but does not invent an auth session',
    (tester) async {
      final provider = MemoryRouteProvider('/settings');
      await tester.pumpWidget(
        UniversityPathApp(
          startAuthenticated: true,
          routeInformationProvider: provider,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        UniversityPathApp(routeInformationProvider: provider),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(provider.value.uri.path, '/settings');
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'test@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(tester.widget<Workspace>(find.byType(Workspace)).selectedPage, 8);
      expect(provider.value.uri.path, '/settings');
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );

  testWidgets('unknown route offers recovery without an empty screen', (
    tester,
  ) async {
    final provider = MemoryRouteProvider('/not-a-menu');
    await tester.pumpWidget(
      UniversityPathApp(
        startAuthenticated: true,
        routeInformationProvider: provider,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('존재하지 않는 화면입니다.'), findsOneWidget);
    await tester.tap(find.text('홈으로 이동'));
    await tester.pumpAndSettle();
    expect(provider.value.uri.path, '/home');
    expect(find.byType(Workspace), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
}
