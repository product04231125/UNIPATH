import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/academic_guidance_models.dart';

void main() {
  test('reference guidance keeps tables, sources and unreviewed OCR state', () {
    final value = AcademicGuidance.fromJson({
      'schema_version': 'academic-click-v3',
      'node_id': 'university:CDE_1:attachment:1:page:1',
      'title': '1쪽',
      'state': 'ready',
      'reason': 'university_pdf_page',
      'message': '안내',
      'cards': [
        {
          'type': 'regulation_page',
          'title': '합성 규정',
          'body': '본문',
          'sources': [
            {'type': 'official_pdf', 'page': 1, 'asset_id': 'a' * 64},
          ],
          'tables': [
            [
              ['구분', null],
            ],
          ],
          'extraction_status': 'ocr_unreviewed',
          'preferred_view': 'image',
          'image_asset_id': 'b' * 64,
        },
      ],
      'warnings': ['주의'],
      'buttons': [
        {
          'id': 'home',
          'label': '처음으로',
          'action': 'select_node',
          'node_id': 'home',
          'availability': 'available',
        },
      ],
    });
    final card = value.cards.single;
    expect(card.extractionStatus, 'ocr_unreviewed');
    expect(card.tables!.single.single.last, isNull);
    expect(card.sources.single.assetId, 'a' * 64);
    expect(value.buttons.single.nodeId, 'home');
  });

  test('unknown guidance states are rejected instead of shown as ready', () {
    expect(
      () => AcademicGuidance.fromJson({
        'schema_version': 'academic-click-v3',
        'node_id': 'home',
        'state': 'approved',
        'reason': 'menu',
        'message': '',
        'cards': const [],
        'warnings': const [],
        'buttons': const [],
      }),
      throwsFormatException,
    );
  });

  test('personalized guidance keeps school and personal material apart', () {
    final value = PersonalizedGuidanceResponse.fromJson({
      'query_id': '00000000-0000-4000-8000-000000000001',
      'status': 'evidence_only',
      'reason': 'generator_not_configured',
      'official': false,
      'school': {
        'query_id': '00000000-0000-4000-8000-000000000002',
        'status': 'insufficient_evidence',
        'reason': 'no_approved_matching_evidence',
      },
      'personal': {
        'official': false,
        'records': [
          {
            'kind': 'activity',
            'record_id': '00000000-0000-4000-8000-000000000003',
            'version': 1,
            'origin': 'personal',
            'official': false,
            'title': '합성 봉사',
            'text': 'title: 합성 봉사',
            'truncated': false,
          },
        ],
      },
    });
    expect(value.answer, isNull);
    expect(value.personal.records.single.origin, 'personal');
    expect(value.school.sources, isEmpty);
  });
}
