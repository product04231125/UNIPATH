"""Boundary for the AI team's extractor, matcher and explanation implementation."""

from typing import Protocol
from uuid import uuid4

from app.core.auth_errors import conflict
from app.schemas import job_analysis as dto
from app.schemas.personalization import PersonalizationContext
from app.services import auth, gemini
from app.services.personalization.context import assemble
from app.services.personalization.redaction import redact_context


class JobAnalyzer(Protocol):
    # The adapter owns extraction + matching; an LLM explanation alone is not a matcher.
    # A provider is called only when configured and the student consented for this request.
    def analyze(
        self, posting_text: str, context: PersonalizationContext
    ) -> list[dto.JobRequirementComparison]: ...


def validate_comparisons(posting, context, values):
    if not isinstance(values, list) or len(values) > 50:
        raise ValueError("Analyzer must return a bounded comparison list")
    comparisons = [dto.JobRequirementComparison.model_validate(value) for value in values]
    selected = {(item.kind, item.record_id, item.version): item for item in context.records}
    for item in comparisons:
        evidence = item.posting_evidence
        if posting[evidence.start : evidence.end] != evidence.excerpt:
            raise ValueError("Posting evidence must preserve exact input offsets")
        for citation in item.personal_evidence:
            record = selected.get((citation.kind, citation.record_id, citation.version))
            if record is None or citation.excerpt not in record.text:
                raise ValueError("Personal citations must refer to selected record text")
    return comparisons


def execute(db, request, payload, analyzer: JobAnalyzer | None):
    identity = auth.current_identity(request, db)
    auth.throttle(db, "job-analysis:" + str(identity.user.id), limit=30)
    db.expire_all()
    identity = auth.current_identity(request, db)
    context = assemble(db, identity, payload.records)
    identifier = uuid4()
    if not context.records:
        return dto.JobAnalysisResponse(
            analysis_id=identifier,
            status=dto.JobAnalysisStatus.NEEDS_USER_INPUT,
            reason=dto.JobAnalysisReason.PERSONAL_RECORDS_REQUIRED,
            missing_fields=["records"],
        )
    if analyzer is None:
        return dto.JobAnalysisResponse(
            analysis_id=identifier,
            status=dto.JobAnalysisStatus.NOT_CONFIGURED,
            reason=dto.JobAnalysisReason.ANALYZER_NOT_CONFIGURED,
        )
    if not payload.external_processing_consent:
        return dto.JobAnalysisResponse(
            analysis_id=identifier,
            status=dto.JobAnalysisStatus.NEEDS_USER_INPUT,
            reason=dto.JobAnalysisReason.EXTERNAL_PROCESSING_CONSENT_REQUIRED,
            missing_fields=["external_processing_consent"],
        )
    # Citations are validated against what the model actually received.
    outbound = redact_context(context, identity)
    gemini.reserve_call(db, request)
    # Release the read transaction before calling the external adapter.
    db.rollback()
    try:
        comparisons = validate_comparisons(
            payload.posting_text, outbound, analyzer.analyze(payload.posting_text, outbound)
        )
        result = dto.JobAnalysisResponse(
            analysis_id=identifier,
            status=(
                dto.JobAnalysisStatus.COMPLETED
                if comparisons
                else dto.JobAnalysisStatus.INSUFFICIENT_EVIDENCE
            ),
            reason=(
                dto.JobAnalysisReason.COMPARED_WITH_PERSONAL_EVIDENCE
                if comparisons
                else dto.JobAnalysisReason.NO_REQUIREMENTS_FOUND
            ),
            comparisons=comparisons,
        )
    except Exception as error:
        # Never return provider errors, input or unvalidated comparisons.
        gemini.log_failure("job analysis", error)
        result = dto.JobAnalysisResponse(
            analysis_id=identifier,
            status=dto.JobAnalysisStatus.FAILED,
            reason=dto.JobAnalysisReason.ANALYSIS_FAILED,
        )
    db.expire_all()
    current_identity = auth.current_identity(request, db)
    current = assemble(db, current_identity, payload.records)
    if current != context:
        # Deletions, version changes and session revocation are also rechecked above.
        raise conflict()
    return result
