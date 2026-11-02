"""Click navigation and deterministic presentation of synthetic, verified audit data."""

import json
import unittest
from copy import deepcopy
from pathlib import Path

from app.rag.guidance import catalog, respond

EXAMPLE = Path(__file__).resolve().parents[1] / "guidance/examples/synthetic-audit.json"


class GuidanceTests(unittest.TestCase):
    def setUp(self):
        self.audit = json.loads(EXAMPLE.read_text())

    def test_every_menu_reachable_and_returns_home(self):
        nodes = catalog()["nodes"]
        reached = set()
        pending = ["home"]
        while pending:
            node = pending.pop()
            if node in reached:
                continue
            reached.add(node)
            payload = respond(node)
            for button in payload["buttons"]:
                self.assertEqual(button["action"], "select_node")
                pending.append(button["node_id"])
            if node != "home":
                self.assertTrue(payload["buttons"])
        self.assertEqual(reached, {node["id"] for node in nodes})

    def test_unknown_and_unprepared_have_no_fabricated_content(self):
        for node in (None, [], "__proto__", "anything"):
            self.assertEqual(respond(node)["reason"], "unknown_node")
        for node in catalog()["nodes"]:
            if node["mode"] == "unavailable":
                payload = respond(node["id"], audit=self.audit)
                self.assertEqual(payload["state"], "unavailable")
                self.assertNotIn("audit", payload)
                self.assertEqual(payload["cards"], [])

    def test_no_audit_and_personal_data_cannot_become_official(self):
        self.assertEqual(respond("summary")["state"], "needs_input")
        self.audit["official"] = False
        self.assertEqual(respond("summary", audit=self.audit)["state"], "unavailable")

    def test_exact_decimals_no_calculation_and_provenance(self):
        row = self.audit["results"][0]
        row.update(current="120.125", required="130.250", deficit="10.125")
        card = respond("credits", audit=self.audit)["cards"][0]
        self.assertIn("10.125학점 부족", card["body"])
        self.assertEqual(card["sources"], self.audit["criteria"][0]["rules"][0]["evidence"])
        self.assertEqual(card["rule_set_version"], row["rule_set_version"])

    def test_null_and_zero_are_different(self):
        row = self.audit["results"][0]
        row.update(
            status="needs_review", reason="incomplete_record_data", current=None, deficit=None
        )
        card = respond("credits", audit=self.audit)["cards"][0]
        self.assertIsNone(card["quantities"]["current"])
        self.assertNotIn("0학점", card["body"])
        row.update(status="not_satisfied", reason="below_threshold", current="0", deficit="130")
        self.assertIn("0학점", respond("credits", audit=self.audit)["cards"][0]["body"])

    def test_all_rule_kinds_and_statuses(self):
        nodes = {
            "credits": "minimum_credits",
            "courses": "required_courses",
            "volunteer": "minimum_volunteer_hours",
            "certificate": "any_certificate",
            "thesis": "thesis",
            "review": "manual_review",
        }
        for node, kind in nodes.items():
            for status in ("satisfied", "not_satisfied", "needs_review", "not_applicable"):
                with self.subTest(kind=kind, status=status):
                    self.audit["criteria"][0]["rules"][0]["condition"]["kind"] = kind
                    self.audit["results"][0]["status"] = status
                    payload = respond(node, audit=self.audit)
                    self.assertEqual(payload["state"], "ready")
                    self.assertEqual(payload["cards"][0]["status"], status)
                    if node in ("certificate", "thesis"):
                        self.assertIsNone(payload["cards"][0]["quantities"])
                        self.assertNotIn("학점", payload["cards"][0]["body"])

    def test_missing_and_uncertain_courses_use_snapshot_names(self):
        rule = self.audit["criteria"][0]["rules"][0]
        rule["condition"]["kind"] = "required_courses"
        rule["references"] = [{"kind": "course", "record_id": "c1", "name": "과거 과목명"}]
        self.audit["results"][0].update(missing_course_ids=["c1"], uncertain_course_ids=["c2"])
        card = respond("courses", audit=self.audit)["cards"][0]
        self.assertIn("과거 과목명", card["body"])
        self.assertIn("과목명 확인 필요", card["body"])

    def test_stale_and_incomplete_preserve_historical_status(self):
        self.audit.update(current_usable=False, catalog_complete=False, status="satisfied")
        payload = respond("summary", audit=self.audit)
        self.assertEqual(payload["audit"]["status"], "satisfied")
        self.assertEqual(len(payload["warnings"]), 2)
        self.assertIn("과거 기준일", payload["message"])

    def test_empty_filter_never_means_satisfied(self):
        payload = respond("thesis", audit=self.audit)
        self.assertEqual(payload["cards"], [])
        self.assertIn("면제나 충족을 의미하지 않습니다", payload["message"])

    def test_invalid_projections_fail_closed(self):
        variants = []
        for amount in ("NaN", "Infinity", -1, 1.1, True, "1e100000", "0.0000001"):
            value = deepcopy(self.audit)
            value["results"][0]["current"] = amount
            variants.append(value)
        value = deepcopy(self.audit)
        value["results"].append(deepcopy(value["results"][0]))
        variants.append(value)
        value = deepcopy(self.audit)
        value["criteria"][0]["version"] = 2
        variants.append(value)
        value = deepcopy(self.audit)
        value["criteria"][0]["rules"][0]["evidence"][0]["source_url"] = "javascript:alert(1)"
        variants.append(value)
        variants.extend([{}, {**self.audit, "current_usable": "true"}])
        for value in variants:
            with self.subTest(value=value):
                payload = respond("summary", audit=value)
                self.assertEqual(payload["reason"], "invalid_audit_projection")
                self.assertEqual(payload["cards"], [])
                self.assertNotIn("audit", payload)

    def test_unknown_reason_uses_generic_status(self):
        self.audit["results"][0]["reason"] = "future_reason"
        card = respond("credits", audit=self.audit)["cards"][0]
        self.assertNotIn("10학점", card["body"])
        self.assertTrue(card["template_id"].endswith(".status"))

    def test_no_mutation_and_deterministic_json(self):
        before = deepcopy(self.audit)
        first = respond("summary", audit=self.audit)
        self.assertEqual(first, respond("summary", audit=self.audit))
        json.dumps(first, allow_nan=False)
        first["audit"]["context"]["track"] = "changed"
        first["cards"][0]["sources"][0]["title"] = "changed"
        self.assertEqual(self.audit, before)
        one = catalog()
        one["nodes"][0]["children"].clear()
        self.assertTrue(catalog()["nodes"][0]["children"])
