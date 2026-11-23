import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/word_export_gateway.dart';
import 'package:university_path_frontend/features/career/career_goal.dart';
import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';
import 'package:university_path_frontend/features/writing/writing_api.dart';
import 'package:university_path_frontend/features/writing/writing_page.dart';

const record = AiRecordOption(
  kind: 'experience',
  id: 'exp-id',
  version: 2,
  title: '합성 캡스톤 프로젝트',
);

Map<String, dynamic> cite(String excerpt) => {
  'kind': 'experience',
  'record_id': 'exp-id',
  'version': 2,
  'excerpt': excerpt,
};

Map<String, dynamic> ready() => {
  'status': 'draft_ready',
  'document_type': 'cover_letter',
  'mode': 'create',
  'draft': {
    'sections': [
      {
        'heading': '지원 직무와 관련된 경험을 적어 주세요.',
        'paragraphs': [
          {
            'text': '캡스톤 프로젝트에서 React로 일정 관리 화면을 만들었습니다.',
            'citations': [cite('React로 일정 관리 화면')],
          },
        ],
        'facts': [],
      },
    ],
    'questions_for_user': ['지원 동기를 알려 주세요.'],
    'revisions': [],
  },
  'original_record_ids': [],
  'document_sources': [],
  'warnings': ['기록에서 근거를 확인하지 못한 문단·항목 1개는 초안에서 뺐습니다.'],
  'notice': '초안입니다. 검토 후 내보내세요.',
};

class WritingGateway extends ApiGateway implements WordExportGateway {
  final posts = <Map<String, Object?>>[];
  final exports = <Map<String, Object?>>[];
  final results = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (path == 'me/career-goal') {
      return {
        'category_codes': ['024'],
        'keyword': '프론트엔드 개발',
        'version': 1,
        'category_label': '소프트웨어',
      };
    }
    expect((method, path), ('POST', 'me/writing-drafts'));
    posts.add(body!);
    return results.removeAt(0);
  }

  @override
  Future<Uint8List> exportWord(String path, Map<String, Object?> body) async {
    expect(path, 'me/writing-exports');
    exports.add(body);
    return Uint8List.fromList([0x50, 0x4B, 3, 4]);
  }
}

Future<(WritingGateway, Map<String, String>, List<String>)> mountWriting(
  WidgetTester tester, {
  List<Map<String, dynamic>> results = const [],
  Map<String, String> saved = const {},
  WritingRequest? request,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = WritingGateway()..results.addAll(results);
  final consent = AiConsentPreferences(
    ownerId: 'owner',
    reader: (_) async => null,
    writer: (_, _) async => true,
  );
  await consent.load();
  await consent.setAllowed(AiConsentFeature.writing, true);
  addTearDown(consent.dispose);
  final goal = CareerGoalController(api);
  addTearDown(goal.dispose);
  await goal.load();
  final storage = {...saved};
  final files = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WritingPage(
          api: StudentApi(api, ownerId: 'owner'),
          consent: consent,
          careerGoal: goal,
          request: request,
          store: WritingSessionStore(
            ownerId: 'owner',
            reader: (key) async => storage[key],
            writer: (key, value) async {
              storage[key] = value;
              return true;
            },
          ),
          loadRecords: () async => [record],
          saveFile: (bytes, name) async {
            files.add(name);
            return true;
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (api, storage, files);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('자기소개서 초안은 모든 기록과 문항을 보내고 근거와 함께 편집하게 한다', (tester) async {
    final (api, storage, _) = await mountWriting(
      tester,
      results: [ready()],
      request: WritingRequest(postingText: '담당업무: React 화면 개발'),
    );
    // The saved target job and the analyzed posting are filled in.
    expect(find.text('프론트엔드 개발'), findsOneWidget);
    expect(find.text('담당업무: React 화면 개발'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('writing-company')),
      '합성 회사',
    );
    await tester.enterText(
      find.byKey(const ValueKey('writing-question-0')),
      '지원 직무와 관련된 경험을 적어 주세요.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('writing-char-limit')),
      '60',
    );
    await tapKey(tester, 'writing-run');
    expect(find.text('문항별 글자 수는 200~5,000자로 입력해 주세요.'), findsOneWidget);
    expect(api.posts, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('writing-char-limit')),
      '200',
    );
    await tapKey(tester, 'writing-run');
    expect(api.posts.single, {
      'document_type': 'cover_letter',
      'mode': 'create',
      'target_role': '프론트엔드 개발',
      'target_company': '합성 회사',
      'posting_text': '담당업무: React 화면 개발',
      'questions': ['지원 직무와 관련된 경험을 적어 주세요.'],
      'char_limit': 200,
      'original_text': '',
      'records': [
        {'kind': 'experience', 'record_id': 'exp-id', 'expected_version': 2},
      ],
      'documents': [],
      'external_processing_consent': true,
    });
    expect(find.text('자기소개서 초안 · 합성 회사'), findsOneWidget);
    expect(find.text('· 지원 동기를 알려 주세요.'), findsOneWidget);
    expect(find.text('기록에서 근거를 확인하지 못한 문단·항목 1개는 초안에서 뺐습니다.'), findsOneWidget);
    expect(find.text('35자 / 200자 (공백 포함)'), findsOneWidget);

    await tester.tap(find.text('근거 1개 보기'));
    await tester.pumpAndSettle();
    expect(find.text('경험 · 합성 캡스톤 프로젝트: React로 일정 관리 화면'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('writing-paragraph-0-0')),
      '고친 문장',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('5자 / 200자 (공백 포함)'), findsOneWidget);
    // The edit is kept on this device and restored next time.
    expect(storage.values.single, contains('고친 문장'));
  });

  testWidgets('저장된 초안을 불러오고 검토 확인 후 Word로 받는다', (tester) async {
    final (first, storage, _) = await mountWriting(tester, results: [ready()]);
    await tapKey(tester, 'writing-run');
    expect(first.posts.single['questions'], isEmpty);
    await tester.pumpWidget(const SizedBox());

    final (api, _, files) = await mountWriting(tester, saved: storage);
    expect(find.text('이 기기에 저장된 마지막 초안을 불러왔습니다.'), findsOneWidget);
    expect(find.text('캡스톤 프로젝트에서 React로 일정 관리 화면을 만들었습니다.'), findsOneWidget);

    await tapKey(tester, 'writing-export');
    await tapKey(tester, 'writing-export-confirm');
    expect(find.text('문서 첫 줄에 넣을 이름을 1~120자로 입력해 주세요.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('writing-export-name')),
      '가상 지원자',
    );
    await tapKey(tester, 'writing-export-confirm');
    expect(find.text('초안을 검토했는지 확인해 주세요.'), findsOneWidget);
    await tapKey(tester, 'writing-export-reviewed');
    await tapKey(tester, 'writing-export-confirm');

    final body = api.exports.single;
    expect(body['document_type'], 'cover_letter');
    expect(body['reviewed'], true);
    expect((body['profile'] as Map)['name'], '가상 지원자');
    final section = ((body['draft'] as Map)['sections'] as List).single as Map;
    expect(section['heading'], '지원 직무와 관련된 경험을 적어 주세요.');
    expect(files, ['cover-letter.docx']);
    expect(find.text('Word 파일을 저장했습니다.'), findsOneWidget);
  });

  testWidgets('근거를 확인하지 못해 실패하면 이유를 보여 주고 입력을 유지한다', (tester) async {
    final (api, _, _) = await mountWriting(
      tester,
      results: [
        {
          'status': 'failed',
          'failure_reason': 'personal_citation',
          'document_type': 'portfolio',
          'mode': 'create',
        },
      ],
    );
    await tapKey(tester, 'writing-type');
    await tester.tap(find.text('포트폴리오'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('writing-question-0')), findsNothing);
    await tapKey(tester, 'writing-run');
    expect(api.posts.single['document_type'], 'portfolio');
    expect(api.posts.single['char_limit'], isNull);
    expect(find.textContaining('근거를 확인한 문장이 없어'), findsOneWidget);
    expect(find.byKey(const ValueKey('writing-draft')), findsNothing);
    expect(find.text('프론트엔드 개발'), findsOneWidget);
  });

  test('Word 내보내기는 로그인한 계정의 연결에서만 한다', () async {
    final api = StudentApi(_PlainGateway(), ownerId: 'owner');
    await expectLater(
      WritingApi(api).exportWord(
        WritingType.portfolio,
        const WritingDraft(sections: []),
        name: '가상',
      ),
      throwsA(isA<AuthFailure>()),
    );
  });
}

class _PlainGateway extends ApiGateway {
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async => null;
}
