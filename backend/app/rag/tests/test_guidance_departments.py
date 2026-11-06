"""Computer Engineering content and pending-only user-provided campus directory."""

import hashlib
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from app.rag.guidance import catalog, respond
from app.rag.guidance.collect import DATA
from app.rag.guidance.departments import URL, collect, parse_computer


class DepartmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads((DATA / "departments.json").read_text())

    def test_directory_counts_and_only_computer_enabled(self):
        campuses = self.data["campuses"]
        self.assertEqual([len(c["departments"]) for c in campuses], [20, 8, 1])
        departments = [d for c in campuses for d in c["departments"]]
        self.assertEqual(len({d["id"] for d in departments}), 29)
        self.assertEqual(
            [d["id"] for d in departments if d["availability"] == "available"], ["DE0013"]
        )
        for d in departments:
            if d["id"] == "DE0013":
                continue
            response = respond("departments:" + d["id"], audit={"secret": "private"})
            self.assertEqual(response["state"], "unavailable")
            self.assertEqual(response["reason"], "department_content_pending")
            self.assertIn("추후 추가 예정", response["message"])
            self.assertEqual(response["cards"], [])
            self.assertNotIn("audit", response)
            self.assertNotIn("fetched_at", response)

    def test_source_and_six_inline_sections(self):
        doc = self.data["computer"]
        raw = (DATA / doc["source_file"]).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), doc["sha256"])
        self.assertEqual(parse_computer(raw)["sections"], doc["sections"])
        self.assertEqual(len(doc["sections"]), 6)
        for section in doc["sections"]:
            response = respond("departments:DE0013:" + section["id"])
            self.assertEqual(response["cards"][0]["body"], section["body"])
            self.assertEqual(response["cards"][0]["sources"][0]["source_url"], URL)
            self.assertIn("fetched_at", response)
        contact = respond("departments:DE0013:contact")["cards"][0]["body"]
        self.assertIn("우당관 1802호", contact)
        self.assertIn("031-869-9870", contact)
        self.assertIn("https://www.kduniv.ac.kr/ce", contact)

    def test_unknown_department_and_no_gallery_or_other_departments_leak(self):
        self.assertEqual(respond("departments:unregistered")["reason"], "unknown_node")
        body = "\n".join(s["body"] for s in self.data["computer"]["sections"])
        self.assertNotIn("SNS 공유하기", body)
        self.assertNotIn("학과 갤러리", body)
        self.assertNotIn("항공서비스학과", body)

    def test_refresh_only_fetches_one_page_and_invalid_response_preserves_data(self):
        doc = self.data["computer"]
        raw = (DATA / doc["source_file"]).read_bytes()
        with TemporaryDirectory() as directory:
            folder = Path(directory)
            with patch("app.rag.guidance.university.fetch", return_value=raw) as fetch:
                collect(folder)
                fetch.assert_called_once_with(URL)
            previous = (folder / "departments.json").read_bytes()
            with patch("app.rag.guidance.university.fetch", return_value=b"maintenance"):
                with self.assertRaises(ValueError):
                    collect(folder)
            self.assertEqual(previous, (folder / "departments.json").read_bytes())

    def test_pending_buttons_badged_and_computer_reachable(self):
        ids = {n["id"] for n in catalog()["nodes"]}
        self.assertIn("departments:DE0013", ids)
        for button in respond("departments:medical")["buttons"]:
            if button["node_id"].startswith("departments:DE"):
                self.assertEqual(button["availability"], "content_pending")
                self.assertIn("추후 추가 예정", button["label"])
        campus = next(n for n in catalog()["nodes"] if n["id"] == "departments:metropol")
        first = respond(campus["children"][0])
        self.assertEqual(first["buttons"][0]["node_id"], "departments:DE0013")
