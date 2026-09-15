#!/usr/bin/env python3
"""Read-only Python source triage from a frozen export manifest.

This is not a plagiarism detector or a quality gate. It validates source hashes,
separates imports from exact code-block candidates and locates comment-review
candidates; business relevance and comment correctness require human review.
Only the local JSON report is written. No source text is sent to a service.
"""
from __future__ import annotations

import argparse
import ast
from collections import defaultdict
import hashlib
import io
import json
import re
from pathlib import Path
import sys
import tokenize


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_lines(text: str, tab_width: int) -> list[str]:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if any(ord(ch) < 32 and ch not in "\n\t" for ch in text):
        raise ValueError("Unsupported source control character; no silent removal allowed")
    if not text:
        return []
    lines = text.split("\n")
    if text.endswith("\n"):
        lines.pop()  # One terminal newline is not a new, empty logical line.
    return [line.replace("\t", " " * tab_width) for line in lines]


def load_sources(manifest_path: Path, label: str) -> list[dict]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    root = Path(manifest["ProjectPath"]).resolve(strict=True)
    width = int(manifest["TabWidth"])
    if not root.is_dir() or not 1 <= width <= 16:
        raise ValueError("Invalid project root or tab width")
    details = manifest["SourceFileDetails"]
    if len(details) != int(manifest["SourceFileCount"]):
        raise ValueError("Manifest file count does not match its records")
    files, all_lines, seen = [], [], set()
    for entry in details:
        relative = Path(entry["RelativePath"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Unsafe relative source path")
        source = (root / relative).resolve(strict=True)
        if not source.is_file() or not source.is_relative_to(root):
            raise ValueError("Source is not a file inside the declared project")
        identity = str(source).casefold() if sys.platform == "win32" else str(source)
        if identity in seen:
            raise ValueError("Manifest lists the same source path more than once")
        seen.add(identity)
        raw = source.read_bytes()
        if digest(raw).lower() != entry["RawSha256"].lower():
            raise ValueError(f"Source changed since collection: {relative.as_posix()}")
        encoding = entry["Encoding"].lower()
        if encoding not in {"utf-8", "utf-8-sig", "gb18030", "gbk", "cp936"}:
            raise ValueError(f"Unsupported declared encoding: {encoding}")
        text = raw.decode(encoding, errors="strict")
        if encoding != "utf-8-sig" and text.startswith("\ufeff"):
            text = text[1:]
        lines = source_lines(text, width)
        exported = "\n".join(lines)
        if len(lines) != int(entry["LogicalLines"]):
            raise ValueError(f"Logical line mismatch: {relative.as_posix()}")
        if digest(exported.encode("utf-8")) != entry["DocumentSha256"].lower():
            raise ValueError(f"Per-file exported text mismatch: {relative.as_posix()}")
        start = len(all_lines) + 1
        end = len(all_lines) + len(lines)
        if int(entry["StartLine"]) != start or int(entry["EndLine"]) != end:
            raise ValueError(f"Source mapping mismatch: {relative.as_posix()}")
        all_lines.extend(lines)
        files.append({"project": label, "path": relative.as_posix(),
                      "raw_sha256": digest(raw), "lines": lines,
                      "text": text, "document_start_line": start})
    if len(all_lines) != int(manifest["TotalLogicalLines"]):
        raise ValueError("Manifest total logical line count is incorrect")
    if digest("\n".join(all_lines).encode("utf-8")) != manifest["SourceFingerprint"].lower():
        raise ValueError("Manifest source fingerprint does not match the original files")
    return files


def docstring_node(node: ast.AST) -> ast.Expr | None:
    if not isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
        return None
    body = node.body
    if body and isinstance(body[0], ast.Expr):
        value = body[0].value
        if isinstance(value, ast.Constant) and isinstance(value.value, str):
            return body[0]
    return None


def analyze_python(file: dict) -> tuple[dict, list, list]:
    lines, text = file["lines"], file["text"]
    result = {"project": file["project"], "path": file["path"],
              "logical_lines": len(lines), "nonblank_lines": sum(bool(s.strip()) for s in lines),
              "document_start_line": file["document_start_line"]}
    if Path(file["path"]).suffix.lower() not in {".py", ".pyw"}:
        result.update(analysis="manual-required", reason="Only Python has syntax-aware analysis")
        return result, [], []
    try:
        tree = ast.parse(text, filename=file["path"])
        tokens = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (SyntaxError, tokenize.TokenError, IndentationError) as exc:
        # Never include an exception's source line: a diagnostic need not expose code.
        result.update(analysis="manual-required", reason=type(exc).__name__,
                      error_line=getattr(exc, "lineno", None))
        return result, [], []
    nodes = list(ast.walk(tree))
    comments = {token.start[0] for token in tokens if token.type == tokenize.COMMENT}
    directive_pattern = re.compile(r"^#\s*(?:!|(?:-\*-\s*)?coding[:=]|noqa\b|type:|pragma:|pylint:|ruff:|fmt:|isort:|pyright:|mypy:|nosec\b)", re.I)
    directive_rows = {token.start[0] for token in tokens
                      if token.type == tokenize.COMMENT and directive_pattern.search(token.string)}
    explanation_candidates = comments - directive_rows
    doc_rows, import_rows, imports, functions = set(), set(), [], []
    for node in nodes:
        doc = docstring_node(node)
        if doc is not None:
            doc_rows.update(range(doc.lineno, doc.end_lineno + 1))
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            import_rows.update(range(node.lineno, node.end_lineno + 1))
            imports.append({"statement": ast.unparse(node), "line": node.lineno,
                            "end_line": node.end_lineno})
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            decision_types = (ast.If, ast.For, ast.AsyncFor, ast.While, ast.Try,
                              ast.Match, ast.Raise, ast.With, ast.AsyncWith)
            decisions = sum(isinstance(n, decision_types) for n in ast.walk(node))
            in_scope_comments = sorted(n for n in explanation_candidates if node.lineno <= n <= node.end_lineno)
            functions.append({"name": node.name, "line": node.lineno, "end_line": node.end_lineno,
                              "has_docstring": docstring_node(node) is not None,
                              "comment_lines": in_scope_comments, "decision_nodes": decisions,
                              "review_reason": "decisions-without-local-explanation"
                              if decisions and docstring_node(node) is None and not in_scope_comments else None})
    ignored_rows = doc_rows | import_rows
    code_tokens = defaultdict(list)
    ignored_types = {tokenize.COMMENT, tokenize.NL, tokenize.NEWLINE, tokenize.INDENT,
                     tokenize.DEDENT, tokenize.ENDMARKER, tokenize.ENCODING}
    for token in tokens:
        if token.type in ignored_types or token.start[0] in ignored_rows:
            continue
        # Preserve identifiers and literal values; only layout/comments are ignored.
        code_tokens[token.start[0]].append((token.type, token.string))
    blocks = [(number, json.dumps(items, ensure_ascii=False))
              for number, items in sorted(code_tokens.items())]
    result.update(analysis="python-ast", module_docstring=ast.get_docstring(tree) is not None,
                  comment_lines=len(comments), tool_directive_lines=len(directive_rows),
                  explanatory_comment_candidate_lines=len(explanation_candidates), docstring_lines=len(doc_rows),
                  import_statements=len(imports), import_physical_lines=len(import_rows),
                  functions=functions,
                  comment_review_candidates=[f for f in functions if f["review_reason"]])
    return result, imports, blocks


def review(files: list[dict], min_block_lines: int = 8, max_groups: int = 200) -> dict:
    reports, imports_by_statement, blocks_by_file = [], defaultdict(list), []
    for index, file in enumerate(files):
        report, imports, blocks = analyze_python(file)
        reports.append(report)
        blocks_by_file.append(blocks)
        for item in imports:
            imports_by_statement[item["statement"]].append(
                {"project": file["project"], "path": file["path"], "line": item["line"],
                 "end_line": item["end_line"]})
    windows = defaultdict(list)
    for index, blocks in enumerate(blocks_by_file):
        for offset in range(len(blocks) - min_block_lines + 1):
            window = tuple(line[1] for line in blocks[offset:offset + min_block_lines])
            windows[window].append((index, offset))
    repeated = [(window, places) for window, places in windows.items() if len(places) > 1]
    groups, covered = [], set()
    truncated = False
    for window, places in repeated:
        if all((i, offset) in covered for i, offset in places):
            continue
        if len(groups) >= max_groups:
            truncated = True
            break
        matches = []
        for index, offset in places:
            block = blocks_by_file[index][offset:offset + min_block_lines]
            file = files[index]
            matches.append({"project": file["project"], "path": file["path"],
                            "start_line": block[0][0], "end_line": block[-1][0]})
            # Adjacent windows of the same run are triaged by this representative.
            covered.update((index, k) for k in range(offset, offset + min_block_lines))
        groups.append({"candidate_hash": digest("\n".join(window).encode("utf-8")),
                       "token_bearing_lines": min_block_lines, "locations": matches})
    same_bytes = defaultdict(list)
    for file in files:
        same_bytes[file["raw_sha256"]].append({"project": file["project"], "path": file["path"]})
    return {
        "schema_version": 1,
        "status": "needs-human-review",
        "source_integrity": "verified-against-supplied-manifests",
        "scope": {
            "python_syntax_aware_files": sum(r["analysis"] == "python-ast" for r in reports),
            "manual_required_files": sum(r["analysis"] != "python-ast" for r in reports),
            "block_window_lines": min_block_lines,
            "repeated_window_patterns": len(repeated),
            "reported_block_groups": len(groups),
            "block_examples_truncated": truncated,
        },
        "files": reports,
        "repeated_imports": [{"statement": statement, "locations": places,
                              "interpretation": "normal-dependency-declarations-not-a-defect"}
                             for statement, places in sorted(imports_by_statement.items()) if len(places) > 1],
        "identical_file_candidates": [places for places in same_bytes.values() if len(places) > 1],
        "exact_code_block_candidates": groups,
        "limits": [
            "No plagiarism percentage, originality verdict, or automatic code modification.",
            "Imports, docstrings and comments are excluded only from code-block analysis, never from export.",
            "Windows preserve names and literals; renamed/semantic clones may be missed.",
            "Repeated frameworks, contracts and tests may be legitimate; candidates need business review.",
            "Comment counts and presence do not establish usefulness or correctness.",
            "Only supplied manifests are checked; this does not prove project-wide candidate coverage.",
            "Non-Python files and Python parse failures require manual review.",
            "Block locations are representative windows, not maximal clone spans or duplicate line totals.",
        ],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--compare-manifest", type=Path, action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--min-block-lines", type=int, default=8)
    parser.add_argument("--max-groups", type=int, default=200)
    args = parser.parse_args(argv)
    if args.min_block_lines < 2 or args.max_groups < 1:
        parser.error("--min-block-lines must be >= 2 and --max-groups must be >= 1")
    try:
        manifests = [args.manifest, *args.compare_manifest]
        files = []
        for index, manifest in enumerate(manifests):
            files.extend(load_sources(manifest, "current" if index == 0 else f"comparison-{index}"))
        report = review(files, args.min_block_lines, args.max_groups)
        report["manifest_paths"] = [str(m.resolve()) for m in manifests]
        # Exclusive creation prevents a mistyped report path from replacing a source file.
        with args.output.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(report, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        print(json.dumps({"report": str(args.output.resolve()), "status": report["status"],
                          "scope": report["scope"]}, ensure_ascii=False))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"Review stopped: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
