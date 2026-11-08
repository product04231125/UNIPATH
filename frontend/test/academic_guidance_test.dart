import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/api/guidance_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/guidance_asset_gateway.dart';
import 'package:university_path_frontend/features/assistant/academic_guidance_view.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/conversation_bridge.dart';

import 'support/auth_fixture.dart';

final assetId = 'a' * 64;
Map<String, dynamic> node(String id) => {
  'schema_version': 'academic-click-v3',
  'node_id': id,
  'title': '학사 안내',
  'state': 'ready',
  'reason': 'menu',
  'message': '항목을 선택하세요.',
  'cards': [],
  'warnings': [],
  'buttons': [
    {
      'id': 'calendar',
      'label': '학사일정',
      'action': 'select_node',
      'node_id': 'calendar:2026:11',
      'availability': 'available',
    },
    {
      'id': 'pending',
      'label': '공지사항',
      'action': 'select_node',
      'node_id': 'notices',
      'availability': 'content_pending',
    },
    {
      'id': 'home',
      'label': '처음으로',
      'action': 'select_node',
      'node_id': 'home',
      'availability': 'available',
    },
  ],
};

class AcademicGateway extends ApiGateway implements GuidanceAssetGateway {
  final paths = <String>[];
  Map<String, dynamic>? response;
  Object? failure;
  List<Map<String, dynamic>> auditRows = [];
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    paths.add(path);
    if (failure != null) throw failure!;
    if (path.startsWith('me/graduation-audits?')) {
      return {'items': auditRows, 'next_cursor': null};
    }
    if (pending != null) return pending!.future;
    return response ?? node(path.split('/').last);
  }

  @override
  Future<GuidanceAsset> guidanceAsset(String id) async => GuidanceAsset(
    Uint8List.fromList('%PDF-1.4'.codeUnits),
    'application/pdf',
  );
}

AssistantConversation conversation(AcademicGateway api) =>
    AssistantConversation(
      guidanceApi: GuidanceApi(api, ownerId: userId),
      registeredOnly: true,
    )..setContext(
      const SchoolQueryContext(
        institutionId: 'school',
        departmentId: 'department',
        institution: '합성 학교',
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'school mode opens tree directly and switching preserves personal draft',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = AcademicGateway();
      final c = AssistantConversation(
        guidanceApi: GuidanceApi(api),
        registeredOnly: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: AssistantPanel(
                conversation: c,
                onClose: () {},
                width: 480,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.paths, ['me/academic-guidance/nodes/home']);
      await tester.tap(find.text('기타 안내'));
      await tester.pumpAndSettle();
      expect(find.text('학사일정'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('전송 전 동의'), findsNothing);
      await tester.tap(find.text('학사일정'));
      await tester.pumpAndSettle();
      expect(api.paths.last, 'me/academic-guidance/nodes/calendar:2026:11');
      await tester.tap(find.text('처음으로'));
      await tester.pumpAndSettle();
      expect(c.guidance!.nodeId, 'home');
      await tester.tap(find.widgetWithText(ChoiceChip, '내 자료로 질문'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '보존할 내 자료 질문');
      await tester.tap(find.widgetWithText(ChoiceChip, '학교 질문'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기타 안내'));
      await tester.pumpAndSettle();
      expect(find.text('학사일정'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, '내 자료로 질문'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '보존할 내 자료 질문',
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('tree load failure shows retry inside school mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = AcademicGateway()
      ..failure = const AuthFailure('서버 연결을 확인해 주세요.', status: 503);
    final c = conversation(api);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantPanel(conversation: c, onClose: () {}, width: 480),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('서버 연결을 확인해 주세요.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    api.failure = null;
    await tester.tap(find.text('안내 다시 읽기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기타 안내'));
    await tester.pumpAndSettle();
    expect(find.text('학사일정'), findsOneWidget);
    expect(api.paths.length, 2);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  test(
    'tree fetches server snapshot without a school mapping or personal profile',
    () async {
      final api = AcademicGateway();
      final c = AssistantConversation(
        guidanceApi: GuidanceApi(api),
        registeredOnly: true,
      );
      await c.showGuidance();
      expect(api.paths.single, 'me/academic-guidance/nodes/home');
      expect(c.guidance!.nodeId, 'home');
      expect(c.guidanceError, isNull);
      await c.refreshAudits();
      expect(c.guidanceError, contains('등록 학교·학과'));
      expect(api.paths.length, 1);
      c.dispose();
    },
  );
  test(
    'navigation uses server IDs and errors retain last readable node',
    () async {
      final api = AcademicGateway(), c = conversation(api);
      await c.showGuidance();
      expect(c.guidance!.nodeId, 'home');
      await c.navigateGuidance(c.guidance!.buttons.first.nodeId);
      expect(api.paths.last, 'me/academic-guidance/nodes/calendar:2026:11');
      api.failure = const AuthFailure('다시 읽기', status: 404);
      await c.navigateGuidance('notices');
      expect(c.guidance!.nodeId, 'calendar:2026:11');
      expect(c.guidanceError, contains('서버가 최신 버전'));
      c.dispose();
    },
  );
  test('only assets in current node may be requested', () async {
    final api = AcademicGateway()
      ..response = {
        ...node('home'),
        'source': {'asset_id': assetId},
      };
    final c = conversation(api);
    await c.showGuidance();
    expect((await c.loadGuidanceAsset(assetId)).contentType, 'application/pdf');
    await expectLater(
      Future.sync(() => c.loadGuidanceAsset('b' * 64)),
      throwsA(isA<AuthFailure>()),
    );
    c.dispose();
  });
  test('audit picker sends only selected matching owner audit ID', () async {
    final api = AcademicGateway()
      ..auditRows = [
        {
          'id': 'audit-id',
          'owner_id': userId,
          'client_id': 'client',
          'version': 1,
          'context': {
            'institution_id': 'school',
            'department_id': 'department',
            'curriculum_id': 'curriculum',
            'admission_year': 2026,
            'track': 'single_major',
          },
          'evaluated_on': '2026-11-08',
          'created_at': '2026-11-08T00:00:00Z',
          'official': true,
          'status': 'needs_review',
          'reason': 'incomplete',
          'catalog_complete': false,
          'eligible_as_of': false,
        },
      ];
    final c = conversation(api)
      ..setContext(
        const SchoolQueryContext(
          institutionId: 'school',
          departmentId: 'department',
          curriculumId: 'curriculum',
          admissionYear: 2026,
          track: 'single_major',
        ),
      );
    await c.navigateGuidance('summary');
    await c.refreshAudits();
    expect(c.auditOptions.single.id, 'audit-id');
    await c.selectAudit('unknown');
    expect(api.paths.where((v) => v.contains('audit_id=')), isEmpty);
    await c.selectAudit('audit-id');
    expect(
      api.paths.last,
      'me/academic-guidance/nodes/summary?audit_id=audit-id',
    );
    api.auditRows = [
      {...api.auditRows.single, 'owner_id': otherId},
    ];
    await c.refreshAudits();
    expect(c.guidanceError, isNotNull);
    c.dispose();
  });
  test('late node response after profile change is discarded', () async {
    final api = AcademicGateway()..pending = Completer<Map<String, dynamic>>();
    final c = conversation(api);
    final loading = c.showGuidance();
    c.setContext(
      const SchoolQueryContext(institutionId: 'other', departmentId: 'other'),
    );
    final old = api.pending!;
    api.pending = Completer<Map<String, dynamic>>();
    old.complete({...node('home'), 'title': '이전 학교 응답'});
    await loading;
    expect(c.guidance, isNull);
    expect(c.guidanceLoading, true);
    api.pending!.complete({...node('home'), 'title': '새 학교 응답'});
    await Future<void>.delayed(Duration.zero);
    expect(c.guidance!.title, '새 학교 응답');
    expect(c.guidanceLoading, false);
    c.dispose();
  });
  test(
    'remote navigation and authenticated asset reads use main owner',
    () async {
      final api = AcademicGateway()
        ..response = {
          ...node('home'),
          'source': {'asset_id': assetId},
        };
      final c = conversation(api),
          updates = StreamController<Map<String, dynamic>>.broadcast(
            sync: true,
          );
      final bridge = ConversationBridge(c, (v) async => updates.add(v));
      final remote = RemoteConversation(
        request: (cmd) async =>
            cmd == null ? bridge.read() : bridge.dispatch(cmd),
        changes: updates.stream,
      );
      await remote.load();
      await remote.showGuidance();
      await Future<void>.delayed(Duration.zero);
      expect(remote.guidanceOpen, true);
      expect(remote.guidance!.nodeId, 'home');
      expect(
        (await remote.loadGuidanceAsset(assetId)).bytes,
        Uint8List.fromList('%PDF-1.4'.codeUnits),
      );
      remote.closeGuidance();
      await remote.flush();
      expect(c.guidanceOpen, false);
      remote.dispose();
      bridge.dispose();
      c.dispose();
      await updates.close();
    },
  );
  testWidgets(
    'warnings OCR table blanks pending and audit need remain visible',
    (tester) async {
      final api = AcademicGateway()
        ..response = {
          ...node('summary'),
          'state': 'needs_input',
          'reason': 'verified_audit_required',
          'warnings': ['수집 시점 경고'],
          'snapshot_stale': true,
          'cards': [
            {
              'type': 'regulation_page',
              'title': '규정 원문',
              'body': 'OCR 본문',
              'extraction_status': 'ocr_unreviewed',
              'preferred_view': 'image',
              'image_asset_id': assetId,
              'tables': [
                [
                  ['분류', null],
                  ['항목', '내용'],
                ],
              ],
              'sources': [],
            },
          ],
        };
      final c = conversation(api);
      await c.showGuidance();
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 600,
                child: AcademicGuidanceView(conversation: c),
              ),
            ),
          ),
        ),
      );
      expect(find.text('수집 시각:'), findsNothing);
      await tester.ensureVisible(find.text('자료 정보'));
      await tester.tap(find.text('자료 정보'));
      await tester.pumpAndSettle();
      expect(find.text('수집 시점 경고'), findsOneWidget);
      await tester.ensureVisible(find.text('규정 원문'));
      await tester.tap(find.text('규정 원문'));
      await tester.pumpAndSettle();
      expect(find.text('원본 이미지 읽기'), findsOneWidget);
      expect(find.text('공지사항 · 준비 중'), findsOneWidget);
      expect(find.text('저장된 내 졸업요건 결과 불러오기'), findsOneWidget);
      expect(find.text('분류'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test('asset transport binds bearer and owner, rejects wrong type and stale login', () async {
    var bad = false;
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((req) async {
        if (req.url.path.endsWith('/login')) {
          return http.Response(
            jsonEncode({...identityJson(), 'access_token': token}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        expect(req.headers['Authorization'], 'Bearer $token');
        expect(req.headers['X-Unipath-Owner'], userId);
        expect(req.followRedirects, false);
        return http.Response(
          bad ? '<html>error</html>' : '%PDF-1.4',
          200,
          headers: {'content-type': bad ? 'text/html' : 'application/pdf'},
        );
      }),
    );
    await auth.authenticate(
      email: 'synthetic@example.test',
      password: 'synthetic password',
    );
    final files = auth.forOwner(userId) as GuidanceAssetGateway;
    expect((await files.guidanceAsset(assetId)).contentType, 'application/pdf');
    bad = true;
    await expectLater(
      files.guidanceAsset(assetId),
      throwsA(isA<AuthFailure>()),
    );
    auth.close();
    await expectLater(
      files.guidanceAsset(assetId),
      throwsA(isA<AuthFailure>()),
    );
  });
}
