"""Local integration harness. Never stores input, credentials or model output in logs."""

import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Career document draft/export")
    sub = parser.add_subparsers(dest="command", required=True)
    generate = sub.add_parser("generate")
    generate.add_argument("--input", type=Path, required=True, help="request + context JSON")
    generate.add_argument("--file", type=Path, action="append", default=[])
    generate.add_argument("--name", action="append", default=[], help="Names to redact")
    generate.add_argument("--output", type=Path, required=True)
    export = sub.add_parser("export")
    export.add_argument("--input", type=Path, required=True, help="Generation response JSON")
    export.add_argument("--profile", type=Path, required=True)
    export.add_argument("--reviewed", action="store_true")
    export.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = json.loads(args.input.read_text())
    if args.command == "generate":
        from app.core.config import Settings
        from app.services.gemini import create_model

        from .service import generate_draft

        config = Settings()
        result = generate_draft(
            data["request"],
            data["context"],
            create_model(config, timeout=config.vertex_timeout_seconds),
            files=[(p.name, p.read_bytes()) for p in args.file],
            names=tuple(args.name),
        )
        raw = json.dumps(result, ensure_ascii=False, indent=2).encode()
    else:
        from .docx_export import export_docx

        raw = export_docx(
            data["draft"],
            json.loads(args.profile.read_text()),
            document_type=data["document_type"],
            reviewed=args.reviewed,
        )
    # Never overwrite an existing draft or source file, even if paths are mistaken.
    with args.output.open("xb") as stream:
        stream.write(raw)
    args.output.chmod(0o600)
    print("Created:", args.output)


if __name__ == "__main__":
    main()
