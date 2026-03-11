"""Check tools: check_language, check_journal, check_figure, citation_lint,
citation_lookup, citation_verify, citation_verify_all, citation_manifest.

All check and citation tools are implemented inline — no subprocess calls.
Citation tools delegate to tools._citation for API interactions.
"""

import io
import os
import re
import statistics
import sys
from pathlib import Path

from tools._paths import scripts_dir as _scripts_dir


# ── check_language (inlined from scripts/check_language.py) ──────────────


def _is_markdown(filepath: str) -> bool:
    """Detect if a file is Markdown based on extension."""
    return Path(filepath).suffix.lower() in ('.md', '.markdown', '.mdown', '.mkd')


def strip_latex_commands(text: str) -> str:
    """Remove LaTeX commands but keep text content."""
    # Remove comments
    text = re.sub(r'%.*$', '', text, flags=re.MULTILINE)
    # Remove \begin{...} and \end{...}
    text = re.sub(r'\\(begin|end)\{[^}]*\}', '', text)
    # Remove figure/table environments entirely (they're not prose)
    text = re.sub(r'\\begin\{(figure|table|equation|align|tabular|longtable)\*?\}.*?\\end\{\1\*?\}',
                  '', text, flags=re.DOTALL)
    # Keep \cite{} markers for citation counting
    # Remove other commands but keep their text arguments
    text = re.sub(r'\\(?!cite)[a-zA-Z]+\*?(?:\[[^\]]*\])*\{([^}]*)\}', r'\1', text)
    # Remove remaining bare commands
    text = re.sub(r'\\[a-zA-Z]+\*?', '', text)
    # Remove braces
    text = re.sub(r'[{}]', '', text)
    # Clean up whitespace
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def extract_body(latex_content: str) -> str:
    """Extract content between \\begin{document} and \\end{document}."""
    match = re.search(r'\\begin\{document\}(.*?)\\end\{document\}', latex_content, re.DOTALL)
    if match:
        return match.group(1)
    return latex_content


def split_sections(body: str) -> list:
    """Split LaTeX body into sections, returning (section_name, content) pairs."""
    pattern = r'\\(?:section|subsection|subsubsection)\{([^}]*)\}'
    parts = re.split(pattern, body)
    sections = []
    if parts[0].strip():
        sections.append(("Preamble", parts[0]))
    for i in range(1, len(parts), 2):
        name = parts[i] if i < len(parts) else "Unknown"
        content = parts[i + 1] if i + 1 < len(parts) else ""
        sections.append((name, content))
    return sections


def strip_markdown_formatting(text: str) -> str:
    """Remove markdown formatting but keep text content."""
    # Remove fenced code blocks
    text = re.sub(r'```.*?```', '', text, flags=re.DOTALL)
    # Remove inline code
    text = re.sub(r'`[^`]+`', '', text)
    # Remove images (before links, since images start with !)
    text = re.sub(r'!\[([^\]]*)\]\([^)]*\)', r'\1', text)
    # Remove links but keep text (won't match [@cite] since no (...) follows)
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)
    # Remove header markers
    text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
    # Remove bold/italic markers
    text = re.sub(r'\*{1,3}([^*]+)\*{1,3}', r'\1', text)
    text = re.sub(r'_{1,3}([^_]+)_{1,3}', r'\1', text)
    # Remove horizontal rules
    text = re.sub(r'^[-*_]{3,}\s*$', '', text, flags=re.MULTILINE)
    # Remove HTML comments
    text = re.sub(r'<!--.*?-->', '', text, flags=re.DOTALL)
    # Clean up whitespace
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def extract_markdown_body(content: str) -> str:
    """Extract body content, stripping YAML frontmatter if present."""
    if content.startswith('---'):
        match = re.match(r'^---\s*\n.*?\n---\s*\n', content, re.DOTALL)
        if match:
            return content[match.end():]
    return content


def split_markdown_sections(body: str) -> list:
    """Split markdown body into sections by headers."""
    pattern = r'^(#{1,3})\s+(.+)$'
    parts = re.split(pattern, body, flags=re.MULTILINE)
    sections = []
    if parts[0].strip():
        sections.append(("Preamble", parts[0]))
    # Each match produces 3 items: hash-marks, header text, content after
    for i in range(1, len(parts), 3):
        name = parts[i + 1] if i + 1 < len(parts) else "Unknown"
        content = parts[i + 2] if i + 2 < len(parts) else ""
        sections.append((name, content))
    return sections


def split_paragraphs(text: str) -> list:
    """Split text into paragraphs (separated by blank lines)."""
    paras = re.split(r'\n\s*\n', text)
    return [p.strip() for p in paras if p.strip() and len(p.strip()) > 50]


def split_sentences(text: str, is_md: bool = False) -> list:
    """Split text into sentences (simple heuristic)."""
    # Remove citations for sentence splitting
    if is_md:
        clean = re.sub(r'\[(?:[^\]]*@[^\]]+)\]', '', text)
    else:
        clean = re.sub(r'\\cite\{[^}]*\}', '', text)
        clean = re.sub(r'~', ' ', clean)
    # Split on sentence-ending punctuation
    sentences = re.split(r'(?<=[.!?])\s+(?=[A-Z])', clean)
    return [s.strip() for s in sentences if len(s.strip()) > 10]


STOCK_FRAMINGS = [
    (r'[Ii]n recent years,?\s+there has been', "Stock framing: 'In recent years, there has been...'"),
    (r'[Ii]t is well known that', "Stock framing: 'It is well known that...'"),
    (r'[Tt]his represents a promising', "Stock framing: 'This represents a promising...'"),
    (r'[Ff]urther research is needed to', "Stock framing: 'Further research is needed to...'"),
    (r'plays a crucial role in', "Stock framing: 'plays a crucial role in...'"),
    (r'has attracted significant attention', "Stock framing: 'has attracted significant attention'"),
    (r'offers? a compelling alternative', "Stock framing: 'offers a compelling alternative'"),
    (r'remains? an active area of research', "Stock framing: 'remains an active area of research'"),
    (r'address(?:es|ing)? critical limitations?', "Stock framing: 'addresses critical limitations'"),
    (r'paving the way for', "Stock framing: 'paving the way for...'"),
    (r'[Tt]here (?:has been|is) (?:a )?growing interest', "Stock framing: 'There is growing interest...'"),
    (r'[Rr]ecent advances have (?:made|shown|demonstrated)', "Stock framing: 'Recent advances have...'"),
    (r'has (?:gained|received) (?:considerable|significant|increasing) attention',
     "Stock framing: 'has gained considerable attention'"),
    (r'represents? a paradigm shift', "Stock framing: 'represents a paradigm shift'"),
    (r'[Ii]t is (?:worth noting|important to note) that', "Stock framing: 'It is worth noting that...'"),
    (r'has (?:emerged|become) as a (?:key|critical|vital|important)', "Stock framing: 'has emerged as a key...'"),
]

BALANCED_CLAUSE_PATTERNS = [
    r'[Ww]hile\s+[^,]{10,},\s+[^.]{10,}\.',
    r'[Aa]lthough\s+[^,]{10,},\s+[^.]{10,}\.',
    r'[Oo]n (?:the )?one hand[^.]*[Oo]n the other hand',
]


def check_citation_density(paragraphs: list, section_name: str, is_md: bool = False) -> list:
    """Check that paragraphs containing factual claims have inline citations."""
    issues = []
    for i, para in enumerate(paragraphs):
        # Skip very short paragraphs and non-prose content
        if len(para) < 100:
            continue

        if is_md:
            # Skip markdown lists and tables
            if para.count('\n- ') > 2 or para.count('|') > 3:
                continue
            cite_count = len(re.findall(r'\[(?:[^\]]*@[^\]]+)\]', para))
        else:
            # Skip LaTeX lists and tables
            if para.count('\\item') > 2 or para.count('&') > 3:
                continue
            cite_count = len(re.findall(r'\\cite\{[^}]*\}', para))

        if cite_count == 0:
            strip_fn = strip_markdown_formatting if is_md else strip_latex_commands
            sentences = split_sentences(strip_fn(para), is_md=is_md)
            if len(sentences) >= 2:
                issues.append({
                    "type": "error",
                    "check": "citation_density",
                    "section": section_name,
                    "paragraph": i + 1,
                    "message": f"Paragraph {i+1} in '{section_name}' has {len(sentences)} sentences but zero citations",
                    "preview": para[:120].replace('\n', ' ') + "...",
                })
    return issues


def check_sentence_length_variance(paragraphs: list, section_name: str, is_md: bool = False) -> list:
    """Check that sentence lengths within paragraphs vary enough."""
    issues = []
    strip_fn = strip_markdown_formatting if is_md else strip_latex_commands
    for i, para in enumerate(paragraphs):
        clean_para = strip_fn(para)
        sentences = split_sentences(clean_para, is_md=is_md)
        if len(sentences) < 3:
            continue

        word_counts = [len(s.split()) for s in sentences]
        try:
            stdev = statistics.stdev(word_counts)
            mean = statistics.mean(word_counts)
        except statistics.StatisticsError:
            continue

        # Threshold: stdev should be at least 30% of mean for natural variation
        if mean > 0 and stdev / mean < 0.25:
            issues.append({
                "type": "warning",
                "check": "sentence_variance",
                "section": section_name,
                "paragraph": i + 1,
                "message": f"Low sentence length variance in '{section_name}' paragraph {i+1}: "
                           f"mean={mean:.1f} words, stdev={stdev:.1f} (ratio={stdev/mean:.2f}, want >=0.25)",
                "lengths": word_counts,
            })
    return issues


def check_stock_framings(text: str, section_name: str) -> list:
    """Check for known LLM stock framing patterns."""
    issues = []
    for pattern, description in STOCK_FRAMINGS:
        matches = list(re.finditer(pattern, text))
        for match in matches:
            # Find approximate line number
            line_num = text[:match.start()].count('\n') + 1
            issues.append({
                "type": "warning",
                "check": "stock_framing",
                "section": section_name,
                "line": line_num,
                "message": f"{description} (line ~{line_num} in '{section_name}')",
                "match": match.group(0),
            })
    return issues


def check_balanced_clauses(text: str, section_name: str) -> list:
    """Check for excessive While X, Y / Although X, Y balanced clauses."""
    issues = []
    total_matches = 0
    for pattern in BALANCED_CLAUSE_PATTERNS:
        matches = re.findall(pattern, text)
        total_matches += len(matches)

    if total_matches > 2:
        issues.append({
            "type": "warning",
            "check": "balanced_clauses",
            "section": section_name,
            "message": f"Section '{section_name}' has {total_matches} balanced 'While/Although X, Y' clauses "
                       f"(max 2 recommended)",
        })
    return issues


def check_citation_free_generalizations(text: str, section_name: str, is_md: bool = False) -> list:
    """Check for generalizations that should have citations."""
    patterns = [
        (r'[Ii]t is (?:well )?known that [^.]*\.', "Citation-free generalization: 'It is known that...'"),
        (r'[Ss]tudies have shown that [^.]*\.', "Citation-free generalization: 'Studies have shown...'"),
        (r'[Rr]esearch(?:ers)? ha(?:s|ve) demonstrated [^.]*\.',
         "Citation-free generalization: 'Research has demonstrated...'"),
        (r'[Ss]everal (?:studies|papers|works|authors) [^.]*\.',
         "Citation-free generalization: 'Several studies...'"),
        (r'[Aa]s (?:many|several|numerous) (?:studies|researchers) have (?:shown|noted|observed)',
         "Citation-free generalization: 'As many studies have shown...'"),
    ]

    cite_token = '@' if is_md else '\\cite'

    issues = []
    for pattern, description in patterns:
        for match in re.finditer(pattern, text):
            # Check if there's a citation nearby (within 20 chars after the match)
            end_pos = match.end()
            nearby = text[max(0, match.start() - 10):min(len(text), end_pos + 30)]
            if cite_token not in nearby:
                line_num = text[:match.start()].count('\n') + 1
                issues.append({
                    "type": "error",
                    "check": "citation_free_generalization",
                    "section": section_name,
                    "line": line_num,
                    "message": f"{description} without citation (line ~{line_num} in '{section_name}')",
                    "match": match.group(0)[:80],
                })
    return issues


def check_file(filepath: str, strict: bool = False, verbose: bool = False) -> bool:
    """Run all checks on a LaTeX or Markdown file. Returns True if pass."""
    path = Path(filepath)
    if not path.exists():
        print(f"Error: {filepath} not found", file=sys.stderr)
        return False

    content = path.read_text(encoding="utf-8")
    is_md = _is_markdown(filepath)

    if is_md:
        body = extract_markdown_body(content)
        sections = split_markdown_sections(body)
    else:
        body = extract_body(content)
        sections = split_sections(body)

    all_issues = []

    for section_name, section_content in sections:
        paragraphs = split_paragraphs(section_content)

        all_issues.extend(check_citation_density(paragraphs, section_name, is_md=is_md))
        all_issues.extend(check_sentence_length_variance(paragraphs, section_name, is_md=is_md))
        all_issues.extend(check_stock_framings(section_content, section_name))
        all_issues.extend(check_balanced_clauses(section_content, section_name))
        all_issues.extend(check_citation_free_generalizations(section_content, section_name, is_md=is_md))

    errors = [i for i in all_issues if i["type"] == "error"]
    warnings = [i for i in all_issues if i["type"] == "warning"]

    # Print results
    if errors:
        print(f"\n{'='*60}")
        print(f"ERRORS ({len(errors)}):")
        print(f"{'='*60}")
        for issue in errors:
            print(f"  [{issue['check']}] {issue['message']}")
            if 'preview' in issue:
                print(f"    Preview: {issue['preview']}")
            if 'match' in issue:
                print(f"    Match: \"{issue['match']}\"")

    if warnings:
        print(f"\n{'='*60}")
        print(f"WARNINGS ({len(warnings)}):")
        print(f"{'='*60}")
        for issue in warnings:
            print(f"  [{issue['check']}] {issue['message']}")
            if 'lengths' in issue:
                print(f"    Sentence lengths: {issue['lengths']}")
            if 'match' in issue:
                print(f"    Match: \"{issue['match']}\"")

    if not errors and not warnings:
        print(f"\nAll checks passed for {filepath}")

    # Summary
    print(f"\n{'='*60}")
    print(f"Summary: {len(errors)} errors, {len(warnings)} warnings")
    print(f"{'='*60}")

    if errors:
        print("FAIL: Fix errors before committing.")
        return False
    elif warnings and strict:
        print("FAIL (strict mode): Fix warnings before committing.")
        return False
    elif warnings:
        print("PASS with warnings. Consider fixing before committing.")
        return True
    else:
        print("PASS")
        return True


# ── check_journal (inlined from scripts/check_journal.py) ────────────────

_JOURNAL_DEFAULTS = {
    "word_limit": 6000,
    "page_limit": 10,
    "words_per_page": 250,  # single-column default
    "required_bib_fields": ["author", "title", "year"],
}


def _journal_parse_pub_reqs(path: str) -> dict:
    """Parse specs/publication-requirements.md for compliance thresholds."""
    reqs = dict(_JOURNAL_DEFAULTS)
    reqs["required_bib_fields"] = list(_JOURNAL_DEFAULTS["required_bib_fields"])
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


# ── Handler: check_language ──────────────────────────────────────────────


def _handle_check_language(inp):
    """Run language checks directly (no subprocess)."""
    buf = io.StringIO()
    old_stdout = sys.stdout
    old_stderr = sys.stderr
    sys.stdout = buf
    sys.stderr = buf
    try:
        check_file(inp["file_path"], strict=inp.get("strict", False))
    finally:
        sys.stdout = old_stdout
        sys.stderr = old_stderr
    output = buf.getvalue()
    return output if output.strip() else "(no output)"


# ── Handler: check_journal ────────────────────────────────────────────────


def _handle_check_journal(inp):
    """Run journal compliance checks directly (no subprocess)."""
    # Build requirements
    reqs = dict(_JOURNAL_DEFAULTS)
    reqs["required_bib_fields"] = list(_JOURNAL_DEFAULTS["required_bib_fields"])
    if inp.get("pub_reqs") and Path(inp["pub_reqs"]).exists():
        reqs = _journal_parse_pub_reqs(inp["pub_reqs"])

    tex_files = collect_tex_files([inp["sections_dir"]])
    if not tex_files:
        return "No .tex files found."

    # Word counts
    section_counts = []
    total_words = 0
    for f in tex_files:
        wc, name = count_words_tex(f)
        section_counts.append({"file": str(f), "section": name, "word_count": wc})
        total_words += wc

    page_estimate = round(total_words / reqs["words_per_page"], 1)

    # Bib checks
    bib_files = collect_bib_files([inp["sections_dir"]])
    bib_issues = []
    for bf in bib_files:
        bib_issues.extend(check_bib_fields(bf, reqs["required_bib_fields"]))

    # Determine pass/fail
    issues = []
    if total_words > reqs["word_limit"]:
        issues.append(f"Total word count {total_words} exceeds limit of {reqs['word_limit']} "
                      f"(over by {total_words - reqs['word_limit']})")
    if page_estimate > reqs["page_limit"]:
        issues.append(f"Estimated {page_estimate} pages exceeds limit of {reqs['page_limit']}")
    if bib_issues:
        issues.append(f"{len(bib_issues)} bibliography entries missing required fields")

    all_pass = len(issues) == 0

    # Build text report
    lines = []
    lines.append(f"\n{'='*50}")
    lines.append("Journal Compliance Check")
    lines.append(f"{'='*50}")
    lines.append(f"\nWord Counts by Section:")
    for sc in section_counts:
        lines.append(f"  {sc['section']}: {sc['word_count']} words")

    total_line = f"\n  Total: {total_words} / {reqs['word_limit']} words"
    if total_words > reqs["word_limit"]:
        total_line += f"  [OVER by {total_words - reqs['word_limit']}]"
    else:
        total_line += f"  [OK — {reqs['word_limit'] - total_words} remaining]"
    lines.append(total_line)

    page_line = (f"\nPage Estimate: {page_estimate} / {reqs['page_limit']} pages "
                 f"({reqs['words_per_page']} words/page)")
    if page_estimate > reqs["page_limit"]:
        page_line += "  [OVER]"
    else:
        page_line += "  [OK]"
    lines.append(page_line)

    if bib_issues:
        lines.append(f"\nBibliography Issues:")
        for bi in bib_issues:
            lines.append(f"  {bi['cite_key']} ({bi['file']}): missing {', '.join(bi['missing_fields'])}")
    elif bib_files:
        lines.append(f"\nBibliography: {len(bib_files)} file(s) checked, all entries OK")
    else:
        lines.append(f"\nBibliography: No .bib files found")

    lines.append(f"\n{'='*50}")
    lines.append("PASS" if all_pass else "FAIL")

    return "\n".join(lines)


# ── check_figure (inlined from scripts/check_figure.py) ──────────────────

_FIGURE_DEFAULTS = {
    "min_dpi": 300,
    "max_width_px": 2400,
    "max_height_px": 3600,
    "max_file_size_mb": 10,
}


def _figure_parse_pub_reqs(path: str) -> dict:
    """Parse specs/publication-requirements.md for figure thresholds."""
    reqs = dict(_FIGURE_DEFAULTS)
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
    """Check a raster image (PNG, TIFF, JPEG). PIL imported lazily."""
    from PIL import Image  # lazy import

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


def check_pdf_figure(filepath: Path, reqs: dict) -> dict:
    """Check a PDF figure (vector format). fitz imported lazily."""
    try:
        import fitz  # lazy import — PyMuPDF
    except ImportError:
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


def collect_figure_files(paths: list) -> list:
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


# ── Handler: check_figure ────────────────────────────────────────────────


def _handle_check_figure(inp):
    """Run figure compliance checks directly (no subprocess)."""
    import json as _json

    # Build requirements
    reqs = dict(_FIGURE_DEFAULTS)
    if inp.get("pub_reqs") and Path(inp["pub_reqs"]).exists():
        reqs = _figure_parse_pub_reqs(inp["pub_reqs"])

    figures = collect_figure_files([inp["figures_dir"]])
    if not figures:
        return "No figure files found."

    results = []
    for fig in figures:
        if fig.suffix.lower() == ".pdf":
            results.append(check_pdf_figure(fig, reqs))
        else:
            results.append(check_raster(fig, reqs))

    all_pass = all(r["pass"] for r in results)
    return _json.dumps({"results": results, "pass": all_pass}, indent=2)


# ── Handlers: citation tools (via tools._citation) ──────────────────────


def _handle_citation_lint(inp):
    """Run citation lint directly (no subprocess)."""
    import json as _json
    from tools._citation import lint_bib_files

    report_path = os.path.join(inp["bib_dir"], "citation_verification_report.md")
    lint_bib_files(inp["bib_dir"], report_path)

    # Return summary only (counts + flagged entries), not the full report
    summary_lines = []
    counts = {"VERIFIED": 0, "LIKELY": 0, "SUSPICIOUS": 0, "UNVERIFIED": 0}
    flagged = []
    try:
        with open(report_path) as f:
            for line in f:
                line_s = line.strip()
                for status in counts:
                    if status in line_s:
                        counts[status] += line_s.count(status)
                if "SUSPICIOUS" in line_s or "UNVERIFIED" in line_s:
                    flagged.append(line_s)
    except FileNotFoundError:
        return "(citation_lint produced no report file)"

    summary_lines.append("Citation lint summary:")
    for status, count in counts.items():
        summary_lines.append(f"  {status}: {count}")
    if flagged:
        summary_lines.append("")
        summary_lines.append("Flagged entries:")
        for entry in flagged[:20]:  # cap at 20 to avoid bloating context
            summary_lines.append(f"  {entry}")
        if len(flagged) > 20:
            summary_lines.append(f"  ... and {len(flagged) - 20} more")
    summary_lines.append(f"\nFull report: {report_path}")
    return "\n".join(summary_lines)


def _handle_citation_lookup(inp):
    """Look up papers directly (no subprocess)."""
    import json as _json
    from tools._citation import lookup_paper

    if inp.get("input_file"):
        # Batch mode: read titles, look up each, write JSONL
        output_file = inp.get("output_file", "corpus/batch_results.jsonl")
        Path(output_file).parent.mkdir(parents=True, exist_ok=True)
        titles = Path(inp["input_file"]).read_text(encoding="utf-8").strip().splitlines()
        found = 0
        with open(output_file, "w", encoding="utf-8") as out:
            for title in titles:
                title = title.strip()
                if not title:
                    continue
                result = lookup_paper(title)
                if result:
                    found += 1
                    out.write(_json.dumps(result) + "\n")
        return f"Batch lookup: {found}/{len(titles)} titles found. Results: {output_file}"

    # Single lookup
    result = lookup_paper(inp["title"], inp.get("authors", ""))
    if result:
        return _json.dumps(result, indent=2)
    return "(no results found)"


def _handle_citation_verify(inp):
    """Verify a DOI directly (no subprocess)."""
    import json as _json
    from tools._citation import verify_doi

    result = verify_doi(inp["doi"])
    if result:
        return _json.dumps(result, indent=2)
    return f"(DOI {inp['doi']} could not be verified)"


def _handle_citation_verify_all(inp):
    """Batch-verify .bib file directly (no subprocess)."""
    from tools._citation import batch_verify_bib

    data = batch_verify_bib(inp["bib_file"])

    if "error" in data:
        return f"Error: {data['error']}"

    lines = ["## citation_verify_all report", ""]
    lines.append(f"Total entries: {data.get('total', '?')}")
    lines.append(f"DOI verified: {data.get('verified', '?')}")
    lines.append(f"DOI failed: {data.get('failed', '?')}")
    lines.append(f"No DOI: {data.get('no_doi', '?')}")
    lines.append("")

    n_issues = data.get("failed", 0) + data.get("no_doi", 0) + len(data.get("warnings", []))
    if n_issues == 0:
        lines.append("**PASS** — all DOIs verified successfully.")
        return "\n".join(lines)

    lines.append(f"**{n_issues} issue(s) found:**")
    lines.append("")

    failed = data.get("failed_entries", [])
    if failed:
        lines.append(f"### Failed DOI verification ({len(failed)})")
        for e in failed[:20]:
            lines.append(f"- [{e.get('key', '?')}] doi:{e.get('doi', '?')} — {e.get('title', '?')[:100]}")
        if len(failed) > 20:
            lines.append(f"  ... and {len(failed) - 20} more")
        lines.append("")

    no_doi = data.get("no_doi_entries", [])
    if no_doi:
        lines.append(f"### Entries without DOI ({len(no_doi)})")
        for e in no_doi[:20]:
            lines.append(f"- [{e.get('key', '?')}] {e.get('title', '?')[:100]}")
        if len(no_doi) > 20:
            lines.append(f"  ... and {len(no_doi) - 20} more")
        lines.append("")

    warnings = data.get("warnings", [])
    if warnings:
        lines.append(f"### DOI/title mismatches ({len(warnings)})")
        for e in warnings[:20]:
            lines.append(f"- [{e.get('key', '?')}] doi:{e.get('doi', '?')} — {e.get('warning', '?')}")
        if len(warnings) > 20:
            lines.append(f"  ... and {len(warnings) - 20} more")
        lines.append("")

    return "\n".join(lines)


def _handle_citation_manifest(inp):
    """Check or update paper manifest directly (no subprocess)."""
    import json as _json
    from tools._citation import manifest_add, manifest_check

    if inp.get("file"):
        # Add mode
        result = manifest_add(
            doi=inp.get("doi", ""),
            file=inp["file"],
            scout=inp.get("scout", ""),
            title=inp.get("title", ""),
            papers_dir=inp.get("papers_dir", "papers/"),
            ntrs_id=inp.get("ntrs_id"),
        )
        return _json.dumps(result, indent=2)

    # Check mode
    result = manifest_check(
        doi=inp.get("doi", ""),
        papers_dir=inp.get("papers_dir", "papers/"),
        title=inp.get("title", ""),
    )
    return _json.dumps(result, indent=2)


# ── Tool definitions ─────────────────────────────────────────────────────

TOOLS = {
    "check_language": {
        "name": "check_language",
        "description": (
            "Check a LaTeX or Markdown file for citation density, sentence length variance, "
            "stock framings, balanced clauses, and citation-free generalizations. "
            "Returns PASS/FAIL with specific violations."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Path to the LaTeX or Markdown file to check"},
                "strict": {"type": "boolean", "description": "Fail on warnings too (default false)"},
            },
            "required": ["file_path"],
        },
        "function": _handle_check_language,
    },
    "check_journal": {
        "name": "check_journal",
        "description": (
            "Check manuscript sections against publication requirements: "
            "word count per section, total word count vs limit, page estimate, "
            "required .bib fields. Returns PASS/FAIL with details."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "sections_dir": {"type": "string", "description": "Path to sections directory (e.g. 'sections/')"},
                "pub_reqs": {"type": "string", "description": "Path to publication-requirements.md (optional)"},
            },
            "required": ["sections_dir"],
        },
        "function": _handle_check_journal,
    },
    "check_figure": {
        "name": "check_figure",
        "description": (
            "Check figure files for publication readiness: DPI, pixel dimensions, "
            "color mode, file size, format. Returns PASS/FAIL per figure."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "figures_dir": {"type": "string", "description": "Path to figures directory (e.g. 'figures/')"},
                "pub_reqs": {"type": "string", "description": "Path to publication-requirements.md (optional)"},
            },
            "required": ["figures_dir"],
        },
        "function": _handle_check_figure,
    },
    "citation_lint": {
        "name": "citation_lint",
        "description": (
            "Lint .bib files against Semantic Scholar/CrossRef/OpenAlex to verify "
            "citation metadata. Returns verification report with unverified entries."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "bib_dir": {"type": "string", "description": "Path to bib directory (e.g. 'references/')"},
            },
            "required": ["bib_dir"],
        },
        "function": _handle_citation_lint,
    },
    "citation_lookup": {
        "name": "citation_lookup",
        "description": (
            "Look up papers by title via Semantic Scholar/CrossRef/OpenAlex. "
            "Single mode: provide title (and optional authors) to find one paper. "
            "Batch mode: provide input_file (one title per line) to look up many papers at once."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "Paper title to look up (single mode)"},
                "authors": {"type": "string", "description": "Author names, comma-separated (optional, improves matching)"},
                "input_file": {"type": "string", "description": "Path to file with one title per line (batch mode)"},
                "output_file": {"type": "string", "description": "Output JSONL path for batch results (default: corpus/batch_results.jsonl)"},
            },
            "required": [],
        },
        "function": _handle_citation_lookup,
    },
    "citation_verify": {
        "name": "citation_verify",
        "description": (
            "Verify a DOI against Semantic Scholar/CrossRef/OpenAlex. "
            "Returns verified metadata (title, authors, year, venue) with match confidence."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "doi": {"type": "string", "description": "DOI to verify (e.g. '10.1016/j.jcp.2024.01.001')"},
            },
            "required": ["doi"],
        },
        "function": _handle_citation_verify,
    },
    "citation_verify_all": {
        "name": "citation_verify_all",
        "description": (
            "Batch-verify every entry in a .bib file by resolving DOIs via CrossRef. "
            "Reports: verified DOIs, failed DOIs, entries without DOI, and DOI/title mismatches. "
            "Use this after bibliography updates to ensure all citations resolve."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "bib_file": {"type": "string", "description": "Path to the .bib file to verify"},
            },
            "required": ["bib_file"],
        },
        "function": _handle_citation_verify_all,
    },
    "citation_manifest": {
        "name": "citation_manifest",
        "description": (
            "Check or update the paper download manifest. "
            "Check mode (no 'file'): see if a paper is already downloaded by DOI or title. "
            "Add mode (with 'file'): register a newly downloaded PDF in the manifest."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "doi": {"type": "string", "description": "DOI of the paper"},
                "title": {"type": "string", "description": "Paper title (for fuzzy matching in check mode)"},
                "file": {"type": "string", "description": "PDF filename to add (triggers add mode, e.g. 'Author2024_Title.pdf')"},
                "scout": {"type": "string", "description": "Which agent downloaded it (add mode)"},
                "papers_dir": {"type": "string", "description": "Papers directory (default: 'papers/')"},
                "ntrs_id": {"type": "string", "description": "NTRS ID if applicable (add mode)"},
            },
            "required": [],
        },
        "function": _handle_citation_manifest,
    },
}
