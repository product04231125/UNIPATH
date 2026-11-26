import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/shared/app_style.dart';
import 'package:university_path_frontend/features/api/guidance_api.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/assistant/academic_guidance_view.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/records/portfolio/job_analysis_page.dart';
import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';
import 'package:university_path_frontend/features/settings/ai_consent_section.dart';

/// Synthetic display fixtures only; never compiled into the product app.
class _VisualGateway extends ApiGateway {
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (path == 'me/personalized-guidance') {
      return {
        'query_id': 'q',
        'status': 'evidence_only',
        'reason': 'generator_not_configured',
        'official': false,
        'school': {
          'query_id': 's',
          'status': 'evidence_found',
          'reason': 'approved_sources_found',
          'sources': [
            {
              'chunk_id': 'c',
              'document_id': 'd',
              'title': '합성 사회봉사 안내',
              'source_url': 'https://example.invalid/volunteer',
              'page': 2,
              'excerpt': '사회봉사 활동의 인정 범위와 제출 절차를 확인합니다.',
            },
          ],
        },
        'personal': {
          'official': false,
          'records': [
            {
              'kind': 'activity',
              'record_id': 'a',
              'version': 2,
              'origin': 'personal',
              'official': false,
              'title': '학습 지원 봉사',
              'text': '지역 도서관에서 학습 자료 정리와 안내 활동에 참여했습니다.',
              'truncated': false,
            },
          ],
        },
      };
    }
    return {
      'schema_version': 'academic-click-v3',
      'node_id': 'scholarship',
      'title': '장학금·학자금 융자',
      'state': 'ready',
      'reason': 'scholarship_overview',
      'message': '장학 안내 항목을 선택하고 신청 조건을 원문에서 확인하세요.',
      'warnings': ['수집 시점의 게시 자료입니다. 현재 신청 기간과 조건은 원문을 확인해 주세요.'],
      'fetched_at': '2026-11-07T00:00:00Z',
      'cards': [
        {
          'type': 'reference_text',
          'title': '장학 신청 안내',
          'body': '장학 종류별 신청 기간과 제출 자료를 확인할 수 있습니다. 학생별 적용 여부는 담당 부서에 확인해 주세요.',
          'sources': [],
        },
        {
          'type': 'reference_table',
          'title': '신청 절차',
          'body': '단계별 준비 항목',
          'table': {
            'rows': [],
            'grid': [
              ['단계', '할 일'],
              ['1', '신청 공고 확인'],
              ['2', '제출 자료 준비'],
              ['3', '신청 결과 확인'],
            ],
          },
          'sources': [],
        },
      ],
      'buttons': [
        {
          'id': 'home',
          'label': '처음으로',
          'action': 'select_node',
          'node_id': 'home',
          'availability': 'available',
        },
        {
          'id': 'pending',
          'label': '추가 장학 안내',
          'action': 'select_node',
          'node_id': 'notices',
          'availability': 'content_pending',
        },
      ],
    };
  }
}

void main() {
  testWidgets('PR52 desktop visual matrix', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetDevicePixelRatio);
    final fonts = FontLoader('Pretendard')
      ..addFont(
        rootBundle.load('assets/fonts/pretendard/Pretendard-Regular.otf'),
      );
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final gateway = _VisualGateway();
    final permission = AiConsentPreferences(
      ownerId: 'visual-account',
      reader: (_) async => null,
      writer: (_, _) async => true,
    );
    await permission.load();
    await permission.setAllowed(AiConsentFeature.personalizedQuestion, true);
    final conversation =
        AssistantConversation(
          api: RegisteredAssistantApi(gateway),
          guidanceApi: GuidanceApi(gateway),
          consent: permission,
          registeredOnly: true,
          loadRecords: () async => [
            const AiRecordOption(
              kind: 'activity',
              id: 'a',
              version: 2,
              title: '학습 지원 봉사',
            ),
          ],
        )..setContext(
          const SchoolQueryContext(
            institution: '합성 대학교',
            department: '컴퓨터공학과',
            institutionId: 'school',
            departmentId: 'department',
            admissionYear: 2026,
            track: 'single_major',
          ),
        );
    conversation.setMode(AssistantMode.personalized);
    await conversation.refreshRecords();
    conversation.selectRecord('activity/a', true);
    conversation.input.text = '내 봉사 기록과 학교 안내를 함께 설명해 주세요.';
    await conversation.send();
    final output = Directory('../output/pr52-frontend-2026-11-08/visuals')
      ..createSync(recursive: true);
    Future<void> capture(String name, Widget child, AppPalette palette) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: universityPathTheme(palette: palette),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: Padding(padding: const EdgeInsets.all(24), child: child),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/${palette.name}-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final palette in AppPalette.values) {
      await capture(
        'chat-career',
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: JobAnalysisPage(
                api: StudentApi(gateway, ownerId: 'visual-account'),
                consent: permission,
                loadRecords: () async => [
                  const AiRecordOption(
                    kind: 'experience',
                    id: 'experience',
                    version: 1,
                    title: '팀 프로젝트 개발 경험',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            SizedBox(
              width: 420,
              child: AssistantPanel(
                conversation: conversation,
                onClose: () {},
                width: 420,
              ),
            ),
          ],
        ),
        palette,
      );
      await conversation.showGuidance();
      await capture(
        'academic',
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 960,
            child: SingleChildScrollView(
              child: AcademicGuidanceView(conversation: conversation),
            ),
          ),
        ),
        palette,
      );
      conversation.closeGuidance();
      await capture(
        'consent',
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 760,
            child: AiConsentSection(preferences: permission),
          ),
        ),
        palette,
      );
    }
    await tester.pumpWidget(const SizedBox());
    conversation.dispose();
    permission.dispose();
  }, skip: !const bool.fromEnvironment('PR52_CAPTURE'));
}
