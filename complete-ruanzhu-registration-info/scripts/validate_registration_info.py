#!/usr/bin/env python3
"""校验软著登记信息的必填项、枚举值、字符数和最终确认状态。"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path
from typing import Any


PLACEHOLDER_RE = re.compile(r"待补充|需补充|TODO|TBD|未知|不详", re.IGNORECASE)
MARKDOWN_RE = re.compile(r"(^|\s)(#{1,6}\s|[-*+]\s|\d+\.\s)|```|\[.+?\]\(.+?\)")
VERSION_RE = re.compile(r"^[Vv]?\d+(?:\.\d+){1,3}(?:[A-Za-z0-9._-]*)?$")
ABSOLUTE_PATH_RE = re.compile(r"(?:[A-Za-z]:\\|/(?:home|Users|tmp|var|opt)/)")
UNVERIFIABLE_CLAIMS = (
    "国内首创",
    "国际领先",
    "世界领先",
    "完全自主",
    "绝对安全",
    "百分之百准确",
)
STYLE_PATTERNS = (
    (re.compile(r"\d+\s*GRAM", re.IGNORECASE), "内存容量建议写作“数字+空格+GB内存”，例如“16 GB内存”。"),
    (re.compile(r"\d+\s*T(?!B)\s*固态硬盘", re.IGNORECASE), "存储容量建议写作“数字+空格+TB固态硬盘”，例如“1 TB固态硬盘”。"),
    (re.compile(r"Windows(?=\d)", re.IGNORECASE), "Windows名称与版本之间建议保留空格，例如“Windows 10”。"),
)
CANONICAL_TECH_NAMES = {
    "pytorch": "PyTorch",
    "numpy": "NumPy",
    "matplotlib": "Matplotlib",
    "streamlit": "Streamlit",
}


def normalize_text(value: Any) -> str:
    return unicodedata.normalize("NFC", str(value)).strip()


def char_count(value: Any) -> int:
    return len(normalize_text(value))


def is_empty(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return normalize_text(value) == ""
    if isinstance(value, list):
        return len(value) == 0
    return False


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def validate_text(
    key: str,
    label: str,
    value: str,
    rule: dict[str, Any],
    errors: list[str],
    warnings: list[str],
    counts: dict[str, int],
) -> None:
    text = normalize_text(value)
    counts[key] = len(text)

    if rule.get("single_line") and ("\n" in text or "\r" in text):
        errors.append(f"{label}：必须为单段文本，不能包含换行。")

    minimum = rule.get("min_chars")
    maximum = rule.get("max_chars")
    if minimum is not None and len(text) < minimum:
        errors.append(f"{label}：当前{len(text)}字符，少于下限{minimum}字符。")
    if maximum is not None and len(text) > maximum:
        errors.append(f"{label}：当前{len(text)}字符，超过上限{maximum}字符。")

    if text in rule.get("forbid_values", []):
        errors.append(f"{label}：不得填写“{text}”，没有内容时应留空。")

    choices = rule.get("choices")
    if choices and text not in choices:
        errors.append(f"{label}：值“{text}”不在允许选项中。")

    if PLACEHOLDER_RE.search(text):
        errors.append(f"{label}：包含未完成标记或不确定表述。")
    if MARKDOWN_RE.search(text):
        errors.append(f"{label}：包含 Markdown 标记，不适合直接填写网站。")
    if ABSOLUTE_PATH_RE.search(text):
        errors.append(f"{label}：包含本机绝对路径。")
    if ";" in text:
        warnings.append(f"{label}：包含英文分号，登记中文内容建议改用中文分号“；”。")
    for pattern, message in STYLE_PATTERNS:
        if pattern.search(text):
            warnings.append(f"{label}：{message}")
    for lower_name, canonical_name in CANONICAL_TECH_NAMES.items():
        for match in re.finditer(rf"\b{re.escape(lower_name)}\b", text, re.IGNORECASE):
            if match.group(0) != canonical_name:
                warnings.append(
                    f"{label}：技术名称“{match.group(0)}”建议规范为“{canonical_name}”。"
                )
                break
    if key == "technical_features":
        for heading in ("创新性", "原创性"):
            if heading in text:
                warnings.append(
                    f"{label}：不要仅以“{heading}”作为固定标题，请改写为有证据支持的具体技术事实。"
                )
    for claim in UNVERIFIABLE_CLAIMS:
        if claim in text:
            warnings.append(f"{label}：包含可能无法证明的表述“{claim}”。")


def validate_array(
    label: str,
    value: list[Any],
    rule: dict[str, Any],
    errors: list[str],
) -> None:
    normalized = [normalize_text(item) for item in value]
    if any(not item for item in normalized):
        errors.append(f"{label}：数组中不能包含空值。")
    if rule.get("unique") and len(set(normalized)) != len(normalized):
        errors.append(f"{label}：存在重复选项。")
    choices = rule.get("choices")
    if choices:
        invalid = [item for item in normalized if item not in choices]
        if invalid:
            errors.append(f"{label}：以下值不在网站选项中：{', '.join(invalid)}。")


def validate_document(
    data: dict[str, Any], schema: dict[str, Any], strict_final: bool
) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    counts: dict[str, int] = {}
    fields = schema["fields"]

    for key, rule in fields.items():
        label = rule["label"]
        present = key in data
        value = data.get(key)

        if rule.get("required") and (not present or is_empty(value)):
            errors.append(f"{label}：必填字段不能为空。")
            continue
        if not present or is_empty(value):
            if rule["type"] == "string":
                counts[key] = 0
            continue

        expected_type = rule["type"]
        if expected_type == "string":
            if not isinstance(value, str):
                errors.append(f"{label}：必须是字符串。")
                continue
            validate_text(key, label, value, rule, errors, warnings, counts)
        elif expected_type == "array":
            if not isinstance(value, list):
                errors.append(f"{label}：必须是数组。")
                continue
            validate_array(label, value, rule, errors)
        elif expected_type == "integer":
            if isinstance(value, bool) or not isinstance(value, int):
                errors.append(f"{label}：必须是整数。")
                continue
            minimum = rule.get("min_value")
            if minimum is not None and value < minimum:
                errors.append(f"{label}：必须大于或等于{minimum}。")

    languages = data.get("programming_languages", [])
    other_language = normalize_text(data.get("other_programming_languages", ""))
    if not languages and not other_language:
        errors.append("编程语言：至少选择一种网站语言或填写其他编程语言。")

    tags = data.get("technical_feature_tags", [])
    feature_text = normalize_text(data.get("technical_features", ""))
    if not tags and not feature_text:
        errors.append("软件的技术特点：至少选择一个分类标签或填写补充说明。")

    version = normalize_text(data.get("version", ""))
    if version and not VERSION_RE.fullmatch(version):
        warnings.append("版本号：格式不是常见的V1.0/1.0形式，请确认与正式材料一致。")

    full_name = normalize_text(data.get("software_full_name", ""))
    if full_name and version and version.lower() in full_name.lower():
        warnings.append("软件全称：名称中包含版本号，请确认正式名称是否确实如此。")

    if data.get("rights_acquisition") == "继受取得":
        warnings.append("权利取得方式：继受取得通常需要继续核对证明材料和后续页面。")
    if data.get("rights_scope") == "部分权利":
        warnings.append("权利范围：部分权利通常需要继续选择具体权项。")

    confirmations = data.get("_confirmation", {})
    confirmation_keys = {
        "rights_acquisition_confirmed": "权利取得方式",
        "rights_scope_confirmed": "权利范围",
        "software_name_version_confirmed": "软件全称和版本号",
    }
    for key, label in confirmation_keys.items():
        if confirmations.get(key) is not True:
            message = f"{label}：尚未记录用户最终确认。"
            if strict_final:
                errors.append(message)
            else:
                warnings.append(message)

    unknown_keys = sorted(
        key for key in data if key not in fields and key != "_confirmation"
    )
    if unknown_keys:
        warnings.append("存在未参与校验的字段：" + ", ".join(unknown_keys) + "。")

    return {
        "valid": not errors,
        "errors": errors,
        "warnings": warnings,
        "character_counts": counts,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="待校验的 UTF-8 JSON 文件")
    parser.add_argument(
        "--schema",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "references" / "field-schema.json",
        help="字段规则文件",
    )
    parser.add_argument(
        "--strict-final",
        action="store_true",
        help="要求法律事实及名称版本均记录为已确认",
    )
    parser.add_argument("--json-report", type=Path, help="可选的 JSON 校验报告路径")
    args = parser.parse_args()

    try:
        data = load_json(args.input)
        schema = load_json(args.schema)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"读取失败：{exc}", file=sys.stderr)
        return 2

    if not isinstance(data, dict):
        print("校验失败：顶层 JSON 必须是对象。", file=sys.stderr)
        return 2

    report = validate_document(data, schema, args.strict_final)

    print("字符统计：")
    for key, count in report["character_counts"].items():
        rule = schema["fields"][key]
        limit = ""
        if "min_chars" in rule and "max_chars" in rule:
            limit = f"/{rule['min_chars']}~{rule['max_chars']}"
        elif "max_chars" in rule:
            limit = f"/{rule['max_chars']}"
        print(f"- {rule['label']}：{count}{limit}")

    if report["warnings"]:
        print("警告：")
        for item in report["warnings"]:
            print(f"- {item}")

    if report["errors"]:
        print("错误：")
        for item in report["errors"]:
            print(f"- {item}")
    else:
        print("校验结论：全部通过。")

    if args.json_report:
        args.json_report.parent.mkdir(parents=True, exist_ok=True)
        args.json_report.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    return 0 if report["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
