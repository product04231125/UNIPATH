"""Deterministic result guidance; the Rule Engine's historical decision is preserved."""

from app.schemas import graduation as dto

SUMMARIES = {
    "satisfied": "기준일의 검토 자료로 등록된 졸업요건을 충족했습니다.",
    "not_satisfied": "기준일의 검토 자료에서 충족하지 못한 졸업요건이 있습니다.",
    "needs_review": "자료 또는 조건이 부족해 추가 확인이 필요합니다.",
    "not_applicable": "적용 가능한 공식 졸업요건이 없어 판정을 안내할 수 없습니다.",
}


def render(audit: dto.GraduationAuditView) -> dto.GraduationGuidance:
    evidence = {
        (program.id, rule.rule_id): rule.evidence
        for program in audit.criteria
        for rule in program.rules
    }
    records = {item.record_id: item for item in audit.record_evidence}
    requirements = [
        dto.GraduationRequirementGuidance(
            **result.model_dump(),
            evidence=evidence.get((result.rule_set_id, result.rule_id), []),
            record_evidence=[
                records[identifier]
                for identifier in result.evidence_record_ids
                if identifier in records
            ],
        )
        for result in audit.results
    ]
    next_steps = []
    if not audit.current_usable:
        next_steps.append(
            "현재 근거의 변경·회수와 추가 확인 사항을 확인한 뒤 감사를 다시 실행하세요."
        )
    if audit.status == "not_applicable" or not audit.catalog_complete:
        next_steps.append("학교 담당자에게 적용되는 전체 졸업요건의 등록·검토를 요청하세요.")
    if any(item.status == "not_satisfied" for item in requirements):
        next_steps.append("미충족 항목의 부족 수치와 필수 과목을 확인하고 이수 계획을 세우세요.")
    if audit.status == "needs_review" or any(
        item.status == "needs_review" for item in requirements
    ):
        next_steps.append("확인 필요 항목의 조건과 학교 승인 기록을 보완하세요.")
    summary = SUMMARIES[audit.status]
    if not audit.current_usable:
        summary = "현재 안내에는 재확인이 필요합니다. 과거 기준일 결과: " + summary
    return dto.GraduationGuidance(
        audit_id=audit.id,
        context=audit.context,
        evaluated_on=audit.evaluated_on,
        status=audit.status,
        reason=audit.reason,
        current_usable=audit.current_usable,
        summary=summary,
        requirements=requirements,
        issues=list(
            {
                (item.kind, item.reason): item for item in [*audit.issues, *audit.current_issues]
            }.values()
        ),
        next_steps=next_steps,
    )
