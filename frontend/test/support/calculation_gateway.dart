import 'dart:convert';

import 'package:university_path_frontend/features/api/personal_evaluation_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

import 'auth_fixture.dart';
import 'personal_gateway.dart';
import 'personal_workspace_fixture.dart';

const calculationResultId = '30000000-0000-4000-8000-000000000001';
String calculationRuleId(int index) =>
    '40000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}';

class CalculationGateway extends PersonalGateway {
  int ruleCount = 1;
  int linkCount = 1;
  bool loseResponse = false, failSources = false, badOwner = false;
  bool repeatSource = false, repeatHistory = false;
  String? ruleFrom = '2024-03-01', ruleTo = '2029-02-28';
  final saved = <String, Map<String, dynamic>>{};
  final posted = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final uri = Uri.parse(path);
    if (linkCount > 1 && uri.path == 'me/personal-curriculum-courses') {
      final list = await super.request(method, path, body);
      final row = (list!['items'] as List).single as Map;
      final start = uri.queryParameters['cursor'] == null
          ? 0
          : int.parse(uri.queryParameters['cursor']!.split('-').last);
      final end = (start + 100).clamp(0, linkCount);
      String id(int i) =>
          '50000000-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}';
      return {
        'items': [
          for (var i = start; i < end; i++) {...row, 'id': id(i)},
        ],
        'next_cursor': end < linkCount ? id(end - 1) : null,
      };
    }
    if (failSources && path.startsWith('me/activity-records')) {
      throw const AuthFailure('합성 통신 실패');
    }
    if (path ==
        'me/personal-curricula/${fixtureId(PersonalRecordKind.personalCurriculum)}') {
      calls.add((method, path, body));
      final list = await super.request(
        'GET',
        'me/personal-curricula?limit=100',
      );
      return Map<String, dynamic>.from((list!['items'] as List).single as Map);
    }
    if (uri.path == 'me/personal-graduation-rules') {
      final list = await super.request(method, path, body);
      final row = (list!['items'] as List).single as Map;
      return {
        'items': [
          for (var i = 0; i < ruleCount; i++)
            {
              ...row,
              'id': calculationRuleId(i),
              'title': '합성 규칙 ${i + 1}',
              'effective_from': ruleFrom,
              'effective_to': ruleTo,
            },
        ],
        'next_cursor': null,
      };
    }
    if (repeatSource && uri.path == 'me/course-records') {
      final list = await super.request(method, path, body);
      return {...list!, 'next_cursor': fixtureId(PersonalRecordKind.course)};
    }
    if (uri.path.startsWith('me/personal-evaluations')) {
      calls.add((method, path, body));
      if (method == 'POST') {
        final copy = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
        posted.add(copy);
        if (failWrites) throw const AuthFailure('합성 버전 충돌', status: 409);
        final calculations = copy['calculations'] as List;
        final value = saved.putIfAbsent(
          calculationResultId,
          () => {
            'id': calculationResultId,
            'owner_id': userId,
            'client_id': copy['client_id'],
            'version': 1,
            'curriculum_id': copy['curriculum_id'],
            'curriculum_version': 1,
            'curriculum_title': '합성 과정',
            'evaluated_on': copy['as_of'],
            'created_at': '2026-10-19T00:00:00Z',
            'official': false,
            'label': PersonalEvaluationSummary.personalLabel,
            'status': 'needs_review',
            'reason': 'record_data_needs_review',
            'results': [
              for (var i = 0; i < ruleCount; i++)
                {
                  'rule_id': calculationRuleId(i),
                  'rule_version': 1,
                  'title': '합성 규칙 ${i + 1}',
                  'status': 'needs_review',
                  'reason': 'explicit_condition_required',
                  'condition':
                      calculations
                          .where((c) => c['rule_id'] == calculationRuleId(i))
                          .isEmpty
                      ? null
                      : calculations.firstWhere(
                          (c) => c['rule_id'] == calculationRuleId(i),
                        )['condition'],
                },
            ],
            'source_versions': copy['expected_source_versions'],
          },
        );
        if (loseResponse) {
          loseResponse = false;
          throw const AuthFailure('합성 응답 유실');
        }
        return badOwner ? {...value, 'owner_id': otherId} : value;
      }
      if (method == 'DELETE') {
        saved.remove(uri.path.split('/').last);
        return null;
      }
      if (uri.path == 'me/personal-evaluations') {
        return {
          'items': saved.values.toList(),
          'next_cursor': repeatHistory ? calculationResultId : null,
        };
      }
      return saved[uri.path.split('/').last];
    }
    return super.request(method, path, body);
  }
}
