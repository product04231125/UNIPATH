"""Three evidence-grounded sentences; academic stage changes action focus, not ability."""

STAGES = {
    "year1": "기초 수업과 교내 활동에서 이 직무를 직접 경험하고 관심 분야를 확인하세요",
    "year2": "이번 방학에는 입문 교육과 첫 실습 프로젝트로 진로 후보를 좁히세요",
    "year3": "이번 방학에는 부족한 조건과 연결되는 프로젝트·현장실습을 우선하세요",
    "year4": "남은 학기에는 실무 교육·인턴·프로젝트 중 실행 가능한 활동으로 핵심 격차를 보완하세요",
    "graduate": (
        "충족 근거가 있는 공고와 추가 준비가 필요한 공고를 나누고 반복되는 부족분부터 보완하세요"
    ),
    None: "희망 직무와 준비 일정을 정하고 부족한 조건을 보여줄 수 있는 활동부터 계획하세요",
}


def build_guidance(item, stage=None):
    if stage not in STAGES:
        raise ValueError("Invalid academic stage")
    if item["analysis_status"] != "completed":
        sentences = [
            "공고와 자료의 비교가 완료되지 않아 현재 역량을 판단할 수 없습니다.",
            "분석 실패나 자료 부족을 역량 부족으로 해석하지 마세요.",
            "분석을 다시 시도하고 공고 원문과 제출 자료를 함께 확인하세요.",
        ]
        return {
            "academic_stage": stage,
            "state": "analysis_unavailable",
            "sentences": sentences,
            "comparison_refs": [],
        }
    values = item["comparisons"]
    supported = [c for c in values if c["status"] == "supported"]
    gaps = [c for c in values if c["status"] != "supported"]
    gaps.sort(key=lambda c: c["priority"] != "required")

    def label(c):
        return str(c.get("requirement", "공고 조건")).strip()[:120]

    current = (
        f"제출 자료에서 {len(supported)}개 조건의 충족 근거가 확인됩니다."
        if supported
        else "현재 제출 자료에서는 공고 조건을 충족하는 근거가 확인되지 않습니다."
    )
    if gaps:
        focus = " · ".join(label(c) for c in gaps[:2])
        gap = f"우선 확인할 격차는 「{focus}」이며 부분 근거나 확인되지 않은 항목이 포함됩니다."
        action = (
            f"「{label(gaps[0])}」의 보유·경험 여부와 제출 근거를 먼저 확인하고, {STAGES[stage]}."
        )
    else:
        gap = (
            "분석된 조건에서 추가 격차는 확인되지 않았지만 "
            "공고 전체의 지원자격을 보증하지는 않습니다."
        )
        action = (
            "이미 확보한 경험을 결과물과 역할 중심으로 정리하고 지원 일정과 증빙서류를 점검하세요."
        )
    return {
        "academic_stage": stage,
        "state": "needs_preparation" if gaps else "evidence_ready",
        "sentences": [current, gap, action],
        "comparison_refs": [c["requirement_id"] for c in gaps[:2] if "requirement_id" in c],
    }
