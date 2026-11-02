"""Print a menu or render a local, synthetic audit fixture. Not an HTTP service."""

import argparse
import json
from pathlib import Path

from .service import catalog, respond


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("node", nargs="?", default="home")
    parser.add_argument("--catalog", action="store_true")
    parser.add_argument("--audit", type=Path, help="Local audit JSON; does not confer approval")
    args = parser.parse_args()
    audit = json.loads(args.audit.read_text(encoding="utf-8")) if args.audit else None
    payload = catalog() if args.catalog else respond(args.node, audit=audit)
    print(json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
