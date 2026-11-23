"""Draft generation safety and real editable DOCX structure, using synthetic data."""

import copy
from io import BytesIO
from unittest.mock import Mock
from zipfile import ZipFile

import pytest

from app.rag.writing.contracts import Draft
from app.rag.writing.demo import CONTEXT, SOURCE, sample
from app.rag.writing.docx_export import export_docx
from app.rag.writing.service import generate_draft


def request(**updates):
    return {
        "document_type": "portfolio",
        "target_role": "백엔드 개발",
        "external_processing_consent": True,
        **updates,
    }


def model():
    return Mock(generate=Mock(return_value=copy.deepcopy(sample("portfolio")["draft"])))


def test_consent_precedes_parsing_and_model_call():
    generator = model()
    with pytest.raises(ValueError, match="consent"):
        generate_draft(
            request(external_processing_consent=False), {}, generator, files=[("bad.pdf", b"bad")]
        )
    generator.generate.assert_not_called()


def test_generation_preserves_sources_and_keeps_private_profile_out():
    generator = model()
    context = copy.deepcopy(CONTEXT)
    context["records"][0]["text"] += " 이름 홍길동 연락처 010-1234-5678"
    before = copy.deepcopy(context)
    output = generate_draft(request(), context, generator, names=("홍길동",))
    assert output["review_required"] is True
    assert output["draft"]["questions_for_user"]
    payload = str(generator.generate.call_args.args[1])
    assert "홍길동" not in payload
    assert "010-1234-5678" not in payload
    assert context == before
    generator.generate.assert_called_once()


def test_selected_profile_is_redacted_and_has_a_traceable_source():
    generator = model()
    output = generate_draft(
        request(), CONTEXT, generator, profile_text="홍길동 컴퓨터공학과", names=("홍길동",)
    )
    payload = generator.generate.call_args.args[1]
    assert "홍길동" not in str(payload)
    profile_record = payload["records"][-1]
    assert "컴퓨터공학과" in profile_record["text"]
    assert output["document_locations"][profile_record["record_id"]]["method"] == "text"


def test_upload_limit_is_checked_before_model_call():
    generator = model()
    with pytest.raises(ValueError, match="8MiB"):
        generate_draft(request(), CONTEXT, generator, files=[("x.txt", b"x")] * 6)
    generator.generate.assert_not_called()


@pytest.mark.parametrize("change", ["excerpt", "version", "record_id"])
def test_unverifiable_citation_rejects_draft(change):
    generator = model()
    cite = generator.generate.return_value["sections"][0]["paragraphs"][0]["citations"][0]
    cite[change] = {
        "excerpt": "취업률 100% 달성",
        "version": 2,
        "record_id": "00000000-0000-4000-8000-000000000199",
    }[change]
    with pytest.raises(ValueError):
        generate_draft(request(), CONTEXT, generator)


def test_improve_returns_new_draft_with_exact_original_reference():
    generator = model()
    generator.generate.return_value["revisions"] = [
        {
            "original_excerpt": "프로젝트를 했습니다",
            "section_index": 1,
            "reason": "등록된 경험을 바탕으로 담당 역할과 구현 내용을 구체화했습니다.",
        }
    ]
    output = generate_draft(
        request(mode="improve", original_text="프로젝트를 했습니다"), CONTEXT, generator
    )
    assert output["draft"]["revisions"][0]["section_index"] == 1
    generator.generate.return_value["revisions"][0]["original_excerpt"] = "없는 원문"
    with pytest.raises(ValueError):
        generate_draft(
            request(mode="improve", original_text="프로젝트를 했습니다"), CONTEXT, generator
        )


def test_improve_requires_original_and_revision_notes():
    with pytest.raises(ValueError, match="original"):
        generate_draft(request(mode="improve"), CONTEXT, model())
    with pytest.raises(ValueError, match="revision"):
        generate_draft(request(mode="improve", original_text=SOURCE), CONTEXT, model())


def test_improve_selected_text_file_reuses_document_extractor():
    generator = model()
    generator.generate.return_value["revisions"] = [
        {
            "original_excerpt": "프로젝트 경험",
            "section_index": 1,
            "reason": "담당 범위를 정리했습니다.",
        }
    ]
    output = generate_draft(
        request(mode="improve"),
        CONTEXT,
        generator,
        files=[("original.txt", "프로젝트 경험".encode())],
    )
    assert len(output["document_locations"]) == 1


def test_material_budget_never_silently_omits_records():
    records = []
    for i in range(6):
        records.append(
            {
                **CONTEXT["records"][0],
                "record_id": f"00000000-0000-4000-8000-{i:012}",
                "text": "가" * 8000,
            }
        )
    generator = model()
    with pytest.raises(ValueError, match="40000"):
        generate_draft(request(), {"records": records}, generator)
    generator.generate.assert_not_called()


def test_empty_sections_and_xml_control_characters_rejected():
    with pytest.raises(ValueError):
        Draft.model_validate({"sections": [{"heading": "빈 문서"}]})
    data = sample("portfolio")["draft"]
    data["sections"][0]["paragraphs"][0]["text"] = "잘못된\x00문자"
    with pytest.raises(ValueError):
        Draft.model_validate(data)


def test_export_requires_review_without_loading_optional_dependency():
    with pytest.raises(ValueError, match="Review"):
        export_docx(sample("portfolio")["draft"], {"name": "가상"}, document_type="portfolio")


@pytest.mark.parametrize("kind", ["portfolio", "cover_letter"])
def test_docx_has_editable_content_no_protection_and_no_review_notes(kind):
    docx = pytest.importorskip("docx", reason="Install writing/requirements-documents.txt")
    data = sample(kind)["draft"]
    data["sections"][0]["paragraphs"][0]["text"] = "사용자가 수정한 문장 <확인> & 검토"
    raw = export_docx(data, {"name": "가상 지원자"}, document_type=kind, reviewed=True)
    document = docx.Document(BytesIO(raw))
    assert any("사용자가 수정한 문장 <확인> & 검토" == p.text for p in document.paragraphs)
    assert bool(document.tables) == (kind == "portfolio")
    document.paragraphs[0].text = "Word에서 편집 가능"
    changed = BytesIO()
    document.save(changed)
    assert docx.Document(BytesIO(changed.getvalue())).paragraphs[0].text == "Word에서 편집 가능"
    with ZipFile(BytesIO(raw)) as archive:
        xml = archive.read("word/document.xml").decode()
        assert "지원 동기를 알려주세요" not in xml
        assert "record_id" not in xml
        assert b"documentProtection" not in archive.read("word/settings.xml")
        assert not any("vbaProject" in name for name in archive.namelist())
