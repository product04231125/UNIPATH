"""Draft generation safety and real editable DOCX structure, using synthetic data."""

import copy
from io import BytesIO
from unittest.mock import Mock
from zipfile import ZipFile

import docx
import pytest

from app.rag.career.contracts import AnalysisRejected
from app.rag.writing.contracts import Draft, EditedDocument
from app.rag.writing.docx_export import export_docx
from app.rag.writing.service import RECORD_BUDGET, generate_draft

RID = "00000000-0000-4000-8000-000000000101"
SOURCE = (
    "교내 도서 대출 실습 프로젝트. 기간 2026년 3월부터 6월. "
    "역할 API 구현과 테스트. Python과 SQL을 사용했다. "
    "대출 및 반납 API를 구현하고 중복 대출 상황의 테스트를 작성했다. "
    "동료와 오류 재현 과정을 공유하고 README에 실행 방법을 정리했다."
)
RECORDS = [dict(kind="experience", record_id=RID, version=1, text=SOURCE)]


def cited(text, excerpt, record_id=RID):
    return {
        "text": text,
        "citations": [dict(kind="experience", record_id=record_id, version=1, excerpt=excerpt)],
    }


def output():
    return {
        "sections": [
            {
                "heading": "직무 관련 경험",
                "paragraphs": [
                    cited(
                        "도서 대출 실습에서 Python과 SQL로 대출 및 반납 API를 구현했습니다.",
                        "대출 및 반납 API를 구현하고",
                    ),
                    cited(
                        "동료와 오류 재현 과정을 공유했습니다.", "동료와 오류 재현 과정을 공유하고"
                    ),
                ],
                "facts": [
                    {"label": "기간", **cited("2026년 3월부터 6월", "기간 2026년 3월부터 6월.")},
                    {"label": "역할", **cited("API 구현과 테스트", "역할 API 구현과 테스트.")},
                ],
            },
            {
                "heading": "협업과 기록",
                "paragraphs": [
                    cited("README에 실행 방법을 정리했습니다.", "README에 실행 방법을 정리했다.")
                ],
            },
        ],
        "questions_for_user": ["지원 동기를 알려주세요."],
        "revisions": [],
    }


def request(**updates):
    return {
        "document_type": "portfolio",
        "target_role": "백엔드 개발",
        "external_processing_consent": True,
        **updates,
    }


def model(value=None):
    return Mock(generate=Mock(return_value=copy.deepcopy(value or output())))


def test_consent_precedes_the_model_call():
    generator = model()
    with pytest.raises(ValueError, match="consent"):
        generate_draft(request(external_processing_consent=False), RECORDS, generator)
    generator.generate.assert_not_called()


def test_generation_redacts_and_sends_posting_questions_and_limit():
    generator = model()
    records = copy.deepcopy(RECORDS)
    records[0]["text"] += " 이름 홍길동 연락처 010-1234-5678"
    before = copy.deepcopy(records)
    result = generate_draft(
        request(
            document_type="cover_letter",
            posting_text="담당업무: 도서관 API 개발 (담당자 홍길동)",
            questions=["지원 직무와 관련된 경험을 적어 주세요."],
            char_limit=800,
        ),
        records,
        generator,
        names=("홍길동",),
    )
    assert result["status"] == "draft_ready" and result["review_required"] is True
    assert result["draft"]["questions_for_user"] == ["지원 동기를 알려주세요."]
    assert result["warnings"] == []
    payload = generator.generate.call_args.args[1]
    assert "홍길동" not in str(payload) and "010-1234-5678" not in str(payload)
    assert "도서관 API 개발" in payload["posting_text"]
    assert payload["questions"] == ["지원 직무와 관련된 경험을 적어 주세요."]
    assert payload["char_limit"] == 800
    assert generator.generate.call_args.kwargs["max_output_tokens"] > 8192
    assert records == before


@pytest.mark.parametrize(
    "change",
    [
        {"excerpt": "취업률 100% 달성"},
        {"version": 2},
        {"record_id": "00000000-0000-4000-8000-000000000199"},
    ],
)
def test_an_unverifiable_paragraph_is_dropped_not_the_whole_draft(change):
    value = output()
    value["sections"][0]["paragraphs"][0]["citations"][0].update(change)
    result = generate_draft(request(), RECORDS, model(value))
    paragraphs = result["draft"]["sections"][0]["paragraphs"]
    assert [p["text"] for p in paragraphs] == ["동료와 오류 재현 과정을 공유했습니다."]
    assert "1개는 초안에서 뺐습니다" in result["warnings"][-1]


def test_only_verified_citations_are_kept_and_excerpts_come_from_the_record():
    value = output()
    paragraph = value["sections"][1]["paragraphs"][0]
    paragraph["citations"].append({**paragraph["citations"][0], "excerpt": "없는 문장"})
    paragraph["citations"][0]["excerpt"] = "README에  실행 방법을 정리했다."
    result = generate_draft(request(), RECORDS, model(value))
    citations = result["draft"]["sections"][1]["paragraphs"][0]["citations"]
    assert [c["excerpt"] for c in citations] == ["README에 실행 방법을 정리했다."]


def test_sections_without_verified_parts_are_removed_and_revisions_follow():
    value = output()
    value["sections"][0]["paragraphs"] = [cited("없는 경험", "없는 문장")]
    value["sections"][0]["facts"] = []
    value["revisions"] = [
        {"original_excerpt": "프로젝트를  했습니다", "section_index": 1, "reason": "구체화"},
        {"original_excerpt": "프로젝트를 했습니다", "section_index": 0, "reason": "삭제된 섹션"},
        {"original_excerpt": "없는 원문", "section_index": 1, "reason": "확인 불가"},
    ]
    result = generate_draft(
        request(mode="improve", original_text="프로젝트를 했습니다"), RECORDS, model(value)
    )
    draft = result["draft"]
    assert [s["heading"] for s in draft["sections"]] == ["협업과 기록"]
    assert draft["revisions"] == [
        {"original_excerpt": "프로젝트를 했습니다", "section_index": 0, "reason": "구체화"}
    ]
    assert len(result["original_record_ids"]) == 1


def test_nothing_verified_fails_and_create_mode_ignores_revisions():
    value = output()
    for section in value["sections"]:
        for part in [*section["paragraphs"], *section.get("facts", [])]:
            part["citations"][0]["excerpt"] = "없는 문장"
    with pytest.raises(AnalysisRejected):
        generate_draft(request(), RECORDS, model(value))
    value = output()
    value["revisions"] = [{"original_excerpt": "x", "section_index": 0, "reason": "y"}]
    assert generate_draft(request(), RECORDS, model(value))["draft"]["revisions"] == []


def test_improve_requires_an_original_and_warns_without_revision_notes():
    with pytest.raises(ValueError, match="original"):
        generate_draft(request(mode="improve"), RECORDS, model())
    result = generate_draft(request(mode="improve", original_text=SOURCE), RECORDS, model())
    assert result["draft"]["sections"] and result["draft"]["revisions"] == []
    assert "어느 부분을 고쳤는지" in result["warnings"][-1]


def test_a_pasted_original_alone_is_citable_evidence():
    generator = Mock()

    def generate(instruction, payload, **options):
        original = payload["records"][0]
        assert original["text"] == "도서 대출 API를 만들었습니다."
        value = output()
        value["sections"] = [
            {
                "heading": "경험",
                "paragraphs": [
                    cited("대출 API를 만들었습니다.", "대출 API를", original["record_id"])
                ],
            }
        ]
        value["revisions"] = [
            {"original_excerpt": "도서 대출 API", "section_index": 0, "reason": "다듬음"}
        ]
        return value

    generator.generate.side_effect = generate
    result = generate_draft(
        request(mode="improve", original_text="도서 대출 API를 만들었습니다."), [], generator
    )
    assert (
        result["draft"]["sections"][0]["paragraphs"][0]["citations"][0]["excerpt"] == "대출 API를"
    )
    assert result["original_record_ids"] == [
        result["draft"]["sections"][0]["paragraphs"][0]["citations"][0]["record_id"]
    ]


def test_records_past_the_budget_keep_the_most_relevant_and_the_whole_original():
    records = [
        dict(
            kind="experience",
            record_id=f"00000000-0000-4000-8000-{i:012}",
            version=1,
            text="백엔드 API 개발 " * 700 if i == 5 else "가" * 8000,
        )
        for i in range(6)
    ] + copy.deepcopy(RECORDS)
    generator = model()
    original = "원문 " * 4000
    result = generate_draft(request(mode="improve", original_text=original), records, generator)
    sent = generator.generate.call_args.args[1]["records"]
    assert sum(len(r["text"]) for r in sent) <= RECORD_BUDGET
    assert sent[0]["text"].startswith("원문")
    assert records[5]["record_id"] in {r["record_id"] for r in sent}
    assert "관련이 높은 기록" in result["warnings"][0]


def test_long_questions_for_the_user_are_trimmed():
    value = output()
    value["questions_for_user"] = ["가" * 300, "", 3]
    result = generate_draft(request(), RECORDS, model(value))
    assert result["draft"]["questions_for_user"] == ["가" * 120]


def test_empty_sections_and_xml_control_characters_rejected():
    with pytest.raises(ValueError):
        Draft.model_validate({"sections": [{"heading": "빈 문서"}]})
    data = output()
    data["sections"][0]["paragraphs"][0]["text"] = "잘못된\x00문자"
    with pytest.raises(ValueError):
        EditedDocument.model_validate(data)


def test_export_requires_review():
    with pytest.raises(ValueError, match="Review"):
        export_docx(output(), {"name": "가상"}, document_type="portfolio")


@pytest.mark.parametrize("kind", ["portfolio", "cover_letter"])
def test_docx_has_edited_content_no_protection_and_no_review_notes(kind):
    data = output()
    if kind == "cover_letter":
        for section in data["sections"]:
            section["facts"] = []
    data["sections"][0]["paragraphs"][0]["text"] = "사용자가 수정한 문장 <확인> & 검토"
    # The owner may add a paragraph of their own; it has no citation and still exports.
    data["sections"][1]["paragraphs"].append({"text": "직접 추가한 문단"})
    raw = export_docx(data, {"name": "가상 지원자"}, document_type=kind, reviewed=True)
    document = docx.Document(BytesIO(raw))
    texts = [p.text for p in document.paragraphs]
    assert "사용자가 수정한 문장 <확인> & 검토" in texts and "직접 추가한 문단" in texts
    assert bool(document.tables) == (kind == "portfolio")
    assert round(document.sections[0].page_width.mm) == 210
    document.paragraphs[0].text = "Word에서 편집 가능"
    changed = BytesIO()
    document.save(changed)
    assert docx.Document(BytesIO(changed.getvalue())).paragraphs[0].text == "Word에서 편집 가능"
    with ZipFile(BytesIO(raw)) as archive:
        xml = archive.read("word/document.xml").decode()
        assert "지원 동기를 알려주세요" not in xml
        assert "record_id" not in xml and "README에 실행 방법을 정리했다." not in xml
        assert b"documentProtection" not in archive.read("word/settings.xml")
        assert not any("vbaProject" in name for name in archive.namelist())
