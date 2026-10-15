"""Evaluate private criteria locally; never accept client-supplied official approvals."""

import argparse
import json
from datetime import date
from pathlib import Path
from uuid import UUID

from pydantic import ValidationError

from app.rules.contracts import Contract, CreditRule, Origin, RuleSet, Snapshot
from app.rules.engine import evaluate_personal


class PersonalInput(Contract):
    rule_sets: tuple[RuleSet, ...]
    snapshot: Snapshot
    evaluated_on: date


def demo() -> PersonalInput:
    return PersonalInput(
        evaluated_on=date(2026, 10, 12),
        rule_sets=(
            RuleSet(
                id=UUID(int=1),
                code="synthetic_personal",
                version=1,
                origin=Origin.PERSONAL,
                rules=(
                    CreditRule(
                        id=UUID(int=2),
                        code="synthetic_credits",
                        title="합성 학점 예시",
                        minimum="6",
                    ),
                ),
            ),
        ),
        snapshot=Snapshot.model_validate(
            {
                "academics": [
                    {
                        "id": str(UUID(int=3)),
                        "course_id": str(UUID(int=4)),
                        "completion_status": "completed",
                        "earned_credits": "3",
                    }
                ]
            }
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--input", type=Path, help="Private personal JSON input, at most 256 KiB")
    mode.add_argument("--demo", action="store_true", help="Run an explicitly synthetic example")
    args = parser.parse_args()
    try:
        if args.demo:
            payload = demo()
        else:
            with args.input.open("rb") as stream:
                raw = stream.read(256 * 1024 + 1)
            if len(raw) > 256 * 1024:
                raise ValueError("Input exceeds 256 KiB")
            payload = PersonalInput.model_validate_json(raw)
        if any(r.origin != Origin.PERSONAL for r in payload.rule_sets):
            raise ValueError(
                "Local input supports only personal criteria, never official approvals"
            )
        result = evaluate_personal(
            payload.rule_sets,
            payload.snapshot,
            as_of=payload.evaluated_on,
        )
    except ValidationError as error:
        fields = [".".join(map(str, e["loc"])) for e in error.errors(include_input=False)]
        parser.exit(2, json.dumps({"error": "invalid_input", "fields": fields}) + "\n")
    except (OSError, ValueError):
        parser.exit(2, '{"error":"invalid_personal_input"}\n')
    print(result.model_dump_json(indent=2))


if __name__ == "__main__":
    main()
