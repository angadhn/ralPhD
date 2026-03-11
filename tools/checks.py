"""Check tools: check_language, check_journal, check_figure, citation_lint,
citation_lookup, citation_verify, citation_verify_all, citation_manifest.

Wrappers around scripts/ that enforce writing quality and publication readiness.
"""

import os
import subprocess

from tools._paths import scripts_dir as _scripts_dir


def _run_cmd(cmd):
    """Run a subprocess, return combined stdout+stderr."""
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout + result.stderr
    return output if output.strip() else f"(exit code {result.returncode}, no output)"


def _handle_check_language(inp):
    cmd = ["python3", str(_scripts_dir() / "check_language.py")]
    if inp.get("strict"):
        cmd.append("--strict")
    cmd.append(inp["file_path"])
    return _run_cmd(cmd)


def _handle_check_journal(inp):
    cmd = ["python3", str(_scripts_dir() / "check_journal.py")]
    if inp.get("pub_reqs"):
        cmd.extend(["--pub-reqs", inp["pub_reqs"]])
    cmd.append(inp["sections_dir"])
    return _run_cmd(cmd)


def _handle_check_figure(inp):
    cmd = ["python3", str(_scripts_dir() / "check_figure.py"), "--json"]
    if inp.get("pub_reqs"):
        cmd.extend(["--pub-reqs", inp["pub_reqs"]])
    cmd.append(inp["figures_dir"])
    return _run_cmd(cmd)


def _handle_citation_lint(inp):
    report_path = os.path.join(inp["bib_dir"], "citation_verification_report.md")
    cmd = ["python3", str(_scripts_dir() / "citation_tools.py"), "lint",
           "--bib-dir", inp["bib_dir"],
           "--output", report_path]
    _run_cmd(cmd)

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
    if inp.get("input_file"):
        # Batch mode
        cmd = ["python3", str(_scripts_dir() / "citation_tools.py"), "batch-lookup",
               "--input", inp["input_file"],
               "--output", inp.get("output_file", "corpus/batch_results.jsonl")]
        return _run_cmd(cmd)
    # Single lookup
    cmd = ["python3", str(_scripts_dir() / "citation_tools.py"), "lookup",
           "--title", inp["title"]]
    if inp.get("authors"):
        cmd.extend(["--authors", inp["authors"]])
    return _run_cmd(cmd)


def _handle_citation_verify(inp):
    cmd = ["python3", str(_scripts_dir() / "citation_tools.py"), "verify",
           "--doi", inp["doi"]]
    return _run_cmd(cmd)


def _handle_citation_verify_all(inp):
    cmd = ["python3", str(_scripts_dir() / "citation_tools.py"), "batch-verify",
           "--bib-file", inp["bib_file"]]
    raw = _run_cmd(cmd)

    # Parse JSON output for a compact summary
    import json as _json
    try:
        data = _json.loads(raw)
    except (ValueError, _json.JSONDecodeError):
        return raw  # fallback: return raw output

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
    if inp.get("file"):
        # Add mode
        cmd = ["python3", str(_scripts_dir() / "citation_tools.py"), "manifest-add",
               "--file", inp["file"]]
        if inp.get("doi"):
            cmd.extend(["--doi", inp["doi"]])
        if inp.get("scout"):
            cmd.extend(["--scout", inp["scout"]])
        if inp.get("title"):
            cmd.extend(["--title", inp["title"]])
        if inp.get("papers_dir"):
            cmd.extend(["--papers-dir", inp["papers_dir"]])
        if inp.get("ntrs_id"):
            cmd.extend(["--ntrs-id", inp["ntrs_id"]])
        return _run_cmd(cmd)
    # Check mode
    cmd = ["python3", str(_scripts_dir() / "citation_tools.py"), "manifest-check"]
    if inp.get("doi"):
        cmd.extend(["--doi", inp["doi"]])
    if inp.get("title"):
        cmd.extend(["--title", inp["title"]])
    if inp.get("papers_dir"):
        cmd.extend(["--papers-dir", inp["papers_dir"]])
    return _run_cmd(cmd)


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
