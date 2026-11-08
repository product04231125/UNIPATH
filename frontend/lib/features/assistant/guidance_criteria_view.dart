import 'package:flutter/material.dart';

import '../api/rule_program_models.dart';
import '../api/academic_guidance_models.dart';
import 'guidance_sources.dart';
import 'assistant_conversation.dart';

/// Displays approved definitions, never a student's evaluation or a computed total.
class GuidanceCriteriaView extends StatelessWidget {
  const GuidanceCriteriaView({super.key, required this.conversation});
  final AssistantConversation conversation;

  @override
  Widget build(BuildContext context) {
    final selection = conversation.guidanceCriteria;
    final kind =
        AssistantConversation.criteriaKinds[conversation.guidance?.nodeId];
    final rules = [
      for (final program in selection?.programs ?? <OfficialPublicProgram>[])
        for (final rule in program.rules)
          if (rule.condition.kind == kind) (program: program, rule: rule),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (conversation.criteriaError != null) ...[
          Text(conversation.criteriaError!),
          TextButton(
            onPressed: conversation.openSettings,
            child: const Text('학업 정보 확인'),
          ),
          TextButton(
            onPressed: conversation.guidanceLoading
                ? null
                : () => conversation.navigateGuidance(
                    conversation.guidanceNodeId,
                  ),
            child: const Text('기준 다시 읽기'),
          ),
        ] else if (selection != null) ...[
          Text(
            '${conversation.context.institution ?? '등록 학교'} · ${conversation.context.department ?? '등록 학과'} · ${selection.context.admissionYear}학번 · ${const {'single_major': '단일전공', 'double_major': '복수전공'}[selection.context.track] ?? selection.context.track}',
          ),
          const SizedBox(height: 12),
          if (rules.isEmpty)
            Text(
              selection.reason == 'rule_catalog_limit_exceeded'
                  ? '조회 범위를 확인하지 못했습니다. 학교 관리자에게 기준 목록 확인을 요청해 주세요.'
                  : '이 항목의 승인된 기준이 아직 조회되지 않습니다. 학교 관리자의 기준 등록·검토가 필요합니다.',
            ),
          if (rules.isNotEmpty && selection.status != 'available')
            const Text('일부 기준의 검토가 남아 있습니다. 현재 조회된 항목만 표시합니다.'),
          for (final item in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.rule.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(_definition(item.rule)),
                  for (final source in item.rule.evidence) ...[
                    SelectableText(source.excerpt),
                    Text(
                      '${source.title} · ${source.page}페이지',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ],
              ),
            ),
          GuidanceSources(
            sources: [
              for (final item in rules)
                for (final source in item.rule.evidence)
                  GuidanceSource(
                    title: source.title,
                    sourceUrl: source.sourceUrl,
                    page: source.page,
                    documentId: source.documentId,
                  ),
            ],
            conversation: conversation,
          ),
        ],
      ],
    );
  }

  String _definition(OfficialProgramRuleView rule) {
    final condition = rule.condition;
    return switch (condition) {
      OfficialCreditCriterion() =>
        '필요 학점: ${condition.minimum}학점${condition.category == null ? '' : ' · ${condition.category}'}',
      OfficialVolunteerCriterion() => '필요 봉사시간: ${condition.minimum}시간',
      OfficialCourseCriterion() => [
        for (final course in condition.courses)
          '${_name(rule, course.courseId)}${course.minimumCredits == null ? '' : ' · ${course.minimumCredits}학점 이상'}${course.minimumGradePoints == null ? '' : ' · 평점 ${course.minimumGradePoints} 이상 (${course.comparisonGradeScale ?? '평점 체계 확인 필요'})'}',
      ].join('\n'),
      OfficialCertificateCriterion() =>
        '다음 자격 중 하나\n${[for (final certificate in condition.certificates) _name(rule, certificate.certificateId)].join('\n')}',
      OfficialThesisCriterion() =>
        '${condition.thesisType}${condition.requiresApproval ? ' · 승인 필요' : ''}${condition.acceptedGrades.isEmpty ? '' : '\n인정 등급: ${condition.acceptedGrades.join(', ')}'}',
      OfficialManualCriterion() => condition.instruction,
    };
  }

  String _name(OfficialProgramRuleView rule, String id) =>
      rule.references.where((ref) => ref.recordId == id).firstOrNull?.name ??
      '항목명 확인 필요';
}
