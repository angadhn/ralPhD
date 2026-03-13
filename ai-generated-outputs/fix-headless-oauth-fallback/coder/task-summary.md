# Task Summary — Task 1: Create tools/cli.py

## What was done

Created `tools/cli.py` (~43 lines) — a CLI dispatcher that lets any ralph tool be invoked from Bash.

## Files modified

- `tools/cli.py` — new file

## What it does

- Parses argv: `<tool_name>` (required) and `<json_args>` (optional, defaults to `{}`)
- Adds `$RALPH_HOME` to `sys.path` so it can be invoked as `python3 $RALPH_HOME/tools/cli.py`
- Imports and calls `execute_tool` from `tools/__init__.py`
- Prints result to stdout
- Exits 0 on success, 1 on error (unknown tool, bad JSON, missing args)

## Usage

```bash
python3 $RALPH_HOME/tools/cli.py check_language '{"file_path":"sections/intro.tex"}'
python3 $RALPH_HOME/tools/cli.py list_files '{"path": "."}'
```

## Test results

- No args → prints usage to stderr, exits 1 ✓
- Unknown tool → prints error to stderr, exits 1 ✓
- Invalid JSON → prints parse error to stderr, exits 1 ✓
- `list_files '{"path": "."}'` → prints directory listing, exits 0 ✓
