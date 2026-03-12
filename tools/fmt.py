"""ANSI formatting for ralph_agent.py headless output.

Pure formatting utility — no TOOLS dict, so it won't affect the tool registry.
Respects NO_COLOR env var and non-TTY stderr.
"""

import os
import sys

_COLOR = (
    hasattr(sys.stderr, "isatty")
    and sys.stderr.isatty()
    and os.environ.get("NO_COLOR") is None
)

# ANSI codes
_RESET = "\033[0m" if _COLOR else ""
_BOLD = "\033[1m" if _COLOR else ""
_DIM = "\033[2m" if _COLOR else ""
_RED = "\033[31m" if _COLOR else ""
_GREEN = "\033[32m" if _COLOR else ""
_YELLOW = "\033[33m" if _COLOR else ""
_BLUE = "\033[34m" if _COLOR else ""
_MAGENTA = "\033[35m" if _COLOR else ""
_CYAN = "\033[36m" if _COLOR else ""

# Tool → color mapping by category
_TOOL_COLORS = {
    # Mutations (green)
    "write_file": _GREEN,
    "git_commit": _GREEN,
    # Read/inspect (cyan)
    "read_file": _CYAN,
    "list_files": _CYAN,
    "code_search": _CYAN,
    "pdf_metadata": _CYAN,
    "view_pdf_page": _CYAN,
    "extract_figure": _CYAN,
    # Shell (yellow)
    "bash": _YELLOW,
    # Verification (magenta)
    "check_language": _MAGENTA,
    "check_journal": _MAGENTA,
    "check_figure": _MAGENTA,
    "check_claims": _MAGENTA,
    "citation_lint": _MAGENTA,
    "citation_verify": _MAGENTA,
    "citation_verify_all": _MAGENTA,
    "citation_lookup": _MAGENTA,
    "citation_manifest": _MAGENTA,
    # Network/external (blue)
    "search_papers": _BLUE,
    "download_paper": _BLUE,
    "citation_download": _BLUE,
    "web_search": _BLUE,
}

# Primary argument key per tool (for concise display)
_PRIMARY_KEYS = {
    "read_file": "path",
    "write_file": "path",
    "bash": "command",
    "code_search": "pattern",
    "git_commit": "message",
    "list_files": "path",
}


def _tool_color(name: str) -> str:
    return _TOOL_COLORS.get(name, _DIM)


def _extract_primary(name: str, inp: dict) -> str:
    """Extract the most informative argument for display."""
    key = _PRIMARY_KEYS.get(name)
    if key and key in inp:
        val = str(inp[key])
        if name == "bash" and len(val) > 80:
            val = val[:77] + "..."
        return val
    # Fallback: first string value
    for v in inp.values():
        if isinstance(v, str):
            return v[:80] + ("..." if len(str(v)) > 80 else "")
    return ""


def fmt_banner(agent: str, provider: str, tools: list[str], model: str) -> str:
    """Format the agent startup banner."""
    lines = [
        f"{_BOLD}Agent:{_RESET} {agent}",
        f"{_DIM}Provider:{_RESET} {provider}",
        f"{_DIM}Tools:{_RESET} {', '.join(tools)}",
        f"{_DIM}Model:{_RESET} {model}",
        "",
    ]
    return "\n".join(lines)


def fmt_tool_call(name: str, inp: dict) -> str:
    """Format a tool call: colored tool name + primary argument."""
    color = _tool_color(name)
    primary = _extract_primary(name, inp)
    if primary:
        return f"  {color}{name}{_RESET}  {_BOLD}{primary}{_RESET}"
    return f"  {color}{name}{_RESET}"


def fmt_tool_result(tool_name: str, preview: str) -> str:
    """Format a tool result preview."""
    if not preview:
        return f"  {_DIM}(empty result){_RESET}"

    # Detect errors
    lower = preview.lower()
    if lower.startswith("tool error:") or lower.startswith("error:"):
        return f"  {_RED}{preview}{_RESET}"

    # Detect successful writes
    if "wrote" in lower and ("chars" in lower or "bytes" in lower):
        return f"  {_GREEN}{preview}{_RESET}"

    return f"  {_DIM}{preview}{_RESET}"


def fmt_separator() -> str:
    """Dim horizontal line between model text and tool execution."""
    width = min(os.get_terminal_size(fallback=(80, 24)).columns, 80)
    return f"{_DIM}{'─' * width}{_RESET}"
