#!/usr/bin/env python3
"""Regression tests for the structural state validator."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import validate_plan  # noqa: E402


class ValidatorTests(unittest.TestCase):
    def write_json(self, directory: Path, name: str, value: dict) -> Path:
        path = directory / name
        path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
        return path

    def base_state(self, mode: str = "title_triage") -> dict:
        return {
            "schema_version": "1.0",
            "mode": mode,
            "baseline_version": "B0",
            "baseline": {"status": "draft"},
            "identity": {"software_name": "", "version": "", "name_status": "candidate"},
            "decisions": [],
            "claims": [],
            "artifacts": [],
            "traceability": [],
            "risks": [],
            "open_conflicts": [],
        }

    def full_state(self) -> dict:
        state = self.base_state("full_plan")
        state["baseline"] = {"status": "confirmed"}
        state["identity"] = {
            "software_name": "测试系统",
            "version": "V1.0",
            "name_status": "confirmed",
        }
        state["claims"] = [{
            "id": "E-001",
            "kind": "user_fact",
            "claim": "用户确认 Web 管理端",
            "source": "user",
            "locator": "conversation",
            "supports": ["D-001"],
            "confidence": "high",
            "verification": "verified",
        }]
        state["decisions"] = [{
            "id": "D-001",
            "field": "目标平台",
            "value": "Web",
            "status": "confirmed",
            "basis": "user",
            "scope": "target",
            "impact": ["架构"],
            "evidence_ids": ["E-001"],
            "updated_at": "2026-09-02",
        }]
        state["traceability"] = [{
            "id": "T-001",
            "source_term": "核心任务",
            "evidence_ids": ["E-001"],
            "goal_ids": ["G-001"],
            "use_case_ids": ["UC-001"],
            "model_ids": ["M-001"],
            "feature_ids": ["F-001"],
            "page_ids": ["P-001"],
            "test_ids": ["AT-001"],
            "material_sections": ["说明书-主流程"],
        }]
        return state

    def test_template_is_structurally_valid(self) -> None:
        path = ROOT / "references" / "state-template.json"
        report = validate_plan.validate(path, None, strict=False)
        self.assertEqual(report.result_code(), 0)

    def test_full_plan_requires_confirmed_baseline(self) -> None:
        state = self.full_state()
        state["baseline"] = {"status": "draft"}
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_json(Path(tmp), "state.json", state)
            report = validate_plan.validate(path, None, strict=False)
        self.assertNotEqual(report.result_code(), 0)
        self.assertTrue(any("baseline.status=confirmed" in item for item in report.errors))

    def test_unknown_evidence_reference_fails(self) -> None:
        state = self.full_state()
        state["decisions"][0]["evidence_ids"] = ["E-404"]
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_json(Path(tmp), "state.json", state)
            report = validate_plan.validate(path, None, strict=False)
        self.assertNotEqual(report.result_code(), 0)
        self.assertTrue(any("E-404" in item for item in report.errors))

    def test_evidence_must_point_to_claim_collection(self) -> None:
        state = self.full_state()
        state["decisions"][0]["evidence_ids"] = ["D-001"]
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_json(Path(tmp), "state.json", state)
            report = validate_plan.validate(path, None, strict=False)
        self.assertNotEqual(report.result_code(), 0)
        self.assertTrue(any("D-001" in item for item in report.errors))

    def test_proposal_cannot_be_confirmed(self) -> None:
        state = self.full_state()
        state["decisions"][0]["basis"] = "proposal"
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_json(Path(tmp), "state.json", state)
            report = validate_plan.validate(path, None, strict=False)
        self.assertNotEqual(report.result_code(), 0)
        self.assertTrue(any("confirmed" in item for item in report.errors))

    def test_external_claim_requires_access_date(self) -> None:
        state = self.base_state()
        state["claims"] = [{
            "id": "E-001",
            "kind": "external_fact",
            "claim": "外部结论",
            "source": "external",
            "locator": "https://example.invalid",
            "verification": "verified",
        }]
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_json(Path(tmp), "state.json", state)
            report = validate_plan.validate(path, None, strict=False)
        self.assertNotEqual(report.result_code(), 0)
        self.assertTrue(any("accessed_at" in item for item in report.errors))

    def test_plan_identity_is_checked_for_full_plan(self) -> None:
        state = self.full_state()
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            state_path = self.write_json(directory, "state.json", state)
            plan_path = directory / "plan.md"
            plan_path.write_text("# 其他名称 V2.0\n", encoding="utf-8")
            report = validate_plan.validate(state_path, plan_path, strict=False)
        self.assertNotEqual(report.result_code(), 0)
        self.assertTrue(any("software_name" in item for item in report.errors))


if __name__ == "__main__":
    unittest.main()
