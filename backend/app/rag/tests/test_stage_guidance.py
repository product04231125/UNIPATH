import unittest

from app.rag.career.stage_guidance import build_guidance


class StageGuidanceTests(unittest.TestCase):
    def test_stages_change_actions_not_evidence(self):
        item = {
            "analysis_status": "completed",
            "comparisons": [
                {
                    "requirement_id": "r1",
                    "priority": "required",
                    "requirement": "API 개발 경험",
                    "status": "insufficient_evidence",
                }
            ],
        }
        outputs = [
            build_guidance(item, s) for s in ["year1", "year2", "year3", "year4", "graduate", None]
        ]
        self.assertEqual(len({o["sentences"][2] for o in outputs}), 6)
        self.assertEqual(len({o["sentences"][0] for o in outputs}), 1)
        for o in outputs:
            self.assertEqual(len(o["sentences"]), 3)
            self.assertEqual(o["comparison_refs"], ["r1"])
            self.assertNotIn("근거가 확인되지", " ".join(o["sentences"]))
            self.assertIn("API 개발 경험", o["sentences"][1])

    def test_experienced_first_year_not_told_to_start_over(self):
        item = {
            "analysis_status": "completed",
            "comparisons": [
                {"priority": "required", "requirement": "API 개발", "status": "supported"}
            ],
        }
        out = build_guidance(item, "year1")
        self.assertEqual(out["state"], "evidence_ready")
        self.assertNotIn("기초 수업", out["sentences"][2])

    def test_failed_model_does_not_imply_missing_skill(self):
        out = build_guidance({"analysis_status": "failed", "comparisons": []}, "year4")
        self.assertEqual(out["state"], "analysis_unavailable")
        self.assertIn("판단할 수 없습니다", out["sentences"][0])
        self.assertEqual(len(out["sentences"]), 3)
