#!/usr/bin/env python3
"""Validate the structured state used by soft-copyright-ideas.

This checker validates structural invariants only. It does not decide whether a
research conclusion is true, whether an official page is current, or whether a
business flow works end to end.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

MODES = {
    "title_triage",
    "scenario_selection",
    "baseline",
    "full_plan",
    "audit",
    "change_impact",
}
DECISION_STATUSES = {
    "confirmed",
    "delegated_confirmed",
    "not_applicable",
    "excluded",
    "recommended_pending",
    "unresolved",
    "conflict",
}
DECISION_BASES = {"user", "delegated", "artifact", "external", "proposal"}
CLAIM_KINDS = {
    "user_fact",
    "workspace_observation",
    "external_fact",
    "existing_claim",
    "model_proposal",
}
VERIFICATION_STATES = {"verified", "unverified", "conflicting"}
CLAIM_SOURCES = {"user", "workspace", "external", "document", "model"}
CONFIDENCE_LEVELS = {"high", "medium", "low"}
ID_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
VERSION_PATTERN = re.compile(r"\bV\d+(?:\.\d+){1,3}\b", re.IGNORECASE)


class Report:
    def __init__(self, strict: bool = False) -> None:
        self.strict = strict
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warning(self, message: str) -> None:
        self.warnings.append(message)

    def result_code(self) -> int:
        return 1 if self.errors or (self.strict and self.warnings) else 0


def is_nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def ensure_list(value: Any, label: str, report: Report) -> list[Any]:
    if value is None:
        report.warning(f"{label} 未提供，按空列表处理")
        return []
    if not isinstance(value, list):
        report.error(f"{label} 必须是数组")
        return []
    return value


def validate_id(value: Any, label: str, report: Report) -> str | None:
    if not is_nonempty_string(value):
        report.error(f"{label} 必须是非空字符串")
        return None
    value = value.strip()
    if not ID_PATTERN.fullmatch(value):
        report.error(f"{label}={value!r} 不是稳定 ID（只允许字母、数字、下划线和连字符）")
        return None
    return value


def collect_ids(state: dict[str, Any], report: Report) -> set[str]:
    all_ids: dict[str, str] = {}
    for collection_name in (
        "decisions",
        "claims",
        "artifacts",
        "traceability",
        "risks",
    ):
        entries = state.get(collection_name, [])
        if not isinstance(entries, list):
            continue
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                report.error(f"{collection_name}[{index}] 必须是对象")
                continue
            item_id = validate_id(entry.get("id"), f"{collection_name}[{index}].id", report)
            if item_id is None:
                continue
            previous = all_ids.get(item_id)
            if previous:
                report.error(f"ID 重复：{item_id}（{previous} 与 {collection_name}[{index}]）")
            else:
                all_ids[item_id] = f"{collection_name}[{index}]"
    return set(all_ids)

def collection_ids(state: dict[str, Any], collection_name: str) -> set[str]:
    """Return valid IDs from one top-level collection without emitting duplicate errors."""
    entries = state.get(collection_name, [])
    if not isinstance(entries, list):
        return set()
    return {
        entry["id"]
        for entry in entries
        if isinstance(entry, dict)
        and is_nonempty_string(entry.get("id"))
        and ID_PATTERN.fullmatch(entry["id"].strip())
    }


def validate_decisions(state: dict[str, Any], report: Report, claim_ids: set[str]) -> None:
    entries = ensure_list(state.get("decisions"), "decisions", report)
    for index, decision in enumerate(entries):
        if not isinstance(decision, dict):
            continue
        prefix = f"decisions[{index}]"
        for field in ("field", "status", "basis", "scope"):
            if not is_nonempty_string(decision.get(field)):
                report.error(f"{prefix}.{field} 必须是非空字符串")
        status = decision.get("status")
        if status not in DECISION_STATUSES:
            report.error(f"{prefix}.status={status!r} 不在允许枚举中")
        basis = decision.get("basis")
        if basis not in DECISION_BASES:
            report.error(f"{prefix}.basis={basis!r} 不在允许枚举中")
        if status == "delegated_confirmed" and basis != "delegated":
            report.error(f"{prefix} 为 delegated_confirmed 时必须使用 basis=delegated")
        if status == "confirmed" and basis in {"proposal", "delegated"}:
            report.error(f"{prefix} 的 confirmed 状态不能由 {basis} 单独产生；请改为待确认或 delegated_confirmed")
        impacts = decision.get("impact", [])
        if not isinstance(impacts, list):
            report.error(f"{prefix}.impact 必须是数组")
        evidence_refs = decision.get("evidence_ids", [])
        if not isinstance(evidence_refs, list):
            report.error(f"{prefix}.evidence_ids 必须是数组")
        else:
            for evidence_id in evidence_refs:
                if evidence_id not in claim_ids:
                    report.error(f"{prefix}.evidence_ids 引用了不存在的 ID：{evidence_id}")
        if status in {"confirmed", "delegated_confirmed"} and not evidence_refs:
            report.warning(f"{prefix} 已确认但没有 evidence_ids；请补充用户确认或代拟确认的定位")


def validate_claims(state: dict[str, Any], report: Report, known_ids: set[str]) -> None:
    entries = ensure_list(state.get("claims"), "claims", report)
    for index, claim in enumerate(entries):
        if not isinstance(claim, dict):
            continue
        prefix = f"claims[{index}]"
        for field in ("claim", "source", "locator", "verification", "confidence"):
            if not is_nonempty_string(claim.get(field)):
                report.error(f"{prefix}.{field} 必须是非空字符串")
        kind = claim.get("kind")
        if kind not in CLAIM_KINDS:
            report.error(f"{prefix}.kind={kind!r} 不在允许枚举中")
        source = claim.get("source")
        if source not in CLAIM_SOURCES:
            report.error(f"{prefix}.source={source!r} 不在允许枚举中")
        confidence = claim.get("confidence")
        if confidence not in CONFIDENCE_LEVELS:
            report.error(f"{prefix}.confidence={confidence!r} 不在允许枚举中")
        verification = claim.get("verification")
        if verification not in VERIFICATION_STATES:
            report.error(f"{prefix}.verification={verification!r} 不在允许枚举中")
        if kind == "external_fact" and not is_nonempty_string(claim.get("accessed_at")):
            report.error(f"{prefix} 是 external_fact，必须有 accessed_at")
        supports = claim.get("supports", [])
        if not isinstance(supports, list):
            report.error(f"{prefix}.supports 必须是数组")
        else:
            for support_id in supports:
                if support_id not in known_ids:
                    report.error(f"{prefix}.supports 引用了不存在的 ID：{support_id}")


def validate_traceability(state: dict[str, Any], report: Report, claim_ids: set[str]) -> None:
    entries = ensure_list(state.get("traceability"), "traceability", report)
    for index, item in enumerate(entries):
        if not isinstance(item, dict):
            continue
        prefix = f"traceability[{index}]"
        if not is_nonempty_string(item.get("source_term")):
            report.error(f"{prefix}.source_term 必须是非空字符串")
        evidence_refs = item.get("evidence_ids", [])
        if not isinstance(evidence_refs, list):
            report.error(f"{prefix}.evidence_ids 必须是数组")
        else:
            for evidence_id in evidence_refs:
                if evidence_id not in claim_ids:
                    report.error(f"{prefix}.evidence_ids 引用了不存在的 ID：{evidence_id}")
        for field in (
            "goal_ids",
            "use_case_ids",
            "model_ids",
            "feature_ids",
            "page_ids",
            "test_ids",
            "material_sections",
        ):
            value = item.get(field, [])
            if not isinstance(value, list):
                report.error(f"{prefix}.{field} 必须是数组")
            elif not value:
                report.warning(f"{prefix}.{field} 为空；如果该词属于核心需求，应补齐追踪落点")


def validate_baseline_gate(state: dict[str, Any], report: Report) -> None:
    mode = state.get("mode")
    baseline = state.get("baseline")
    if baseline is not None and not isinstance(baseline, dict):
        report.error("baseline 必须是对象")
        baseline = None
    baseline_status = baseline.get("status") if isinstance(baseline, dict) else None
    if baseline_status not in {None, "draft", "confirmed"}:
        report.error("baseline.status 只能是 draft 或 confirmed")
    if mode == "full_plan":
        if baseline_status != "confirmed":
            report.error("full_plan 必须有 baseline.status=confirmed")
        if not state.get("decisions"):
            report.error("full_plan 至少需要 decisions 记录")
        if not state.get("claims"):
            report.error("full_plan 至少需要 claims 证据记录")
        unresolved = []
        for index, decision in enumerate(state.get("decisions", []) or []):
            if isinstance(decision, dict) and decision.get("status") in {
                "recommended_pending",
                "unresolved",
                "conflict",
            }:
                unresolved.append(f"decisions[{index}]")
        if unresolved:
            report.error("full_plan 仍有未闭合决策：" + ", ".join(unresolved))
        conflicts = state.get("open_conflicts", [])
        if not isinstance(conflicts, list):
            report.error("open_conflicts 必须是数组")
        elif conflicts:
            report.error("full_plan 仍有 open_conflicts")
        if not state.get("traceability"):
            report.error("full_plan 至少需要一条 traceability 记录")


def validate_identity_and_plan(
    state: dict[str, Any], plan_path: Path | None, report: Report
) -> None:
    if plan_path is None:
        return
    try:
        plan = plan_path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        report.error(f"无法读取计划书 {plan_path}: {exc}")
        return
    if re.search(r"\[TODO[^\]]*\]", plan, flags=re.IGNORECASE):
        report.error("计划书仍含未完成的 TODO 占位符")
    identity = state.get("identity")
    if not isinstance(identity, dict):
        report.warning("未提供 identity，跳过名称/版本与计划书一致性检查")
        identity = {}
    mode = state.get("mode")
    for field in ("software_name", "version"):
        value = identity.get(field)
        if not is_nonempty_string(value):
            continue
        if value not in plan:
            message = f"计划书未出现 identity.{field}={value!r}"
            if mode == "full_plan":
                report.error(message)
            else:
                report.warning(message)
    expected_version = identity.get("version")
    if is_nonempty_string(expected_version):
        versions = {match.upper() for match in VERSION_PATTERN.findall(plan)}
        if versions and expected_version.upper() not in versions:
            report.warning(
                f"计划书中的版本表达 {sorted(versions)} 与状态中的版本 {expected_version!r} 不一致；"
                "如旧版本出现在变更记录中，请人工复核"
            )
    risky_claims = re.findall(r"(?<!未)(?<!计划)(?<!拟)(?<!待)(已上线|已接入|已部署|登记成功)", plan)
    if risky_claims:
        report.warning(
            "计划书含可能未经限定的现状/结果表述：" + ", ".join(sorted(set(risky_claims)))
        )


def load_state(path: Path, report: Report) -> dict[str, Any] | None:
    try:
        raw = path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        report.error(f"无法读取状态文件 {path}: {exc}")
        return None
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        report.error(f"状态文件不是合法 JSON：{exc}")
        return None
    if not isinstance(value, dict):
        report.error("状态根节点必须是 JSON 对象")
        return None
    return value


def validate(state_path: Path, plan_path: Path | None, strict: bool) -> Report:
    report = Report(strict=strict)
    state = load_state(state_path, report)
    if state is None:
        return report
    schema_version = state.get("schema_version")
    if not is_nonempty_string(schema_version):
        report.error("缺少非空 schema_version")
    mode = state.get("mode")
    if mode not in MODES:
        report.error(f"mode={mode!r} 不在允许枚举中：{sorted(MODES)}")
    known_ids = collect_ids(state, report)
    evidence_ids = collection_ids(state, "claims")
    validate_decisions(state, report, evidence_ids)
    validate_claims(state, report, known_ids)
    validate_traceability(state, report, evidence_ids)
    validate_baseline_gate(state, report)
    conflicts = state.get("open_conflicts", [])
    if conflicts is not None and not isinstance(conflicts, list):
        report.error("open_conflicts 必须是数组")
    validate_identity_and_plan(state, plan_path, report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="检查软著项目题目与系统规划 Skill 的结构化状态"
    )
    parser.add_argument("state", type=Path, help="状态 JSON 文件")
    parser.add_argument("plan", type=Path, nargs="?", help="可选的计划书 Markdown")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="将警告也视为失败；默认只要没有结构错误即可通过",
    )
    args = parser.parse_args()
    report = validate(args.state, args.plan, args.strict)
    for message in report.errors:
        print(f"ERROR: {message}")
    for message in report.warnings:
        print(f"WARNING: {message}")
    if report.result_code() == 0:
        suffix = "（含警告）" if report.warnings else ""
        print(f"PASS: 结构化状态检查通过{suffix}")
    else:
        print(f"FAIL: {len(report.errors)} 个错误，{len(report.warnings)} 个警告")
    return report.result_code()


if __name__ == "__main__":
    raise SystemExit(main())


