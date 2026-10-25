"""Create an escaped, offline HTML worksheet. Never changes or approves source data."""

import argparse
import html
import json
from pathlib import Path

from ..school.retriever import load_chunks
from .readiness import inspect_corpus


def render(chunks: list[dict]) -> str:
    report = inspect_corpus(chunks)
    by_id = {c["chunk_id"]: c for c in chunks}
    sections = []
    for document in report["documents"]:
        parts = []
        for issue in document["chunks"]:
            chunk = by_id[issue["chunk_id"]]
            metadata = {
                k: chunk.get(k)
                for k in (
                    "chunk_id",
                    "page",
                    "source_url",
                    "admission_years",
                    "tracks",
                    "track",
                    "observed_admission_years",
                    "content_hash",
                    "source_character_start",
                    "source_character_end",
                )
            }
            metadata.update(blockers=issue["blockers"], warnings=issue["extraction_warnings"])
            parts.append(
                "<h3>페이지 "
                + str(chunk["page"])
                + "</h3><pre>"
                + html.escape(json.dumps(metadata, ensure_ascii=False, indent=2))
                + "</pre><pre>"
                + html.escape(chunk["content"])
                + "</pre>"
            )
        header = {k: v for k, v in document.items() if k != "chunks"}
        sections.append(
            "<section><h2>"
            + html.escape(document["title"])
            + "</h2><pre>"
            + html.escape(json.dumps(header, ensure_ascii=False, indent=2))
            + "</pre>"
            + "".join(parts)
            + "</section>"
        )
    return (
        """<!doctype html><html lang="ko"><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>RAG 원문 대조 검토 자료</title><style>
body{max-width:1000px;margin:32px auto;padding:20px;font-family:sans-serif;line-height:1.6}
pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f3f4f6;padding:16px}
section{border-top:2px solid #555;margin-top:32px}</style>
<h1>RAG 원문 대조 검토 자료</h1>
<p>자동 추출 검토용이며 공식 승인이 아닙니다. PDF 원본과 나란히 비교하세요.
표의 행·열·숫자·예외, 연도와 이수경로를 확인하세요. 관찰된 연도는 승인된 범위가 아닙니다.
빈 페이지는 사람이 확인한 선언이며 자동 추정하지 않습니다.</p>
<p>검토 기록: 문서/페이지/청크 ID · 원문 위치 · 문제 · 수정 제안 · 검토자 · 검토일.
이 HTML은 읽기 전용입니다. 기록은 별도 파일에 남기고 DB 승인 절차를 따르세요.</p>
"""
        + "".join(sections)
        + "</html>"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chunks", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        rendered = render(load_chunks(args.chunks))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        # Never overwrite a corpus, existing review, or a symlink target.
        with args.output.open("x", encoding="utf-8") as stream:
            stream.write(rendered)
    except (OSError, ValueError, KeyError, TypeError):
        parser.exit(2, "Review export failed; validate corpus and use a new output path.\n")


if __name__ == "__main__":
    main()
