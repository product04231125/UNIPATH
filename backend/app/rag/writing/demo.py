"""Synthetic examples only. No network, real student data or fabricated live-model claims."""

import argparse
import json
from pathlib import Path

RID = "00000000-0000-4000-8000-000000000101"
SOURCE = (
    "교내 도서 대출 실습 프로젝트. 기간 2026년 3월부터 6월. "
    "역할 API 구현과 테스트. Python과 SQL을 사용했다. "
    "대출 및 반납 API를 구현하고 중복 대출 상황의 테스트를 작성했다. "
    "동료와 오류 재현 과정을 공유하고 README에 실행 방법을 정리했다."
)
CONTEXT = {"records": [dict(kind="experience", record_id=RID, version=1, text=SOURCE)]}


def cited(text, excerpt):
    return {
        "text": text,
        "citations": [dict(kind="experience", record_id=RID, version=1, excerpt=excerpt)],
    }


def sample(document_type):
    if document_type == "cover_letter":
        sections = [
            {
                "heading": "직무 관련 경험",
                "paragraphs": [
                    cited(
                        "교내 도서 대출 실습 프로젝트에서 Python과 SQL을 활용해 대출 및 반납 API를 "
                        "구현했습니다. 제가 맡은 범위는 API 구현과 테스트였으며, 사용 흐름에 맞춰 "
                        "기능을 만들고 동작을 점검했습니다.",
                        SOURCE,
                    )
                ],
            },
            {
                "heading": "문제 해결 과정",
                "paragraphs": [
                    cited(
                        "중복 대출 상황을 테스트 사례로 작성했습니다. 정상 흐름뿐 아니라 "
                        "예외 상황을 재현할 수 있도록 테스트를 남기는 데 집중했습니다.",
                        "대출 및 반납 API를 구현하고 중복 대출 상황의 테스트를 작성했다.",
                    )
                ],
            },
            {
                "heading": "협업과 기록",
                "paragraphs": [
                    cited(
                        "동료와 오류 재현 과정을 공유하고 README에 실행 방법을 정리했습니다. "
                        "구현 내용을 확인할 수 있도록 설명과 실행 절차를 함께 남겼습니다.",
                        "동료와 오류 재현 과정을 공유하고 README에 실행 방법을 정리했다.",
                    )
                ],
            },
        ]
    else:
        sections = [
            {
                "heading": "경험 소개",
                "paragraphs": [
                    cited(
                        "Python과 SQL을 사용한 교내 실습에서 API 구현과 테스트를 담당했습니다. "
                        "대표 프로젝트의 담당 범위와 결과를 아래에 정리했습니다.",
                        SOURCE,
                    )
                ],
            },
            {
                "heading": "도서 대출 실습 프로젝트",
                "facts": [
                    {"label": "기간", **cited("2026년 3월부터 6월", "기간 2026년 3월부터 6월.")},
                    {"label": "역할", **cited("API 구현과 테스트", "역할 API 구현과 테스트.")},
                    {"label": "사용 기술", **cited("Python 및 SQL", "Python과 SQL을 사용했다.")},
                ],
                "paragraphs": [
                    cited(
                        "대출 및 반납 API를 구현했습니다. 중복 대출 상황의 테스트도 작성했습니다. "
                        "API 구현과 예외 상황 점검을 함께 수행한 프로젝트입니다.",
                        "대출 및 반납 API를 구현하고 중복 대출 상황의 테스트를 작성했다.",
                    )
                ],
            },
            {
                "heading": "협업 결과",
                "paragraphs": [
                    cited(
                        "오류 재현 과정을 동료와 공유하고 README에 실행 방법을 정리했습니다. "
                        "구현 결과를 확인할 수 있는 실행 절차를 문서로 남겼습니다.",
                        "동료와 오류 재현 과정을 공유하고 README에 실행 방법을 정리했다.",
                    )
                ],
            },
        ]
    return {
        "document_type": document_type,
        "draft": {
            "sections": sections,
            "questions_for_user": ["지원 동기를 알려주세요."],
            "revisions": [],
        },
    }


def main():
    from .docx_export import export_docx

    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for kind in ("cover_letter", "portfolio"):
        value = sample(kind)
        raw = export_docx(
            value["draft"], {"name": "가상 지원자"}, document_type=kind, reviewed=True
        )
        with (args.output_dir / f"sample-{kind}.docx").open("xb") as stream:
            stream.write(raw)
        with (args.output_dir / f"sample-{kind}.json").open("x") as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
    print("Created synthetic examples; no model was called.")


if __name__ == "__main__":
    main()
