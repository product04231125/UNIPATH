"""Presentation only: consume a server-verified GraduationAuditView JSON snapshot.

This module does not authenticate, approve records, calculate eligibility or fetch sources.
Never expose the audit argument as user-supplied official data in an HTTP endpoint.
"""

from copy import deepcopy
from datetime import date
from decimal import Decimal, InvalidOperation
from urllib.parse import urlsplit

from . import career_menu, content

VERSION = "academic-click-v3"
STATUS_TEXT = {
    "satisfied": "기준일의 검토 자료로 등록된 요건을 충족했습니다.",
    "not_satisfied": "기준일의 검토 자료에서 충족하지 못한 요건이 있습니다.",
    "needs_review": "자료 또는 조건이 부족해 추가 확인이 필요합니다.",
    "not_applicable": "적용 가능한 요건이 없어 판정을 안내할 수 없습니다.",
}
KINDS = {
    "credits": "minimum_credits",
    "courses": "required_courses",
    "volunteer": "minimum_volunteer_hours",
    "certificate": "any_certificate",
    "thesis": "thesis",
    "review": "manual_review",
}
# These categories are navigation, not assertions that school content is available.
NODES = {
    "home": ("학사 안내", None, "menu"),
    "graduation": ("졸업", "home", "menu"),
    "calendar": ("학사일정", "home", "unavailable"),
    "notices": ("공지사항", "home", "unavailable"),
    "registration": ("수강신청", "home", "unavailable"),
    "major": ("전공", "home", "unavailable"),
    "scholarship": ("장학금", "home", "unavailable"),
    "tuition": ("등록금", "home", "unavailable"),
    "dormitory": ("기숙사", "home", "unavailable"),
    "departments": ("학부·학과", "home", "unavailable"),
    # summary is the student's own audit; the others are general criteria first and show
    # one item of an audit only when the caller names a verified audit.
    "summary": ("내 졸업요건 요약", "graduation", "audit"),
    "credits": ("이수학점", "graduation", "criteria"),
    "courses": ("필수과목", "graduation", "criteria"),
    "volunteer": ("봉사", "graduation", "criteria"),
    "certificate": ("자격", "graduation", "criteria"),
    "thesis": ("논문", "graduation", "criteria"),
    "review": ("추가 확인 항목", "graduation", "criteria"),
}
NOTICE = "학교 검토 자료 기준 안내이며 학교의 최종 학위 수여 승인을 대체하지 않습니다."


_node_cache = (None, None)


def _nodes():
    global _node_cache
    dynamic = content.bundle()[0]
    if _node_cache[0] is not dynamic:
        _node_cache = (dynamic, {**NODES, **dynamic, **career_menu.NODES})
    return _node_cache[1]


def _button(node_id):
    label, _, mode = _nodes()[node_id]
    return {
        "id": node_id,
        "label": label,
        "action": "select_node",
        "node_id": node_id,
        "availability": "content_pending" if mode == "unavailable" else "available",
    }


def catalog():
    """Return a detached serializable catalog for the frontend handoff, not a live API."""
    nodes = _nodes()
    children = {key: [] for key in nodes}
    for key, (_, parent, _) in nodes.items():
        if parent in children:
            children[parent].append(key)
    return {
        "schema_version": VERSION,
        "root_id": "home",
        "nodes": [
            {
                "id": key,
                "label": label,
                "parent_id": parent,
                "mode": mode,
                "children": children[key],
            }
            for key, (label, parent, mode) in _nodes().items()
        ],
    }


def _amount(value):
    if value is None:
        return None
    if isinstance(value, (bool, float)) or not isinstance(value, (str, int, Decimal)):
        raise ValueError("Use exact decimal strings")
    try:
        number = Decimal(value)
    except InvalidOperation as exc:
        raise ValueError("Invalid amount") from exc
    if not number.is_finite() or number < 0 or number > Decimal("1e18"):
        raise ValueError("Invalid amount")
    if number.as_tuple().exponent < -6:
        raise ValueError("Invalid precision")
    return format(number, "f")


def _sources(evidence):
    result = []
    fields = (
        "chunk_id",
        "knowledge_document_id",
        "knowledge_version",
        "document_id",
        "document_version",
        "title",
        "source_url",
        "page",
        "content_hash",
        "document_hash",
    )
    for source in evidence:
        item = {field: source[field] for field in fields}
        url = urlsplit(item["source_url"])
        if url.scheme not in ("https", "http") or not url.hostname or url.username or url.password:
            raise ValueError("Invalid source URL")
        if type(item["page"]) is not int or item["page"] < 1:
            raise ValueError("Invalid source page")
        result.append(item)
    return result


def _course_labels(ids, rule):
    names = {ref["record_id"]: ref["name"] for ref in rule["references"] if ref["kind"] == "course"}
    # Never fetch mutable master names; preserve the audit's historical references.
    return [
        {"course_id": identifier, "label": names.get(identifier, "과목명 확인 필요")}
        for identifier in ids
    ]


def _card(row, rule):
    status, reason, kind = row["status"], row["reason"], rule["condition"]["kind"]
    if status not in STATUS_TEXT or kind not in KINDS.values():
        raise ValueError("Unsupported result")
    unit = {"minimum_credits": "학점", "minimum_volunteer_hours": "시간"}.get(kind)
    amounts = {key: _amount(row.get(key)) for key in ("current", "required", "deficit")}
    text = STATUS_TEXT[status]
    variant = "status"
    if (
        unit
        and (status, reason)
        in {("satisfied", "threshold_met"), ("not_satisfied", "below_threshold")}
        and all(value is not None for value in amounts.values())
    ):
        text = (
            f"검토된 실적은 {amounts['current']}{unit}, "
            f"요구 기준은 {amounts['required']}{unit}입니다."
        )
        text += (
            f" {amounts['deficit']}{unit} 부족합니다."
            if status == "not_satisfied"
            else " 이 항목을 충족했습니다."
        )
        variant = "quantity"
    elif status == "needs_review":
        text = "자료 또는 조건의 추가 확인이 필요합니다. 부족 수치를 확정해 안내할 수 없습니다."
    elif kind in ("any_certificate", "thesis"):
        text = {
            "satisfied": "검토 자료에서 이 항목의 충족이 확인되었습니다.",
            "not_satisfied": "검토 자료에서 이 항목의 충족이 확인되지 않았습니다.",
        }.get(status, text)
    missing = _course_labels(row.get("missing_course_ids", []), rule)
    uncertain = _course_labels(row.get("uncertain_course_ids", []), rule)
    if kind == "required_courses":
        if missing:
            text += " 미충족 과목: " + ", ".join(item["label"] for item in missing) + "."
        if uncertain:
            text += " 확인 필요 과목: " + ", ".join(item["label"] for item in uncertain) + "."
    sources = _sources(rule["evidence"])
    return {
        "template_id": f"{kind}.{status}.{variant}",
        "rule_id": row["rule_id"],
        "rule_set_id": row["rule_set_id"],
        "rule_set_version": row["rule_set_version"],
        "title": row["title"],
        "kind": kind,
        "status": status,
        "reason": reason,
        "body": text,
        "unit": unit,
        # Internal certificate/thesis counts are not display quantities.
        "quantities": amounts if unit else None,
        "missing_courses": missing,
        "uncertain_courses": uncertain,
        "sources": sources,
        "source_state": "available" if sources else "unavailable",
        "evidence_record_ids": list(row.get("evidence_record_ids", [])),
    }


def _audit_payload(audit, node_id):
    # Full Pydantic schema/ownership/integrity checks belong to the calling service.
    # These checks prevent accidental success-shaped output from incomplete projections.
    if audit["official"] is not True or audit["status"] not in STATUS_TEXT:
        raise ValueError("Expected official audit")
    for field in ("current_usable", "catalog_complete"):
        if type(audit[field]) is not bool:
            raise ValueError("Expected explicit boolean")
    date.fromisoformat(audit["evaluated_on"])
    rules = {}
    for program in audit["criteria"]:
        for rule in program["rules"]:
            key = (program["id"], program["version"], rule["rule_id"])
            if key in rules:
                raise ValueError("Ambiguous rule")
            rules[key] = rule
    seen, cards = set(), []
    for row in audit["results"]:
        key = (row["rule_set_id"], row["rule_set_version"], row["rule_id"])
        if key in seen:
            raise ValueError("Duplicate result")
        seen.add(key)
        card = _card(row, rules[key])
        if node_id == "summary" or card["kind"] == KINDS[node_id]:
            cards.append(card)
    warnings = []
    if not audit["current_usable"]:
        warnings.append("현재 안내에는 재확인이 필요합니다. 아래는 과거 기준일의 결과입니다.")
    if not audit["catalog_complete"]:
        warnings.append("전체 졸업요건의 등록·검토가 확인되지 않았습니다.")
    summary = STATUS_TEXT[audit["status"]]
    if not audit["current_usable"]:
        summary = "재확인 필요 — 과거 기준일 결과: " + summary
    if node_id != "summary" and not cards:
        summary = "이 감사에 해당 종류의 판정 항목이 없습니다. 면제나 충족을 의미하지 않습니다."
    return {
        "state": "ready",
        "reason": "audit_rendered",
        "message": summary,
        "audit": {
            key: audit[key]
            for key in (
                "id",
                "context",
                "evaluated_on",
                "status",
                "reason",
                "current_usable",
                "catalog_complete",
            )
        },
        "cards": cards,
        "warnings": warnings,
        "issues": deepcopy(audit.get("issues", []) + audit.get("current_issues", [])),
        "notice": NOTICE,
    }


def respond(node_id="home", *, audit=None):
    """Pure, stateless selection handler. audit is verified server data, never client input.

    Use GraduationAuditView.model_dump(mode='json') after audits.read/view in an adapter.
    No user identifiers or personal records are emitted for menu or unavailable selections.
    """
    if not isinstance(node_id, str) or node_id not in _nodes():
        return {
            "schema_version": VERSION,
            "node_id": None,
            "state": "needs_selection",
            "reason": "unknown_node",
            "message": "안내 메뉴에서 항목을 선택해 주세요.",
            "cards": [],
            "buttons": [_button("home")],
            "warnings": [],
        }
    label, parent, mode = _nodes()[node_id]
    response = {
        "schema_version": VERSION,
        "node_id": node_id,
        "title": label,
        "state": "ready",
        "reason": "menu",
        "message": "궁금한 항목을 선택해 주세요.",
        "cards": [],
        "warnings": [],
        "buttons": [_button(key) for key, value in _nodes().items() if value[1] == node_id],
    }
    if parent:
        response["buttons"].append({**_button(parent), "label": "이전 메뉴"})
    if parent != "home" and node_id != "home":
        response["buttons"].append({**_button("home"), "label": "처음으로"})
    if mode == "unavailable":
        response.update(
            state="unavailable",
            reason="approved_content_not_configured",
            message="검토된 안내 자료를 준비 중입니다. 현재 이 항목의 정보를 제공할 수 없습니다.",
        )
    elif mode == "criteria" and audit is None:
        # General criteria live in the school's approved rule programs (GET
        # /catalog/rule-programs). Nothing personal is required to read them.
        response.update(
            reason="general_criteria",
            message=(
                "이 항목의 기준은 학교가 승인한 졸업 기준에서 안내합니다. "
                "내 충족 여부는 '내 졸업요건 요약'에서 확인해 주세요."
            ),
            criteria_kind=KINDS[node_id],
        )
        response["buttons"].insert(0, {**_button("summary"), "label": "내 충족 여부 보기"})
    elif mode in ("audit", "criteria"):
        if audit is None:
            response.update(
                state="needs_input",
                reason="verified_audit_required",
                message="학교·학과·교육과정을 확인하고 공식 졸업요건 감사를 선택해 주세요.",
            )
        else:
            try:
                response.update(_audit_payload(audit, node_id))
            except (KeyError, TypeError, ValueError, AttributeError, OverflowError):
                response.update(
                    state="unavailable",
                    reason="invalid_audit_projection",
                    message=(
                        "판정 자료를 안전하게 표시할 수 없습니다. 감사 결과를 다시 확인해 주세요."
                    ),
                )
    response.update(content.payload(node_id))
    response.update(career_menu.payload(node_id))
    for related in response.pop("related_node_ids", []):
        response["buttons"].append(_button(related))
    return deepcopy(response)
