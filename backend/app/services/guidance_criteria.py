"""School-published criteria shown in the graduation menu.

The cards come from the same place as the student's academic requirements screen: the
published requirement revisions the student applied, already filtered to their department,
admission year and track, and the curriculum revision they chose. They describe the school's
standard and never judge whether the student meets it; that stays with the Rule Engine audit
and the student's own checks.
"""

from sqlalchemy import exists, or_, select

from app.models.academic_workspace import AcademicCurriculumRevision, AcademicRequirementRevision
from app.schemas.academic_guidance import GuidanceCard, GuidanceSource, GuidanceTable
from app.services import student_academic

DOCUMENT_KINDS = {
    "credits": ("credit_table",),
    "certificate": ("certification",),
    "review": ("checklist",),
    "thesis": ("checklist", "certification"),
    "volunteer": ("checklist", "certification"),
}
# Nodes without a document of their own show only the lines and items that mention these words.
LINE_WORDS = {"thesis": ("논문", "졸업작품", "졸업시험"), "volunteer": ("봉사",)}
CELL_TEXT = {"not_applicable": "해당 없음", "empty": "-"}
CHOICE_TEXT = {"all": "모두 충족", "pickOne": "1개 선택"}
NOTICE = "학교 관리자가 게시한 기준이며 내 충족 여부 판정이 아닙니다."
STALE_ISSUES = {
    "context_changed",
    "profile_context_changed",
    "requirement_withdrawn",
    "requirement_expired",
}
OPTION_NOTICE = (
    "괄호 안 선택 조건 중 하나일 수 있습니다. 전체 조건은 '졸업인증' 항목에서 확인해 주세요."
)


def table(caption, grid):
    rows = [
        [{"text": text or "", "rowspan": 1, "colspan": 1, "header": index == 0} for text in row]
        for index, row in enumerate(grid)
    ]
    return GuidanceTable(caption=caption, rows=rows, grid=grid)


def source(document):
    return GuidanceSource(
        title=f"학교 게시 기준 · {document.name}",
        document_id=str(document.id),
        document_version=document.revision,
    )


def context_label(context):
    return (
        f"적용: {context['department_name']} · {context['admission_year']}학년도 입학 · "
        f"{context['track_name']}"
    )


def applies_to(document, contexts):
    applied = {str(item) for item in document.context_ids}
    return "\n".join(context_label(c) for c in contexts if c["id"] in applied)


def credit_grid(content):
    children = {}
    for header in content["headers"]:
        children.setdefault(header["parent_id"], []).append(header)
    columns = []

    # Positions order siblings, so columns follow the header tree as the admin table shows it.
    def walk(parent, labels):
        for header in sorted(children.get(parent, []), key=lambda h: h["position"]):
            path = (*labels, header["label"].replace("\n", " "))
            if header["role"] != "group":
                columns.append((" · ".join(path), header))
            walk(header["id"], path)

    walk(None, ())
    cells = {(c["row_id"], c["header_id"]): c for c in content["cells"]}
    grid = [["구분"] + [row["label"] for row in content["rows"]]]
    for label, header in columns:
        values = []
        for row in content["rows"]:
            cell = cells.get((row["id"], header["id"]))
            state = cell["state"] if cell else "empty"
            values.append(str(cell["value"]) if state == "number" else CELL_TEXT[state])
        grid.append([label] + values)
    return grid


def group_label(group):
    choice = CHOICE_TEXT.get(group["choice"]) or (
        f"{group['pick_count']}개 선택" if group["pick_count"] is not None else "선택"
    )
    return f"{group['label']} ({choice})"


def certification_matches(groups, words, path=()):
    """Matching items with the groups above them: they are usually one option among several."""
    lines = []
    for group in groups:
        here = (*path, group_label(group))
        lines += [
            " › ".join(here) + f": {item['label']}"
            for item in group["items"]
            if any(word in item["label"] for word in words)
        ]
        lines += certification_matches(group["groups"], words, here)
    return lines


def certification_lines(groups, depth=0):
    lines = []
    for group in groups:
        lines.append("  " * depth + f"■ {group_label(group)}")
        lines += ["  " * (depth + 1) + f"· {item['label']}" for item in group["items"]]
        lines += ["  " * (depth + 1) + f"면제: {text}" for text in group["exemptions"]]
        lines += certification_lines(group["groups"], depth + 1)
    return lines


def document_cards(document, contexts, words=None):
    content = document.content.model_dump(mode="json")
    scope = applies_to(document, contexts)
    body = "\n".join(part for part in (scope, NOTICE) if part)
    meta = {"sources": [source(document)]}
    if content["kind"] == "credit_table":
        grid = credit_grid(content)
        return [
            GuidanceCard(
                type="reference_table",
                title=document.name,
                body=body,
                table=table(None, grid),
                **meta,
            )
        ]
    if content["kind"] == "checklist":
        lines = [line["text"] for line in content["lines"]]
        if words is not None:
            lines = [line for line in lines if any(word in line for word in words)]
        if not lines:
            return []
        return [
            GuidanceCard(
                type="reference_text",
                title=document.name,
                body="\n".join(lines + ["", body]),
                **meta,
            )
        ]
    if words is not None:
        lines = certification_matches(content["groups"], words)
        if not lines:
            return []
        return [
            GuidanceCard(
                type="reference_text",
                title=document.name,
                body="\n".join(lines + ["", OPTION_NOTICE, body]),
                **meta,
            )
        ]
    cards = [
        GuidanceCard(
            type="reference_text",
            title=document.name,
            body="\n".join(certification_lines(content["groups"]) + ["", body]),
            **meta,
        )
    ]
    for item in content["tables"]:
        cards.append(
            GuidanceCard(
                type="reference_table",
                title=item["title"],
                body=NOTICE,
                table=table(item["title"], [item["columns"], *item["rows"]]),
                **meta,
            )
        )
    return cards


def required_course_cards(contexts):
    cards = []
    for context in contexts:
        courses = [c for c in context["courses"] if c["requirement"] == "required"]
        if not courses:
            continue
        grid = [["과목", "과목 코드", "인정 학점", "분류"]] + [
            [
                c["course_name"],
                c["course_code"] or "-",
                c["recognized_credits"] if c["recognized_credits"] is not None else "미정",
                c["classification_label"] or "-",
            ]
            for c in courses
        ]
        cards.append(
            GuidanceCard(
                type="reference_table",
                title=f"{context['curriculum_name']} 필수 과목",
                body=f"{context_label(context)}\n{NOTICE}",
                table=table(None, grid),
                sources=[
                    GuidanceSource(
                        title=f"학교 게시 교육과정 · {context['curriculum_name']}",
                        document_id=context["curriculum_revision_id"],
                        document_version=context["curriculum_revision"],
                    )
                ],
            )
        )
    return cards


def school_publishes(db, institution_id):
    """Whether the school keeps its criteria as published revisions, not only rule programs."""
    return db.scalar(
        select(
            or_(
                exists().where(
                    AcademicRequirementRevision.institution_id == institution_id,
                    AcademicRequirementRevision.status == "published",
                ),
                exists().where(
                    AcademicCurriculumRevision.institution_id == institution_id,
                    AcademicCurriculumRevision.status == "published",
                ),
            )
        )
    )


def published_criteria(db, owner, node_id):
    """(cards, state, stale): state is "shown", "not_in_standard" or "not_applied".

    stale is true when the applied requirements no longer match the student's settings or the
    school withdrew or ended one of them, as the academic requirements screen reports.
    """
    workspace = student_academic.read_contexts(db, owner)
    contexts = workspace["contexts"]
    requirements = student_academic.read_requirements(db, owner)
    stale = bool(set(requirements.issues) & STALE_ISSUES)
    if node_id == "courses":
        cards = required_course_cards(contexts)
        state = "shown" if cards else "not_applied" if not contexts else "not_in_standard"
        return cards, state, stale
    documents = [d for d in requirements.documents if d.status == "published" and d.usable]
    if not documents:
        return [], "not_applied", stale
    kinds = DOCUMENT_KINDS.get(node_id, ("checklist",))
    words = LINE_WORDS.get(node_id)
    cards = [
        card
        for kind in kinds
        for document in documents
        if document.kind == kind
        for card in document_cards(document, contexts, words)
    ]
    return cards, ("shown" if cards else "not_in_standard"), stale
