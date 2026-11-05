"""Export the selected-personal-evidence and minimal job-analysis wire contracts."""

import importlib

from export_personal_import_contracts import ROOT, render_model, runtime_helpers

personal = importlib.import_module("app.schemas.personalization")
jobs = importlib.import_module("app.schemas.job_analysis")
MODELS = [
    personal.PersonalEvidenceSelection,
    personal.PersonalizationRequest,
    personal.PersonalEvidence,
    personal.PersonalizationContext,
    jobs.JobAnalysisRequest,
    jobs.PostingEvidence,
    jobs.PersonalEvidenceCitation,
    jobs.JobRequirementComparison,
    jobs.JobAnalysisResponse,
]
NAMES = {model.__name__: model.__name__ for model in MODELS}


def inline_enums(value, definitions):
    if isinstance(value, list):
        return [inline_enums(item, definitions) for item in value]
    if not isinstance(value, dict):
        return value
    definition = definitions.get(value.get("$ref", "").rsplit("/", 1)[-1], {})
    if "enum" in definition:
        return definition
    return {key: inline_enums(item, definitions) for key, item in value.items()}


def main():
    output = [
        "// GENERATED: scripts/export_job_analysis_contracts.py.\n"
        "// Personal evidence is unverified. No persistence, network or UI effects.\n"
        "abstract interface class JobAnalysisPayload { Map<String,Object?> toJson(); }\n",
        runtime_helpers(decimals=False),
    ]
    for model in MODELS:
        schema = model.model_json_schema()
        output.append(
            render_model(
                model,
                names=NAMES,
                payload_name="JobAnalysisPayload",
                schema=inline_enums(schema, schema.get("$defs", {})),
            )
        )
    (ROOT / "frontend/lib/features/api/job_analysis_models.dart").write_text("".join(output))
    print(f"Exported {len(MODELS)} personal evidence/job analysis models")


if __name__ == "__main__":
    main()
