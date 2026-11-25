import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/job_recommendation_api.dart';
import 'package:university_path_frontend/features/records/portfolio/job_recommendation_result.dart';
import 'package:university_path_frontend/features/writing/posting_link.dart';
import 'package:university_path_frontend/features/writing/writing_api.dart';

Map<String, dynamic> fixture() => jsonDecode(
  File('test/fixtures/job_recommendation_response.json').readAsStringSync(),
) as Map<String, dynamic>;

Map<String, dynamic> withPreferredFirst({bool metadataOnly = false}) {
  final json = fixture();
  final item = (json['items'] as List).first as Map<String, dynamic>;
  final required = (item['comparisons'] as List).first as Map;
  item['comparisons'] = [
    {
      ...required,
      'requirement_id': 'pref',
      'priority': 'preferred',
      'requirement': 'Docker 배포',
      'status': 'unknown_status',
      'personal_evidence': [],
    },
    required,
  ];
  if (metadataOnly) (item['posting'] as Map)['text_scope'] = 'metadata_only';
  return json;
}

void main() {
  test('a found posting links its text and its requirements, 필수 first', () {
    final entry = rankPostings(
      JobRecommendationResponse.fromJson(withPreferredFirst()),
    ).single;
    final at = DateTime.utc(2026, 11, 25, 1);
    final link = PostingLink.fromRanked(entry, analyzedAt: at);
    expect(link.title, 'Engineer');
    expect(link.company, 'Test');
    expect(link.text, 'Python required');
    expect(link.requirements.map((r) => r.requirement), [
      'Python',
      'Docker 배포',
    ]);
    // An unknown status from an older result is sent as unconfirmed.
    expect(link.requirements.last.status, 'insufficient_evidence');
    expect(link.requirements.first.records.single.kind, 'experience');
    expect(link.ready, 1);
    expect(link.toSource(), {
      'source': 'greenhouse',
      'source_id': 'example/1',
      'title': 'Engineer',
      'company': 'Test',
      'url': 'https://job-boards.greenhouse.io/example/jobs/1',
      'analyzed_at': '2026-11-25T01:00:00.000Z',
    });
    final again = PostingLink.fromSaved(
      link.toSource(),
      link.text,
      link.requirementsJson(),
    )!;
    expect(again.requirementsJson(), link.requirementsJson());
    expect(again.analyzedAt, at);
  });

  test('a posting known only by its listing sends no text', () {
    final entry = rankPostings(
      JobRecommendationResponse.fromJson(
        withPreferredFirst(metadataOnly: true),
      ),
    ).single;
    expect(PostingLink.fromRanked(entry).hasText, isFalse);
  });

  test('a saved document names the posting it was written for', () {
    final summary = WritingDocumentSummary.fromJson({
      'id': 'd',
      'title': '초안',
      'document_type': 'portfolio',
      'version': 1,
      'updated_at': '2026-11-25T01:00:00Z',
      'posting': {'title': '합성 신입', 'company': '합성 회사'},
    });
    expect(summary.postingLabel, '합성 회사 · 합성 신입');
  });

  testWidgets('each found posting offers a 자기소개서 and a 포트폴리오', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final written = <(PostingLink, WritingType)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: JobRecommendationResult(
              result: JobRecommendationResponse.fromJson(fixture()),
              onWrite: (link, type) => written.add((link, type)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final key = 'greenhouse/example/1';
    for (final type in WritingType.values) {
      final button = find.byKey(ValueKey('recommend-write-${type.value}-$key'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(written.map((w) => w.$2), WritingType.values);
    expect(written.first.$1.title, 'Engineer');
    expect(written.first.$1.requirements.single.requirement, 'Python');
  });
}
