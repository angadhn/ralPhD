"""Tool registry for ralph_agent.py.

Collects tool definitions from submodules and provides per-agent registries.
Adding a tool = adding it to the right submodule's TOOLS dict + AGENT_TOOLS here.
"""

from tools.core import TOOLS as _core_tools
from tools.checks import TOOLS as _checks_tools
from tools.pdf import TOOLS as _pdf_tools

# ── Merged registry ───────────────────────────────────────────

TOOLS = {}
TOOLS.update(_core_tools)
TOOLS.update(_checks_tools)
TOOLS.update(_pdf_tools)

# ── Per-agent tool registries ─────────────────────────────────

AGENT_TOOLS = {
    "paper-writer": ["read_file", "write_file", "bash", "check_language", "citation_lint"],
    "critic": ["read_file", "write_file", "bash", "check_language", "check_journal", "check_figure"],
    "scout": ["read_file", "write_file", "bash", "pdf_metadata"],
    "deep-reader": ["read_file", "write_file", "bash", "pdf_metadata", "extract_figure"],
    "research-coder": ["read_file", "write_file", "bash"],
    "figure-stylist": ["read_file", "write_file", "bash", "check_figure"],
}

DEFAULT_TOOLS = ["read_file", "write_file", "bash"]


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
