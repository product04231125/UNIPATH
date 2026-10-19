"""Generate the typed, local-ID import contract; no workspace access or upload."""

import importlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
dto = importlib.import_module("app.schemas.personal_imports")
personal = importlib.import_module("app.schemas.personal")
MODELS = [
    dto.ImportEvent,
    dto.ImportCourseRecord,
    dto.ImportActivityRecord,
    dto.ImportExperienceRecord,
    dto.ImportCredentialRecord,
    dto.ImportAchievementRecord,
    dto.ImportPersonalCurriculum,
    dto.ImportRecordReference,
    dto.ImportCurriculumCourse,
    dto.ImportGraduationRule,
    dto.ImportComposition,
    dto.ImportApplicationDocument,
    personal.ProfileData,
    dto.PersonalImportCreate,
    dto.ImportMapping,
    dto.PersonalImportView,
]
NAMES = {model.__name__: "Personal" + model.__name__ for model in MODELS}
NAMES.update(
    {
        "ProfileData": "PersonalImportProfile",
        "PersonalImportCreate": "PersonalImportRequest",
        "PersonalImportView": "PersonalImportReceipt",
    }
)


def camel(value):
    first, *parts = value.split("_")
    return first + "".join(part.title() for part in parts)


def shape(field):
    choices = field.get("anyOf", [])
    nullable = any(item.get("type") == "null" for item in choices)
    actual = [item for item in choices if item.get("type") != "null"]
    if {item.get("type") for item in actual} == {"number", "string"}:
        return {"type": "decimal"}, nullable
    return actual[0] if len(actual) == 1 else field, nullable


def dart_type(field):
    field, nullable = shape(field)
    if "$ref" in field:
        value = NAMES[field["$ref"].rsplit("/", 1)[1]]
    elif field.get("type") == "array":
        value = "List<" + dart_type(field["items"]) + ">"
    elif field.get("format") == "date-time":
        value = "DateTime"
    else:
        value = {"string": "String", "decimal": "String", "integer": "int", "boolean": "bool"}[
            field["type"]
        ]
    return value + ("?" if nullable else "")


def decode(field, expression):
    field, _ = shape(field)
    if "$ref" in field:
        return (
            NAMES[field["$ref"].rsplit("/", 1)[1]]
            + f".fromJson(Map<String,dynamic>.from({expression} as Map))"
        )
    if field.get("type") == "array":
        return (
            f"List.unmodifiable(({expression} as List).map((v) => {decode(field['items'], 'v')}))"
        )
    if field.get("format") == "date-time":
        return f"DateTime.parse({expression} as String)"
    if field.get("type") == "decimal":
        return f"_decimal({expression})"
    if "const" in field:
        return f"_constant({expression}, {json.dumps(field['const'])}) as {dart_type(field)}"
    if "enum" in field:
        return f"_choice({expression}, {json.dumps(field['enum'])})"
    return f"{expression} as {dart_type(field)}"


def encode(field, key):
    field, nullable = shape(field)
    suffix = "?" if nullable else ""
    if "$ref" in field:
        return key + suffix + ".toJson()"
    if field.get("type") == "array":
        return key + suffix + f".map((v) => {encode(field['items'], 'v')}).toList()"
    if field.get("format") == "date-time":
        return key + suffix + ".toUtc().toIso8601String()"
    return key


def main():
    output = [
        (
            "// GENERATED: scripts/export_personal_import_contracts.py.\n"
            "// Local reference UUIDs are explicit client IDs. No storage or upload effects.\n"
            "abstract interface class PersonalImportPayload { Map<String,Object?> toJson(); }\n"
            "String _decimal(Object? value) {\n"
            " if (value is String || (value is num && value.isFinite)) "
            "{ return value.toString(); }\n"
            " throw const FormatException('Expected decimal wire value');\n}\n"
            "Object _constant(Object? value, Object expected) {\n"
            " if (value != expected) { "
            "throw const FormatException('Unexpected contract constant'); }\n"
            " return expected;\n}\n"
            "String _choice(Object? value, List<String> allowed) {\n"
            " if (value is! String || !allowed.contains(value)) { "
            "throw const FormatException('Unknown contract value'); }\n"
            " return value;\n}\n"
        )
    ]
    for model in MODELS:
        schema = model.model_json_schema()
        required = set(schema.get("required", []))
        fields, arguments, reads, writes = [], [], [], []
        for wire, field in schema["properties"].items():
            key = camel(wire)
            base, nullable = shape(field)
            optional = wire not in required
            default = (
                "const []"
                if optional and not nullable and base.get("type") == "array"
                else json.dumps(field.get("default"), ensure_ascii=False)
            )
            value_type = dart_type(field)
            if optional and default == "null" and not value_type.endswith("?"):
                value_type += "?"
            fields.append(f"final {value_type} {key};")
            arguments.append(
                f"required this.{key}"
                if not optional
                else f"this.{key}"
                if default == "null"
                else f"this.{key} = {default}"
            )
            expression = f"value['{wire}']"
            read = decode(field, expression)
            if nullable or optional:
                read = f"{expression} == null ? {default} : {read}"
            reads.append(f"{key}: {read}")
            writes.append(f"'{wire}': {encode(field, key)}")
        name = NAMES[model.__name__]
        output.append(
            f"\nclass {name} implements PersonalImportPayload {{\n"
            f"const {name}({{{', '.join(arguments)}}});\n"
            + "\n".join(fields)
            + f"\nfactory {name}.fromJson(Map<String,dynamic> value) "
            + f"=> {name}({', '.join(reads)});\n"
            + "@override\nMap<String,Object?> toJson() => {"
            + ", ".join(writes)
            + "};\n}\n"
        )
    path = ROOT / "frontend/lib/features/api/personal_import_models.dart"
    path.write_text("".join(output))
    print(f"Exported {len(MODELS)} personal import wire models")


if __name__ == "__main__":
    main()
