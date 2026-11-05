import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:university_path_frontend/features/api/record_source_api.dart';
import 'package:university_path_frontend/features/api/official_records_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/official_record_editor.dart';
import 'package:university_path_frontend/features/records/official_records_dialog.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';

import 'official_graduation_ui_test.dart' as catalog;
import 'official_records_api_test.dart' as fixture;
import 'official_sources_ui_test.dart' as ui;
import 'record_source_api_test.dart' as source;
import 'support/auth_fixture.dart';

void main() {
  for (final kind in ['academics', 'volunteers', 'certificates', 'theses']) {
    testWidgets(
      'typed $kind row preserves unconfirmed data and master versions',
      (tester) async {
        final auth = AuthApi(
          cookieMode: false,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login')) {
              return fixture.json({
                ...identityJson(role: 'school_admin'),
                'access_token': token,
              });
            }
            return fixture.json({
              'items': [
                {
                  ...catalog.catalogRow(request.url.path),
                  'name': '검증 항목',
                  'code': 'TEST',
                  'credits': '3',
                  'status': 'active',
                  'provider_id': otherId,
                  'official_url': 'https://example.test',
                },
              ],
              'next_cursor': null,
            });
          }),
        );
        addTearDown(auth.close);
        await fixture.login(auth);
        SchoolRecordPayload? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showInputDialog<SchoolRecordPayload>(
                      context: context,
                      builder: (_) => OfficialRecordRowDialog(
                        api: auth.forOwner(userId),
                        institutionId: otherId,
                        kind: kind,
                      ),
                    );
                  },
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        if (kind == 'academics' || kind == 'certificates') {
          await catalog.choose(tester, '선택하세요', '검증 항목 (TEST) · 판 1');
        }
        await tester.enterText(find.widgetWithText(TextField, '원본 쪽'), '2');
        if (kind == 'academics') {
          await tester.enterText(
            find.widgetWithText(TextField, '취득 학점 (미확인 시 비움)'),
            '3.500001',
          );
        }
        if (kind == 'theses') {
          await tester.enterText(
            find.widgetWithText(TextField, '논문 유형'),
            '캡스톤',
          );
        }
        await tester.tap(find.text('대조 내용 반영'));
        await tester.pumpAndSettle();
        switch (result) {
          case SchoolRecordAcademicRecord r:
            expect(r.earnedCredits, '3.500001');
            expect(r.gradePoints, isNull);
            expect(r.expectedCourseVersion, 1);
          case SchoolRecordVolunteerRecord r:
            expect(r.approvedHours, isNull);
          case SchoolRecordCertificateRecord r:
            expect(r.validityKnown, false);
            expect(r.expiresOn, isNull);
            expect(r.expectedCertificateVersion, 1);
          case SchoolRecordThesisRecord r:
            expect(r.isCompleted, isNull);
            expect(r.thesisType, '캡스톤');
          default:
            fail('typed row missing');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final size in [const Size(1440, 900), const Size(480, 720)]) {
    testWidgets(
      'record draft keeps explicit reviewed context, exact amount and source at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Map<String, dynamic>? sent;
        final attempts = <Map<String, dynamic>>[];
        final auth = AuthApi(
          cookieMode: false,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login')) {
              return fixture.json({
                ...identityJson(role: 'school_admin'),
                'access_token': token,
              });
            }
            expect(request.headers['X-Unipath-Owner'], userId);
            if (request.url.path.contains('/catalog/')) {
              return fixture.json({
                'items': [catalog.catalogRow(request.url.path)],
                'next_cursor': null,
              });
            }
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            attempts.add(sent!);
            if (attempts.length == 1) {
              throw http.ClientException('synthetic offline');
            }
            return fixture.json({
              ...fixture.batchJson(owner: otherId),
              'source_id': source.sourceId,
              'client_id': sent!['client_id'],
              'kind': 'volunteers',
              'data': sent!['data'],
              'context': (sent!['data'] as Map)['context'],
              'status': 'draft',
              'usable_for_audit': false,
              'issues': ['not_approved'],
            }, 201);
          }),
        );
        addTearDown(auth.close);
        await fixture.login(auth);
        await ui.launch(
          tester,
          OfficialRecordEditor(
            auth: auth,
            ownerId: userId,
            source: RecordSource.fromJson({
              ...source.sourceJson(),
              'document_kind': 'volunteer',
              'owner_id': otherId,
              'status': 'verified',
            }),
          ),
        );
        await catalog.choose(tester, '학과 선택', '검증 학과');
        for (final entry in {
          '입학연도': '2026',
          '이수 경로': 'single_major',
          '원본 전체 쪽수': '2',
          '기록 기준일 (YYYY-MM-DD)': '2026-01-01',
        }.entries) {
          final f = find.widgetWithText(TextField, entry.key);
          await tester.ensureVisible(f);
          await tester.enterText(f, entry.value);
        }
        await tester.ensureVisible(find.text('대조한 기록 추가'));
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -250),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('대조한 기록 추가'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, '원본 쪽'), '2');
        await tester.enterText(
          find.widgetWithText(TextField, '승인 봉사시간 (미확인 시 비움)'),
          '3.500001',
        );
        await tester.tap(find.text('대조 내용 반영'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('검토 초안 저장'));
        await tester.pumpAndSettle();
        expect(find.textContaining('검토 내용과 입력을 유지했습니다.'), findsOneWidget);
        await tester.tap(find.text('검토 초안 저장'));
        await tester.pumpAndSettle();
        expect(attempts, hasLength(2));
        expect(attempts.first, attempts.last);
        expect(sent!['source_id'], source.sourceId);
        expect(sent!['expected_source_version'], 1);
        final data = sent!['data'] as Map;
        expect(data['kind'], 'volunteers');
        expect(data['coverage'], 'partial');
        expect((data['context'] as Map)['department_id'], otherId);
        expect((data['context'] as Map)['curriculum_id'], isNull);
        final row = (data['records'] as List).single as Map;
        expect(row['approved_hours'], '3.500001');
        expect(row['source_page'], 2);
        expect(row['approval_status'], 'needs_review');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'record approval requires independent review and uses version and source hash',
    (tester) async {
      Map<String, dynamic>? sent;
      var batch = {
        ...fixture.batchJson(owner: otherId),
        'status': 'draft',
        'usable_for_audit': false,
        'issues': ['not_approved'],
      };
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return fixture.json({
              ...identityJson(role: 'school_admin'),
              'access_token': token,
            });
          }
          if (request.url.path.contains('/catalog/')) {
            return fixture.json(catalog.catalogRow(request.url.path));
          }
          if (request.url.path.endsWith('/events')) {
            return fixture.json({'items': []});
          }
          if (request.method == 'POST') {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            batch = {
              ...batch,
              'status': 'approved',
              'usable_for_audit': true,
              'issues': [],
            };
          }
          return fixture.json(batch);
        }),
      );
      addTearDown(auth.close);
      await fixture.login(auth);
      await ui.launch(
        tester,
        OfficialRecordReviewDialog(
          auth: auth,
          ownerId: userId,
          admin: true,
          batch: SchoolRecordBatchView.fromJson(batch),
        ),
      );
      final approve = find.widgetWithText(FilledButton, '학생 기록 승인');
      expect(tester.widget<FilledButton>(approve).onPressed, isNull);
      for (final label in [
        '원본의 기록과 각 페이지 대응을 대조했습니다.',
        '학과·교육과정·입학연도·이수 경로를 확인했습니다.',
        '전체/일부 검토 범위를 확인했습니다.',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(sent, {
        'expected_version': 2,
        'expected_source_sha256': 'a' * 64,
        'records_reviewed': true,
        'context_reviewed': true,
        'coverage_reviewed': true,
        'replaces_batch_id': null,
        'expected_replaced_version': null,
      });
      expect(find.text('현재 졸업감사 입력으로 사용할 수 있는 기록입니다.'), findsOneWidget);
      expect(find.text('학생 기록 승인'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('student cannot approve or edit own school record', (
    tester,
  ) async {
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return fixture.json({...identityJson(), 'access_token': token});
        }
        expect(request.url.path.contains('/me/'), isTrue);
        expect(request.method, 'GET');
        if (request.url.path.contains('/catalog/')) {
          return fixture.json(catalog.catalogRow(request.url.path));
        }
        if (request.url.path.endsWith('/events')) {
          return fixture.json({'items': []});
        }
        return fixture.json(fixture.batchJson());
      }),
    );
    addTearDown(auth.close);
    await fixture.login(auth);
    await ui.launch(
      tester,
      OfficialRecordReviewDialog(
        auth: auth,
        ownerId: userId,
        admin: false,
        batch: SchoolRecordBatchView.fromJson(fixture.batchJson()),
      ),
    );
    expect(find.text('학생 기록 승인'), findsNothing);
    expect(find.text('검토 초안 수정'), findsNothing);
    expect(find.textContaining('3.500001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
