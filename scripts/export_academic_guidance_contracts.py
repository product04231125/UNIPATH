"""Export the structured academic guidance and separated personal guidance wire contracts."""

import importlib

from export_job_analysis_contracts import inline_enums
from export_personal_import_contracts import ROOT, render_model, runtime_helpers

guidance = importlib.import_module("app.schemas.academic_guidance")
graduation = importlib.import_module("app.schemas.graduation")
assistant = importlib.import_module("app.schemas.assistant")
knowledge = importlib.import_module("app.schemas.knowledge")
jobs = importlib.import_module("app.schemas.job_analysis")
personal = importlib.import_module("app.schemas.personalization")
personalized = importlib.import_module("app.schemas.personalized_guidance")
MODELS = [
    guidance.GuidanceButton,
    guidance.GuidanceSource,
    guidance.GuidanceTableCell,
    guidance.GuidanceTable,
    guidance.GuidanceQuantities,
    guidance.GuidanceCard,
    guidance.GuidanceCoverage,
    guidance.GuidanceWorkflow,
    graduation.GraduationContext,
    graduation.AuditIssue,
    guidance.GuidanceAudit,
    guidance.AcademicGuidance,
    assistant.CitationApplicability,
    assistant.AssistantCitation,
    knowledge.KnowledgeSearchResponse,
    personal.PersonalEvidenceSelection,
    knowledge.KnowledgeContext,
    personalized.PersonalizedGuidanceRequest,
    personal.PersonalEvidence,
    personal.PersonalizationContext,
    jobs.PersonalEvidenceCitation,
    personalized.PersonalizedGuidanceResponse,
]
NAMES = {model.__name__: model.__name__ for model in MODELS}
NAMES.update(
    {
        "GraduationContext": "GuidanceGraduationContext",
        "AuditIssue": "GuidanceAuditIssue",
        "CitationApplicability": "GuidanceCitationApplicability",
        "AssistantCitation": "GuidanceSchoolCitation",
        "KnowledgeSearchResponse": "GuidanceSchoolEvidence",
        "KnowledgeContext": "GuidanceSchoolContext",
        "PersonalEvidenceSelection": "GuidanceRecordSelection",
        "PersonalEvidence": "GuidancePersonalEvidence",
        "PersonalizationContext": "GuidancePersonalContext",
        "PersonalEvidenceCitation": "GuidancePersonalCitation",
    }
)


def main():
    output = [
        "// GENERATED: scripts/export_academic_guidance_contracts.py.\n"
        "// Reference guidance never judges eligibility. No storage or UI effects.\n"
        "abstract interface class AcademicGuidancePayload { Map<String,Object?> toJson(); }\n",
        runtime_helpers(decimals=False),
    ]
    for model in MODELS:
        schema = model.model_json_schema()
        output.append(
            render_model(
                model,
                names=NAMES,
                payload_name="AcademicGuidancePayload",
                schema=inline_enums(schema, schema.get("$defs", {})),
            )
        )
    (ROOT / "frontend/lib/features/api/academic_guidance_models.dart").write_text("".join(output))
    print(f"Exported {len(MODELS)} academic guidance models")


if __name__ == "__main__":
    main()
