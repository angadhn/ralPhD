# scripts/

Utility scripts and project scaffolding. Most tool implementations have been
inlined into `tools/*.py` (see `tools/README.md`).

## Scripts

| Script | Purpose | Used by |
|--------|---------|---------|
| `usage_report.py` | Token usage and cost reporting from `logs/usage.jsonl` | operator (manual) |
| `extract_session_usage.py` | Extract token usage from interactive Claude session JSONL | ralph-loop.sh (interactive mode) |
| `evaluate_iteration.py` | Post-iteration metric capture → `logs/eval.jsonl` | ralph-loop.sh (via post-run.sh) |
| `evaluate_run.py` | Run aggregation + `--compare` mode for benchmarking | operator (manual) |
| `tool_report.py` | Tool usage analysis from usage logs | operator (manual) |
| `init-project.sh` | Scaffold a new project workspace (dirs, symlinks, launcher) | operator (manual) |
| `archive.sh` | Archive completed thread, restore blank templates, reset iteration counter | operator (manual) |
| `redact_secrets.py` | Redact secret-like content from stdin or files | workflow + operator |
