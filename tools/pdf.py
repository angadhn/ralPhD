"""PDF tools: pdf_metadata, extract_figure.

pdf_metadata is implemented inline (get_fast_metadata, get_section_headings,
estimate_reading_chunks). extract_figure still delegates to scripts/.
"""

import json
import math
import os
import re
import subprocess

from pathlib import Path

from tools._paths import scripts_dir as _scripts_dir


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
    import fitz  # lazy import — PyMuPDF

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
    import fitz  # lazy import — PyMuPDF

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
                if len(candidate) < 4 or candidate.isdigit():
                    continue
                if "\n" in candidate:
                    continue
                if len(candidate) > 80:
                    continue
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
    """Estimate number of 5-page reading chunks, adjusted for image density."""
    base = math.ceil(pages / 5)
    if image_density > 2.0:
        return math.ceil(base * 1.2)
    return base


def _run_cmd(cmd):
    """Run a subprocess, return combined stdout+stderr."""
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout + result.stderr
    return output if output.strip() else f"(exit code {result.returncode}, no output)"


def _handle_pdf_metadata(inp):
    meta = get_fast_metadata(inp["pdf_path"])
    return json.dumps(meta, indent=2)


def _handle_extract_figure(inp):
    if inp.get("list_only"):
        cmd = ["python3", str(_scripts_dir() / "extract_figure.py"), "--list", inp["pdf_path"]]
    elif inp.get("render_page"):
        cmd = ["python3", str(_scripts_dir() / "extract_figure.py"), inp["pdf_path"],
               "--render-page", str(inp["render_page"]),
               "--output", inp.get("output_dir", "figures/")]
        if inp.get("dpi"):
            cmd.extend(["--dpi", str(inp["dpi"])])
    else:
        cmd = ["python3", str(_scripts_dir() / "extract_figure.py"), inp["pdf_path"],
               "--output", inp.get("output_dir", "figures/")]
        if inp.get("pages"):
            cmd.extend(["--pages", inp["pages"]])
    return _run_cmd(cmd)


TOOLS = {
    "pdf_metadata": {
        "name": "pdf_metadata",
        "description": (
            "Extract metadata from a PDF: page count, table of contents, figure/table counts, "
            "section headings, image density, scanned-PDF detection, and estimated reading chunks. "
            "Returns JSON. Use before reading a paper to plan reading budget."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "pdf_path": {"type": "string", "description": "Path to the PDF file"},
            },
            "required": ["pdf_path"],
        },
        "function": _handle_pdf_metadata,
    },
    "extract_figure": {
        "name": "extract_figure",
        "description": (
            "Extract figures from a PDF file. Can list images without extracting, "
            "extract embedded images from specific pages, or render a full page as a high-res PNG."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "pdf_path": {"type": "string", "description": "Path to the PDF file"},
                "output_dir": {"type": "string", "description": "Output directory for extracted images (default: 'figures/')"},
                "pages": {"type": "string", "description": "Page range to extract from (e.g. '1-5', '3', '1,3,5')"},
                "list_only": {"type": "boolean", "description": "List images without extracting (default false)"},
                "render_page": {"type": "integer", "description": "Render a specific page number as a full PNG image"},
                "dpi": {"type": "integer", "description": "DPI for page rendering (default: 200)"},
            },
            "required": ["pdf_path"],
        },
        "function": _handle_extract_figure,
    },
}
