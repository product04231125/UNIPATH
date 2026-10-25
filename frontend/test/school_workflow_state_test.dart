import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/api/record_source_api.dart';
import 'package:university_path_frontend/features/api/official_records_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/graduation/official_graduation_page.dart';
import 'package:university_path_frontend/features/records/official_sources_dialog.dart';
import 'package:university_path_frontend/features/records/official_records_dialog.dart';
import 'package:university_path_frontend/features/graduation/school_document_search_dialog.dart';
import 'package:university_path_frontend/features/admin/school_admin_applications_dialog.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';
import 'package:university_path_frontend/features/auth/school_workflow_session.dart';
import 'package:university_path_frontend/features/auth/school_workflow_actions.dart';

import 'official_graduation_ui_test.dart' as catalog;
import 'official_records_api_test.dart' as records;
import 'official_sources_ui_test.dart' as ui;
import 'record_source_api_test.dart' as source;
import 'graduation_api_test.dart' as audit;
import 'support/auth_fixture.dart';
import 'school_admin_applications_ui_test.dart' as applications;

void main() {
  for (final role in ['user', 'school_admin', 'super_admin']) {
    testWidgets(
      '$role entry points use the authenticated owner and matching read permissions',
      (tester) async {
        final paths = <String>[];
        final auth = AuthApi(
          cookieMode: false,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login')) {
              return source.json({
                ...identityJson(role: role),
                'access_token': token,
              });
            }
            expect(request.headers['X-Unipath-Owner'], userId);
            expect(request.method, 'GET');
            paths.add(request.url.path);
            return source.json({'items': [], 'next_cursor': null});
          }),
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
        final admin = role != 'user';
        await tester.tap(find.text(admin ? '학교 발급 원본 검토' : '학교 발급 PDF 제출·이력'));
        await tester.pumpAndSettle();
        expect(
          paths.last,
          '/api/v1/${admin ? 'admin' : 'me'}/official-record-sources',
        );
        await tester.tap(find.text('닫기'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(admin ? '학교 확인 학생 기록 검토' : '학교 확인 학생 기록'));
        await tester.pumpAndSettle();
        expect(
          paths.last,
          '/api/v1/${admin ? 'admin' : 'me'}/official-record-batches',
        );
        await tester.tap(find.text('닫기'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('학교 문서 검색·근거'));
        await tester.pumpAndSettle();
        expect(paths.last, '/api/v1/catalog/institutions');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('application review hides applicant after permission failure', (
    tester,
  ) async {
    final applicant = {
      ...applications.record(),
      'applicant_id': otherId,
      'applicant': {
        'id': otherId,
        'email': 'staff@example.test',
        'display_name': '신청 담당자',
        'role': 'user',
        'account_status': 'active',
        'version': 3,
      },
    };
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return source.json({
            ...identityJson(role: 'super_admin'),
            'access_token': token,
          });
        }
        if (request.method == 'POST') return source.json({}, 403);
        if (request.url.path.endsWith('/${applications.application}')) {
          return source.json(applicant);
        }
        return source.json({
          'items': [applicant],
          'next_cursor': null,
        });
      }),
    );
    addTearDown(auth.close);
    final identity = await auth.authenticate(
      email: 'admin@example.test',
      password: 'synthetic password',
    );
    await applications.open(tester, auth, identity);
    await tester.tap(find.text('검증 대학 · 승인 대기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신청자 신원을 별도로 확인했습니다'));
    await tester.tap(find.text('해당 학교 담당자 자격을 확인했습니다'));
    await tester.enterText(
      find.widgetWithText(TextField, '검토 사유 (신청자에게 표시)'),
      '검토 완료',
    );
    await tester.tap(find.text('승인·학교 범위 부여'));
    await tester.pumpAndSettle();
    expect(find.textContaining('staff@example.test'), findsNothing);
    expect(find.textContaining('신청 담당자'), findsNothing);
    expect(find.text('승인·학교 범위 부여'), findsNothing);
    expect(find.textContaining('현재 권한으로 이 신청을 검토할 수 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('core dialogs fit minimum window with 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return source.json({...identityJson(), 'access_token': token});
        }
        return source.json({'items': [], 'next_cursor': null});
      }),
    );
    addTearDown(auth.close);
    final identity = await auth.authenticate(
      email: 'student@example.test',
      password: 'synthetic password',
    );
    for (final dialog in [
      SchoolAdminApplicationsDialog(auth: auth, identity: identity),
      OfficialSourcesDialog(auth: auth, ownerId: userId),
      OfficialRecordsDialog(auth: auth, ownerId: userId),
      SchoolDocumentSearchDialog(auth: auth, ownerId: userId),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showInputDialog<void>(
                  context: context,
                  builder: (_) => dialog,
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
  for (final kind in ['source', 'records']) {
    testWidgets(
      '$kind permission loss hides previously displayed detail and review actions',
      (tester) async {
        var denied = false;
        final auth = AuthApi(
          cookieMode: false,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login')) {
              return source.json({
                ...identityJson(role: 'school_admin'),
                'access_token': token,
              });
            }
            if (denied) return source.json({}, 403);
            if (request.url.path.contains('/catalog/')) {
              return source.json(catalog.catalogRow(request.url.path));
            }
            if (request.url.path.endsWith('/events')) {
              return source.json({'items': []});
            }
            return source.json(
              kind == 'source'
                  ? {...source.sourceJson(), 'owner_id': otherId}
                  : records.batchJson(owner: otherId),
            );
          }),
        );
        addTearDown(auth.close);
        await source.login(auth);
        await ui.launch(
          tester,
          kind == 'source'
              ? SourceReviewDialog(
                  api: RecordSourceApi.forOwner(auth, userId, admin: true),
                  source: RecordSource.fromJson({
                    ...source.sourceJson(),
                    'owner_id': otherId,
                  }),
                  actorId: userId,
                  admin: true,
                )
              : OfficialRecordReviewDialog(
                  auth: auth,
                  ownerId: userId,
                  admin: true,
                  batch: SchoolRecordBatchView.fromJson(
                    records.batchJson(owner: otherId),
                  ),
                ),
        );
        final sensitive = kind == 'source'
            ? find.textContaining('합성 성적.pdf')
            : find.textContaining('3.500001');
        expect(sensitive, findsOneWidget);
        denied = true;
        final reload = find.text(
          kind == 'source' ? '상세·검토 이력 다시 읽기' : '기록·이력 다시 읽기',
        );
        await tester.ensureVisible(reload);
        await tester.tap(reload);
        await tester.pumpAndSettle();
        expect(sensitive, findsNothing);
        expect(find.text('현재 계정이나 학교 범위로 이 자료를 확인할 수 없습니다.'), findsOneWidget);
        expect(find.text('원본 확인 승인'), findsNothing);
        expect(find.text('학생 기록 승인'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'graduation draft requires discard confirmation before personal settings',
    (tester) async {
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return source.json({...identityJson(), 'access_token': token});
          }
          if (request.url.path.contains('/catalog/')) {
            return source.json({
              'items': [catalog.catalogRow(request.url.path)],
              'next_cursor': null,
            });
          }
          return source.json({'items': [], 'next_cursor': null});
        }),
      );
      addTearDown(auth.close);
      await source.login(auth);
      var moved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfficialGraduationPage(
              auth: auth,
              ownerId: userId,
              onPersonal: () => moved = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '입학연도'), '2026');
      await tester.ensureVisible(find.text('내 학교·학과 기준 설정'));
      await tester.tap(find.text('내 학교·학과 기준 설정'));
      await tester.pumpAndSettle();
      expect(moved, false);
      expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
      await tester.tap(find.text('계속 작성'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '2026'), findsOneWidget);
      await tester.tap(find.text('내 학교·학과 기준 설정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('내용 폐기'));
      await tester.pumpAndSettle();
      expect(moved, true);
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in ['not_satisfied', 'needs_review', 'not_applicable']) {
    testWidgets('audit $status renders received rule and record evidence', (
      tester,
    ) async {
      final data = {
        ...audit.auditJson(),
        'status': status,
        'eligible_as_of': false,
        'criteria': [
          {
            'id': otherId,
            'version': 1,
            'rule_set_id': otherId,
            'rule_id': null,
            'source_version': 2,
            'name': '검토한 규정',
            'rules': [
              {
                'rule_id': otherId,
                'source_version': 2,
                'title': '근거 연결 규칙',
                'condition': {'kind': 'minimum_credits', 'minimum': '3'},
                'references': [],
                'evidence': [
                  {
                    'chunk_id': otherId,
                    'knowledge_document_id': otherId,
                    'knowledge_version': 2,
                    'document_id': otherId,
                    'document_version': 3,
                    'title': '공식 졸업 규정',
                    'source_url': 'https://example.test/rules.pdf',
                    'page': 4,
                    'content_hash': 'a' * 64,
                    'document_hash': 'b' * 64,
                  },
                ],
              },
            ],
          },
        ],
        'record_evidence': [
          {
            'record_id': otherId,
            'batch_id': otherId,
            'client_id': otherId,
            'kind': 'academics',
            'source_page': 2,
          },
        ],
      };
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return source.json({...identityJson(), 'access_token': token});
          }
          if (request.url.path.contains('/catalog/')) {
            return source.json({'items': [], 'next_cursor': null});
          }
          if (request.url.path.endsWith('/${audit.auditId}')) {
            return source.json(data);
          }
          return source.json({
            'items': [data],
            'next_cursor': null,
          });
        }),
      );
      addTearDown(auth.close);
      await source.login(auth);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfficialGraduationPage(
              auth: auth,
              ownerId: userId,
              onPersonal: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final history = find.text('2026-10-21 · ${auditStatus(status)}');
      await tester.ensureVisible(history);
      await tester.tap(history);
      await tester.pumpAndSettle();
      expect(find.text('감사 결과 · ${auditStatus(status)}'), findsOneWidget);
      expect(find.text('공식 졸업 규정 · 4쪽 · 문서 판 3'), findsOneWidget);
      expect(find.text('규정 원문 확인 · 외부 열기'), findsOneWidget);
      expect(find.text('승인 기록 근거 · 원본 2쪽'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
