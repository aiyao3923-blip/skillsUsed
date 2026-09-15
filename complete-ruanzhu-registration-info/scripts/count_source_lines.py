#!/usr/bin/env python3
"""统计软著项目源文件的物理行数和非空物理行数。"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


DEFAULT_EXTENSIONS = {
    ".asm", ".s", ".c", ".h", ".cc", ".cpp", ".cxx", ".hpp",
    ".cs", ".go", ".java", ".kt", ".kts", ".m", ".mm", ".pas",
    ".php", ".pl", ".pm", ".py", ".pyw", ".r", ".rb", ".rs",
    ".scala", ".swift", ".vb", ".fs", ".fsx", ".dart", ".lua",
    ".groovy", ".sol", ".ts", ".tsx", ".js", ".jsx", ".vue",
    ".svelte", ".html", ".htm", ".css", ".scss", ".sass", ".less",
    ".sql", ".xml", ".xaml", ".qml", ".sh", ".ps1", ".bat", ".cmd"
}

DEFAULT_EXCLUDED_DIRS = {
    ".git", ".hg", ".svn", ".idea", ".vscode", "node_modules", "vendor",
    ".venv", "venv", "env", "__pycache__", ".pytest_cache", ".mypy_cache",
    ".ruff_cache", "dist", "build", "out", "target", "bin", "obj",
    "coverage", ".coverage", ".next", ".nuxt", ".gradle", ".cache"
}

GENERATED_SUFFIXES = (".min.js", ".min.css", ".map", ".designer.cs", ".g.cs")
ENCODINGS = ("utf-8-sig", "utf-8", "gb18030")


def read_text(path: Path) -> tuple[str | None, str | None]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        return None, str(exc)
    if b"\x00" in raw:
        return None, "疑似二进制文件"
    for encoding in ENCODINGS:
        try:
            return raw.decode(encoding), None
        except UnicodeDecodeError:
            continue
    return None, "无法按UTF-8或GB18030解码"


def count_file(path: Path) -> tuple[int, int, str | None]:
    text, error = read_text(path)
    if text is None:
        return 0, 0, error
    lines = text.splitlines()
    return len(lines), sum(1 for line in lines if line.strip()), None


def scan(
    root: Path, extensions: set[str], excluded_dirs: set[str]
) -> dict[str, Any]:
    files: list[dict[str, Any]] = []
    skipped: list[dict[str, str]] = []
    by_extension: dict[str, dict[str, int]] = defaultdict(
        lambda: {"files": 0, "physical_lines": 0, "nonblank_lines": 0}
    )

    for current, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in excluded_dirs)
        current_path = Path(current)
        for name in sorted(names):
            path = current_path / name
            lower_name = name.lower()
            suffix = path.suffix.lower()
            if suffix not in extensions or lower_name.endswith(GENERATED_SUFFIXES):
                continue
            physical, nonblank, error = count_file(path)
            relative = path.relative_to(root).as_posix()
            if error:
                skipped.append({"path": relative, "reason": error})
                continue
            item = {
                "path": relative,
                "extension": suffix,
                "physical_lines": physical,
                "nonblank_lines": nonblank,
            }
            files.append(item)
            stats = by_extension[suffix]
            stats["files"] += 1
            stats["physical_lines"] += physical
            stats["nonblank_lines"] += nonblank

    physical_total = sum(item["physical_lines"] for item in files)
    nonblank_total = sum(item["nonblank_lines"] for item in files)
    return {
        "root": str(root.resolve()),
        "method": "排除依赖、缓存、构建产物和常见生成文件；统计文本源文件物理行与非空物理行",
        "file_count": len(files),
        "physical_lines": physical_total,
        "nonblank_lines": nonblank_total,
        "recommended_registration_lines": nonblank_total,
        "by_extension": dict(sorted(by_extension.items())),
        "files": files,
        "skipped": skipped,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="源代码根目录")
    parser.add_argument(
        "--extension",
        action="append",
        default=[],
        help="追加或限定扩展名；可重复，如 --extension .py",
    )
    parser.add_argument(
        "--exclude-dir", action="append", default=[], help="追加排除的目录名"
    )
    parser.add_argument("--json-output", type=Path, help="输出完整JSON报告")
    args = parser.parse_args()

    root = args.root.resolve()
    if not root.is_dir():
        print(f"目录不存在：{root}", file=sys.stderr)
        return 2

    if args.extension:
        extensions = {
            ext.lower() if ext.startswith(".") else f".{ext.lower()}"
            for ext in args.extension
        }
    else:
        extensions = set(DEFAULT_EXTENSIONS)
    excluded_dirs = set(DEFAULT_EXCLUDED_DIRS) | set(args.exclude_dir)

    report = scan(root, extensions, excluded_dirs)
    print(f"源文件数量：{report['file_count']}")
    print(f"物理总行数：{report['physical_lines']}")
    print(f"非空物理行数：{report['nonblank_lines']}")
    print(f"建议登记源程序量：{report['recommended_registration_lines']} 行")
    if report["skipped"]:
        print(f"跳过无法读取文件：{len(report['skipped'])}")

    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    return 0 if report["file_count"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
