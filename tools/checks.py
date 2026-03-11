"""Check tools: check_language, check_journal, check_figure, citation_lint.

Wrappers around scripts/ that enforce writing quality and publication readiness.
"""

import subprocess


def _run_cmd(cmd):
    """Run a subprocess, return combined stdout+stderr."""
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout + result.stderr
    return output if output.strip() else f"(exit code {result.returncode}, no output)"


def _handle_check_language(inp):
    cmd = ["python3", "scripts/check_language.py"]
    if inp.get("strict"):
        cmd.append("--strict")
    cmd.append(inp["file_path"])
    return _run_cmd(cmd)


def _handle_check_journal(inp):
    cmd = ["python3", "scripts/check_journal.py"]
    if inp.get("pub_reqs"):
        cmd.extend(["--pub-reqs", inp["pub_reqs"]])
    cmd.append(inp["sections_dir"])
    return _run_cmd(cmd)


def _handle_check_figure(inp):
    cmd = ["python3", "scripts/check_figure.py", "--json"]
    if inp.get("pub_reqs"):
        cmd.extend(["--pub-reqs", inp["pub_reqs"]])
    cmd.append(inp["figures_dir"])
    return _run_cmd(cmd)


def _handle_citation_lint(inp):
    cmd = ["python3", "scripts/citation_tools.py", "lint",
           "--bib-dir", inp["bib_dir"],
           "--output", "/dev/stdout"]
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
}
