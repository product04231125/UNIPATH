"""Export administrator request/review DTOs without changing any screens."""

import importlib

from export_personal_import_contracts import ROOT, render_model, runtime_helpers

dto = importlib.import_module("app.schemas.admin_applications")
MODELS = [
    dto.SchoolAdminApplicationCreate,
    dto.SchoolAdminApplicationCancel,
    dto.SchoolAdminApplicationReject,
    dto.SchoolAdminApplicationApprove,
    dto.SchoolAdminApplicationView,
    dto.SchoolAdminApplicant,
    dto.SchoolAdminApplicationReviewView,
    dto.SchoolAdminApplicationList,
    dto.SchoolAdminApplicationReviewList,
]
NAMES = {model.__name__: model.__name__ for model in MODELS}


def main():
    output = [
        "// GENERATED: scripts/export_admin_application_contracts.py.\n"
        "abstract interface class AdminApplicationPayload { Map<String,Object?> toJson(); }\n",
        "String _choice" + runtime_helpers().split("String _choice", 1)[1],
    ]
    for model in MODELS:
        output.append(render_model(model, names=NAMES, payload_name="AdminApplicationPayload"))
    (ROOT / "frontend/lib/features/api/admin_application_models.dart").write_text("".join(output))
    print(f"Exported {len(MODELS)} school administrator application models")


if __name__ == "__main__":
    main()
