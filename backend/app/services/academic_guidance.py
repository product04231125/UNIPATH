"""Authenticated adapter for the static reference snapshot and verified audit results."""

from pathlib import Path

from app.models.personal import PlanningProfile
from app.rag.guidance import respond
from app.rag.guidance.assets import resolve_asset
from app.schemas.academic_guidance import AcademicGuidance
from app.services import academic, auth, graduation_audits, guidance_bindings, guidance_criteria

CONNECTED_WORKFLOW = "career:posting"
NODE_LIMIT = 600
ASSET_LIMIT = 120


UNBOUND = {
    "school_required": (
        "needs_input",
        "school_required",
        "설정에서 등록 학교를 선택하면 그 학교의 학사 안내를 볼 수 있습니다.",
    ),
    "unbound": (
        "unavailable",
        "school_guidance_not_connected",
        "등록 학교에 연결된 학사 안내 자료가 아직 없습니다.",
    ),
    "unavailable": (
        "unavailable",
        "school_guidance_not_connected",
        "등록 학교에 연결된 학사 안내 자료를 지금 제공할 수 없습니다.",
    ),
}


CRITERIA_MESSAGES = {
    "shown": (
        "학교 관리자가 게시한 기준입니다. 내 학업 기준에 맞는 부분만 보여 드립니다. "
        "충족 여부는 '내 졸업요건 요약'과 학업 기준 화면에서 확인해 주세요."
    ),
    "not_in_standard": (
        "학교가 게시한 졸업 기준에 이 항목은 따로 정해져 있지 않습니다. "
        "전체 졸업 요건은 '추가 확인 항목'에서 확인해 주세요."
    ),
    "not_applied": (
        "설정에서 학업 기준(학과·입학연도·이수 경로·교육과정)을 적용하면 학교가 게시한 기준을 "
        "여기에서 볼 수 있습니다."
    ),
}
STALE_REQUIREMENTS = (
    " 학업 기준이 바뀌었거나 학교가 기준을 고쳐 다시 적용해야 합니다."
    " 학업 기준 화면에서 확인해 주세요."
)


def add_published_criteria(db, identity, binding, value):
    """Same published requirements as the student's academic requirements screen."""
    profile = db.get(PlanningProfile, identity.user.id)
    if profile is None or profile.institution_id != binding.institution_id:
        return
    # Schools that only approved rule programs keep the original pointer to those rules.
    if not guidance_criteria.school_publishes(db, binding.institution_id):
        return
    cards, state, stale = guidance_criteria.published_criteria(
        db, identity.user.id, value["node_id"]
    )
    published = [card.model_dump(mode="json", exclude_none=True) for card in cards]
    value["cards"] = published + value["cards"]
    value["message"] = CRITERIA_MESSAGES[state] + (STALE_REQUIREMENTS if stale else "")
    if state == "not_applied":
        value["missing_fields"] = ["academic_requirements"]


def unbound(node_id, state):
    status, reason, message = UNBOUND[state]
    return AcademicGuidance.model_validate(
        {
            "schema_version": "academic-click-v3",
            "node_id": node_id,
            "title": "학사 안내",
            "state": status,
            "reason": reason,
            "message": message,
            "cards": [],
            "warnings": [],
            "buttons": [],
        }
    )


def read_node(db, request, node_id, audit_id, institution_id=None) -> AcademicGuidance:
    identity = auth.current_identity(request, db)
    auth.throttle(db, "academic-guidance:" + str(identity.user.id), limit=NODE_LIMIT)
    binding, bundle = guidance_bindings.resolve(db, identity, institution_id)
    if bundle is None:
        # Never show another school's collected material.
        return unbound(node_id, binding.state)
    audit = None
    if audit_id is not None:
        # Re-read on the server: a client never supplies an audit result.
        db.expire_all()
        identity = auth.current_identity(request, db)
        row = graduation_audits.read(db, identity, audit_id)
        audit = graduation_audits.view(db, identity, row).model_dump(mode="json")
    value = respond(node_id, audit=audit)
    if value.get("reason") == "general_criteria":
        add_published_criteria(db, identity, binding, value)
    for card in value["cards"]:
        if "template_id" in card:
            card["type"] = "audit_requirement"
    if node_id == CONNECTED_WORKFLOW and request.app.state.job_analyzer is not None:
        value["integration_state"] = "connected"
    return AcademicGuidance.model_validate(value)


def read_asset(db, request, asset_id, institution_id=None) -> Path:
    identity = auth.current_identity(request, db)
    auth.throttle(db, "academic-guidance-asset:" + str(identity.user.id), limit=ASSET_LIMIT)
    if guidance_bindings.resolve(db, identity, institution_id)[1] is None:
        raise academic.failure("자료를 찾을 수 없습니다.", 404)
    try:
        return resolve_asset(asset_id)
    except ValueError:
        raise academic.failure("자료를 찾을 수 없습니다.", 404) from None
