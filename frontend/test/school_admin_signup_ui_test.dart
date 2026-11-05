import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/auth/login_page.dart';

Finder field(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  ),
  matching: find.byType(TextFormField),
);

Future<void> select(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(1440, 900), const Size(480, 520)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('signup types and school fields reflow at $size/$scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: LoginPage(onSignedIn: () {}),
          ),
        );
        await select(tester, 'signup-tab');
        expect(field('학교명'), findsNothing);
        await select(tester, 'signup-school-admin');
        for (final label in [
          '이름',
          '이메일 주소',
          '비밀번호',
          '비밀번호 확인',
          '학교명',
          '공식 홈페이지',
          '직책',
          '연락 이메일',
          '신청 사유',
        ]) {
          expect(field(label), findsOneWidget);
        }
        expect(find.byType(Form), findsOneWidget);
        expect(find.textContaining('일반 계정으로 가입 또는 로그인한 후'), findsNothing);
        expect(find.widgetWithText(TextButton, '학교관리자 가입 신청'), findsNothing);
        await tester.ensureVisible(field('신청 사유'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'type and login switches retain drafts, admin enter never creates a normal account',
    (tester) async {
      var calls = 0, signedIn = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            onSignedIn: () => signedIn++,
            authenticate:
                ({required email, required password, displayName}) async {
                  calls++;
                },
          ),
        ),
      );
      await select(tester, 'signup-tab');
      await tester.enterText(field('이름'), '합성 담당자');
      await select(tester, 'signup-school-admin');
      await tester.ensureVisible(field('학교명'));
      await tester.enterText(field('학교명'), '합성 대학');
      await tester.ensureVisible(field('직책'));
      await tester.enterText(field('직책'), '학사 담당');
      await select(tester, 'signup-student');
      expect(field('학교명'), findsNothing);
      expect(
        tester.widget<TextFormField>(field('이름')).controller!.text,
        '합성 담당자',
      );
      await select(tester, 'signup-school-admin');
      expect(
        tester.widget<TextFormField>(field('학교명')).controller!.text,
        '합성 대학',
      );
      expect(
        tester.widget<TextFormField>(field('직책')).controller!.text,
        '학사 담당',
      );
      await select(tester, 'login-tab');
      await select(tester, 'signup-tab');
      expect(
        tester.widget<TextFormField>(field('학교명')).controller!.text,
        '합성 대학',
      );
      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('signup-submit')),
      );
      expect(submit.onPressed, isNull);
      await tester.ensureVisible(field('비밀번호 확인'));
      await tester.enterText(field('비밀번호 확인'), 'synthetic password');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(signedIn, 0);
      expect(find.textContaining('서버에 저장되지 않습니다'), findsOneWidget);
    },
  );

  testWidgets(
    'school fields validate URL and contact email and student signup remains available',
    (tester) async {
      final submissions = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            onSignedIn: () {},
            authenticate:
                ({required email, required password, displayName}) async {
                  submissions.add(displayName);
                },
          ),
        ),
      );
      await select(tester, 'signup-tab');
      await select(tester, 'signup-school-admin');
      await tester.ensureVisible(field('공식 홈페이지'));
      await tester.enterText(field('공식 홈페이지'), 'javascript:invalid');
      await tester.ensureVisible(field('연락 이메일'));
      await tester.enterText(field('연락 이메일'), 'invalid');
      await tester.pumpAndSettle();
      expect(find.text('유효한 http/https 홈페이지 주소를 입력하세요.'), findsOneWidget);
      expect(find.text('연락 이메일 주소 형식을 확인하세요.'), findsOneWidget);
      await select(tester, 'signup-student');
      await tester.enterText(field('이름'), '합성 학생');
      await tester.enterText(field('이메일 주소'), 'student@example.test');
      await tester.enterText(field('비밀번호'), 'synthetic long password');
      await tester.enterText(field('비밀번호 확인'), 'synthetic long password');
      await select(tester, 'signup-submit');
      expect(submissions, ['합성 학생']);
    },
  );
}
