# Implementation Plan — Fix headless auth for Max plan (OAuth) users

**Thread:** fix-headless-oauth-fallback
**Created:** 2026-03-13

## Context

`ralph_agent.py` calls the Anthropic API directly and requires a regular API key (`sk-ant-api*`). OAuth tokens (`sk-ant-oat*`) are rejected by `api.anthropic.com`. This blocks Max plan users from using headless mode (`-p`). Fix: when no API key is available, fall back to `claude -p` for headless mode.

## Tasks

- [x] 1. Create `tools/cli.py` — CLI entry point so any ralph tool can be invoked from Bash (`python3 $RALPH_HOME/tools/cli.py check_language '{"file_path":"sections/intro.tex"}'`). Import `execute_tool` from `tools/__init__.py`, parse argv (tool name + JSON args), print result to stdout, exit 0/1. ~20 lines. — **coder**
- [x] 2. Create `templates/tool-via-bash.md` — System prompt appendix telling Claude Code how to invoke ralph custom tools via Bash. Template parameterized with the agent's tool list (exclude essentials since Claude Code has better built-ins). — **coder**
- [x] 3. Add `build_claude_system_prompt()` and `has_anthropic_api_key()` helpers to `lib/exec.sh` — Shell function that reads agent .md file, builds path preamble (same logic as `ralph_agent.py:build_path_preamble`), gets agent's custom tool list from `tools/__init__.py`, appends tool-via-bash instructions with the filtered tool list. Also add `is_anthropic_model()` helper. — **coder**
- [ ] 4. Add auth-detection branch in `ralph-loop.sh` pipe mode (line ~167) — If `is_anthropic_model` and `! has_anthropic_api_key`, fall back to `claude -p` with `--append-system-prompt`, `--output-format json`, `--dangerously-skip-permissions`. Otherwise use existing `ralph_agent.py` path. — **coder**
- [ ] 5. Add same auth-detection fallback in `run_parallel_phase()` in `lib/exec.sh` (~line 70) — **coder**
- [ ] 6. Validate/adapt usage JSON parsing in `lib/post-run.sh` — Check if `claude -p --output-format json` output is compatible with `print_output_json_summary` and `log_usage_from_output_json`. Adapt if needed. — **coder**
- [ ] 7. Update `providers.py` error messages to mention the `claude -p` fallback — "ralph_agent.py requires an API key, but ralph-loop.sh will automatically fall back to claude -p when no key is set." — **coder**
