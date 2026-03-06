#!/usr/bin/env python3
"""
pdf_metadata.py — Programmatic PDF metadata extraction using PyMuPDF.

Extracts page count, ToC, figure/table counts, image density, and section
headings for triage reading-plan generation. No LLM calls — regex heuristics only.

Usage:
  python scripts/pdf_metadata.py papers/Author2024_Title.pdf          # human-readable
  python scripts/pdf_metadata.py papers/Author2024_Title.pdf --json   # JSON output
  python scripts/pdf_metadata.py --batch papers/ --output corpus/pdf_metadata.jsonl

Dependencies: pymupdf (pip install pymupdf)
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError:
    print("Error: PyMuPDF not installed. Run: pip install pymupdf", file=sys.stderr)
    sys.exit(1)


# ── Regex patterns for figure/table detection ────────────────────

_FIG_PATTERN = re.compile(
    r"(?:Fig(?:ure|\.)\s*\d+|FIGURE\s+\d+)", re.IGNORECASE
)
_TABLE_PATTERN = re.compile(
    r"(?:Table\s+\d+|TABLE\s+\d+)", re.IGNORECASE
)
_HEADING_PATTERNS = [
    re.compile(r"^\d+\.?\s+[A-Z][A-Za-z\s:,\-]+$", re.MULTILINE),      # "1. Introduction"
    re.compile(r"^[IVX]+\.\s+[A-Z][A-Za-z\s:,\-]+$", re.MULTILINE),    # "IV. Results"
    re.compile(r"^[A-Z][A-Z\s:,\-]{4,}$", re.MULTILINE),               # "INTRODUCTION"
]


def get_fast_metadata(pdf_path: str) -> dict:
    """Extract metadata from a PDF without reading full text.

    Returns dict with: page_count, has_toc, toc, figure_count, table_count,
    image_obj_count, image_density, is_scanned, file_size_mb, sections.
    """
    doc = fitz.open(pdf_path)
    page_count = len(doc)
    file_size_mb = round(Path(pdf_path).stat().st_size / (1024 * 1024), 2)

    # ToC extraction — works for ~40-60% of arXiv papers
    toc_raw = doc.get_toc()
    has_toc = len(toc_raw) > 0
    toc = []
    for level, title, page_num in toc_raw:
        toc.append({"level": level, "title": title, "page": page_num})

    # Count image objects and detect scanned PDFs
    total_images = 0
    total_text_len = 0
    fig_mentions = set()
    table_mentions = set()

    for page_num in range(page_count):
        page = doc[page_num]
        images = page.get_images(full=True)
        total_images += len(images)

        text = page.get_text("text")
        total_text_len += len(text)

        # Count unique figure/table references by regex
        for m in _FIG_PATTERN.finditer(text):
            # Normalize "Fig. 3" and "Figure 3" to same key
            num = re.search(r"\d+", m.group())
            if num:
                fig_mentions.add(int(num.group()))

        for m in _TABLE_PATTERN.finditer(text):
            num = re.search(r"\d+", m.group())
            if num:
                table_mentions.add(int(num.group()))

    figure_count = len(fig_mentions)
    table_count = len(table_mentions)
    image_density = round(total_images / max(page_count, 1), 2)

    # Heuristic: scanned PDF has images but very little text
    avg_text_per_page = total_text_len / max(page_count, 1)
    is_scanned = total_images > 0 and avg_text_per_page < 100

    # Section headings from ToC or heuristic
    sections = []
    if has_toc:
        sections = [{"title": t["title"], "page": t["page"]} for t in toc if t["level"] <= 2]
    else:
        sections = get_section_headings(pdf_path, doc=doc)

    doc.close()

    return {
        "file": str(Path(pdf_path).name),
        "page_count": page_count,
        "has_toc": has_toc,
        "toc": toc if has_toc else [],
        "figure_count": figure_count,
        "table_count": table_count,
        "image_obj_count": total_images,
        "image_density": image_density,
        "is_scanned": is_scanned,
        "file_size_mb": file_size_mb,
        "sections": sections,
        "estimated_chunks": estimate_reading_chunks(page_count, image_density),
    }


def get_section_headings(pdf_path: str, doc=None) -> list:
    """Detect section headings from first 3 pages when ToC is absent.

    Uses regex heuristics — not an LLM call. Returns list of
    {"title": str, "page": int} dicts.
    """
    close_doc = False
    if doc is None:
        doc = fitz.open(pdf_path)
        close_doc = True

    headings = []
    pages_to_scan = min(3, len(doc))

    for page_num in range(pages_to_scan):
        text = doc[page_num].get_text("text")
        for pattern in _HEADING_PATTERNS:
            for m in pattern.finditer(text):
                candidate = m.group().strip()
                # Filter noise: too short, digits only, contains newlines (multi-line false positive)
                if len(candidate) < 4 or candidate.isdigit():
                    continue
                if "\n" in candidate:
                    continue
                # Skip if too long (likely a sentence, not a heading)
                if len(candidate) > 80:
                    continue
                # Skip common non-heading lines
                if candidate.upper() in ("ABSTRACT", "KEYWORDS", "REFERENCES"):
                    continue
                headings.append({"title": candidate, "page": page_num + 1})

    if close_doc:
        doc.close()

    # Deduplicate by title
    seen = set()
    unique = []
    for h in headings:
        key = h["title"].lower().strip()
        if key not in seen:
            seen.add(key)
            unique.append(h)

    return unique


def estimate_reading_chunks(pages: int, image_density: float) -> int:
    """Estimate number of 5-page reading chunks, adjusted for image density.

    High image density (>2.0 images/page) means pages carry more information,
    so we add a small multiplier.
    """
    base = math.ceil(pages / 5)
    if image_density > 2.0:
        return math.ceil(base * 1.2)
    return base


def batch_metadata(papers_dir: str, output_path: str) -> int:
    """Run get_fast_metadata on all PDFs in a directory, write JSONL output."""
    papers = sorted(Path(papers_dir).glob("*.pdf"))
    if not papers:
        print(f"No PDFs found in {papers_dir}", file=sys.stderr)
        return 0

    out_path = Path(output_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    count = 0
    with open(out_path, "w", encoding="utf-8") as f:
        for pdf in papers:
            try:
                meta = get_fast_metadata(str(pdf))
                f.write(json.dumps(meta) + "\n")
                count += 1
                print(f"  [{count}/{len(papers)}] {pdf.name}: {meta['page_count']}pp, "
                      f"{meta['figure_count']} figs, {meta['table_count']} tables",
                      file=sys.stderr)
            except Exception as e:
                print(f"  ERROR: {pdf.name}: {e}", file=sys.stderr)

    print(f"\nWrote {count} entries to {output_path}", file=sys.stderr)
    return count


def print_human_readable(meta: dict):
    """Print metadata in a human-friendly format."""
    print(f"\n  File:           {meta['file']}")
    print(f"  Pages:          {meta['page_count']}")
    print(f"  File size:      {meta['file_size_mb']} MB")
    print(f"  Has ToC:        {meta['has_toc']}")
    print(f"  Figures:        {meta['figure_count']}")
    print(f"  Tables:         {meta['table_count']}")
    print(f"  Image objects:  {meta['image_obj_count']}")
    print(f"  Image density:  {meta['image_density']} img/page")
    print(f"  Scanned PDF:    {meta['is_scanned']}")
    print(f"  Est. chunks:    {meta['estimated_chunks']} (5-page reads)")

    if meta['sections']:
        print(f"\n  Detected sections:")
        for s in meta['sections']:
            print(f"    p.{s['page']:>3}  {s['title']}")

    print()


def main():
    parser = argparse.ArgumentParser(
        description="Extract PDF metadata for triage reading plans"
    )
    parser.add_argument("pdf", nargs="?", help="Path to a single PDF file")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--batch", help="Directory of PDFs for batch processing")
    parser.add_argument("--output", "-o", help="Output path for batch JSONL")

    args = parser.parse_args()

    if args.batch:
        if not args.output:
            print("Error: --output required with --batch", file=sys.stderr)
            sys.exit(1)
        count = batch_metadata(args.batch, args.output)
        if count == 0:
            sys.exit(1)
    elif args.pdf:
        pdf_path = Path(args.pdf)
        if not pdf_path.exists():
            print(f"Error: {args.pdf} not found", file=sys.stderr)
            sys.exit(1)
        meta = get_fast_metadata(str(pdf_path))
        if args.json:
            print(json.dumps(meta, indent=2))
        else:
            print_human_readable(meta)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
