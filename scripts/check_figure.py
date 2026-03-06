#!/usr/bin/env python3
"""
check_figure.py — Deterministic figure compliance checker.

Checks image files for publication readiness:
- DPI (from image metadata or PDF render resolution)
- Pixel dimensions (width x height)
- Color mode (RGB, CMYK, grayscale)
- File size
- File format (PDF vector vs PNG raster)

Usage:
  python scripts/check_figure.py figures/fig_01_*.pdf figures/fig_01_*.png
  python scripts/check_figure.py --pub-reqs specs/publication-requirements.md figures/
  python scripts/check_figure.py --min-dpi 300 --max-width-px 2400 figures/fig_01_name.png
  python scripts/check_figure.py --json figures/

Exit code 0 = pass, 1 = fail
"""

import argparse
import json
import re
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Error: Pillow not installed. Run: pip install Pillow", file=sys.stderr)
    sys.exit(1)

try:
    import fitz  # PyMuPDF
except ImportError:
    fitz = None  # PDF checks disabled


# ── Defaults ────────────────────────────────────────────────────

DEFAULTS = {
    "min_dpi": 300,
    "max_width_px": 2400,
    "max_height_px": 3600,
    "max_file_size_mb": 10,
}


def parse_pub_reqs(path: str) -> dict:
    """Parse specs/publication-requirements.md for figure thresholds."""
    reqs = dict(DEFAULTS)
    text = Path(path).read_text(encoding="utf-8")
    patterns = {
        "min_dpi": r"(?:min[_\s-]*)?dpi\s*[:=]\s*(\d+)",
        "max_width_px": r"max[_\s-]*width[_\s-]*(?:px|pixels?)?\s*[:=]\s*(\d+)",
        "max_height_px": r"max[_\s-]*height[_\s-]*(?:px|pixels?)?\s*[:=]\s*(\d+)",
        "max_file_size_mb": r"max[_\s-]*(?:file[_\s-]*)?size[_\s-]*(?:mb)?\s*[:=]\s*(\d+(?:\.\d+)?)",
    }
    for key, pat in patterns.items():
        m = re.search(pat, text, re.IGNORECASE)
        if m:
            reqs[key] = float(m.group(1)) if "." in m.group(1) else int(m.group(1))
    return reqs


def check_raster(filepath: Path, reqs: dict) -> dict:
    """Check a raster image (PNG, TIFF, JPEG)."""
    result = {"file": str(filepath), "format": filepath.suffix.upper().lstrip(".")}
    issues = []

    img = Image.open(filepath)
    w, h = img.size
    result["width_px"] = w
    result["height_px"] = h
    result["color_mode"] = img.mode
    result["file_size_mb"] = round(filepath.stat().st_size / (1024 * 1024), 2)

    # DPI from metadata
    dpi_info = img.info.get("dpi", (None, None))
    if dpi_info and dpi_info[0]:
        dpi = int(round(dpi_info[0]))
    else:
        dpi = None
    result["dpi"] = dpi

    # Checks
    if dpi is not None and dpi < reqs["min_dpi"]:
        issues.append(f"DPI {dpi} < minimum {reqs['min_dpi']}")
    elif dpi is None:
        issues.append(f"No DPI metadata found (expect >= {reqs['min_dpi']})")

    if w > reqs["max_width_px"]:
        issues.append(f"Width {w}px > maximum {reqs['max_width_px']}px")
    if h > reqs["max_height_px"]:
        issues.append(f"Height {h}px > maximum {reqs['max_height_px']}px")
    if result["file_size_mb"] > reqs["max_file_size_mb"]:
        issues.append(f"File size {result['file_size_mb']}MB > maximum {reqs['max_file_size_mb']}MB")

    result["issues"] = issues
    result["pass"] = len(issues) == 0
    return result


def check_pdf(filepath: Path, reqs: dict) -> dict:
    """Check a PDF figure (vector format)."""
    if fitz is None:
        return {
            "file": str(filepath),
            "format": "PDF",
            "issues": ["PyMuPDF not installed — cannot check PDF figures"],
            "pass": False,
        }

    result = {"file": str(filepath), "format": "PDF (vector)"}
    issues = []

    doc = fitz.open(str(filepath))
    result["pages"] = len(doc)
    result["file_size_mb"] = round(filepath.stat().st_size / (1024 * 1024), 2)

    if len(doc) > 0:
        page = doc[0]
        rect = page.rect
        result["width_pt"] = round(rect.width, 1)
        result["height_pt"] = round(rect.height, 1)
        # Convert points to inches (72 pt = 1 inch)
        result["width_in"] = round(rect.width / 72, 2)
        result["height_in"] = round(rect.height / 72, 2)

    if result["file_size_mb"] > reqs["max_file_size_mb"]:
        issues.append(f"File size {result['file_size_mb']}MB > maximum {reqs['max_file_size_mb']}MB")
    if len(doc) > 1:
        issues.append(f"PDF has {len(doc)} pages (expected single-page figure)")

    doc.close()
    result["issues"] = issues
    result["pass"] = len(issues) == 0
    return result


def collect_files(paths: list) -> list:
    """Expand directories and glob patterns into a flat list of figure files."""
    extensions = {".png", ".jpg", ".jpeg", ".tiff", ".tif", ".pdf"}
    files = []
    for p in paths:
        path = Path(p)
        if path.is_dir():
            for ext in extensions:
                files.extend(sorted(path.glob(f"*{ext}")))
        elif path.exists():
            files.append(path)
        else:
            # Try glob from parent
            for match in sorted(Path(".").glob(p)):
                if match.suffix.lower() in extensions:
                    files.append(match)
    return files


def main():
    parser = argparse.ArgumentParser(description="Figure compliance checker")
    parser.add_argument("files", nargs="+", help="Figure files or directories to check")
    parser.add_argument("--pub-reqs", default=None, help="Path to publication requirements markdown")
    parser.add_argument("--min-dpi", type=int, default=None, help="Override minimum DPI")
    parser.add_argument("--max-width-px", type=int, default=None, help="Override max width in pixels")
    parser.add_argument("--max-height-px", type=int, default=None, help="Override max height in pixels")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    args = parser.parse_args()

    # Build requirements
    reqs = dict(DEFAULTS)
    if args.pub_reqs and Path(args.pub_reqs).exists():
        reqs = parse_pub_reqs(args.pub_reqs)
    if args.min_dpi is not None:
        reqs["min_dpi"] = args.min_dpi
    if args.max_width_px is not None:
        reqs["max_width_px"] = args.max_width_px
    if args.max_height_px is not None:
        reqs["max_height_px"] = args.max_height_px

    figures = collect_files(args.files)
    if not figures:
        print("No figure files found.", file=sys.stderr)
        sys.exit(1)

    results = []
    for fig in figures:
        if fig.suffix.lower() == ".pdf":
            results.append(check_pdf(fig, reqs))
        else:
            results.append(check_raster(fig, reqs))

    # Output
    all_pass = all(r["pass"] for r in results)

    if args.json:
        print(json.dumps({"results": results, "pass": all_pass}, indent=2))
    else:
        for r in results:
            status = "PASS" if r["pass"] else "FAIL"
            print(f"\n[{status}] {r['file']}")
            print(f"  Format: {r['format']}")
            if "dpi" in r:
                print(f"  DPI: {r['dpi'] or 'N/A'}")
            if "width_px" in r:
                print(f"  Dimensions: {r['width_px']} x {r['height_px']} px")
            if "width_pt" in r:
                print(f"  Dimensions: {r['width_pt']} x {r['height_pt']} pt ({r['width_in']} x {r['height_in']} in)")
            if "color_mode" in r:
                print(f"  Color mode: {r['color_mode']}")
            print(f"  File size: {r.get('file_size_mb', 'N/A')} MB")
            if r["issues"]:
                print(f"  Issues:")
                for issue in r["issues"]:
                    print(f"    - {issue}")

        print(f"\n{'='*50}")
        passed = sum(1 for r in results if r["pass"])
        print(f"Result: {passed}/{len(results)} figures passed")
        print("PASS" if all_pass else "FAIL")

    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
