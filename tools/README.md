# tools/

Self-contained tool implementations for `ralph_agent.py`. Each module contains both
the tool schema definitions and their full handler logic — no subprocess indirection.
Per-agent tool registries defined in `__init__.py`.

Based on [ghuntley's agent architecture](https://ghuntley.com/agent) ([repo](https://github.com/ghuntley/how-to-build-a-coding-agent)): colocated tool definitions + handlers, registered per-agent.

| Module | Tools | Notes |
|--------|-------|-------|
| `core.py` | read_file, write_file, bash | |
| `search.py` | list_files, code_search | |
| `checks.py` | check_language, check_journal, check_figure, citation_lint/lookup/verify/verify_all/manifest | Inlined from scripts; citation handlers use `_citation.py` |
| `claims.py` | check_claims | Cross-ref .tex + evidence-ledger + .bib |
| `pdf.py` | pdf_metadata, extract_figure | Inlined from scripts; fitz lazy-imported |
| `download.py` | citation_download | Unpaywall + SciHub fallback; uses `_citation.manifest_add` |
| `_citation.py` | *(internal)* | Shared citation functions (17 funcs from former `scripts/citation_tools.py`) |
| `_paths.py` | *(internal)* | `_scripts_dir()` path resolution |

`__init__.py` merges all modules into a single TOOLS dict, defines AGENT_TOOLS (per-agent tool assignments), and provides `execute_tool()` and `get_tools_for_agent()` for dispatch. 17 tools total, 5 essentials shared by all agents.
