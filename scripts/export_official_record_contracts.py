"""Generate reviewed school record contracts, preserving unknown and exact amounts."""

import importlib

from export_personal_import_contracts import ROOT, render_model, runtime_helpers

dto = importlib.import_module("app.schemas.official_records")
DATA = [dto.AcademicData, dto.VolunteerData, dto.CertificateData, dto.ThesisData]
MODELS = [
    dto.ReviewedContext,
    dto.AcademicRecord,
    dto.VolunteerRecord,
    dto.CertificateRecord,
    dto.ThesisRecord,
    *DATA,
    dto.BatchCreate,
    dto.BatchReplace,
    dto.BatchApprove,
    dto.BatchRevoke,
    dto.RecordReferenceSnapshot,
    dto.BatchHeader,
    dto.BatchView,
    dto.BatchList,
    dto.BatchEventView,
    dto.BatchEventList,
]
NAMES = {model.__name__: "SchoolRecord" + model.__name__ for model in MODELS}
NAMES["ReviewedContext"] = "SchoolRecordContext"
NAMES["RecordReferenceSnapshot"] = "SchoolRecordReferenceSnapshot"
UNIONS = {frozenset(model.__name__ for model in DATA): "SchoolRecordData"}


def main():
    output = [
        "// GENERATED: scripts/export_official_record_contracts.py.\n"
        "// Reviewed records remain separate from personal inputs and graduation decisions.\n"
        "abstract interface class SchoolRecordPayload { Map<String,Object?> toJson(); }\n",
        runtime_helpers(),
        "sealed class SchoolRecordData implements SchoolRecordPayload {\n"
        "const SchoolRecordData();\nString get kind;\n"
        "factory SchoolRecordData.fromJson(Map<String,dynamic> value) "
        "=> switch (value['kind']) {\n",
    ]
    for model in DATA:
        kind = model.model_json_schema()["properties"]["kind"]["const"]
        output.append(f"'{kind}' => {NAMES[model.__name__]}.fromJson(value),\n")
    output.append("_ => throw const FormatException('Unknown school record kind'),\n};\n}\n")
    for model in MODELS:
        output.append(
            render_model(
                model,
                names=NAMES,
                unions=UNIONS,
                payload_name="SchoolRecordPayload",
                base="SchoolRecordData" if model in DATA else None,
            )
        )
    (ROOT / "frontend/lib/features/api/official_record_models.dart").write_text("".join(output))
    print(f"Exported {len(MODELS)} reviewed school record models")


if __name__ == "__main__":
    main()
