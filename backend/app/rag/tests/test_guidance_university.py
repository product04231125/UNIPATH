"""Real source inventory coverage, offline parsing, table relationships and click routing."""

import hashlib
import json
import unittest
from datetime import UTC, datetime
from unittest.mock import patch

from app.rag.guidance import catalog, respond
from app.rag.guidance.collect import DATA
from app.rag.guidance.university import (
    parse_index,
    parse_page,
    parse_rules,
    parse_table,
    safe_url,
    soup,
)


class UniversityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads((DATA / "university.json").read_text())

    def test_inventory_matches_categories_and_download_links(self):
        d = self.data
        categories = parse_index((DATA / d["index_source"]["source_file"]).read_bytes())
        rows = parse_rules((DATA / d["list_source"]["source_file"]).read_bytes(), categories)
        self.assertEqual(len(rows), 189)
        self.assertEqual({r["id"] for r in rows}, {r["id"] for r in d["regulations"]})
        for parsed, saved in zip(rows, d["regulations"], strict=True):
            self.assertEqual(
                [a["url"] for a in parsed["attachments"]], [a["url"] for a in saved["attachments"]]
            )
        self.assertEqual(sum(len(r["attachments"]) for r in rows), 171)
        self.assertEqual(sum(not r["attachments"] for r in rows), 18)
        self.assertEqual(sum(p["parent_id"] is None for p in rows), 1)

    def test_missing_duplicate_and_changed_listing_rejected(self):
        d = self.data
        categories = d["categories"]
        tree = soup((DATA / d["list_source"]["source_file"]).read_bytes())
        tree.select_one("tbody tr").decompose()
        with self.assertRaises(ValueError):
            parse_rules(str(tree), categories)
        with self.assertRaises(ValueError):
            parse_index("<html>maintenance</html>")

    def test_all_attachment_bytes_and_pages_preserved(self):
        total = 0
        for r in self.data["regulations"]:
            for index, a in enumerate(r["attachments"], 1):
                raw = (DATA / a["source_file"]).read_bytes()
                self.assertTrue(raw.startswith(b"%PDF-"))
                self.assertEqual(hashlib.sha256(raw).hexdigest(), a["sha256"])
                self.assertEqual(len(a["pages"]), a["page_count"])
                total += a["page_count"]
                for page in a["pages"]:
                    node = f"university:{r['id']}:attachment:{index}:page:{page['page']}"
                    payload = respond(node)
                    self.assertEqual(payload["reason"], "university_pdf_page")
                    if page["text"]:
                        self.assertEqual(payload["cards"][0]["body"], page["text"])
                    if page["extraction_status"] == "ocr_unreviewed":
                        self.assertTrue(payload["cards"][0]["image_asset_id"])
                        self.assertTrue(any("OCR" in w for w in payload["warnings"]))
                    self.assertNotIn("audit", payload)
        self.assertEqual(total, 1197)

    def test_withdrawn_and_moved_not_lost_or_claimed_current(self):
        for r in self.data["regulations"]:
            if not r["attachments"]:
                p = respond("university:" + r["id"])
                self.assertEqual(p["attachment_state"], "not_listed")
                self.assertNotEqual(p["listing_status"], "listed")
                self.assertTrue(p["warnings"])

    def test_scholarship_body_tables_and_source_integrity(self):
        for page in self.data["scholarships"]:
            raw = (DATA / page["source_file"]).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), page["sha256"])
            parsed = parse_page(raw, page["title"])
            self.assertEqual(parsed["body"], page["body"])
            self.assertEqual(parsed["tables"], page["tables"])
            p = respond("scholarship:" + page["id"])
            self.assertEqual(p["cards"][0]["body"], page["body"])
            self.assertEqual(p["fetched_at"], self.data["fetched_at"])
        self.assertTrue(
            any(
                b["node_id"] == "university:CDE_000275"
                for b in respond("scholarship:MN149")["buttons"]
            )
        )

    def test_table_merged_cells_and_blank_are_preserved(self):
        table = soup(
            '<table><tr><th>A</th><th colspan="2">B</th></tr>'
            '<tr><td rowspan="2">공통</td><td>조건1</td><td></td></tr>'
            "<tr><td>조건2</td><td>금액</td></tr></table>"
        ).table
        result = parse_table(table)
        self.assertEqual(
            result["grid"], [["A", "B", "B"], ["공통", "조건1", ""], ["공통", "조건2", "금액"]]
        )
        self.assertEqual(result["rows"][1][0]["rowspan"], 2)

    def test_stale_menus_and_pages_work_without_existing_warning(self):
        class Later(datetime):
            @classmethod
            def now(cls, tz=None):
                return cls(2030, 1, 1, tzinfo=UTC)

        with patch("app.rag.guidance.content.datetime", Later):
            for node in ("university", "scholarship", "scholarship:MN150"):
                p = respond(node)
                self.assertTrue(p["snapshot_stale"])
                self.assertTrue(p["warnings"])

    def test_catalog_ids_unique_and_connected(self):
        nodes = catalog()["nodes"]
        ids = {n["id"] for n in nodes}
        self.assertEqual(len(ids), len(nodes))
        for node in nodes:
            if node["parent_id"] is not None:
                self.assertIn(node["parent_id"], ids)
            self.assertLessEqual(len(node["children"]), 12)

    def test_source_url_boundary(self):
        for url in (
            "file:///tmp/a",
            "http://localhost/a",
            "https://evil.com/a",
            "https://www.kduniv.ac.kr@evil.com/a",
            "https://www.kduniv.ac.kr:8080/a",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                safe_url(url)

    def test_image_assets_are_registered_and_verified(self):
        from app.rag.guidance.assets import asset_index, resolve_asset

        assets = asset_index()
        ocr = [
            p
            for r in self.data["regulations"]
            for a in r["attachments"]
            for p in a["pages"]
            if p["extraction_status"] == "ocr_unreviewed"
        ]
        self.assertEqual(len(ocr), self.data["coverage"]["ocr_pages"])
        self.assertEqual(len(ocr), 53)
        for page in ocr:
            self.assertTrue(page["text"])
            self.assertIn(page["image"]["sha256"], assets)
        image = resolve_asset(ocr[0]["image"]["sha256"])
        self.assertEqual(image.suffix, ".jpg")
        for invalid in ("../../etc/passwd", "0" * 64, None):
            with self.assertRaises(ValueError):
                resolve_asset(invalid)
