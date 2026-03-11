# tools/

Tool implementations for `ralph_agent.py`. Each submodule defines tools as dicts with `name`, `description`, `input_schema`, and a colocated `function` handler.

## Submodules

| File | Tools | Purpose |
|------|-------|---------|
| `core.py` | read_file, write_file, bash | Essential primitives (every agent gets these) |
| `search.py` | list_files, code_search | Codebase navigation (every agent gets these) |
| `checks.py` | check_language, check_journal, check_figure, citation_lint/lookup/verify/manifest | Quality enforcement wrappers around `scripts/` |
| `pdf.py` | pdf_metadata, extract_figure | PDF analysis wrappers around `scripts/` |

## Registry

`__init__.py` merges all submodule `TOOLS` dicts into a single registry and defines `AGENT_TOOLS` — which agent gets which tools. It also provides:

- `execute_tool(name, input)` — dispatch a tool call to its handler
- `get_tools_for_agent(agent_name)` — return (tool_names, api_schemas) for an agent
- `api_schema(tool)` — strip the `function` key for API payloads

## Adding a tool

1. Add the handler function and tool dict to the appropriate submodule (or create a new one)
2. If new submodule: import its `TOOLS` in `__init__.py` and merge into the global `TOOLS`
3. Add the tool name to the relevant agents in `AGENT_TOOLS`
