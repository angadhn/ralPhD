"""Rich formatting for ralph_agent.py headless output.

Pure formatting utility — no TOOLS dict, so it won't affect the tool registry.
Auto-handles NO_COLOR env var and non-TTY stderr via Rich's Console.
"""

import os
import sys

from rich.console import Console
from rich.panel import Panel
from rich.syntax import Syntax
from rich.text import Text
from rich import box

# Rich auto-respects NO_COLOR and non-TTY
_stderr = Console(file=sys.stderr)

# Tool → color mapping by category
_TOOL_COLORS = {
    # Mutations (green)
    "write_file": "green",
    "git_commit": "green",
    "git_push": "green",
    # Read/inspect (cyan)
    "read_file": "cyan",
    "list_files": "cyan",
    "code_search": "cyan",
    "pdf_metadata": "cyan",
    "view_pdf_page": "cyan",
    "extract_figure": "cyan",
    # Shell (yellow)
    "bash": "yellow",
    # Verification (magenta)
    "check_language": "magenta",
    "check_journal": "magenta",
    "check_figure": "magenta",
    "check_claims": "magenta",
    "citation_lint": "magenta",
    "citation_verify": "magenta",
    "citation_verify_all": "magenta",
    "citation_lookup": "magenta",
    "citation_manifest": "magenta",
    # Network/external (blue)
    "search_papers": "blue",
    "download_paper": "blue",
    "citation_download": "blue",
    "web_search": "blue",
    "gh": "blue",
}

# Primary argument key per tool (for concise display)
_PRIMARY_KEYS = {
    "read_file": "path",
    "write_file": "path",
    "bash": "command",
    "code_search": "pattern",
    "git_commit": "message",
    "git_push": "branch",
    "list_files": "path",
    "gh": "subcommand",
}

# File extensions → Syntax lexer names
_LEXERS = {
    ".py": "python", ".md": "markdown", ".tex": "latex", ".sh": "bash",
    ".json": "json", ".yaml": "yaml", ".yml": "yaml", ".js": "javascript",
    ".ts": "typescript", ".toml": "toml", ".bib": "bibtex",
}


def _tool_color(name: str) -> str:
    return _TOOL_COLORS.get(name, "dim")


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


def fmt_banner(agent: str, provider: str, tools: list[str], model: str):
    """Print the agent startup banner as a bordered panel to stderr."""
    body = (
        f"[bold]{agent}[/bold]\n"
        f"[dim]Provider:[/dim] {provider}\n"
        f"[dim]Model:[/dim] {model}\n"
        f"[dim]Tools:[/dim] {', '.join(tools)}"
    )
    _stderr.print(Panel(
        body,
        title="[bold blue]ralph[/bold blue]",
        border_style="blue",
        box=box.ROUNDED,
    ))


def fmt_tool_call(name: str, inp: dict):
    """Print a tool call: colored tool name + primary argument to stderr."""
    text = Text()
    text.append(f"  {name}", style=f"bold {_tool_color(name)}")
    primary = _extract_primary(name, inp)
    if primary:
        text.append(f"  {primary}", style="bold")
    _stderr.print(text)


def fmt_tool_result(tool_name: str, preview: str):
    """Print a tool result preview to stderr."""
    if not preview:
        _stderr.print(Text("  (empty result)", style="dim"))
        return

    lower = preview.lower()

    # Errors → red bordered panel
    if lower.startswith("tool error:") or lower.startswith("error:"):
        _stderr.print(Panel(preview, border_style="red", title="Error", box=box.ROUNDED))
        return

    # Successful writes → green bordered panel
    if "wrote" in lower and ("chars" in lower or "bytes" in lower):
        _stderr.print(Panel(preview, border_style="green", box=box.ROUNDED))
        return

    # Normal → dim text
    _stderr.print(Text(f"  {preview}", style="dim"))


def fmt_code_result(code: str, filepath: str):
    """Print syntax-highlighted code to stderr when a file was read."""
    ext = os.path.splitext(filepath)[1].lower()
    lexer = _LEXERS.get(ext)
    if not lexer:
        _stderr.print(Text(code, style="dim"))
        return
    _stderr.print(Syntax(code, lexer, line_numbers=True, theme="monokai"))


def fmt_separator():
    """Print a dim horizontal rule to stderr."""
    _stderr.rule(style="dim")
