import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';
import 'package:university_path_frontend/features/settings/ai_consent_section.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('permissions are isolated by owner and feature and revocable', () async {
    final a = AiConsentPreferences(ownerId: 'account-a');
    final b = AiConsentPreferences(ownerId: 'account-b');
    await Future.wait([a.load(), b.load()]);
    expect(a.allows(AiConsentFeature.schoolQuestion), false);
    expect(await a.setAllowed(AiConsentFeature.schoolQuestion, true), true);
    expect(a.allows(AiConsentFeature.personalizedQuestion), false);
    expect(b.allows(AiConsentFeature.schoolQuestion), false);
    final restored = AiConsentPreferences(ownerId: 'account-a');
    await restored.load();
    expect(restored.allows(AiConsentFeature.schoolQuestion), true);
    await restored.setAllowed(AiConsentFeature.schoolQuestion, false);
    expect(restored.allows(AiConsentFeature.schoolQuestion), false);
    a.dispose();
    b.dispose();
    restored.dispose();
  });
  test('write failure never grants and revocation fails closed', () async {
    var writesSucceed = true;
    final p = AiConsentPreferences(
      ownerId: 'a',
      reader: (_) async => null,
      writer: (_, _) async => writesSucceed,
    );
    await p.load();
    await p.setAllowed(AiConsentFeature.jobAnalysis, true);
    writesSucceed = false;
    expect(await p.setAllowed(AiConsentFeature.jobAnalysis, false), false);
    expect(p.allows(AiConsentFeature.jobAnalysis), false);
    expect(p.error, isNotNull);
    expect(await p.setAllowed(AiConsentFeature.schoolQuestion, true), false);
    expect(p.allows(AiConsentFeature.schoolQuestion), false);
    p.dispose();
  });
  test(
    'unknown notice version and invalid owner never enable transmission',
    () async {
      for (final payload in [
        {
          'owner_id': 'a',
          'notice_version': 999,
          'allowed': ['schoolQuestion'],
        },
        {
          'owner_id': 'b',
          'notice_version': 1,
          'allowed': ['schoolQuestion'],
        },
      ]) {
        final p = AiConsentPreferences(
          ownerId: 'a',
          reader: (_) async => jsonEncode(payload),
        );
        await p.load();
        expect(p.allows(AiConsentFeature.schoolQuestion), false);
        p.dispose();
      }
    },
  );
  test('late load after disposal cannot grant consent', () async {
    final read = Completer<String?>();
    final p = AiConsentPreferences(ownerId: 'a', reader: (_) => read.future);
    final pending = p.load();
    p.dispose();
    read.complete(
      jsonEncode({
        'owner_id': 'a',
        'notice_version': 1,
        'allowed': ['schoolQuestion'],
      }),
    );
    await pending;
    expect(p.allows(AiConsentFeature.schoolQuestion), false);
  });
  testWidgets('one-time permission does not persist and cancel never grants', (
    tester,
  ) async {
    final p = AiConsentPreferences(ownerId: 'a');
    await p.load();
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                accepted = await requestAiConsent(
                  context,
                  p,
                  AiConsentFeature.jobAnalysis,
                );
              },
              child: const Text('요청'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('요청'));
    await tester.pumpAndSettle();
    expect(find.text('이 기기에서 이후 요청에도 적용'), findsOneWidget);
    await tester.tap(find.text('이번만 허용'));
    await tester.pumpAndSettle();
    expect(accepted, true);
    expect(p.allows(AiConsentFeature.jobAnalysis), false);
    await tester.tap(find.text('요청'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(accepted, false);
    p.dispose();
  });
  testWidgets('settings ON explicitly asks persistent permission', (
    tester,
  ) async {
    final p = AiConsentPreferences(ownerId: 'a');
    await p.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiConsentSection(preferences: p)),
      ),
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('허용하고 저장'), findsOneWidget);
    expect(find.text('이번만 허용'), findsNothing);
    await tester.tap(find.text('허용하고 저장'));
    await tester.pumpAndSettle();
    expect(p.allows(AiConsentFeature.schoolQuestion), true);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(p.allows(AiConsentFeature.schoolQuestion), false);
    p.dispose();
  });
}
