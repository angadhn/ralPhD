# tools/

Tool implementations for `ralph_agent.py`. Per-agent tool registries defined in `__init__.py`.

Based on [ghuntley's agent architecture](https://ghuntley.com/agent) ([repo](https://github.com/ghuntley/how-to-build-a-coding-agent)): colocated tool definitions + handlers, registered per-agent.

- `core.py` — read_file, write_file, bash
- `search.py` — list_files, code_search
- `checks.py` — check_language, check_journal, check_figure, citation tools
- `pdf.py` — pdf_metadata, extract_figure
