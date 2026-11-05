import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/auth/account_security_dialog.dart';
import 'package:university_path_frontend/features/auth/account_security_gateway.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/login_page.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';

import 'support/auth_fixture.dart';

const secret = '  한글 비밀번호 2026  ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login password keeps a pasted passphrase and hides copy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LoginPage(onSignedIn: () {})));

    await checkPasswordEntry(
      tester,
      field: fieldLabeled('비밀번호'),
      showTooltip: '비밀번호 표시',
    );
  });

  testWidgets('signup confirmation keeps a pasted passphrase and hides copy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LoginPage(onSignedIn: () {})));
    await tester.tap(find.byKey(const Key('signup-tab')));
    await tester.pumpAndSettle();

    await checkPasswordEntry(
      tester,
      field: fieldLabeled('비밀번호 확인'),
      showTooltip: '비밀번호 표시',
    );
  });

  testWidgets('account security password keeps a pasted passphrase and hides copy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showInputDialog<void>(
                context: context,
                builder: (_) => AccountSecurityDialog(
                  identity: AuthIdentity.fromJson(
                    Map<String, dynamic>.from(identityJson()),
                  ),
                  gateway: _IdleGateway(),
                  onKnownEnd: (_) {},
                ),
              ),
              child: const Text('계정 보안 열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('계정 보안 열기'));
    await tester.pumpAndSettle();

    await checkPasswordEntry(
      tester,
      field: find.byKey(const ValueKey('security-new-password')),
      showTooltip: '새 비밀번호 표시',
    );
  });
}

Finder fieldLabeled(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> checkPasswordEntry(
  WidgetTester tester, {
  required Finder field,
  required String showTooltip,
}) async {
  var clipboard = '';
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboard = (call.arguments as Map)['text'] as String;
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboard};
        default:
          return null;
      }
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  final textField = tester.widget<TextField>(
    find
            .descendant(of: field, matching: find.byType(TextField))
            .evaluate()
            .isEmpty
        ? field
        : find.descendant(of: field, matching: find.byType(TextField)),
  );
  expect(textField.inputFormatters, anyOf(isNull, isEmpty));
  final editable = tester.state<EditableTextState>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  expect(editable.widget.obscureText, isTrue);
  expect(editable.copyEnabled, isFalse);
  expect(editable.cutEnabled, isFalse);

  await tester.tap(field);
  await tester.pump();
  clipboard = secret;
  await editable.pasteText(SelectionChangedCause.keyboard);
  await tester.pump();
  expect(textField.controller!.text, secret);

  clipboard = 'sentinel';
  editable.userUpdateTextEditingValue(
    editable.textEditingValue.copyWith(
      selection: TextSelection(baseOffset: 0, extentOffset: secret.length),
    ),
    SelectionChangedCause.keyboard,
  );
  editable.copySelection(SelectionChangedCause.toolbar);
  await tester.pump();
  expect(clipboard, 'sentinel');

  await tester.tap(
    find.descendant(of: field, matching: find.byTooltip(showTooltip)),
  );
  await tester.pump();
  expect(editable.widget.obscureText, isFalse);
  expect(editable.copyEnabled, isTrue);
  expect(editable.cutEnabled, isTrue);

  editable.copySelection(SelectionChangedCause.toolbar);
  await tester.pump();
  expect(clipboard, secret);
  expect(tester.takeException(), isNull);
}

class _IdleGateway implements AccountSecurityGateway {
  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {}

  @override
  Future<AccountSessionStatus> checkSession() async =>
      AccountSessionStatus.active;

  @override
  Future<void> logoutAll() async {}
}
