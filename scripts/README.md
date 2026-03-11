# scripts/

Utility scripts and project scaffolding. Most tool implementations have been
inlined into `tools/*.py` (see `tools/README.md`).

## Scripts

| Script | Purpose | Used by |
|--------|---------|---------|
| `usage_report.py` | Token usage and cost reporting from `logs/usage.jsonl` | operator (manual) |
| `extract_session_usage.py` | Extract token usage from interactive Claude session JSONL | ralph-loop.sh (interactive mode) |
| `init-project.sh` | Scaffold a new project workspace (dirs, symlinks, launcher) | operator (manual) |
| `archive.sh` | Archive completed thread, restore blank templates, reset iteration counter | operator (manual) |
