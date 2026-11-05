import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/rule_program_api.dart';
import 'package:university_path_frontend/features/api/rule_program_models.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

const identifier = '00000000-0000-4000-8000-000000000001';
const scope = OfficialSelectionContext(
  institutionId: identifier,
  departmentId: identifier,
  curriculumId: identifier,
  admissionYear: 2026,
  track: 'single_major',
);

class Gateway implements ApiGateway {
  Map<String, dynamic> response = {};
  final requests = <(String, String, Map<String, Object?>?)>[];
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    requests.add((method, path, body));
    return response;
  }
}

Map<String, dynamic> program() => {
  'id': identifier,
  'institution_id': identifier,
  'department_id': null,
  'curriculum_id': null,
  'name': '합성 실행 규칙',
  'rule_set_id': identifier,
  'rule_id': null,
  'source_version': 2,
  'version': 2,
  'admission_year_from': 2026,
  'admission_year_to': 2026,
  'tracks': ['single_major'],
  'effective_from': null,
  'effective_to': null,
  'status': 'approved',
  'created_at': '2026-10-19T00:00:00Z',
  'updated_at': '2026-10-19T00:00:00Z',
  'approved_at': '2026-10-19T00:00:00Z',
  'revoked_at': null,
  'rules': [
    {
      'rule_id': identifier,
      'source_version': 2,
      'title': '합성 학점',
      'condition': {'kind': 'minimum_credits', 'minimum': '3'},
      'references': [],
      'evidence': [
        {
          'chunk_id': identifier,
          'knowledge_document_id': identifier,
          'knowledge_version': 3,
          'document_id': identifier,
          'document_version': 2,
          'title': '합성 규정',
          'source_url': 'https://school.example.invalid/rules',
          'page': 1,
          'content_hash': 'a' * 64,
          'document_hash': 'b' * 64,
          'excerpt': '합성 원문 근거',
        },
      ],
    },
  ],
};

Map<String, dynamic> selection() => {
  'context': scope.toJson(),
  'as_of': '2026-10-19',
  'status': 'available',
  'reason': 'registered_programs_available',
  'catalog_complete': false,
  'programs': [program()],
  'issues': [],
};

Map<String, dynamic> certificate() => {
  'id': identifier,
  'provider_id': identifier,
  'code': 'SYN',
  'name': '합성 자격',
  'official_url': 'https://certificate.example.invalid',
  'version': 1,
  'status': 'active',
  'created_at': '2026-10-19T00:00:00Z',
  'updated_at': '2026-10-19T00:00:00Z',
};

void main() {
  test('closed condition types preserve decimals and versioned identities', () {
    final values = <Map<String, dynamic>>[
      {'kind': 'minimum_credits', 'minimum': '130.001', 'category': null},
      {
        'kind': 'required_courses',
        'courses': [
          {
            'course_id': identifier,
            'expected_version': 7,
            'minimum_credits': '3',
            'minimum_grade_points': '2.5',
            'comparison_grade_scale': '4.5',
          },
        ],
      },
      {'kind': 'minimum_volunteer_hours', 'minimum': '10'},
      {
        'kind': 'any_certificate',
        'certificates': [
          {'certificate_id': identifier, 'expected_version': 5},
        ],
      },
      {
        'kind': 'thesis',
        'thesis_type': 'graduation',
        'requires_approval': true,
        'accepted_grades': ['PASS'],
      },
      {'kind': 'manual_review', 'instruction': '원본 별도 확인 필요'},
    ];
    for (final value in values) {
      final condition = OfficialCondition.fromJson(value);
      expect(condition.toJson(), value);
    }
    expect(
      OfficialCondition.fromJson(values[0]),
      isA<OfficialCreditCriterion>(),
    );
    final course =
        OfficialCondition.fromJson(values[1]) as OfficialCourseCriterion;
    expect(course.courses.single.expectedVersion, 7);
    expect(
      () => OfficialCondition.fromJson({'kind': 'python_expression'}),
      throwsFormatException,
    );
  });

  test(
    'selection sends explicit context and retains incomplete coverage',
    () async {
      final gateway = Gateway()..response = selection();
      final result = await OfficialProgramApi(gateway)
          .select(scope, on: '2026-10-19');
      final (method, path, body) = gateway.requests.single;
      expect(method, 'GET');
      expect(body, isNull);
      final uri = Uri.parse(path);
      expect(uri.path, 'catalog/rule-programs');
      expect(uri.queryParameters['admission_year'], '2026');
      expect(uri.queryParameters['curriculum_id'], identifier);
      expect(result.catalogComplete, isFalse);
      expect(
        result.programs.single.rules.single.condition,
        isA<OfficialCreditCriterion>(),
      );
    },
  );

  test('unmapped and manual requirements stay visible', () async {
    final gateway = Gateway()
      ..response = {
        ...selection(),
        'status': 'needs_review',
        'reason': 'rule_program_review_required',
        'programs': [],
        'issues': [
          {
            'kind': 'rule',
            'record_id': identifier,
            'reason': 'execution_program_required',
          },
          {
            'kind': 'rule_set',
            'record_id': identifier,
            'reason': 'manual_requirement',
          },
        ],
      };
    final result = await OfficialProgramApi(gateway).select(scope);
    expect(result.issues.map((issue) => issue.reason), [
      'execution_program_required',
      'manual_requirement',
    ]);
  });

  test(
    'false completeness claims and unapproved or unsafe evidence are rejected',
    () async {
      final gateway = Gateway();
      final api = OfficialProgramApi(gateway);
      for (final invalid in [
        {...selection(), 'catalog_complete': true},
        {...selection(), 'programs': []},
        {...selection(), 'status': 'satisfied'},
        {
          ...selection(),
          'programs': [
            {...program(), 'status': 'draft'},
          ],
        },
      ]) {
        gateway.response = invalid;
        await expectLater(api.select(scope), throwsFormatException);
      }
      final invalid = program();
      (((invalid['rules'] as List).single as Map)['evidence'] as List)
              .single['source_url'] =
          'https://user:secret@example.invalid';
      gateway.response = invalid;
      await expectLater(api.get(identifier), throwsFormatException);
    },
  );

  test(
    'review request preserves attestations and does not approve automatically',
    () async {
      final gateway = Gateway()
        ..response = {
          ...program(),
          'approved_by': identifier,
          'review_note': '합성 검토',
          'revoked_by': null,
          'revocation_reason': '',
          'missing_rule_ids': [],
          'usable': true,
        };
      await OfficialProgramAdminApi(gateway).approve(
        identifier,
        const OfficialProgramApprove(
          expectedVersion: 2,
          conditionsVerified: false,
          sourcesVerified: true,
          applicabilityVerified: true,
          completeSourceContextVerified: true,
          reviewNote: '검토 전송',
        ),
      );
      expect(gateway.requests.single.$3!['conditions_verified'], isFalse);
      expect(gateway.requests.single.$3!['expected_version'], 2);
      expect(
        gateway.requests.single.$2,
        'admin/rule-programs/$identifier/approve',
      );
    },
  );

  test(
    'certificate catalog and admin mutations use separate scoped routes',
    () async {
      final gateway = Gateway()
        ..response = {
          'items': [certificate()],
          'next_cursor': null,
        };
      final result = await CertificateCatalogApi(gateway)
          .certificates(providerId: identifier);
      expect(result.items.single.providerId, identifier);
      expect(gateway.requests.last.$2, startsWith('catalog/certificates?'));
      gateway.response = certificate();
      await CertificateRegistryAdminApi(gateway)
          .setCertificateActive(identifier, false, expectedVersion: 3);
      expect(
        gateway.requests.last.$2,
        'admin/certificates/$identifier/deactivate',
      );
      expect(gateway.requests.last.$3, {'expected_version': 3});
    },
  );
}
