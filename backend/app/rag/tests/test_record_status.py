"""Plans are not finished work: every model call that reads records knows today and the rule."""

from datetime import date
from unittest.mock import Mock
from uuid import uuid4

from app.rag.career import activities, analyzer, certificates, gap
from app.rag.career.contracts import RECORD_STATUS_RULE, record_field
from app.rag.writing import service as writing
from app.services.personalization import guidance

TODAY = date(2026, 11, 25)


def test_every_instruction_that_reads_records_carries_the_status_rule():
    for instruction in (
        analyzer.INSTRUCTION,
        gap.INSTRUCTION,
        activities.INSTRUCTION,
        certificates.INSTRUCTION,
        certificates.STUDY_INSTRUCTION,
        writing.INSTRUCTION,
        guidance.INSTRUCTION,
    ):
        assert instruction.endswith(RECORD_STATUS_RULE)
    assert "참여 예정" in RECORD_STATUS_RULE and "today" in RECORD_STATUS_RULE


def test_record_field_reads_the_assembled_field_lines():
    # A detail spanning lines can look like a field; the real field comes after it.
    record = {"text": "title: 해커톤\ndetail: 메모\nstatus_label: 가짜\nstatus_label: 참여 예정"}
    assert record_field(record, "status_label") == "참여 예정"
    assert record_field(record, "earned_on") == ""
    assert record_field({}, "status_label") == ""


def test_comparison_requests_carry_today(monkeypatch):
    monkeypatch.setattr(analyzer, "local_today", lambda: TODAY)
    records = [
        {
            "kind": "experience",
            "record_id": str(uuid4()),
            "version": 1,
            "title": "합성 해커톤",
            "text": "title: 합성 해커톤\nstatus_label: 참여 예정",
            "truncated": False,
        }
    ]
    generator = Mock(generate=Mock(return_value={"comparisons": []}))
    analyzer.EvidenceAnalyzer(generator).analyze("담당업무: 웹 개발", {"records": records})
    payload = generator.generate.call_args.args[1]
    assert payload["today"] == "2026-11-25" and payload["records"][0]["text"].endswith("참여 예정")
