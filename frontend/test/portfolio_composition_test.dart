import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/career/career_gap.dart';
import 'package:university_path_frontend/features/writing/portfolio_composition.dart';
import 'package:university_path_frontend/features/writing/writing_api.dart';

const web = AiRecordOption(
  kind: 'experience',
  id: 'web',
  version: 1,
  title: '합성 웹 프로젝트',
);
const db = AiRecordOption(
  kind: 'course',
  id: 'db',
  version: 2,
  title: '합성 데이터베이스',
);

Map<String, dynamic> requirement(
  String text,
  int frequency,
  String status,
  List<String> ids,
) => {
  'requirement_id': text,
  'requirement': text,
  'category': 'skill',
  'frequency': frequency,
  'postings': [],
  'status': status,
  'personal_evidence': [
    for (final id in ids)
      {'kind': 'experience', 'record_id': id, 'version': 1, 'excerpt': '합성'},
  ],
  'explanation': '합성 설명',
  'actions': [],
};

Map<String, dynamic> gap() => {
  'status': 'completed',
  'goal': {'label': '소프트웨어', 'keyword': ''},
  'postings': [
    for (var i = 1; i <= 3; i++)
      {
        'posting': i,
        'source': 'work24',
        'title': '합성 공고 $i',
        'company': '합성 회사',
        'url': 'https://example.test/$i',
      },
  ],
  'requirements': [
    requirement('SQL 활용', 2, 'supported', ['db']),
    requirement('Docker 배포', 3, 'insufficient_evidence', []),
    requirement('React 화면 개발', 3, 'supported', ['web', 'gone']),
  ],
};

class Gateway extends ApiGateway {
  final bodies = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (path == 'me/analysis-results?kind=gap') {
      return {
        'items': [
          {
            'id': 'old',
            'kind': 'gap',
            'title': '예전',
            'created_at': '2026-11-01T00:00:00Z',
          },
          {
            'id': 'new',
            'kind': 'gap',
            'title': '최근',
            'created_at': '2026-11-24T00:00:00Z',
          },
        ],
      };
    }
    if (path == 'me/analysis-results/new') {
      return {'id': 'new', 'kind': 'gap', 'title': '최근', 'result': gap()};
    }
    bodies.add(body!);
    return {'status': 'failed', 'failure_reason': 'model_timeout'};
  }
}

void main() {
  test('groups follow posting frequency and keep only cited saved records', () {
    final groups = composeFromGap(GapReport.fromJson(gap()), [web, db]);
    expect(groups.map((g) => g.requirement), ['React 화면 개발', 'SQL 활용']);
    // A record deleted since the analysis is left out; requirements without records too.
    expect(groups.first.records, [web]);
    expect(groups.first.frequency, 3);
    expect(groups.first.postings, 3);
  });

  testWidgets(
    'builds from the newest analysis, edits and sends only sent records',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = Gateway();
      var groups = <CompositionGroup>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => PortfolioCompositionCard(
                api: StudentApi(gateway, ownerId: 'owner'),
                groups: groups,
                loadRecords: () async => [web, db],
                onChanged: (value) => setState(() => groups = value),
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('portfolio-composition-build')),
      );
      await tester.pumpAndSettle();
      expect(groups.map((g) => g.requirement), ['React 화면 개발', 'SQL 활용']);
      expect(find.text('공고 3건 중 3건'), findsOneWidget);
      // Move SQL up, then drop its only record: the group disappears.
      await tester.tap(find.byTooltip('위로').last);
      await tester.pumpAndSettle();
      expect(groups.first.requirement, 'SQL 활용');
      await tester.tap(find.byKey(const ValueKey('portfolio-record-0-db')));
      await tester.pumpAndSettle();
      expect(groups.map((g) => g.requirement), ['React 화면 개발']);

      final input = WritingInput(
        type: WritingType.portfolio,
        targetRole: '프론트엔드',
        composition: [
          for (final g in groups) g.toJson(),
          {
            'requirement': '삭제된 기록만',
            'records': [
              {'kind': 'experience', 'record_id': 'gone'},
            ],
          },
        ],
      );
      await WritingApi(StudentApi(gateway, ownerId: 'owner'))
          .generate(input, records: [web, db]);
      expect(gateway.bodies.single['composition'], [
        {
          'requirement': 'React 화면 개발',
          'records': [
            {'kind': 'experience', 'record_id': 'web'},
          ],
        },
      ]);
      // A cover letter never sends a composition.
      final cover = WritingInput(
        type: WritingType.coverLetter,
        targetRole: '프론트엔드',
        composition: [groups.first.toJson()],
      );
      expect(cover.toJson().containsKey('composition'), isFalse);
    },
  );
}
