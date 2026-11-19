"""Opt-in live analysis evaluation. Does not create accounts or store user documents in Git."""

import argparse
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from time import monotonic

from app.core.config import get_settings

from .api import portfolio_analyzer
from .contracts import Posting, failure_reason
from .documents import prepare_documents


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--postings", type=Path, required=True)
    parser.add_argument("--profiles", type=Path, required=True)
    parser.add_argument("--portfolio", type=Path)
    parser.add_argument("--redact-name", action="append", default=[])
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Private output location outside the Git checkout",
    )
    parser.add_argument("--workers", type=int, choices=(1, 2, 3), default=1)
    parser.add_argument("--allow-network", action="store_true")
    args = parser.parse_args()
    if not args.allow_network:
        parser.error("--allow-network is required for paid external model calls")
    if args.portfolio and args.output.resolve().is_relative_to(Path(__file__).resolve().parents[4]):
        parser.error("Personal portfolio results must be written outside this checkout")
    model = portfolio_analyzer(get_settings())
    if model is None:
        parser.error("Configure VERTEX_PROJECT, VERTEX_LOCATION, VERTEX_MODEL and ADC")
    postings = [Posting(**p) for p in json.loads(args.postings.read_text())]
    if not 1 <= len(postings) <= 20:
        parser.error("Choose 1 to 20 fixed public postings")
    profiles = json.loads(args.profiles.read_text())
    if not 1 <= len(profiles) <= 4:
        parser.error("Choose 1 to 4 synthetic profiles")
    cases = []
    for profile in profiles:
        context, _, _ = prepare_documents([(profile["case"] + ".txt", profile["text"].encode())])
        cases.append((profile["case"], context))
    if args.portfolio:
        context, _, _ = prepare_documents(
            [(args.portfolio.name, args.portfolio.read_bytes())], names=tuple(args.redact_name)
        )
        cases.insert(0, ("actual_pdf", context))

    def compare(posting, case):
        name, context = case
        started = monotonic()
        result = {"case": name, "posting_id": posting.source_id, "title": posting.title}
        try:
            values = model.analyze(posting.text, context)
            result.update(
                status="completed",
                comparisons=[
                    {
                        k: v
                        for k, v in value.items()
                        if k in {"priority", "requirement", "status", "explanation"}
                    }
                    for value in values
                ],
            )
        except Exception as error:
            result.update(status="failed", reason=failure_reason(error))
        result["seconds"] = round(monotonic() - started, 1)
        return result

    results = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(compare, posting, case) for posting in postings for case in cases]
        for future in as_completed(futures):
            result = future.result()
            results.append(result)
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2))
            print(
                json.dumps(
                    {
                        "done": len(results),
                        "total": len(futures),
                        "status": result["status"],
                        "reason": result.get("reason"),
                    }
                ),
                flush=True,
            )


if __name__ == "__main__":
    main()
