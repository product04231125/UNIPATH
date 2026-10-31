"""Generate explicit Dart wire models for the school knowledge review API."""

import importlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

dto = importlib.import_module("app.schemas.knowledge")
AssistantCitation = importlib.import_module("app.schemas.assistant").AssistantCitation
CitationApplicability = importlib.import_module("app.schemas.assistant").CitationApplicability

MODELS = [
    dto.ChunkPart,
    dto.ChunkView,
    dto.KnowledgeCreate,
    dto.PageReplace,
    dto.KnowledgeApprove,
    dto.KnowledgeRevoke,
    dto.KnowledgeView,
    dto.KnowledgeList,
    dto.PageView,
    dto.PageSummary,
    dto.PageList,
    dto.KnowledgeContext,
    dto.KnowledgeQuery,
    dto.KnowledgeSearch,
    CitationApplicability,
    AssistantCitation,
    dto.KnowledgeSearchResponse,
]
NAMES = {
    model.__name__: "SchoolKnowledge" + model.__name__.removeprefix("Knowledge") for model in MODELS
}
NAMES["AssistantCitation"] = "SchoolKnowledgeCitation"


def camel(value):
    first, *parts = value.split("_")
    return first + "".join(part.title() for part in parts)


def shape(field):
    choices = field.get("anyOf", [])
    nullable = any(item.get("type") == "null" for item in choices)
    actual = [item for item in choices if item.get("type") != "null"]
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
        value = {"string": "String", "integer": "int", "boolean": "bool"}[field["type"]]
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
    return f"{expression} as {dart_type(field)}"


def encode(field, expression):
    field, nullable = shape(field)
    suffix = "?" if nullable else ""
    if "$ref" in field:
        return expression + suffix + ".toJson()"
    if field.get("type") == "array":
        return expression + suffix + f".map((v) => {encode(field['items'], 'v')}).toList()"
    if field.get("format") == "date-time":
        return expression + suffix + ".toUtc().toIso8601String()"
    return expression


def main():
    output = [
        (
            "// GENERATED from Pydantic; run scripts/export_knowledge_contracts.py.\n"
            "// UUIDs/calendar dates are strings; instants are DateTime. "
            "No UI or storage effects.\n\n"
            "abstract interface class SchoolKnowledgePayload { Map<String,Object?> toJson(); }\n"
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
                else (f"this.{key}" if default == "null" else f"this.{key} = {default}")
            )
            expression = f"value['{wire}']"
            read = decode(field, expression)
            if nullable or optional:
                read = f"{expression} == null ? {default} : {read}"
            reads.append(f"{key}: {read}")
            writes.append(f"'{wire}': {encode(field, key)}")
        name = NAMES[model.__name__]
        decoded_arguments = ", ".join(reads)
        output.append(
            f"\nclass {name} implements SchoolKnowledgePayload {{\n"
            f"const {name}({{{', '.join(arguments)}}});\n"
            + "\n".join(fields)
            + f"\nfactory {name}.fromJson(Map<String,dynamic> value) => "
            + f"{name}({decoded_arguments});\n"
            + "\n@override\nMap<String,Object?> toJson() => {"
            + ", ".join(writes)
            + "};\n}\n"
        )
    destination = ROOT / "frontend/lib/features/api/school_knowledge_models.dart"
    destination.write_text("".join(output))
    print(f"Exported {len(MODELS)} school knowledge wire models")


if __name__ == "__main__":
    main()
