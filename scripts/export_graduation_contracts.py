"""Generate typed graduation review/audit contracts without UI or storage effects."""

import importlib

from export_personal_import_contracts import ROOT, render_model, runtime_helpers
from export_rule_program_contracts import CONDITIONS
from export_rule_program_contracts import NAMES as PROGRAM_NAMES

dto = importlib.import_module("app.schemas.graduation")
MODELS = [
    dto.GraduationContext,
    dto.CatalogPreview,
    dto.CatalogReviewCreate,
    dto.CatalogReviewRevoke,
    dto.CatalogReviewHeader,
    dto.CatalogReviewView,
    dto.CatalogReviewList,
    dto.CatalogReviewEvent,
    dto.CatalogReviewEvents,
    dto.GraduationAuditCreate,
    dto.AuditEvidence,
    dto.AuditedRule,
    dto.AuditedProgram,
    dto.AuditedBatch,
    dto.AuditRecordEvidence,
    dto.AuditIssue,
    dto.AuditResultItem,
    dto.GraduationAuditHeader,
    dto.GraduationAuditView,
    dto.GraduationAuditList,
]
NAMES = {**PROGRAM_NAMES, **{model.__name__: model.__name__ for model in MODELS}}
UNIONS = {frozenset(model.__name__ for model in CONDITIONS): "OfficialCondition"}


def main():
    output = [
        "// GENERATED: scripts/export_graduation_contracts.py.\n"
        "// eligible_as_of is historical; always check evaluated_on and current_usable.\n"
        "import 'rule_program_models.dart';\n"
        "abstract interface class GraduationPayload { Map<String,Object?> toJson(); }\n",
        runtime_helpers(),
    ]
    for model in MODELS:
        output.append(
            render_model(model, names=NAMES, unions=UNIONS, payload_name="GraduationPayload")
        )
    (ROOT / "frontend/lib/features/api/graduation_models.dart").write_text("".join(output))
    print(f"Exported {len(MODELS)} graduation review/audit models")


if __name__ == "__main__":
    main()
