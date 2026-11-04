"""Offline tests for source collection, preserved contents and click navigation."""

import hashlib
import json
import re
import unittest
from collections import Counter
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from app.rag.guidance import respond
from app.rag.guidance.collect import DATA, crawl, parse_calendar, split_pages
from app.rag.guidance.content import bundle


def sample(year=2026, dates="11. 30(월) ∼ 12. 03(목)"):
    return "".join(
        f'<h4 class="cal-month"><span>{year}. </span>{month:02d} 월</h4>'
        + (
            f'<div class="date-core">{dates}</div><div class="body-core">시험 &amp; 일정</div>'
            if month == 11
            else ""
        )
        for month in range(1, 13)
    )


class ContentTests(unittest.TestCase):
    def test_calendar_source_matches_all_events(self):
        data = json.loads((DATA / "calendar-2026.json").read_text())
        raw = (DATA / data["source_file"]).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), data["sha256"])
        self.assertEqual(parse_calendar(raw.decode(), 2026), data["events"])
        self.assertEqual(len(data["events"]), 88)
        self.assertEqual(len(data["events"]), raw.count(b'class="date-core"'))

    def test_dates_and_entities(self):
        event = parse_calendar(sample(), 2026)[0]
        self.assertEqual(event["end_date"], "2026-12-03")
        self.assertEqual(event["title"], "시험 & 일정")
        event = parse_calendar(sample(dates="12. 30(수) ~ 01. 02(토)"), 2026)[0]
        self.assertEqual(event["end_date"], "2027-01-02")

    def test_layout_changes_fail_closed(self):
        for html in (
            "<html>error</html>",
            sample(2027),
            sample(dates="미정"),
            sample(dates="11. 31(월)"),
            sample().replace("12 월", "13 월"),
            sample().replace('class="body-core"', 'class="changed"'),
        ):
            with self.subTest(html=html), self.assertRaises(ValueError):
                parse_calendar(html, 2026)

    def test_failed_refresh_preserves_previous_data(self):
        class Response:
            url = (
                "https://www.kduniv.ac.kr/kor/CMS/ScheduleMgr/YearList.do"
                "?mCode=MN096&calendar_year=2026"
            )

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self, size):
                return b"maintenance"

        with TemporaryDirectory() as temp:
            output = Path(temp)
            target = output / "calendar-2026.json"
            target.write_text("previous")
            with patch("app.rag.guidance.collect.urlopen", return_value=Response()):
                with self.assertRaises(ValueError):
                    crawl(2026, output)
            self.assertEqual(target.read_text(), "previous")

    def test_cross_month_event_shown_once_in_each_month(self):
        for month in ("11", "12"):
            payload = respond(f"calendar:2026:{month}")
            matches = [
                c
                for c in payload["cards"]
                if c["start_date"] == "2026-11-30" and c["end_date"] == "2026-12-03"
            ]
            self.assertEqual(len(matches), 1)
            self.assertIn("fetched_at", payload)
            self.assertNotIn("audit", payload)

    def test_pdf_hashes_pages_and_line_coverage(self):
        data = json.loads((DATA / "regulations.json").read_text())
        self.assertEqual(len(data["documents"]), 6)
        self.assertEqual(sum(d["page_count"] for d in data["documents"]), 158)
        for doc in data["documents"]:
            raw = (DATA / doc["source_file"]).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), doc["sha256"])
            expected = Counter(
                (p["page"], line)
                for p in doc["pages"]
                for line in p["text"].splitlines()
                if not re.fullmatch(r".*\s" + re.escape(doc["id"]), line.strip())
            )
            actual = Counter(
                (p["page"], line)
                for s in doc["sections"]
                for i in s["items"]
                for p in i["parts"]
                for line in p["text"].splitlines()
            )
            self.assertEqual(actual, expected, doc["id"])
            for page in doc["pages"]:
                payload = respond(f"regulations:{doc['id']}:pages:{page['page']}")
                self.assertEqual(payload["cards"][0]["body"], page["text"])
                self.assertEqual(payload["cards"][0]["tables"], page["tables"])
                self.assertEqual(payload["scope"], doc["scope"])

    def test_cross_page_article_and_supplement(self):
        pages = [
            {"page": 1, "text": "규정 2-0-1\n제1장 총칙\n제1조 (목적) 첫째\n① 조건"},
            {"page": 2, "text": "규정 2-0-1\n② 예외\n부 칙\n제1조 (시행일) 별도 날짜"},
        ]
        sections = split_pages(pages, "2-0-1")
        article = sections[0]["items"][1]
        self.assertEqual([p["page"] for p in article["parts"]], [1, 2])
        self.assertIn("② 예외", article["parts"][1]["text"])
        self.assertEqual(sections[1]["title"], "부 칙")

    def test_menus_bounded_and_content_inline(self):
        nodes, payloads = bundle()
        for key, (_, parent, mode) in nodes.items():
            self.assertTrue(parent == "home" or parent in nodes)
            if mode == "menu":
                self.assertLessEqual(sum(v[1] == key for v in nodes.values()), 12)
            if mode == "content":
                self.assertIn(key, payloads)
                self.assertTrue(payloads[key]["cards"] or key.startswith("calendar:"))
        self.assertEqual(len(respond("regulations")["buttons"]), 7)

    def test_reference_content_does_not_use_private_audit(self):
        for key in ("calendar:2026:11", "regulations:2-0-5:pages:1"):
            payload = respond(key, audit={"owner_id": "SECRET_STUDENT"})
            self.assertNotIn("SECRET_STUDENT", json.dumps(payload))
            self.assertNotIn("audit", payload)
