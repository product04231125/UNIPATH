"""Database-approved indexes for explicit catalogue IDs; never cache user questions."""

from collections import OrderedDict
from datetime import UTC, datetime
from threading import RLock
from uuid import uuid4

from sqlalchemy import func, or_, select

from app.models.academic import Curriculum, Department, GraduationRule, OfficialDocument
from app.models.identity import Institution
from app.models.knowledge import KnowledgeChunk, KnowledgeDocument
from app.rag.school.contracts import SchoolContext
from app.rag.school.retriever import SchoolRetriever
from app.rag.school.service import SchoolRagService, query_requirements
from app.schemas.assistant import (
    AssistantCitation,
    AssistantQueryRequest,
    AssistantQueryResponse,
    CitationApplicability,
    SchoolQueryContext,
)
from app.schemas.knowledge import KnowledgeSearchResponse
from app.services import auth, catalog, knowledge
from app.services.assistant import query_school

MAX_DOCUMENTS = 32
MAX_CHUNKS = 2000
MAX_CHARACTERS = 1_000_000


class KnowledgeIndexCache:
    def __init__(self):
        self._indexes = OrderedDict()
        self._lock = RLock()
        # Provider selection remains an explicit integration step. Tests may inject
        # a synthetic generator; no real provider or credential is configured here.
        self.generator = None

    def get(self, key, build):
        with self._lock:
            if key not in self._indexes:
                value = build()
                # Remove a superseded index for the same selected catalogue scope.
                for old in list(self._indexes):
                    if old[0] == key[0]:
                        del self._indexes[old]
                self._indexes[key] = value
            self._indexes.move_to_end(key)
            while len(self._indexes) > 2:
                self._indexes.popitem(last=False)
            return self._indexes[key]

    def discard(self, key):
        with self._lock:
            self._indexes.pop(key, None)


def selection(db, context):
    catalog.context(db, context.institution_id, context.department_id, context.curriculum_id)
    school = db.get(Institution, context.institution_id)
    department = db.get(Department, context.department_id)
    curriculum = db.get(Curriculum, context.curriculum_id) if context.curriculum_id else None
    on = datetime.now(UTC).date()
    statement = (
        catalog.statement(
            OfficialDocument,
            on,
            context.institution_id,
            context.department_id,
            context.curriculum_id,
        )
        .add_columns(KnowledgeDocument)
        .join(KnowledgeDocument, KnowledgeDocument.source_document_id == OfficialDocument.id)
        .where(
            KnowledgeDocument.status == "approved",
            KnowledgeDocument.source_document_version == OfficialDocument.version,
            KnowledgeDocument.institution_id == OfficialDocument.institution_id,
        )
    )
    if context.curriculum_id is None:
        # A course-specific source is not evidence for an unspecified curriculum.
        rules = (
            catalog.statement(GraduationRule, on, context.institution_id, context.department_id)
            .where(GraduationRule.curriculum_id.is_(None))
            .with_only_columns(GraduationRule.id)
        )
        statement = statement.where(
            OfficialDocument.curriculum_id.is_(None),
            or_(OfficialDocument.rule_id.is_(None), OfficialDocument.rule_id.in_(rules)),
        )
    records = list(db.execute(statement.order_by(OfficialDocument.id).limit(MAX_DOCUMENTS + 1)))
    if len(records) > MAX_DOCUMENTS:
        raise ValueError("Selected corpus exceeds the document limit")
    scope = (str(school.id), str(department.id), str(curriculum.id) if curriculum else None)
    key = (
        scope,
        on,
        school.version,
        school.name,
        department.version,
        department.name,
        curriculum.version if curriculum else None,
        tuple(
            (str(source.id), source.version, str(document.id), document.version)
            for source, document in records
        ),
    )
    return (
        key,
        records,
        SchoolContext(school.name, department.name, context.admission_year, context.track),
    )


def build_index(db, records, context):
    identifiers = [document.id for _, document in records]
    count, length = db.execute(
        select(
            func.count(), func.coalesce(func.sum(func.char_length(KnowledgeChunk.content)), 0)
        ).where(KnowledgeChunk.knowledge_document_id.in_(identifiers))
    ).one()
    if count > MAX_CHUNKS or length > MAX_CHARACTERS:
        # No partial corpus: omitted pages may contain exceptions or qualifications.
        raise ValueError("Selected corpus exceeds the index limit")
    rows = list(
        db.scalars(
            select(KnowledgeChunk)
            .where(KnowledgeChunk.knowledge_document_id.in_(identifiers))
            .order_by(
                KnowledgeChunk.knowledge_document_id, KnowledgeChunk.page, KnowledgeChunk.part_index
            )
        )
    )
    by_document = {identifier: [] for identifier in identifiers}
    for row in rows:
        by_document[row.knowledge_document_id].append(row)
    chunks = []
    for source, document in records:
        parts = by_document[document.id]
        if {part.page for part in parts} != set(range(1, document.page_count + 1)):
            raise ValueError("Incomplete approved document")
        chunks.extend(
            knowledge.rag_chunks(document, source, parts, context.institution, context.department)
        )
    return SchoolRetriever(chunks)


def failure(search, reason="rag_processing_failed", *, status="failed"):
    values = dict(query_id=uuid4(), status=status, reason=reason)
    return KnowledgeSearchResponse(**values) if search else AssistantQueryResponse(**values)


def add_applicability(db, records, citations):
    """Attach current DB metadata, never metadata invented by a generator."""
    by_source = {source.id: (source, document) for source, document in records}
    rows = {
        row.id: row
        for row in db.scalars(
            select(KnowledgeChunk).where(KnowledgeChunk.id.in_([c.chunk_id for c in citations]))
        )
    }
    result = []
    for citation in citations:
        source, document = by_source[citation.document_id]
        row = rows[citation.chunk_id]
        if row.knowledge_document_id != document.id:
            raise ValueError("Citation does not belong to the selected approved source")
        result.append(
            citation.model_copy(
                update={
                    "applicability": CitationApplicability(
                        institution_id=source.institution_id,
                        department_id=source.department_id,
                        curriculum_id=source.curriculum_id,
                        source_version=source.version,
                        knowledge_document_id=document.id,
                        knowledge_version=document.version,
                        effective_from=source.effective_from,
                        effective_to=source.effective_to,
                        source_checked_on=document.source_checked_on,
                        admission_years=row.admission_years or [],
                        tracks=row.tracks or [],
                    )
                }
            )
        )
    return result


def execute(db, request, payload, cache, *, search=False):
    identity = auth.current_identity(request, db)
    auth.throttle(db, "school-knowledge:" + str(identity.user.id), limit=60)
    # Refresh after throttle's transaction: catalogue edits/revocations may have committed.
    db.expire_all()
    try:
        key, records, context = selection(db, payload.context)
    except ValueError:
        return failure(search)
    required = query_requirements(payload.question, context, require_complete_scope=True)
    if required is not None:
        values = dict(
            query_id=uuid4(),
            status=required.status,
            reason=required.reason,
            missing_fields=required.missing_fields,
        )
        return KnowledgeSearchResponse(**values) if search else AssistantQueryResponse(**values)
    try:
        retriever = cache.get(key, lambda: build_index(db, records, context))
    except (ValueError, KeyError, TypeError):
        return failure(search)
    # Do not retain an open read transaction across a future external generation call.
    db.rollback()
    if search:
        try:
            hits = retriever.search(payload.question, context, top_k=payload.limit)
            if not hits:
                result = failure(
                    True, "no_approved_matching_evidence", status="insufficient_evidence"
                )
            elif not retriever.approved_context(hits, context):
                result = failure(
                    True,
                    "document_context_not_approved_or_incomplete",
                    status="insufficient_evidence",
                )
            else:
                result = KnowledgeSearchResponse(
                    query_id=uuid4(),
                    status="evidence_found",
                    reason="approved_sources_found",
                    sources=[
                        AssistantCitation(
                            chunk_id=hit.chunk_id,
                            document_id=hit.document_id,
                            title=hit.title,
                            source_url=hit.source_url,
                            page=hit.page,
                            excerpt=hit.content[:800],
                        )
                        for hit in hits
                    ],
                )
        except (ValueError, KeyError, TypeError):
            result = failure(True)
    else:
        result = query_school(
            AssistantQueryRequest(
                question=payload.question,
                context=SchoolQueryContext(
                    **{
                        "institution": context.institution,
                        "department": context.department,
                        "admission_year": context.admission_year,
                        "track": context.track,
                    }
                ),
            ),
            SchoolRagService(retriever, cache.generator),
        )
    db.expire_all()
    auth.current_identity(request, db)
    try:
        current, current_records, _ = selection(db, payload.context)
    except ValueError:
        cache.discard(key)
        return failure(search)
    if current != key:
        cache.discard(key)
        return failure(
            search, "document_context_not_approved_or_incomplete", status="insufficient_evidence"
        )
    try:
        if search:
            result.sources = add_applicability(db, current_records, result.sources)
        else:
            result.citations = add_applicability(db, current_records, result.citations)
    except (KeyError, ValueError, TypeError):
        return failure(search)
    return result
