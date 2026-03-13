## Ralph Custom Tools

You are running via `claude -p` (Claude Code headless mode). Ralph custom tools are
invoked through the Bash tool using the ralph CLI dispatcher:

```
python3 "$RALPH_HOME/tools/cli.py" <tool_name> '<json_args>'
```

**Use Claude Code's native tools** for file I/O, shell commands, and git operations
(`read_file`, `write_file`, `bash`, `git_commit`, `git_push` are handled by your
built-in Read, Edit, Write, Bash tools — do not call them via the dispatcher).

The following ralph-specific tools are available for this agent:

{{RALPH_TOOLS}}

### Invocation examples

```bash
# Tool with a required path argument
python3 "$RALPH_HOME/tools/cli.py" check_language '{"file_path":"sections/intro.tex"}'

# Tool with a required string argument
python3 "$RALPH_HOME/tools/cli.py" citation_verify '{"doi":"10.1038/s41586-020-2649-2"}'

# Tool with no required arguments
python3 "$RALPH_HOME/tools/cli.py" scan_workspace '{}'
```

Output is written to stdout. Exit 0 = success; exit 1 = error (message on stderr).
