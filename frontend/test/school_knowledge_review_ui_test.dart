import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/admin/school_knowledge_review_dialog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/school_workflow_actions.dart';
import 'package:university_path_frontend/features/auth/school_workflow_session.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';

import 'school_knowledge_api_test.dart' as fixture;
import 'support/auth_fixture.dart';

http.Response json(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Server {
  String status = 'draft';
  int? failure;
  bool empty = false, failList = false, changedPage = false, paginate = false;
  bool warnings = false;
  Completer<void>? writeGate;
  final writes = <http.Request>[], reads = <http.Request>[];
  Map<String, Object?> get document => {...fixture.header(), 'status': status};
  late final auth = AuthApi(
    cookieMode: false,
    client: MockClient((r) async {
      if (r.url.path.endsWith('/login')) {
        return json({
          ...identityJson(role: 'school_admin'),
          'access_token': token,
        });
      }
      expect(r.headers['X-Unipath-Owner'], userId);
      if (r.method == 'POST') {
        writes.add(r);
        if (failure != null) {
          return json({
            'error': {
              'message': '합성 검토 실패',
              'field_errors': [
                {'field': 'body.reason', 'reason': 'invalid'},
              ],
            },
          }, failure!);
        }
        await writeGate?.future;
        status = r.url.path.endsWith('/approve') ? 'approved' : 'revoked';
        return json(document);
      }
      reads.add(r);
      if (r.url.path.endsWith('/pages')) {
        return json({
          'items': [
            for (var n = 1; n <= 2; n++)
              {
                'page': n,
                'part_count': n == 1 ? 1 : 0,
                'character_count': n == 1 ? 12 : 0,
                'page_hash': 'b' * 64,
                'is_blank': n == 2,
              },
          ],
          'next_cursor': null,
        });
      }
      if (r.url.path.contains('/pages/')) {
        final number = int.parse(r.url.pathSegments.last);
        return json({
          'knowledge_document_id': fixture.document,
          'version': changedPage ? 4 : 3,
          'page': number,
          'page_hash': 'b' * 64,
          'is_blank': number == 2,
          'parts': number == 2
              ? []
              : [
                  {
                    'id': fixture.chunk,
                    'part_index': 0,
                    'part_count': 1,
                    'character_start': 0,
                    'character_end': 12,
                    'content_hash': 'c' * 64,
                    'content': '검토 대상 합성 원문',
                    'admission_years': [2026],
                    'tracks': ['single_major'],
                    'warnings': warnings
                        ? ['table_structure_requires_review']
                        : [],
                  },
                ],
        });
      }
      if (r.url.path.endsWith('/${fixture.document}')) return json(document);
      if (failList) return json({}, 500);
      final filter = r.url.queryParameters['status'];
      return json({
        'items': empty || filter != null && filter != status ? [] : [document],
        'next_cursor': paginate && !r.url.queryParameters.containsKey('cursor')
            ? otherId
            : null,
      });
    }),
  );
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String label, String value) async {
  final target = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pumpAndSettle();
}

Future<void> open(
  WidgetTester tester,
  Server server, {
  double scale = 1,
}) async {
  addTearDown(server.auth.close);
  await server.auth.authenticate(
    email: 'admin@example.test',
    password: 'synthetic long password',
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showInputDialog<void>(
              context: context,
              builder: (_) => SchoolKnowledgeReviewDialog(
                auth: server.auth,
                ownerId: userId,
              ),
            ),
            child: const Text('검토 열기'),
          ),
        ),
      ),
    ),
  );
  await tap(tester, find.text('검토 열기'));
}

Future<void> detail(WidgetTester tester) => tap(tester, find.text('합성 추출 초안'));
Future<void> checks(WidgetTester tester) async {
  for (final title in [
    '공식 출처와 원본을 확인했습니다',
    '학교·입학연도·이수 경로 적용 범위를 확인했습니다',
    '추출 본문과 원본을 대조했습니다',
    '빈 페이지를 포함한 원본 전체를 검토했습니다',
  ]) {
    await tap(tester, find.text(title));
  }
}

void main() {
  testWidgets(
    'read failure retries and empty list does not fabricate documents',
    (tester) async {
      final server = Server()..failList = true;
      await open(tester, server);
      expect(
        find.textContaining('결과를 확인하지 못했습니다'),
        findsNothing,
      ); // server uses the shared safe HTTP error
      expect(find.text('합성 추출 초안'), findsNothing);
      server.failList = false;
      server.empty = true;
      await tap(tester, find.text('문서 목록 다시 읽기'));
      expect(find.textContaining('등록된 추출본이 없습니다'), findsOneWidget);
      expect(server.writes, isEmpty);
    },
  );

  testWidgets('list uses server cursor and status filters', (tester) async {
    final server = Server()..paginate = true;
    await open(tester, server);
    await tap(tester, find.text('문서 더 보기'));
    expect(server.reads.last.url.queryParameters['cursor'], otherId);
    await tap(tester, find.text('전체'));
    await tap(tester, find.text('근거 승인'));
    expect(server.reads.last.url.queryParameters['status'], 'approved');
    expect(
      server.reads.last.url.queryParameters.containsKey('cursor'),
      isFalse,
    );
  });

  testWidgets(
    'review shows received text, scope, warnings and explicit blank pages without writes',
    (tester) async {
      final server = Server()..warnings = true;
      await open(tester, server);
      await detail(tester);
      await tap(tester, find.text('1쪽 본문 보기'));
      expect(find.text('검토 대상 합성 원문'), findsOneWidget);
      expect(find.textContaining('입학연도: 2026'), findsOneWidget);
      expect(
        find.text('추출 경고: 표 구조를 원본과 대조해야 합니다.'),
        findsOneWidget,
      );
      await tap(tester, find.text('2쪽 빈 페이지'));
      expect(find.textContaining('검색 본문이나 인용으로 사용하지 않습니다'), findsOneWidget);
      expect(find.text('검토 대상 합성 원문'), findsNothing);
      expect(server.writes, isEmpty);
    },
  );

  testWidgets(
    'approval requires independent checks, matching hash and note and sends expected version',
    (tester) async {
      final server = Server();
      await open(tester, server);
      await detail(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '검색 근거로 승인'),
            )
            .onPressed,
        isNull,
      );
      await checks(tester);
      await type(tester, '검토 사유', '원본 전체를 대조했습니다');
      await type(tester, '검토한 원본 SHA-256', 'd' * 64);
      await tap(tester, find.text('검색 근거로 승인'));
      expect(server.writes, isEmpty);
      await type(tester, '검토한 원본 SHA-256', 'a' * 64);
      await tap(tester, find.text('검색 근거로 승인'));
      final body = jsonDecode(server.writes.single.body) as Map;
      expect(body, {
        'expected_version': 3,
        'reviewed_document_hash': 'a' * 64,
        'source_verified': true,
        'applicability_verified': true,
        'extraction_verified': true,
        'complete_document_verified': true,
        'review_note': '원본 전체를 대조했습니다',
      });
      expect(server.writes.single.url.path, endsWith('/approve'));
      expect(find.textContaining('근거 승인 · 2쪽'), findsOneWidget);
    },
  );

  testWidgets(
    'revocation validates, preserves input after 422 and retries explicitly',
    (tester) async {
      final server = Server()
        ..status = 'approved'
        ..failure = 422;
      await open(tester, server);
      await detail(tester);
      await tap(tester, find.text('근거 승인 회수'));
      expect(server.writes, isEmpty);
      await type(tester, '승인 회수 사유', '원본 내용 변경 확인');
      await tap(tester, find.text('근거 승인 회수'));
      expect(find.text('원본 내용 변경 확인'), findsOneWidget);
      expect(find.text('서버가 입력을 거부했습니다. 형식과 내용을 확인하세요.'), findsOneWidget);
      server.failure = null;
      await tap(tester, find.text('근거 승인 회수'));
      expect(server.writes.length, 2);
      expect(jsonDecode(server.writes.last.body), {
        'expected_version': 3,
        'reason': '원본 내용 변경 확인',
      });
      expect(find.textContaining('승인 회수 · 2쪽'), findsOneWidget);
    },
  );

  testWidgets(
    'submission locks duplicate decisions and close until the response returns',
    (tester) async {
      final server = Server()..writeGate = Completer<void>();
      await open(tester, server);
      await detail(tester);
      await checks(tester);
      await type(tester, '검토한 원본 SHA-256', 'a' * 64);
      await type(tester, '검토 사유', '원본 전체 확인');
      await tester.tap(find.text('검색 근거로 승인'));
      await tester.pump();
      expect(server.writes.length, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '검색 근거로 승인'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '닫기').last)
            .onPressed,
        isNull,
      );
      server.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(server.writes.length, 1);
      expect(find.textContaining('근거 승인 · 2쪽'), findsOneWidget);
    },
  );

  for (final failure in [403, 409, 500]) {
    testWidgets(
      'approval failure $failure hides denied content or requires fresh review',
      (tester) async {
        final server = Server()..failure = failure;
        await open(tester, server);
        await detail(tester);
        await tap(tester, find.text('1쪽 본문 보기'));
        await checks(tester);
        await type(tester, '검토한 원본 SHA-256', 'a' * 64);
        await type(tester, '검토 사유', '유지할 검토 메모');
        await tap(tester, find.text('검색 근거로 승인'));
        expect(server.writes.length, 1);
        if (failure == 403) {
          expect(find.text('검토 대상 합성 원문'), findsNothing);
          expect(find.text('합성 추출 초안'), findsNothing);
          expect(find.text('검색 근거로 승인'), findsNothing);
        } else {
          expect(find.text('유지할 검토 메모'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, '검색 근거로 승인'),
                )
                .onPressed,
            isNull,
          );
          await tap(tester, find.text('최신 자료 다시 읽기'));
          await tap(tester, find.text('계속 작성'));
          expect(find.text('유지할 검토 메모'), findsOneWidget);
          await tap(tester, find.text('최신 자료 다시 읽기'));
          await tap(tester, find.text('내용 폐기'));
          expect(find.text('유지할 검토 메모'), findsNothing);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, '검색 근거로 승인'),
                )
                .onPressed,
            isNull,
          );
        }
      },
    );
  }

  testWidgets(
    'changed page version is never displayed as current review content',
    (tester) async {
      final server = Server()..changedPage = true;
      await open(tester, server);
      await detail(tester);
      await tap(tester, find.text('1쪽 본문 보기'));
      expect(find.text('검토 대상 합성 원문'), findsNothing);
      expect(find.textContaining('최신 자료를 다시 읽고 페이지를 확인하세요'), findsOneWidget);
      expect(server.writes, isEmpty);
    },
  );

  for (final size in [const Size(1440, 900), const Size(480, 520)]) {
    testWidgets('review and dirty close fit $size with 200 percent text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = Server();
      await open(tester, server, scale: 2);
      await detail(tester);
      await tap(tester, find.text('1쪽 본문 보기'));
      await type(tester, '검토 사유', '작성 중인 메모');
      await tap(tester, find.text('닫기').last);
      expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
      await tap(tester, find.text('계속 작성'));
      expect(find.text('작성 중인 메모'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(server.writes, isEmpty);
    });
  }

  for (final role in ['user', 'school_admin', 'super_admin']) {
    testWidgets('$role has only its real document-review entry', (
      tester,
    ) async {
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient(
          (r) async => r.url.path.endsWith('/login')
              ? json({...identityJson(role: role), 'access_token': token})
              : json({'items': [], 'next_cursor': null}),
        ),
      );
      addTearDown(auth.close);
      final identity = await auth.authenticate(
        email: 'synthetic@example.test',
        password: 'synthetic password',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchoolWorkflowSession(
              auth: auth,
              identity: identity,
              child: const SchoolWorkflowActions(),
            ),
          ),
        ),
      );
      expect(
        find.text('학교 문서 근거 검토'),
        role == 'user' ? findsNothing : findsOneWidget,
      );
      if (role != 'user') {
        await tap(tester, find.text('학교 문서 근거 검토'));
        expect(find.byType(SchoolKnowledgeReviewDialog), findsOneWidget);
      }
    });
  }
}
