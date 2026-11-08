"""Exact-decimal progress from explicitly linked, student-confirmed records."""

from collections import defaultdict
from decimal import Decimal

from app.models.academic_workspace import AcademicCurriculumCourse, ClassificationNode
from app.models.personal import CourseRecord
from app.schemas import student_academic as dto
from app.services import student_academic as academic


def classification_matches(db, entry, header):
    if header.classification_node_id is None:
        return None
    target = db.get(ClassificationNode, header.classification_node_id)
    current = db.get(ClassificationNode, entry.classification_node_id)
    if target is None or current is None or target.institution_id != current.institution_id:
        return None
    seen = set()
    while current is not None and current.id not in seen:
        if current.logical_id == target.logical_id:
            return True
        if header.match_mode == "exact":
            break
        seen.add(current.id)
        current = db.get(ClassificationNode, current.parent_id) if current.parent_id else None
    return False


def progress(db, owner):
    current = academic.read_requirements(db, owner)
    links = academic.rows(db, academic.CourseLink, owner)
    records = academic.rows(db, CourseRecord, owner)
    record_map = {r.id: r for r in records}
    ctxs = {c.id: c for c in academic.contexts(db, owner)}
    entries = {link.entry_id: db.get(AcademicCurriculumCourse, link.entry_id) for link in links}
    active_links = [link for link in links if link.context_id in ctxs]
    by_course = defaultdict(list)
    for link in active_links:
        if (
            link.included
            and link.result == "completed"
            and link.course_record_id in record_map
            and record_map[link.course_record_id].completion == "recorded"
        ):
            by_course[entries[link.entry_id].course_id].append(link)
    output = []
    for document in current.documents:
        if document.kind != "credit_table":
            continue
        headers = {h.id: h for h in document.content.headers}
        cells = {(c.row_id, c.header_id): c for c in document.content.cells}
        group_ids = {h.parent_id for h in document.content.headers if h.parent_id}
        results = []
        for row in document.content.rows:
            context_ids = set(document.node_contexts[str(row.id)])
            local_links = [link for link in active_links if link.context_id in context_ids]
            cache = {}

            def matches(header, entry, seen=None, headers=headers):
                seen = set() if seen is None else seen
                if header.id in seen:
                    return None
                if header.aggregate_members:
                    children = [
                        matches(headers[m], entry, seen | {header.id})
                        for m in header.aggregate_members
                    ]
                    return True if True in children else None if None in children else False
                if header.role in ("subtotal", "total"):
                    return None
                classified = classification_matches(db, entry, header)
                if header.requirement is not None and entry.requirement != header.requirement:
                    return False
                return classified

            def evaluate(header, cache=cache, document=document, local_links=local_links):
                if header.id in cache:
                    return cache[header.id]
                evidence, included = [], {}
                uncertain = bool(current.issues) or document.status != "published"
                relevant_ids = set()
                for link in local_links:
                    record = record_map.get(link.course_record_id)
                    if record is None:
                        continue
                    entry = entries[link.entry_id]
                    matched = matches(header, entry)
                    relevant_ids.add(record.id)
                    state, reason, amount = "excluded", "outside_column", None
                    if not link.included:
                        reason = "excluded_by_student"
                    elif record.completion != "recorded":
                        reason = (
                            "not_completed"
                            if record.completion == "not_completed"
                            else "not_recorded"
                        )
                    elif matched is False:
                        reason = "outside_column"
                    elif current.issues:
                        state, reason = "needs_review", "academic_context_changed"
                    elif matched is None:
                        state, reason = "needs_review", "column_mapping_required"
                    elif link.record_version != record.version:
                        state, reason = "needs_review", "record_changed"
                    elif (
                        entry.curriculum_revision_id != ctxs[link.context_id].curriculum_revision_id
                    ):
                        state, reason = "needs_review", "curriculum_changed"
                    elif link.result == "needs_review":
                        state, reason = "needs_review", "completion_unconfirmed"
                    elif link.result != "completed":
                        reason = "not_completed"
                    elif len({link.context_id for link in by_course[entry.course_id]}) > 1:
                        state, reason = "needs_review", "multiple_major_policy_required"
                    elif len({link.course_record_id for link in by_course[entry.course_id]}) > 1:
                        state, reason = "needs_review", "retake_selection_required"
                    elif entry.recognized_credits is None:
                        state, reason = "needs_review", "recognized_credits_required"
                    elif link.earned_credits is None:
                        state, reason = "needs_review", "earned_credits_required"
                    else:
                        state, reason = "included", "confirmed"
                        amount = min(link.earned_credits, entry.recognized_credits)
                        included[record.id] = amount
                    uncertain |= state == "needs_review"
                    if (
                        state == "needs_review"
                        and link.earned_credits is not None
                        and entry.recognized_credits is not None
                    ):
                        amount = min(link.earned_credits, entry.recognized_credits)
                    evidence.append(
                        dto.StudentAcademicCreditEvidence(
                            record_id=record.id,
                            context_id=link.context_id,
                            title=record.title,
                            state=state,
                            reason=reason,
                            credits=amount,
                        )
                    )
                for record in records:
                    if record.id not in relevant_ids:
                        known_elsewhere = any(
                            link.course_record_id == record.id for link in active_links
                        )
                        state = (
                            "needs_review"
                            if record.completion == "recorded" and not known_elsewhere
                            else "excluded"
                        )
                        uncertain |= state == "needs_review"
                        evidence.append(
                            dto.StudentAcademicCreditEvidence(
                                record_id=record.id,
                                context_id=None,
                                title=record.title,
                                state=state,
                                reason="course_link_required"
                                if state == "needs_review"
                                else "outside_context"
                                if known_elsewhere
                                else "not_recorded",
                                credits=None,
                            )
                        )
                # An unmapped empty column must not masquerade as a confirmed zero.
                if (
                    not local_links
                    and not header.classification_node_id
                    and not header.aggregate_members
                ):
                    uncertain = True
                result = (sum(included.values(), Decimal(0)), uncertain, evidence)
                cache[header.id] = result
                return result

            def mapping_known(header, headers=headers):
                if header.aggregate_members:
                    return all(mapping_known(headers[key]) for key in header.aggregate_members)
                return header.classification_node_id is not None and header.role == "value"

            for header in document.content.headers:
                if header.id in group_ids or header.role == "group":
                    continue
                cell = cells.get((row.id, header.id))
                target = cell.value if cell and cell.state == "number" else None
                if cell and cell.state == "not_applicable":
                    results.append(
                        dto.StudentAcademicCreditCell(
                            row_id=row.id,
                            header_id=header.id,
                            target=None,
                            earned=None,
                            remaining=None,
                            status="not_applicable",
                            evidence=[],
                        )
                    )
                    continue
                earned, uncertain, evidence = evaluate(header)
                issues = [] if mapping_known(header) else ["column_mapping_required"]
                uncertain |= bool(issues)
                status = (
                    "no_target"
                    if target is None
                    else "needs_review"
                    if uncertain
                    else "satisfied"
                    if earned >= target
                    else "not_satisfied"
                )
                results.append(
                    dto.StudentAcademicCreditCell(
                        row_id=row.id,
                        header_id=header.id,
                        target=target,
                        earned=earned,
                        remaining=max(Decimal(0), target - earned) if target is not None else None,
                        status=status,
                        evidence=evidence,
                        issues=issues,
                    )
                )
        output.append(
            dto.StudentAcademicCreditTable(requirement_revision_id=document.id, cells=results)
        )
    return dto.StudentAcademicCreditProgress(
        owner_id=owner,
        activation_id=current.activation_id,
        issues=current.issues,
        tables=output,
        links=[academic.course_link_view(link) for link in links],
    )
