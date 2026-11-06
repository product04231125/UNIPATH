"""Static career entry points. Selecting a menu never sends personal data or calls a model."""

NODES = {
    "career": ("취업 분석", "home", "menu"),
    "career:recommend": ("내 자료로 공고 찾기", "career", "workflow"),
    "career:profile": ("내 자격증·경험 분석", "career", "workflow"),
    "career:posting": ("공고 1개와 비교", "career", "workflow"),
    "career:sources": ("공고 수집처 안내", "career", "content"),
}


def payload(node_id):
    if node_id == "career":
        return {
            "message": "원하는 직무·지역을 직접 선택하고 분석에 사용할 자격증·경험을 골라 주세요."
        }
    if node_id == "career:sources":
        return {
            "reason": "career_sources",
            "cards": [
                {
                    "type": "reference_text",
                    "title": "사람인 · 고용24(워크넷)",
                    "body": (
                        "공식 API 검색 어댑터가 준비되어 있습니다. "
                        "발급받은 인증키와 서버 연결이 필요합니다."
                    ),
                },
                {
                    "type": "reference_text",
                    "title": "잡코리아",
                    "body": "이용 승인 후 전용 호출 주소와 명세를 받아 연결해야 합니다.",
                },
            ],
        }
    if node_id in {"career:recommend", "career:profile", "career:posting"}:
        missing = ["records"]
        if node_id == "career:recommend":
            missing += ["job_keyword", "region"]
        if node_id == "career:posting":
            missing += ["posting_text"]
        return {
            "state": "needs_input",
            "reason": "career_inputs_required",
            "missing_fields": missing,
            "message": "분석에 사용할 내 자료와 검색·비교 조건을 선택해 주세요.",
            "workflow": {
                "id": node_id.split(":")[1],
                "requires_authenticated_user": True,
                "record_kinds": ["credential", "experience", "activity", "achievement", "course"],
                "job_selection": "user_selected",
                "region_selection": "user_selected",
                "steps": ["자료 선택", "직무·지역 또는 공고 입력", "분석 자료 확인", "결과 확인"],
            },
            "integration_state": "adapter_not_connected",
            "cards": [],
            "notice": "선택한 자료만 분석에 사용하며 메뉴 선택만으로 외부에 전송하지 않습니다.",
        }
    return {}
