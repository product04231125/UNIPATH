"""Export the new Pydantic student DTOs as dependency-free Dart wire models.

Run from backend: uv run --frozen python ../scripts/export_student_contracts.py
Then dart format frontend/lib/features/api/student_api_models.dart.
This exports contracts only; it does not switch local student screens to remote storage.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from app.schemas import catalog  # noqa: E402
from app.schemas import personal as dto  # noqa: E402
from app.schemas.auth import InstitutionView  # noqa: E402


def camel(value):
    first, *rest = value.split("_")
    return first + "".join(part.title() for part in rest)


def field_type(field):
    alternatives = field.get("anyOf", [])
    nullable = any(item.get("type") == "null" for item in alternatives)
    options = [item for item in alternatives if item.get("type") != "null"]
    if {item.get("type") for item in options} == {"number", "string"}:
        return "String", nullable, "decimal"
    if len(options) == 1:
        field = options[0]
    if "$ref" in field:
        assert field["$ref"].endswith("/RecordReference")
        return "StudentRecordReference", nullable, "reference"
    if field.get("type") == "array":
        assert field["items"].get("$ref", "").endswith("/RecordReference")
        return "List<StudentRecordReference>", nullable, "references"
    if field.get("format") == "date-time":
        return "DateTime", nullable, "instant"
    return (
        {"string": "String", "boolean": "bool", "integer": "int"}[field["type"]],
        nullable,
        "scalar",
    )


def decode(kind, dart_type, expression):
    if kind == "decimal":
        return f"_decimal({expression})"
    if kind == "instant":
        return f"DateTime.parse({expression} as String)"
    if kind == "reference":
        return f"StudentRecordReference.fromJson(Map<String, dynamic>.from({expression} as Map))"
    if kind == "references":
        return (
            f"List.unmodifiable(({expression} as List).map((v) => "
            "StudentRecordReference.fromJson(Map<String, dynamic>.from(v as Map))))"
        )
    return f"{expression} as {dart_type}"


def encode(kind, key, nullable):
    suffix = "?" if nullable else ""
    if kind == "instant":
        return f"{key}{suffix}.toUtc().toIso8601String()"
    if kind == "reference":
        return f"{key}{suffix}.toJson()"
    if kind == "references":
        return f"{key}{suffix}.map((v) => v.toJson()).toList()"
    return key


def main():
    output = [
        "// GENERATED from backend Pydantic DTOs; run scripts/export_student_contracts.py.\n"
        "// Dates/UUIDs/Decimals stay wire strings. Instants are explicit DateTime values.\n"
        "// These models do not upload, replace or remove existing local student data.\n\n"
        "abstract interface class StudentPayload { Map<String, Object?> toJson(); }\n\n"
        "String _decimal(Object? value) {\n"
        "  if (value is String || value is num) return value.toString();\n"
        "  throw const FormatException('Expected a decimal wire value');\n}\n"
    ]
    models = [dto.RecordReference, dto.ProfileData, dto.ProfileView]
    for prefix in (
        "Event",
        "CourseRecord",
        "ActivityRecord",
        "ExperienceRecord",
        "CredentialRecord",
        "AchievementRecord",
        "PersonalCurriculum",
        "PersonalCurriculumCourse",
        "PersonalGraduationRule",
        "PortfolioComposition",
        "ApplicationDocument",
    ):
        models.append(getattr(dto, prefix + "Create"))
    models.append(InstitutionView)
    for prefix in (
        "Department",
        "Curriculum",
        "Course",
        "CurriculumCourse",
        "RuleSet",
        "Rule",
        "Document",
    ):
        models.append(getattr(catalog, prefix + "PublicView"))
    for model in models:
        name = "Student" + model.__name__
        schema = model.model_json_schema()
        properties = schema["properties"]
        required = schema.get("required", [])
        fields = []
        arguments = []
        reads = []
        writes = []
        for wire, field in properties.items():
            key = camel(wire)
            dart_type, nullable, kind = field_type(field)
            # Pydantic default_factory lists are optional without a JSON default.
            default = (
                "const []"
                if kind == "references"
                else json.dumps(field.get("default"), ensure_ascii=False)
            )
            is_required = wire in required
            if not is_required and default == "null":
                nullable = True
            fields.append(f"final {dart_type}{'?' if nullable else ''} {key};")
            arguments.append(
                f"required this.{key}"
                if is_required
                else (f"this.{key}" if default == "null" else f"this.{key} = {default}")
            )
            expression = f"value['{wire}']"
            read = decode(kind, dart_type, expression)
            if not is_required or nullable:
                read = f"{expression} == null ? {default} : {read}"
            reads.append(f"{key}: {read}")
            writes.append(f"'{wire}': {encode(kind, key, nullable)}")
        output.append(
            f"\nclass {name} implements StudentPayload {{\n"
            f"const {name}({{{', '.join(arguments)}}});\n"
            + "\n".join(fields)
            + f"\nfactory {name}.fromJson(Map<String, dynamic> value) => {name}("
            + ", ".join(reads)
            + ");\n@override\nMap<String, Object?> toJson() => {"
            + ", ".join(writes)
            + "};\n}\n"
        )
    target = ROOT / "frontend/lib/features/api/student_api_models.dart"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("".join(output), encoding="utf-8")
    print("Exported", len(models), "student wire models")


if __name__ == "__main__":
    main()
