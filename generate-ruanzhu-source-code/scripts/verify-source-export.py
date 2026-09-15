#!/usr/bin/env python3
"""Independently compare original files, DOCX text and the exported PDF.

Requires PyMuPDF for PDF text/geometry checks. Word COM's style checks remain a
separate validation step. This does not establish originality, legal compliance,
or whether the manifest includes every eligible file in the project.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import runpy
import sys
import xml.etree.ElementTree as ET
import zipfile

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def no_space(text: str) -> str:
    return re.sub(r"\s+", "", text)


def inspect_docx(docx_path: Path, expected: list[str], manifest: dict) -> dict:
    with zipfile.ZipFile(docx_path) as archive:
        root = ET.fromstring(archive.read("word/document.xml"))
        settings = ET.fromstring(archive.read("word/settings.xml"))
        app = ET.fromstring(archive.read("docProps/app.xml"))
    body = root.find(W + "body")
    paragraphs = body.findall(W + "p")
    if len(paragraphs) != 1 or body.findall(W + "tbl"):
        raise ValueError("DOCX must contain one source paragraph and no cover/table")
    chars = []
    for node in paragraphs[0].iter():
        if node.tag == W + "t":
            chars.append(node.text or "")
        elif node.tag == W + "br":
            if node.get(W + "type", "textWrapping") != "textWrapping":
                raise ValueError("Unexpected hard page/column break in source")
            chars.append("\n")
        elif node.tag in {W + "tab", W + "cr"}:
            raise ValueError("Unexpected tab or nonstandard source line break")
    actual = "".join(chars).split("\n")
    if actual[:len(expected)] != expected:
        raise ValueError("DOCX source text differs from the original files and their declared order")
    padding = actual[len(expected):]
    if any(line != "" for line in padding):
        raise ValueError("Nonempty text follows the original source; padding must be empty")
    variables = {v.get(W + "name"): v.get(W + "val") for v in settings.iter(W + "docVar")}
    expected_variables = {
        "RuanzhuSourceLogicalLines": str(len(expected)),
        "RuanzhuSourceFileCount": str(manifest["SourceFileCount"]),
        "RuanzhuSourceFingerprint": manifest["SourceFingerprint"],
        "RuanzhuSelectionStrategy": manifest["SelectionStrategy"],
    }
    for name, value in expected_variables.items():
        if variables.get(name) != value:
            raise ValueError(f"DOCX metadata does not match independently checked source: {name}")
    sections = list(root.iter(W + "sectPr"))
    if len(sections) != 1:
        raise ValueError("Expected a single section")
    title_page = sections[0].find(W + "titlePg")
    if title_page is not None and title_page.get(W + "val", "1") not in {"0", "false", "off"}:
        raise ValueError("First-page header/footer must not differ")
    pages = app.find("{http://schemas.openxmlformats.org/officeDocument/2006/extended-properties}Pages")
    return {"original_logical_lines": len(expected), "padding_slots": len(padding),
            "cached_word_pages": int(pages.text) if pages is not None else None,
            "source_text_exact": True, "single_section_no_cover": True}


def inspect_pdf(pdf_path: Path, expected: list[str], system: str, version: str, no_footer: bool) -> dict:
    import fitz

    page_reports, pdf_source = [], []
    with fitz.open(pdf_path) as pdf:
        for index, page in enumerate(pdf, 1):
            width, height = page.rect.width, page.rect.height
            if abs(width - 595.3) > 1 or abs(height - 841.9) > 1:
                raise ValueError(f"PDF page {index}: not A4 portrait")
            words = page.get_text("words")
            gutter = sorted((w for w in words if 15 < w[0] and w[2] < 71 and 60 < w[1] < height - 67),
                            key=lambda word: (word[1], word[0]))
            numbers = [w[4] for w in gutter]
            if numbers != [str(n) for n in range(1, 51)]:
                raise ValueError(f"PDF page {index}: visible line numbers are not exactly 1-50")
            header = page.get_text("text", clip=fitz.Rect(71, 20, width - 70, 64), sort=True)
            wanted_header = f"{system} {version} 源程序 {index} / {len(pdf)}"
            if no_space(header) != no_space(wanted_header):
                raise ValueError(f"PDF page {index}: header/system/version/page fields mismatch or wrapping")
            footer = page.get_text("text", clip=fitz.Rect(100, height - 65, width - 100, height - 20), sort=True)
            if no_space(footer) != ("" if no_footer else str(index)):
                raise ValueError(f"PDF page {index}: footer page number mismatch")
            body = page.get_text("text", clip=fitz.Rect(71.8, 69, width - 71, height - 68), sort=True)
            pdf_source.append(body)
            page_reports.append({"page": index, "visible_line_numbers": "1-50", "header": True, "footer": True})
        if not len(pdf):
            raise ValueError("PDF has no pages")
    # PDF extraction cannot preserve indentation exactly; DOCX was checked byte-for-text.
    # Here whitespace-insensitive equality catches missing/replaced visible code glyphs.
    if no_space("".join(pdf_source)) != no_space("\n".join(expected)):
        raise ValueError("PDF visible non-whitespace source differs; inspect clipping/fonts/text extraction")
    return {"pages": len(page_reports), "page_checks": page_reports,
            "visible_nonwhitespace_source_matches": True}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--docx", type=Path, required=True)
    parser.add_argument("--pdf", type=Path, required=True)
    parser.add_argument("--system-name", required=True)
    parser.add_argument("--version", default="V1.0")
    parser.add_argument("--no-footer", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    result = {"passed": False, "project_scope_reviewed": False, "originality_assessed": False,
              "visual_review_performed": False, "errors": []}
    try:
        helper = runpy.run_path(str(Path(__file__).with_name("review-source.py")))
        files = helper["load_sources"](args.manifest, "current")
        manifest = json.loads(args.manifest.read_text(encoding="utf-8-sig"))
        expected = [line for file in files for line in file["lines"]]
        result["docx"] = inspect_docx(args.docx, expected, manifest)
        result["pdf"] = inspect_pdf(args.pdf, expected, args.system_name, args.version, args.no_footer)
        cached = result["docx"]["cached_word_pages"]
        if cached is not None and cached != result["pdf"]["pages"]:
            raise ValueError("DOCX cached page count differs from PDF; also check live Word statistics")
        result["passed"] = True
    except Exception as exc:
        result["errors"].append(f"{type(exc).__name__}: {exc}")
    try:
        with args.output.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(result, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
    except OSError as exc:
        print(f"Cannot write verification result: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
