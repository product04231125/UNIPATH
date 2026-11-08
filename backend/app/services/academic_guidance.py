"""Authenticated adapter for the static reference snapshot and verified audit results."""

from pathlib import Path

from app.rag.guidance import respond
from app.rag.guidance.assets import resolve_asset
from app.schemas.academic_guidance import AcademicGuidance
from app.services import academic, auth, graduation_audits, guidance_bindings

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
