import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/api/record_source_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/official_sources_dialog.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';

import 'official_graduation_ui_test.dart' as catalog;
import 'record_source_api_test.dart' as fixture;
import 'support/auth_fixture.dart';

Future<void> launch(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showInputDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(1440, 900), const Size(480, 720)]) {
    testWidgets('source submission consent, PDF and same-key retry $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final posts = <Map<String, dynamic>>[];
      Map<String, Object?>? saved;
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return fixture.json({...identityJson(), 'access_token': token});
          }
          expect(request.headers['X-Unipath-Owner'], userId);
          if (request.url.path.contains('/catalog/')) {
            return fixture.json({
              'items': [catalog.catalogRow(request.url.path)],
              'next_cursor': null,
            });
          }
          if (request.method == 'POST') {
            expect(request.bodyBytes, fixture.pdf);
            posts.add(
              jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    request.headers['X-Unipath-Source-Metadata']!,
                  ),
                ),
              ) as Map<String, dynamic>,
            );
            if (posts.length == 1) {
              throw http.ClientException('synthetic offline');
            }
            saved = {
              ...fixture.sourceJson(),
              'client_id': posts.last['client_id'],
            };
            return fixture.json(saved!, 201);
          }
          return fixture.json({
            'items': [if (saved != null) saved!],
            'next_cursor': null,
          });
        }),
      );
      addTearDown(auth.close);
      await fixture.login(auth);
      await launch(
        tester,
        OfficialSourcesDialog(
          auth: auth,
          ownerId: userId,
          pickPdf: () async =>
              XFile.fromData(fixture.pdf, name: '합성 성적.pdf', path: '합성 성적.pdf'),
        ),
      );
      await tester.tap(find.text('학교 발급 PDF 제출하기'));
      await tester.pumpAndSettle();
      await catalog.choose(tester, '학교 선택', '검증 대학');
      final date = find.widgetWithText(TextField, '발급일 (YYYY-MM-DD)');
      await tester.ensureVisible(date);
      await tester.enterText(date, '2026-01-01');
      final submit = find.text('검토 요청 제출');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(posts, isEmpty);
      await tester.ensureVisible(find.text('PDF 선택 (최대 2 MiB)'));
      await tester.tap(find.text('PDF 선택 (최대 2 MiB)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('합성 성적.pdf ·'), findsOneWidget);
      final consent = find.text('선택한 학교 관리자가 이 원본과 검토 이력을 확인하는 데 동의합니다.');
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(posts, hasLength(1));
      expect(find.textContaining('선택한 PDF와 입력을 유지했습니다.'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
      await tester.tap(find.text('계속 작성'));
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(posts, hasLength(2));
      expect(posts.first, posts.last);
      expect(posts.last['review_consent_confirmed'], isTrue);
      expect(find.text('합성 성적.pdf'), findsOneWidget);
      expect(find.text('원본 확인 승인'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'administrator verifies downloaded source with explicit identity checks and latest version',
    (tester) async {
      final mutations = <Map<String, dynamic>>[];
      var row = fixture.sourceJson();
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return fixture.json({
              ...identityJson(role: 'school_admin', id: otherId),
              'access_token': token,
            });
          }
          expect(request.headers['X-Unipath-Owner'], otherId);
          if (request.url.path.endsWith('/file')) {
            return http.Response.bytes(
              fixture.pdf,
              200,
              headers: {'content-type': 'application/octet-stream'},
            );
          }
          if (request.url.path.endsWith('/events')) {
            return fixture.json({'items': []});
          }
          if (request.method == 'POST') {
            expect(request.url.path.endsWith('/verify'), isTrue);
            mutations.add(jsonDecode(request.body) as Map<String, dynamic>);
            row = {...row, 'status': 'verified', 'version': 2};
          }
          return fixture.json(row);
        }),
      );
      addTearDown(auth.close);
      await fixture.login(auth);
      final api = RecordSourceApi.forOwner(auth, otherId, admin: true);
      var exported = false;
      await launch(
        tester,
        SourceReviewDialog(
          api: api,
          source: RecordSource.fromJson(Map<String, dynamic>.from(row)),
          actorId: otherId,
          admin: true,
          exportPdf: (_, bytes) async {
            expect(bytes, fixture.pdf);
            exported = true;
          },
        ),
      );
      final approve = find.widgetWithText(FilledButton, '원본 확인 승인');
      expect(tester.widget<FilledButton>(approve).onPressed, isNull);
      await tester.ensureVisible(find.text('원본 PDF 내려받기'));
      await tester.tap(find.text('원본 PDF 내려받기'));
      await tester.pumpAndSettle();
      expect(exported, isTrue);
      for (final label in ['학교 발급 원본임을 확인했습니다.', '제출자와 원본 대상자의 신원을 확인했습니다.']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(mutations.single, {
        'expected_version': 1,
        'expected_sha256': 'a' * 64,
        'school_issued_confirmed': true,
        'subject_identity_confirmed': true,
      });
      expect(find.textContaining('원본 확인됨'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
