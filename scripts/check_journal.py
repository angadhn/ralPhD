#!/usr/bin/env python3
"""
check_journal.py — Deterministic journal compliance checker.

Checks manuscript against publication requirements (journal, conference, memo, etc.):
1. Word count per section (strips LaTeX commands, then counts)
2. Total word count vs journal limit
3. Page estimate (word count / ~250 for single-column, ~500 for double)
4. Required .bib fields present (author, title, year, doi) per entry

Usage:
  python scripts/check_journal.py sections/
  python scripts/check_journal.py --pub-reqs specs/publication-requirements.md sections/
  python scripts/check_journal.py --word-limit 6000 --page-limit 10 sections/

Exit code 0 = pass, 1 = fail (over limits)
"""

import argparse
import json
import re
import sys
from pathlib import Path

# Reuse LaTeX stripping from check_language.py
sys.path.insert(0, str(Path(__file__).parent))
from check_language import strip_latex_commands, extract_body


# ── Defaults ────────────────────────────────────────────────────

DEFAULTS = {
    "word_limit": 6000,
    "page_limit": 10,
    "words_per_page": 250,  # single-column default
    "required_bib_fields": ["author", "title", "year"],
}


def parse_pub_reqs(path: str) -> dict:
    """Parse specs/publication-requirements.md for compliance thresholds."""
    reqs = dict(DEFAULTS)
    reqs["required_bib_fields"] = list(DEFAULTS["required_bib_fields"])
    text = Path(path).read_text(encoding="utf-8")
    patterns = {
        "word_limit": r"word[_\s-]*limit\s*[:=]\s*(\d+)",
        "page_limit": r"page[_\s-]*limit\s*[:=]\s*(\d+)",
        "words_per_page": r"words[_\s-]*per[_\s-]*page\s*[:=]\s*(\d+)",
    }
    for key, pat in patterns.items():
        m = re.search(pat, text, re.IGNORECASE)
        if m:
            reqs[key] = int(m.group(1))
    # Check for double-column hint
    if re.search(r"double[_\s-]*column", text, re.IGNORECASE):
        reqs["words_per_page"] = 500
    return reqs


def count_words_tex(filepath: Path) -> tuple:
    """Count words in a .tex file after stripping LaTeX. Returns (word_count, section_name)."""
    content = filepath.read_text(encoding="utf-8")
    body = extract_body(content)
    stripped = strip_latex_commands(body)
    # Remove citation markers left by strip_latex_commands
    stripped = re.sub(r'\\cite\{[^}]*\}', '', stripped)
    words = stripped.split()
    return len(words), filepath.stem


def check_bib_fields(bib_path: Path, required_fields: list) -> list:
    """Check that each .bib entry has required fields."""
    issues = []
    content = bib_path.read_text(encoding="utf-8")

    # Simple bib parser: split on @ entries
    entries = re.split(r'(?=@\w+\{)', content)
    for entry in entries:
        entry = entry.strip()
        if not entry or not entry.startswith("@"):
            continue
        # Skip @comment, @preamble, @string
        entry_type_match = re.match(r'@(\w+)\{([^,]*)', entry)
        if not entry_type_match:
            continue
        entry_type = entry_type_match.group(1).lower()
        cite_key = entry_type_match.group(2).strip()
        if entry_type in ("comment", "preamble", "string"):
            continue

        entry_lower = entry.lower()
        missing = []
        for field in required_fields:
            # Check for field = or field={ patterns
            if not re.search(rf'\b{field}\s*=', entry_lower):
                missing.append(field)
        if missing:
            issues.append({
                "cite_key": cite_key,
                "file": str(bib_path),
                "missing_fields": missing,
            })
    return issues


def collect_tex_files(paths: list) -> list:
    """Expand directories into .tex files."""
    files = []
    for p in paths:
        path = Path(p)
        if path.is_dir():
            files.extend(sorted(path.glob("*.tex")))
        elif path.exists() and path.suffix == ".tex":
            files.append(path)
    return files


def collect_bib_files(paths: list) -> list:
    """Find .bib files in references/ or alongside .tex files."""
    bib_files = []
    checked = set()
    for p in paths:
        path = Path(p)
        search_dir = path if path.is_dir() else path.parent
        if search_dir not in checked:
            checked.add(search_dir)
            bib_files.extend(sorted(search_dir.glob("*.bib")))
    # Also check references/ directory
    ref_dir = Path("references")
    if ref_dir.exists() and ref_dir not in checked:
        bib_files.extend(sorted(ref_dir.glob("*.bib")))
    return bib_files


def main():
    parser = argparse.ArgumentParser(description="Journal compliance checker")
    parser.add_argument("paths", nargs="+", help="Section .tex files or directories")
    parser.add_argument("--pub-reqs", default=None, help="Path to publication requirements markdown")
    parser.add_argument("--word-limit", type=int, default=None, help="Override word limit")
    parser.add_argument("--page-limit", type=int, default=None, help="Override page limit")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    args = parser.parse_args()

    # Build requirements
    reqs = dict(DEFAULTS)
    reqs["required_bib_fields"] = list(DEFAULTS["required_bib_fields"])
    if args.pub_reqs and Path(args.pub_reqs).exists():
        reqs = parse_pub_reqs(args.pub_reqs)
    if args.word_limit is not None:
        reqs["word_limit"] = args.word_limit
    if args.page_limit is not None:
        reqs["page_limit"] = args.page_limit

    tex_files = collect_tex_files(args.paths)
    if not tex_files:
        print("No .tex files found.", file=sys.stderr)
        sys.exit(1)

    # Word counts
    section_counts = []
    total_words = 0
    for f in tex_files:
        wc, name = count_words_tex(f)
        section_counts.append({"file": str(f), "section": name, "word_count": wc})
        total_words += wc

    page_estimate = round(total_words / reqs["words_per_page"], 1)

    # Bib checks
    bib_files = collect_bib_files(args.paths)
    bib_issues = []
    for bf in bib_files:
        bib_issues.extend(check_bib_fields(bf, reqs["required_bib_fields"]))

    # Determine pass/fail
    issues = []
    if total_words > reqs["word_limit"]:
        issues.append(f"Total word count {total_words} exceeds limit of {reqs['word_limit']} (over by {total_words - reqs['word_limit']})")
    if page_estimate > reqs["page_limit"]:
        issues.append(f"Estimated {page_estimate} pages exceeds limit of {reqs['page_limit']}")
    if bib_issues:
        issues.append(f"{len(bib_issues)} bibliography entries missing required fields")

    all_pass = len(issues) == 0

    report = {
        "sections": section_counts,
        "total_words": total_words,
        "word_limit": reqs["word_limit"],
        "page_estimate": page_estimate,
        "page_limit": reqs["page_limit"],
        "words_per_page": reqs["words_per_page"],
        "bib_issues": bib_issues,
        "issues": issues,
        "pass": all_pass,
    }

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"\n{'='*50}")
        print("Journal Compliance Check")
        print(f"{'='*50}")
        print(f"\nWord Counts by Section:")
        for sc in section_counts:
            print(f"  {sc['section']}: {sc['word_count']} words")
        print(f"\n  Total: {total_words} / {reqs['word_limit']} words", end="")
        if total_words > reqs["word_limit"]:
            print(f"  [OVER by {total_words - reqs['word_limit']}]")
        else:
            print(f"  [OK — {reqs['word_limit'] - total_words} remaining]")

        print(f"\nPage Estimate: {page_estimate} / {reqs['page_limit']} pages "
              f"({reqs['words_per_page']} words/page)", end="")
        if page_estimate > reqs["page_limit"]:
            print(f"  [OVER]")
        else:
            print(f"  [OK]")

        if bib_issues:
            print(f"\nBibliography Issues:")
            for bi in bib_issues:
                print(f"  {bi['cite_key']} ({bi['file']}): missing {', '.join(bi['missing_fields'])}")
        elif bib_files:
            print(f"\nBibliography: {len(bib_files)} file(s) checked, all entries OK")
        else:
            print(f"\nBibliography: No .bib files found")

        print(f"\n{'='*50}")
        print("PASS" if all_pass else "FAIL")

    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
