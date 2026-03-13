# Task Summary — Task 2: Create templates/tool-via-bash.md

## What was done

Created `templates/tool-via-bash.md`: a system prompt appendix that tells Claude Code
(running in `claude -p` headless mode) how to invoke ralph custom tools via the Bash
tool using `tools/cli.py`.

## Files changed

- `templates/tool-via-bash.md` — new file (1032 chars)

## Design

- Uses `{{RALPH_TOOLS}}` placeholder — the shell function added in task 3
  (`build_claude_system_prompt`) will substitute this with the agent's non-essential
  tool list (name + description + parameter list).
- Instructs Claude Code to use its native tools (Read, Edit, Write, Bash) for
  essentials (`read_file`, `write_file`, `bash`, `git_commit`, `git_push`) and only
  call the dispatcher for ralph-specific tools.
- Provides concrete invocation examples showing the JSON arg format.

## Test results

- Template structure verified: `{{RALPH_TOOLS}}` placeholder present (1 occurrence),
  `RALPH_HOME` reference present, `cli.py` reference present.

---

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
