"""Export initial school signup DTOs; account credentials remain in AuthApi."""

import importlib

from export_personal_import_contracts import ROOT, render_model, runtime_helpers

dto = importlib.import_module("app.schemas.admin_signups")
auth = importlib.import_module("app.schemas.auth")
MODELS = [
    auth.InstitutionCreate,
    dto.SchoolAdminSignupDetails,
    dto.SchoolAdminSignupApprove,
    dto.SchoolAdminSignupView,
    dto.SchoolAdminSignupReviewView,
    dto.SchoolAdminSignupList,
    dto.SchoolAdminSignupReviewList,
]
NAMES = {model.__name__: model.__name__ for model in MODELS}
NAMES.update(InstitutionCreate="SignupNewInstitution", SchoolAdminApplicant="SchoolAdminApplicant")


def main():
    output = [
        "// GENERATED: scripts/export_school_signup_contracts.py.\n"
        "import 'admin_application_models.dart' show SchoolAdminApplicant;\n"
        "abstract interface class SchoolSignupPayload { Map<String,Object?> toJson(); }\n",
        "String _choice" + runtime_helpers().split("String _choice", 1)[1],
    ]
    for model in MODELS:
        output.append(render_model(model, names=NAMES, payload_name="SchoolSignupPayload"))
    (ROOT / "frontend/lib/features/api/school_signup_models.dart").write_text("".join(output))
    print(f"Exported {len(MODELS)} school signup models")


if __name__ == "__main__":
    main()
