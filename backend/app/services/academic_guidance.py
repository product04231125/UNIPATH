"""Authenticated adapter for the static reference snapshot and verified audit results."""

from pathlib import Path

from app.rag.guidance import respond
from app.rag.guidance.assets import resolve_asset
from app.schemas.academic_guidance import AcademicGuidance
from app.services import academic, auth, graduation_audits

CONNECTED_WORKFLOW = "career:posting"
NODE_LIMIT = 600
ASSET_LIMIT = 120


def read_node(db, request, node_id, audit_id) -> AcademicGuidance:
    identity = auth.current_identity(request, db)
    auth.throttle(db, "academic-guidance:" + str(identity.user.id), limit=NODE_LIMIT)
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


def read_asset(db, request, asset_id) -> Path:
    identity = auth.current_identity(request, db)
    auth.throttle(db, "academic-guidance-asset:" + str(identity.user.id), limit=ASSET_LIMIT)
    try:
        return resolve_asset(asset_id)
    except ValueError:
        raise academic.failure("자료를 찾을 수 없습니다.", 404) from None
