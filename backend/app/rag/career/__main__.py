"""Run the document → live postings → Vertex comparison path with local selected files."""

import argparse
import json
from pathlib import Path

from app.core.config import get_settings

from .api import configured_sources, portfolio_analyzer
from .contracts import SearchQuery
from .documents import MAX_BYTES, prepare_documents
from .recommendations import recommend


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path)
    parser.add_argument("--keyword", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--saramin-region")
    parser.add_argument("--work24-region")
    parser.add_argument("--name", default="", help="Name to redact from selected files")
    parser.add_argument("--limit", type=int, choices=(1, 2, 3), default=1)
    parser.add_argument(
        "--consent",
        action="store_true",
        help="Send redacted personal evidence to the configured paid Vertex project",
    )
    args = parser.parse_args()
    if not args.consent:
        parser.error("--consent is required for external processing")
    settings = get_settings()
    analyzer = portfolio_analyzer(settings)
    if analyzer is None:
        parser.exit(2, "Vertex 프로젝트·리전·모델 설정과 ADC를 확인해 주세요.\n")
    codes = {
        k: v for k, v in [("saramin", args.saramin_region), ("work24", args.work24_region)] if v
    }
    query = SearchQuery(args.keyword, args.region, args.region == "전국", codes, args.limit)
    if len(args.files) > 5 or sum(file.stat().st_size for file in args.files) > MAX_BYTES:
        parser.error("파일은 최대 5개, 총 8MiB까지 지원합니다.")
    records, locations, warnings = prepare_documents(
        [(file.name, file.read_bytes()) for file in args.files], names=(args.name,)
    )
    result = recommend(query, records["records"], configured_sources(), analyzer)
    print(
        json.dumps(
            {
                **result,
                "model": settings.vertex_model,
                "document_locations": locations,
                "document_warnings": warnings,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    if not any(
        i["analysis_status"] in {"completed", "insufficient_evidence"} for i in result["items"]
    ):
        parser.exit(
            1, "모델 비교가 끝난 공고가 없습니다. 검색 결과와 공급자별 상태를 확인해 주세요.\n"
        )


if __name__ == "__main__":
    main()
