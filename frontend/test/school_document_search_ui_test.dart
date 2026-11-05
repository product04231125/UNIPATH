import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/graduation/school_document_search_dialog.dart';

import 'official_graduation_ui_test.dart' as catalog;
import 'official_sources_ui_test.dart' as ui;
import 'record_source_api_test.dart' as source;
import 'school_knowledge_api_test.dart' as knowledge;
import 'support/auth_fixture.dart';

void main() {
  for (final size in [const Size(1440, 900), const Size(480, 720)]) {
    for (final status in [
      'evidence_found',
      'insufficient_evidence',
      'needs_user_input',
      'failed',
    ]) {
      testWidgets(
        'school document search renders $status with explicit scope $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          Map<String, dynamic>? sent;
          final auth = AuthApi(
            cookieMode: false,
            client: MockClient((request) async {
              if (request.url.path.endsWith('/login')) {
                return source.json({...identityJson(), 'access_token': token});
              }
              expect(request.headers['X-Unipath-Owner'], userId);
              if (request.url.path.contains('/catalog/')) {
                return source.json({
                  'items': [catalog.catalogRow(request.url.path)],
                  'next_cursor': null,
                });
              }
              expect(request.url.path, '/api/v1/me/school-searches');
              sent = jsonDecode(request.body) as Map<String, dynamic>;
              return source.json({
                ...knowledge.evidence(),
                'status': status,
                'sources': status == 'evidence_found'
                    ? knowledge.evidence()['sources']
                    : [],
                'missing_fields': status == 'needs_user_input'
                    ? ['admission_year', 'track']
                    : [],
              });
            }),
          );
          addTearDown(auth.close);
          await source.login(auth);
          await ui.launch(
            tester,
            SchoolDocumentSearchDialog(auth: auth, ownerId: userId),
          );
          await catalog.choose(tester, '학교 선택', '검증 대학');
          await catalog.choose(tester, '학과 선택', '검증 학과');
          final question = find.widgetWithText(TextField, '검색 질문');
          await tester.ensureVisible(question);
          await tester.enterText(question, '봉사 규정은?');
          await tester.tap(find.text('학교 문서 검색'));
          await tester.pumpAndSettle();
          expect(sent!['question'], '봉사 규정은?');
          expect(sent!['context'], {
            'institution_id': otherId,
            'department_id': otherId,
            'curriculum_id': null,
            'admission_year': null,
            'track': null,
          });
          if (status == 'evidence_found') {
            expect(find.text('합성 공식 규정 · 1쪽'), findsOneWidget);
            expect(find.text('합성 검색 발췌'), findsOneWidget);
            expect(find.text('공식 원문 확인 · 외부 열기'), findsOneWidget);
            await tester.ensureVisible(question);
            await tester.enterText(question, '다른 질문');
            await tester.pumpAndSettle();
            expect(find.text('합성 검색 발췌'), findsNothing);
          } else if (status == 'needs_user_input') {
            expect(find.text('추가 확인: 입학연도, 이수 경로'), findsOneWidget);
          } else if (status == 'insufficient_evidence') {
            expect(find.textContaining('조건에 맞는 승인 근거가 부족합니다.'), findsOneWidget);
          } else {
            expect(find.textContaining('문서 검색을 완료하지 못했습니다.'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('failed search retains question and context for explicit retry', (
    tester,
  ) async {
    final attempts = <Map<String, dynamic>>[];
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
        attempts.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (attempts.length == 1) {
          throw http.ClientException('synthetic offline');
        }
        return source.json(knowledge.evidence());
      }),
    );
    addTearDown(auth.close);
    await source.login(auth);
    await ui.launch(
      tester,
      SchoolDocumentSearchDialog(auth: auth, ownerId: userId),
    );
    await catalog.choose(tester, '학교 선택', '검증 대학');
    await catalog.choose(tester, '학과 선택', '검증 학과');
    await tester.ensureVisible(find.widgetWithText(TextField, '검색 질문'));
    await tester.enterText(find.widgetWithText(TextField, '검색 질문'), '봉사 조건 확인');
    await tester.tap(find.text('학교 문서 검색'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '봉사 조건 확인'), findsOneWidget);
    expect(find.textContaining('검색 질문과 학교 선택을 유지했습니다.'), findsOneWidget);
    await tester.tap(find.text('학교 문서 검색'));
    await tester.pumpAndSettle();
    expect(attempts, hasLength(2));
    expect(attempts.first, attempts.last);
    expect(find.text('합성 검색 발췌'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
