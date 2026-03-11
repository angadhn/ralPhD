"""
tools.py — Tool definitions with colocated handlers + per-agent registries.

Each tool is a single dict: name, description, input_schema, and function.
Adding a tool means adding one dict entry. The agent loop imports TOOLS,
AGENT_TOOLS, and execute_tool — nothing else.

Follows ghuntley's coding-agent pattern: tools are separate from the
orchestrator (ralph_agent.py).
"""

import os
import subprocess


# ── Subprocess helper ──────────────────────────────────────────

def _run_cmd(cmd):
    """Run a subprocess, return combined stdout+stderr."""
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout + result.stderr
    return output if output.strip() else f"(exit code {result.returncode}, no output)"


# ── Tool handlers ──────────────────────────────────────────────

def _handle_check_language(inp):
    cmd = ["python3", "scripts/check_language.py"]
    if inp.get("strict"):
        cmd.append("--strict")
    cmd.append(inp["file_path"])
    return _run_cmd(cmd)


def _handle_read_file(inp):
    try:
        with open(inp["file_path"], "r") as f:
            return f.read()
    except Exception as e:
        return f"Error reading file: {e}"


def _handle_write_file(inp):
    try:
        os.makedirs(os.path.dirname(inp["file_path"]) or ".", exist_ok=True)
        with open(inp["file_path"], "w") as f:
            f.write(inp["content"])
        return f"Wrote {len(inp['content'])} chars to {inp['file_path']}"
    except Exception as e:
        return f"Error writing file: {e}"


def _handle_bash(inp):
    result = subprocess.run(
        ["bash", "-c", inp["command"]],
        capture_output=True, text=True, timeout=120,
    )
    output = result.stdout + result.stderr
    if result.returncode != 0:
        return f"(exit code {result.returncode})\n{output}"
    return output if output.strip() else "(no output)"


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


def _handle_pdf_metadata(inp):
    cmd = ["python3", "scripts/pdf_metadata.py", "--json", inp["pdf_path"]]
    return _run_cmd(cmd)


def _handle_extract_figure(inp):
    if inp.get("list_only"):
        cmd = ["python3", "scripts/extract_figure.py", "--list", inp["pdf_path"]]
    elif inp.get("render_page"):
        cmd = ["python3", "scripts/extract_figure.py", inp["pdf_path"],
               "--render-page", str(inp["render_page"]),
               "--output", inp.get("output_dir", "figures/")]
        if inp.get("dpi"):
            cmd.extend(["--dpi", str(inp["dpi"])])
    else:
        cmd = ["python3", "scripts/extract_figure.py", inp["pdf_path"],
               "--output", inp.get("output_dir", "figures/")]
        if inp.get("pages"):
            cmd.extend(["--pages", inp["pages"]])
    return _run_cmd(cmd)


# ── Tool definitions (schema + handler colocated) ──────────────

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
    "read_file": {
        "name": "read_file",
        "description": "Read the contents of a file. Use this to inspect any file.",
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Path to the file to read"},
            },
            "required": ["file_path"],
        },
        "function": _handle_read_file,
    },
    "write_file": {
        "name": "write_file",
        "description": "Write content to a file. Creates the file if it doesn't exist, overwrites if it does.",
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Path to the file to write"},
                "content": {"type": "string", "description": "Content to write"},
            },
            "required": ["file_path", "content"],
        },
        "function": _handle_write_file,
    },
    "bash": {
        "name": "bash",
        "description": "Execute a bash command and return its output. Use for git, pdflatex, and other shell operations.",
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "The bash command to execute"},
            },
            "required": ["command"],
        },
        "function": _handle_bash,
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

# ── Per-agent tool registries ──────────────────────────────────

AGENT_TOOLS = {
    "paper-writer": ["read_file", "write_file", "bash", "check_language", "citation_lint"],
    "critic": ["read_file", "write_file", "bash", "check_language", "check_journal", "check_figure"],
    "scout": ["read_file", "write_file", "bash", "pdf_metadata"],
    "deep-reader": ["read_file", "write_file", "bash", "pdf_metadata", "extract_figure"],
    "research-coder": ["read_file", "write_file", "bash"],
    "figure-stylist": ["read_file", "write_file", "bash", "check_figure"],
}

DEFAULT_TOOLS = ["read_file", "write_file", "bash"]


# ── Dispatch ───────────────────────────────────────────────────

def api_schema(tool: dict) -> dict:
    """Strip function from tool def for the API payload."""
    return {k: v for k, v in tool.items() if k != "function"}


def execute_tool(name: str, tool_input: dict) -> str:
    """Dispatch a tool call to its colocated handler."""
    tool = TOOLS.get(name)
    if not tool:
        return f"Unknown tool: {name}"
    return tool["function"](tool_input)
