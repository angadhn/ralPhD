"""Tool registry for ralph_agent.py.

Collects tool definitions from submodules and provides per-agent registries.
Adding a tool = adding it to the right submodule's TOOLS dict + AGENT_TOOLS here.
"""

from tools.core import TOOLS as _core_tools
from tools.checks import TOOLS as _checks_tools
from tools.pdf import TOOLS as _pdf_tools
from tools.search import TOOLS as _search_tools
from tools.download import TOOLS as _download_tools
from tools.claims import TOOLS as _claims_tools

# ── Merged registry ───────────────────────────────────────────

TOOLS = {}
TOOLS.update(_core_tools)
TOOLS.update(_checks_tools)
TOOLS.update(_pdf_tools)
TOOLS.update(_search_tools)
TOOLS.update(_download_tools)
TOOLS.update(_claims_tools)

# ── Per-agent tool registries ─────────────────────────────────
# Every agent gets the 5 essentials: read_file, write_file, bash, list_files, code_search

_ESSENTIALS = ["read_file", "write_file", "bash", "list_files", "code_search"]

AGENT_TOOLS = {
    "paper-writer": _ESSENTIALS + ["check_language", "citation_lint"],
    "critic": _ESSENTIALS + ["check_language", "check_journal", "check_figure", "check_claims", "citation_verify_all"],
    "scout": _ESSENTIALS + ["pdf_metadata", "citation_lookup", "citation_verify", "citation_verify_all", "citation_manifest", "citation_download"],
    "deep-reader": _ESSENTIALS + ["pdf_metadata", "extract_figure"],
    "research-coder": _ESSENTIALS + [],
    "figure-stylist": _ESSENTIALS + ["check_figure"],
    "editor": _ESSENTIALS + ["check_claims", "check_language", "citation_lint", "citation_verify_all"],
    "coherence-reviewer": _ESSENTIALS + ["check_claims", "check_language"],
    "provocateur": _ESSENTIALS + [],
}

DEFAULT_TOOLS = _ESSENTIALS


# ── Tool dispatch ─────────────────────────────────────────────

def api_schema(tool: dict) -> dict:
    """Strip function from tool def for the API payload."""
    return {k: v for k, v in tool.items() if k != "function"}


def execute_tool(name: str, tool_input: dict) -> str:
    """Dispatch a tool call to its colocated handler."""
    tool = TOOLS.get(name)
    if not tool:
        return f"Unknown tool: {name}"
    return tool["function"](tool_input)


def get_tools_for_agent(agent_name: str) -> tuple[list[str], list[dict]]:
    """Return (tool_names, api_schemas) for an agent."""
    tool_names = AGENT_TOOLS.get(agent_name, DEFAULT_TOOLS)
    schemas = [api_schema(TOOLS[t]) for t in tool_names]
    return tool_names, schemas
